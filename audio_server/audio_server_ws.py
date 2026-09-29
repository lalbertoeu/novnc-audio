#!/usr/bin/env python3
"""noVNC Audio Bridge - WebSocket audio server.

Streams system audio (via PulseAudio null sink) as raw Float32 PCM
over WebSocket so a browser can play it through the Web Audio API.

Requires: python3-websockets, ffmpeg, PulseAudio.
"""

import asyncio
import os
import shutil
import subprocess
import sys

import websockets

# ---------------------------------------------------------------------------
# Configuration (override via environment variables)
# ---------------------------------------------------------------------------
WS_HOST = os.environ.get("AUDIO_WS_HOST", "0.0.0.0")
WS_PORT = int(os.environ.get("AUDIO_WS_PORT", "8088"))
SINK_NAME = os.environ.get("AUDIO_SINK", "distro_sink")
SAMPLE_RATE = int(os.environ.get("AUDIO_SAMPLE_RATE", "48000"))
CHANNELS = int(os.environ.get("AUDIO_CHANNELS", "2"))
CHUNK_MS = int(os.environ.get("AUDIO_CHUNK_MS", "30"))  # milliseconds per frame

FFMPEG_CMD = None
CHUNK = None


def build_ffmpeg_command():
    """Build the ffmpeg command used to capture the PulseAudio monitor."""
    global CHUNK, FFMPEG_CMD
    ffmpeg = shutil.which("ffmpeg")
    if not ffmpeg:
        print("[FATAL] ffmpeg no encontrado. Instala ffmpeg o añádelo al PATH.", file=sys.stderr)
        sys.exit(1)

    bytes_per_sample = 4  # float32
    CHUNK = int(SAMPLE_RATE * bytes_per_sample * CHANNELS * CHUNK_MS / 1000)

    FFMPEG_CMD = [
        ffmpeg,
        "-f", "pulse",
        "-i", f"{SINK_NAME}.monitor",
        "-ac", str(CHANNELS),
        "-ar", str(SAMPLE_RATE),
        "-f", "f32le",
        "pipe:1",
    ]


clients = set()


async def start_ffmpeg():
    build_ffmpeg_command()
    process = await asyncio.create_subprocess_exec(
        *FFMPEG_CMD,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.DEVNULL,
    )
    print(f"[INFO] ffmpeg arrancado PID: {process.pid} ({SINK_NAME}.monitor, {SAMPLE_RATE}Hz)")
    if process.stdout is None:
        raise RuntimeError("No se pudo abrir stdout de ffmpeg")
    return process


async def broadcast(process):
    buffer = b""

    while True:
        data = await process.stdout.read(4096)

        if not data:
            await asyncio.sleep(0.001)
            continue

        buffer += data

        while len(buffer) >= CHUNK:
            chunk = buffer[:CHUNK]
            buffer = buffer[CHUNK:]

            if clients:
                await asyncio.gather(
                    *[client.send(chunk) for client in clients],
                    return_exceptions=True,
                )


async def handler(websocket):
    ip = websocket.remote_address
    print("[INFO] Cliente conectado:", ip)

    clients.add(websocket)

    try:
        await websocket.wait_closed()
    finally:
        clients.remove(websocket)
        print("[INFO] Cliente desconectado:", ip)


async def main():
    process = await start_ffmpeg()
    asyncio.create_task(broadcast(process))

    async with websockets.serve(handler, WS_HOST, WS_PORT):
        print(f"[INFO] WebSocket en {WS_HOST}:{WS_PORT}")
        await asyncio.Future()  # run forever


if __name__ == "__main__":
    asyncio.run(main())