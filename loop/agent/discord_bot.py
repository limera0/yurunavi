"""
유루나비 24시간 상주 디스코드 에이전트.

VS Code 세션과 완전히 무관하게 systemd로 상시 구동된다(westinx-bot.py의
검증된 패턴을 그대로 따름). 실제 코딩 작업의 뇌는 여전히 Claude Code이며,
이 봇은 그걸 원격에서 켜고/끄고/상태를 물어볼 수 있게 하는 얇은 제어 계층일
뿐이다 — 별도의 LLM 호출이나 자체 판단 로직은 없다.

명령(디스코드 DM 또는 지정 길드(DISCORD_GUILD_ID) 내 어느 채널에서든,
DISCORD_OWNER_USER_ID 본인만):
  !plan <자연어>     요청을 해석해 작업지시서를 새로 쓰고, 목표 확인(goal-gate) 후 실행
  !run <task_file>   이미 있는 지시서로 loop/run_night_auto.sh 를 백그라운드로 시작
  !status            현재 실행 중인지, 최근 handoff 상태, 최근 커밋 확인
  !stop              실행 중인 틱체인을 정지
  !wiki              loop/ 문서 색인(WIKI_INDEX.md) 재생성
  !help              명령 목록
  (그 외 일반 텍스트) — 그대로 claude -p 로 전달해 실제 대화/작업 수행.
  세션은 CHAT_SESSION_FILE에 저장해 재시작해도 대화가 이어짐.
"""

import asyncio
import json
import os
import re
import shlex
import signal
from datetime import datetime
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

# 디스코드 첨부(이미지/PDF/텍스트 등) 저장 규칙.
# archive HDD(sdb, /archive) 밑 프로젝트별 폴더 — 이 repo가 아니라 별도 디스크라
# git 오염이 없다. 새 프로젝트 봇은 PROJECT 상수만 바꾸면 된다.
PROJECT = "yurunavi"
UPLOAD_ROOT = Path("/archive/discord") / PROJECT
MAX_ATTACHMENT_BYTES = 50 * 1024 * 1024  # 50MB — 디스코드 기본 첨부 한도 수준


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
CHANNEL_ID = int(ENV["DISCORD_CHANNEL_ID"])  # 상태 브로드캐스트(기동/야간루프 종료 알림) 기본 채널
GUILD_ID = int(ENV["DISCORD_GUILD_ID"])
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
    return message.guild is not None and message.guild.id == GUILD_ID


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


def _safe_name(name: str) -> str:
    """첨부 파일명을 안전하게 정리한다. 경로 구분자/traversal 제거, 한글 등은 보존(\\w+UNICODE)."""
    name = os.path.basename(name or "file")
    name = re.sub(r"[^\w.\-]", "_", name, flags=re.UNICODE)
    return name.strip("._") or "file"


async def save_attachments(message: discord.Message) -> list[Path]:
    """OWNER가 올린 첨부를 /archive/discord/<project>/ 에 yymmddhhmmss_<원본명> 으로 저장.

    저장된 로컬 경로 리스트를 반환한다. 크기 초과/저장 실패는 건너뛰고 사용자에게 알린다.
    (is_authorized 로 OWNER 메시지만 여기 도달하므로 임의 파일 업로드 위험은 없다.)
    """
    if not message.attachments:
        return []
    UPLOAD_ROOT.mkdir(parents=True, exist_ok=True)
    saved: list[Path] = []
    for att in message.attachments:
        if att.size and att.size > MAX_ATTACHMENT_BYTES:
            await message.reply(
                f"⚠️ 첨부 `{att.filename}` 가 너무 큽니다({att.size // 1024 // 1024}MB > 50MB) — 건너뜀."
            )
            continue
        ts = datetime.now().strftime("%y%m%d%H%M%S")
        dest = UPLOAD_ROOT / f"{ts}_{_safe_name(att.filename)}"
        # 같은 초에 동명 파일이 또 오면(드묾) 덮어쓰지 않게 카운터를 붙인다.
        base, n = dest, 1
        while dest.exists():
            dest = base.with_name(f"{base.stem}_{n}{base.suffix}")
            n += 1
        try:
            await att.save(dest)
            saved.append(dest)
        except Exception as e:  # noqa: BLE001 — 개별 첨부 실패가 전체를 막지 않게
            await message.reply(f"⚠️ 첨부 `{att.filename}` 저장 실패: {e}")
    return saved


def _augment_prompt(text: str, paths: list[Path]) -> str:
    """claude -p 프롬프트에 첨부 로컬 경로 블록을 덧붙인다. Read 도구가 이미지/PDF/텍스트를
    직접 렌더링하므로, 경로만 알려주면 모델이 열어서 실제 내용을 본다."""
    text = (text or "").strip()
    if not paths:
        return text
    block = "\n".join(f"- {p}" for p in paths)
    note = (
        "\n\n[첨부파일 — Read 도구로 열어서 확인해라. 이미지/PDF/텍스트 모두 Read로 직접 볼 수 있다]\n"
        + block
    )
    return (text or "(본문 없음 — 첨부파일을 열어보고 무엇을 원하는지 판단해라)") + note


# run_night_auto.sh 에 그대로 통과시킬 수 있는 옵션 화이트리스트.
# (create_subprocess_exec는 셸을 안 거쳐 인젝션 위험은 없지만, 오타/실수 방지용으로 좁게 제한)
ALLOWED_RUN_FLAGS = {
    "--goal-gate", "--goal-gate-wait-seconds",
    "--max-ticks", "--max-wall-seconds", "--tick-timeout",
    "--blocked-wait-seconds", "--effort",
}


async def cmd_run(message: discord.Message, arg_str: str):
    if running_pid() is not None:
        await message.reply("이미 실행 중입니다. 먼저 `!stop` 하거나 `!status`로 확인하세요.")
        return
    # !plan 이 지시서를 쓰는 중이거나 대화 요청이 처리 중이면 시작하지 않는다 —
    # 그쪽이 끝나면서 자기 실행을 띄우면 러너가 둘이 되기 때문(반대 방향 TOCTOU 차단).
    if chat_busy:
        await message.reply(
            "지금 `!plan` 지시서 작성 또는 대화 요청을 처리 중입니다. 끝난 뒤 다시 시도하세요."
        )
        return

    try:
        tokens = shlex.split(arg_str)
    except ValueError:
        await message.reply("명령 파싱 실패 — 따옴표를 확인하세요.")
        return
    if not tokens:
        await message.reply("작업 지시서 파일명이 필요합니다. 예: `!run HANDOFF_0722_night.md --goal-gate`")
        return

    task_file, extra_args = tokens[0], tokens[1:]

    # 옵션 검증: 화이트리스트에 있는 플래그와 그 값만 허용.
    i = 0
    while i < len(extra_args):
        flag = extra_args[i]
        if flag not in ALLOWED_RUN_FLAGS:
            await message.reply(f"허용되지 않은 옵션: `{flag}`. 사용 가능: {', '.join(sorted(ALLOWED_RUN_FLAGS))}")
            return
        if flag == "--goal-gate":
            i += 1  # 값 없는 플래그
        else:
            # 값을 동반하는 플래그: 다음 토큰이 값으로 실제 존재해야 함(빠지면 자식이 set -u로 죽음)
            if i + 1 >= len(extra_args) or extra_args[i + 1].startswith("--"):
                await message.reply(f"옵션 `{flag}` 에는 값이 필요합니다. 예: `{flag} 20`")
                return
            i += 2

    # 사용자가 'loop/' 를 붙여 써도 받아준다(도움말은 파일명만 안내하지만 둘 다 허용).
    task_file = task_file[len("loop/"):] if task_file.startswith("loop/") else task_file
    task_path = LOOP_DIR / task_file
    if not task_path.exists():
        await message.reply(f"작업 지시서를 못 찾음: `{task_path}`")
        return

    await _spawn_run(message, task_file, extra_args)


async def _spawn_run(message: discord.Message, task_file: str, extra_args: list[str]):
    """run_night_auto.sh 를 백그라운드로 띄우고 pid를 기록한다. (!run / !plan 공용)

    task_file 은 loop/ 기준 파일명(예: HANDOFF_0722_x.md)으로 받되, 러너에는 반드시
    리포 루트 기준 경로('loop/…')로 넘겨야 한다 — 러너가 `cd <repo>` 후
    `[ -f "$TASK_FILE" ]` 로 검사하기 때문에 파일명만 넘기면 무조건
    'FATAL: task file not found' 로 죽는다(2026-07-22 발견, 그 전까지 !run 은 동작한 적 없음).
    """
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    log_f = open(RUN_LOG, "wb")
    proc = await asyncio.create_subprocess_exec(
        str(RUNNER), f"loop/{task_file}", *extra_args,
        cwd=str(REPO),
        stdout=log_f,
        stderr=asyncio.subprocess.STDOUT,
        preexec_fn=os.setsid,
    )
    PID_FILE.write_text(str(proc.pid))
    opts = (" " + " ".join(extra_args)) if extra_args else ""
    await message.reply(f"시작함: `{task_file}`{opts} (pid {proc.pid}). `!status`로 진행 확인 가능.")

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


async def cmd_wiki(message: discord.Message):
    if running_pid() is not None:
        await message.reply(
            "야간루프 실행 중엔 위키 큐레이션을 돌리지 않습니다(같은 저장소 동시 작업 방지). "
            "끝난 뒤 다시 시도하세요."
        )
        return
    script = LOOP_DIR / "curate_wiki.sh"
    if not script.exists():
        await message.reply(f"스크립트를 못 찾음: `{script}`")
        return
    await message.reply("🗂️ 위키 큐레이션 시작 — `loop/WIKI_INDEX.md` 재정리 (몇 분 걸립니다).")
    proc = await asyncio.create_subprocess_exec(
        str(script),
        cwd=str(REPO),
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.STDOUT,
        preexec_fn=os.setsid,
    )
    asyncio.create_task(_wiki_report(message, proc))


async def _wiki_report(message: discord.Message, proc: asyncio.subprocess.Process):
    out, _ = await proc.communicate()
    tail = (out.decode(errors="ignore").strip() or "(출력 없음)")[-1500:]
    await message.reply(f"🗂️ 위키 큐레이션 종료(exit={proc.returncode}):\n```\n{tail}\n```")


PLAN_TIMEOUT_SECONDS = 900  # 15min — 지시서 초안 1회 작성

PLAN_PROMPT = """\
너는 유루나비 프로젝트의 작업 계획자다. 아래 마스터의 자연어 요청을 받아, 무인 실행용
작업 지시서 파일 하나를 만드는 것이 너의 유일한 임무다.

## 마스터 요청
{request}

## 할 일
1. 네 컨텍스트에 이미 주입된 loop/STATUS.md(현재 상태 + 미완료 릴리스 항목)를 근거로
   이 요청이 어느 항목에 해당하는지 판단해라. 해당 항목이 있으면 거기 적힌 줄번호로
   loop/RELEASE_ROADMAP.md의 **그 부분만** 읽어라(62KB 전체를 읽지 마라).
2. loop/WIKI_INDEX.md를 grep해서 관련된 과거 조사/작업 문서가 있는지 확인하고, 있으면
   지시서에 링크로 남겨라 — 같은 조사를 두 번 하지 않는 게 목적이다.
3. loop/HANDOFF_{date}_<슬러그>.md 파일을 새로 써라. <슬러그>는 영문 소문자+언더스코어로
   짧게(예: app_icon, privacy_policy).

## 지시서 형식 (첫 줄은 반드시 GOAL:)
GOAL: <이번 작업의 목표 한 줄 — 자동화가 이 줄을 뽑아 마스터에게 확인받는다>

그 아래는 기존 loop/HANDOFF_*.md 관례를 따라라: 배경/근거(로드맵 항목 번호·줄번호, 관련
과거 문서 링크) / 구체적 단계(번호 매겨서, 각 단계는 한 틱에 끝날 크기로) / 완료 판정 기준 /
건드리지 말아야 할 것 / 막힐 만한 지점.

## 금지
- 코드를 고치지 마라. git 커밋/스테이징 하지 마라. 지시서 파일 하나만 써라.
- 요청이 모호해 목표를 특정할 수 없으면 파일을 만들지 말고, 마지막 줄에 정확히
  `NEED_CLARIFICATION: <되물을 질문 한 줄>` 만 출력해라.

## 출력 형식
마지막 줄에 정확히 아래 한 줄만 출력해라(다른 말 붙이지 마라):
CREATED: <만든 파일명>
"""


async def cmd_plan(message: discord.Message, request: str):
    """자연어 요청 → 작업지시서 초안 → goal-gate 확인과 함께 무인 실행 시작."""
    global chat_busy

    if running_pid() is not None:
        await message.reply("야간루프가 이미 실행 중입니다. `!stop` 하거나 끝난 뒤 다시 시도하세요.")
        return
    if chat_busy:
        await message.reply("이전 요청 아직 처리 중입니다. 끝나면 답 드릴게요.")
        return

    chat_busy = True
    thinking = await message.reply("🧭 지시서 초안 작성 중... (최대 15분)")
    try:
        # 첨부(스크린샷 등)가 있으면 저장해 경로를 요청에 덧붙인다 — 본문 없이 이미지만
        # 보낸 !plan 도 허용(모델이 이미지를 Read 로 보고 작업을 특정).
        attach_paths = await save_attachments(message)
        if not request and not attach_paths:
            await thinking.edit(
                content="무슨 작업인지 자연어로 적어주세요. 예: `!plan 앱 아이콘 확정 작업 해줘`"
            )
            return
        request_aug = _augment_prompt(request, attach_paths)
        prompt = PLAN_PROMPT.format(request=request_aug, date=datetime.now().strftime("%m%d"))
        proc = await asyncio.create_subprocess_exec(
            "claude", "-p", prompt,
            "--output-format", "json",
            "--permission-mode", "bypassPermissions",
            cwd=str(REPO),
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
            preexec_fn=os.setsid,
        )
        try:
            out, err = await asyncio.wait_for(proc.communicate(), timeout=PLAN_TIMEOUT_SECONDS)
        except asyncio.TimeoutError:
            os.killpg(proc.pid, signal.SIGKILL)
            await thinking.edit(content="⏱️ 지시서 작성이 15분을 넘겨 중단했습니다.")
            return

        if proc.returncode != 0:
            await thinking.edit(content=f"❌ 실행 실패(exit={proc.returncode}):\n```\n{err.decode()[-1200:]}\n```")
            return
        try:
            result = json.loads(out.decode()).get("result", "")
        except json.JSONDecodeError:
            await thinking.edit(content="❌ 응답 파싱 실패:\n```\n" + out.decode()[-1200:] + "\n```")
            return

        lines = [ln.strip().strip("`").strip() for ln in result.splitlines()]

        for ln in lines:
            if ln.startswith("NEED_CLARIFICATION:"):
                q = ln.split(":", 1)[1].strip()
                await thinking.edit(
                    content=f"❓ 요청이 모호해서 지시서를 못 만들었습니다.\n\n{q}\n\n"
                            "답을 포함해서 `!plan` 을 다시 보내주세요."
                )
                return

        created = next((ln.split(":", 1)[1].strip() for ln in lines if ln.startswith("CREATED:")), None)
        if not created:
            await thinking.edit(
                content="❌ 지시서 파일명을 못 찾았습니다(`CREATED:` 줄 없음).\n```\n" + result[-1000:] + "\n```"
            )
            return

        # 모델이 낸 문자열이므로 경로를 반드시 검증한다(loop/ 직속 HANDOFF_*.md 만 허용).
        created = created[len("loop/"):] if created.startswith("loop/") else created
        task_path = (LOOP_DIR / created).resolve()
        if (task_path.parent != LOOP_DIR.resolve()
                or task_path.suffix != ".md"
                or not task_path.name.startswith("HANDOFF_")):
            await thinking.edit(content=f"❌ 허용되지 않은 지시서 경로/이름: `{created}`")
            return
        if not task_path.exists():
            await thinking.edit(content=f"❌ 지시서가 실제로 만들어지지 않았습니다: `{created}`")
            return

        goal = ""
        for ln in task_path.read_text(encoding="utf-8", errors="ignore").splitlines():
            if ln.strip().startswith("GOAL:"):
                goal = ln.split(":", 1)[1].strip()
                break

        # 지시서 작성에 최대 15분이 걸리므로, 그 사이 !run 으로 다른 실행이 시작됐을 수
        # 있다. 여기서 다시 확인하지 않으면 러너가 두 개 동시에 돌아 같은 워킹트리에
        # 서로의 미완성 변경을 커밋하는 사고가 난다(CLAUDE.md: 동시 세션이 브랜치 공유).
        if running_pid() is not None:
            await thinking.edit(content=(
                f"📝 지시서는 저장했습니다: `{created}`\n"
                f"🎯 목표: {goal or '(GOAL 줄 없음)'}\n\n"
                "⚠️ 다만 지시서를 쓰는 동안 다른 실행이 먼저 시작돼서 이번엔 실행하지 않았습니다. "
                f"끝난 뒤 `!run {created} --goal-gate` 로 시작하세요."
            ))
            return

        await thinking.edit(content=(
            f"📝 지시서 작성됨: `{created}`\n"
            f"🎯 목표: {goal or '(GOAL 줄 없음 — 확인 필요)'}\n\n"
            "이제 목표 확인(goal-gate)과 함께 실행합니다. 곧 목표를 다시 보내드릴 테니 "
            "**맞으면 `ok`, 고칠 게 있으면 그대로 지시**해 주세요. 무응답이면 작업은 시작되지 않습니다."
        ))
        await _spawn_run(message, created, ["--goal-gate"])
    finally:
        chat_busy = False


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
        attach_paths = await save_attachments(message)
        prompt = _augment_prompt(message.content, attach_paths)
        cmd = [
            "claude", "-p", prompt,
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
    "`!plan <자연어 지시>` — 지시서를 알아서 쓰고 목표 확인 후 바로 실행\n"
    "  예: `!plan 앱 아이콘 확정 작업 해줘` → 지시서 작성 → 목표 확인(ok/보정) → 무인 실행\n"
    "`!run <task_file> [옵션]` — 이미 있는 지시서로 야간루프 시작 (예: `!run HANDOFF_0722_night.md --goal-gate`)\n"
    "  옵션: `--goal-gate`(시작 전 목표 확인), `--max-ticks N`, `--tick-timeout N` 등\n"
    "`!status` — 실행 중인지, 최근 상태, 최근 커밋 확인\n"
    "`!stop` — 실행 중인 야간루프 정지\n"
    "`!wiki` — loop/ 문서를 loop/WIKI_INDEX.md로 재정리(위키 큐레이션, 매일 04:10 자동)\n"
    "그 외 그냥 말 걸면 클로드 코드와 실제 대화(대화 이어짐, 루프 실행 중엔 비활성)\n"
    "📎 이미지/파일을 첨부하면 자동 저장 후 클로드가 열어봅니다 — `!plan`에 스크린샷을 "
    "붙여 버그 수정을 맡기거나, 그냥 이미지만 올려 물어봐도 됩니다.\n"
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
    elif content.startswith("!plan"):
        # 지시서 작성에 몇 분 걸리므로 이벤트 루프를 막지 않게 태스크로 띄운다.
        asyncio.create_task(cmd_plan(message, content[len("!plan"):].strip()))
    elif content.startswith("!run "):
        await cmd_run(message, content[len("!run "):].strip())
    elif content == "!status":
        await cmd_status(message)
    elif content == "!stop":
        await cmd_stop(message)
    elif content == "!wiki":
        await cmd_wiki(message)
    elif content.startswith("!"):
        await message.reply("모르는 명령입니다. `!help` 참고.")
    elif content or message.attachments:
        # 본문 텍스트가 있거나, 텍스트 없이 이미지/파일만 올린 경우도 대화로 처리.
        asyncio.create_task(handle_chat(message))


if __name__ == "__main__":
    client.run(BOT_TOKEN)
