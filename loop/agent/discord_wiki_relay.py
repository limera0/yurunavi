"""
디스코드 위키 채널 -> N8N LLM-Wiki 워크플로우 릴레이.

N8N에는 디스코드용 트리거 노드가 없어서(아웃바운드 전송 노드만 있음), 이 작은
상주 봇이 대신 게이트웨이로 메시지를 받아 N8N의 Webhook 노드로 그대로
전달한다. 응답은 N8N이 자체 Discord 노드로 직접 보내므로 이 릴레이는
편도(fire-and-forget)만 담당한다.

payload는 기존 텔레그램 트리거가 주던 모양을 그대로 흉내낸다
({"message": {"text", "chat": {"id"}, "photo": [{"file_id"}]}}) —
N8N 쪽 파싱 로직을 건드리지 않기 위함.
"""

import asyncio
from pathlib import Path

import aiohttp
import discord

REPO = Path("/data/projects/yurunavi")
ENV_FILE = REPO / ".env"
N8N_WEBHOOK_URL = "https://n8n.westinx.com/webhook/discord-wiki"


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
BOT_TOKEN = ENV["DISCORD_WIKI_BOT_TOKEN"]
CHANNEL_ID = int(ENV["DISCORD_WIKI_CHANNEL_ID"])

intents = discord.Intents.default()
intents.message_content = True
client = discord.Client(intents=intents)


@client.event
async def on_ready():
    print(f"[discord_wiki_relay] 로그인됨: {client.user}")


@client.event
async def on_message(message: discord.Message):
    if message.author.bot:
        return
    if message.channel.id != CHANNEL_ID:
        return

    image_attachment = next(
        (a for a in message.attachments if (a.content_type or "").startswith("image/")),
        None,
    )
    payload = {
        "message": {
            "text": message.content,
            "chat": {"id": str(message.channel.id)},
        }
    }
    if image_attachment:
        payload["message"]["photo"] = [{"file_id": image_attachment.url}]

    try:
        async with aiohttp.ClientSession() as session:
            async with session.post(N8N_WEBHOOK_URL, json=payload, timeout=aiohttp.ClientTimeout(total=15)) as resp:
                if resp.status >= 300:
                    await message.channel.send(f"⚠️ N8N 전달 실패(HTTP {resp.status})")
    except asyncio.TimeoutError:
        await message.channel.send("⚠️ N8N 응답 시간 초과")
    except Exception as e:
        await message.channel.send(f"⚠️ N8N 전달 중 오류: {e}")


if __name__ == "__main__":
    client.run(BOT_TOKEN)
