"""
유루나비 24시간 상주 디스코드 에이전트.

VS Code 세션과 완전히 무관하게 systemd로 상시 구동된다(westinx-bot.py의
검증된 패턴을 그대로 따름). 실제 코딩 작업의 뇌는 여전히 Claude Code이며,
이 봇은 그걸 원격에서 켜고/끄고/상태를 물어볼 수 있게 하는 얇은 제어 계층일
뿐이다 — 별도의 LLM 호출이나 자체 판단 로직은 없다.

명령(디스코드 DM 또는 지정 채널에서, DISCORD_OWNER_USER_ID 본인만):
  !run <task_file>   loop/run_night_auto.sh <task_file> 를 백그라운드로 시작
  !status            현재 실행 중인지, 최근 handoff 상태, 최근 커밋 확인
  !stop              실행 중인 틱체인을 정지
  !help              명령 목록
  (그 외 일반 텍스트) — 그대로 claude -p 로 전달해 실제 대화/작업 수행.
  세션은 CHAT_SESSION_FILE에 저장해 재시작해도 대화가 이어짐.
"""

import asyncio
import json
import os
import signal
from pathlib import Path

import discord

REPO = Path("/data/projects/yurunavi")
ENV_FILE = REPO / ".env"
LOOP_DIR = REPO / "loop"
RUNNER = LOOP_DIR / "run_night_auto.sh"
STATE_DIR = LOOP_DIR / ".auto"
PID_FILE = STATE_DIR / "agent_run.pid"
RUN_LOG = STATE_DIR / "agent_run_current.log"
HANDOFF = STATE_DIR / "handoff.md"
CHAT_SESSION_FILE = STATE_DIR / "discord_chat_session_id.txt"
CHAT_TIMEOUT_SECONDS = 1800


def load_env() -> dict:
    env = {}
    for line in ENV_FILE.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        env[k] = v
    return env


ENV = load_env()
BOT_TOKEN = ENV["DISCORD_BOT_TOKEN"]
CHANNEL_ID = int(ENV["DISCORD_CHANNEL_ID"])
OWNER_ID = int(ENV["DISCORD_OWNER_USER_ID"])

intents = discord.Intents.default()
intents.message_content = True
client = discord.Client(intents=intents)

chat_busy = False


def is_authorized(message: discord.Message) -> bool:
    if message.author.id != OWNER_ID:
        return False
    if isinstance(message.channel, discord.DMChannel):
        return True
    return message.channel.id == CHANNEL_ID


def running_pid() -> int | None:
    if not PID_FILE.exists():
        return None
    try:
        pid = int(PID_FILE.read_text().strip())
    except ValueError:
        return None
    try:
        os.killpg(pid, 0)
    except ProcessLookupError:
        return None
    except PermissionError:
        return pid
    return pid


async def cmd_run(message: discord.Message, task_file: str):
    if running_pid() is not None:
        await message.reply("이미 실행 중입니다. 먼저 `!stop` 하거나 `!status`로 확인하세요.")
        return
    task_path = LOOP_DIR / task_file
    if not task_path.exists():
        await message.reply(f"작업 지시서를 못 찾음: `{task_path}`")
        return

    STATE_DIR.mkdir(parents=True, exist_ok=True)
    log_f = open(RUN_LOG, "wb")
    proc = await asyncio.create_subprocess_exec(
        str(RUNNER), task_file,
        cwd=str(REPO),
        stdout=log_f,
        stderr=asyncio.subprocess.STDOUT,
        preexec_fn=os.setsid,
    )
    PID_FILE.write_text(str(proc.pid))
    await message.reply(f"시작함: `{task_file}` (pid {proc.pid}). `!status`로 진행 확인 가능.")

    asyncio.create_task(_wait_and_report(proc, task_file))


async def _wait_and_report(proc: asyncio.subprocess.Process, task_file: str):
    rc = await proc.wait()
    if PID_FILE.exists():
        try:
            if int(PID_FILE.read_text().strip()) == proc.pid:
                PID_FILE.unlink()
        except (ValueError, FileNotFoundError):
            pass
    channel = client.get_channel(CHANNEL_ID)
    if channel:
        status = "정상 종료" if rc == 0 else f"비정상 종료(exit={rc})"
        await channel.send(f"🔔 야간루프 종료: `{task_file}` — {status}. `!status`로 상세 확인 가능.")


async def cmd_status(message: discord.Message):
    lines = []
    pid = running_pid()
    lines.append(f"실행 중: {'예 (pid ' + str(pid) + ')' if pid else '아니오'}")

    if HANDOFF.exists():
        first_line = HANDOFF.read_text().splitlines()[0] if HANDOFF.read_text().strip() else "(비어있음)"
        lines.append(f"마지막 handoff: `{first_line}`")
    else:
        lines.append("handoff.md 없음")

    proc = await asyncio.create_subprocess_shell(
        "git -C /data/projects/yurunavi log --oneline -3",
        stdout=asyncio.subprocess.PIPE,
    )
    out, _ = await proc.communicate()
    lines.append("최근 커밋:\n```\n" + out.decode().strip() + "\n```")

    if RUN_LOG.exists():
        tail_proc = await asyncio.create_subprocess_shell(
            f"tail -n 10 {RUN_LOG}",
            stdout=asyncio.subprocess.PIPE,
        )
        out, _ = await tail_proc.communicate()
        tail = out.decode().strip()
        if tail:
            lines.append("최근 로그:\n```\n" + tail[-1200:] + "\n```")

    await message.reply("\n".join(lines))


async def cmd_stop(message: discord.Message):
    pid = running_pid()
    if pid is None:
        await message.reply("실행 중인 게 없습니다.")
        return
    try:
        os.killpg(pid, signal.SIGTERM)
        await message.reply(f"정지 신호 보냄(pid {pid}).")
    except ProcessLookupError:
        await message.reply("이미 종료된 것 같습니다.")
    if PID_FILE.exists():
        PID_FILE.unlink()


async def send_chunked(message: discord.Message, text: str):
    text = text.strip() or "(빈 응답)"
    for i in range(0, len(text), 1900):
        await message.reply(text[i:i + 1900])


async def handle_chat(message: discord.Message):
    global chat_busy

    if running_pid() is not None:
        await message.reply(
            "지금 `!run` 야간루프가 실행 중입니다. 같은 저장소에서 동시에 작업하면 "
            "커밋/파일 충돌이 날 수 있어 대화 요청은 받지 않습니다. "
            "`!stop` 하거나 끝난 뒤 다시 말 걸어주세요."
        )
        return
    if chat_busy:
        await message.reply("이전 요청 아직 처리 중입니다. 끝나면 답 드릴게요.")
        return

    chat_busy = True
    thinking = await message.reply("🤔 처리 중...")
    try:
        cmd = [
            "claude", "-p", message.content,
            "--output-format", "json",
            "--permission-mode", "bypassPermissions",
        ]
        if CHAT_SESSION_FILE.exists():
            cmd += ["--resume", CHAT_SESSION_FILE.read_text().strip()]

        proc = await asyncio.create_subprocess_exec(
            *cmd, cwd=str(REPO),
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
            preexec_fn=os.setsid,
        )
        try:
            out, err = await asyncio.wait_for(proc.communicate(), timeout=CHAT_TIMEOUT_SECONDS)
        except asyncio.TimeoutError:
            os.killpg(proc.pid, signal.SIGKILL)
            await thinking.edit(content="⏱️ 시간 초과(30분)로 중단했습니다.")
            return

        if proc.returncode != 0:
            await thinking.edit(content=f"❌ 실행 실패(exit={proc.returncode}):\n```\n{err.decode()[-1500:]}\n```")
            return

        try:
            data = json.loads(out.decode())
        except json.JSONDecodeError:
            await thinking.edit(content="❌ 응답 파싱 실패:\n```\n" + out.decode()[-1500:] + "\n```")
            return

        if data.get("session_id"):
            STATE_DIR.mkdir(parents=True, exist_ok=True)
            CHAT_SESSION_FILE.write_text(data["session_id"])

        result = data.get("result", "(결과 없음)")
        await thinking.delete()
        await send_chunked(message, result)
    finally:
        chat_busy = False


HELP_TEXT = (
    "명령:\n"
    "`!run <task_file>` — loop/ 안의 작업지시서로 야간루프 시작 (예: `!run HANDOFF_0722_night.md`)\n"
    "`!status` — 실행 중인지, 최근 상태, 최근 커밋 확인\n"
    "`!stop` — 실행 중인 야간루프 정지\n"
    "그 외 그냥 말 걸면 클로드 코드와 실제 대화(대화 이어짐, `!run` 중엔 비활성)\n"
)


@client.event
async def on_ready():
    print(f"[discord_bot] 로그인됨: {client.user}")
    channel = client.get_channel(CHANNEL_ID)
    if channel:
        await channel.send("🟢 상시 에이전트 기동됨. `!help`로 명령 확인.")


@client.event
async def on_message(message: discord.Message):
    if message.author.id == client.user.id:
        return
    if not is_authorized(message):
        return

    content = message.content.strip()
    if content == "!help":
        await message.reply(HELP_TEXT)
    elif content.startswith("!run "):
        await cmd_run(message, content[len("!run "):].strip())
    elif content == "!status":
        await cmd_status(message)
    elif content == "!stop":
        await cmd_stop(message)
    elif content.startswith("!"):
        await message.reply("모르는 명령입니다. `!help` 참고.")
    elif content:
        asyncio.create_task(handle_chat(message))


if __name__ == "__main__":
    client.run(BOT_TOKEN)
