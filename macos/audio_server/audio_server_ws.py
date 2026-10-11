#!/usr/bin/env python3
"""noVNC Audio Bridge - WebSocket audio server (macOS).

Streams the macOS system audio (via the BlackHole virtual device) as raw
Float32 PCM over a WebSocket so a browser can play it through the Web Audio
API. Same protocol as the Linux version; only the capture source changes:
ffmpeg with AVFoundation instead of PulseAudio, and there is no pactl.

Requires: python3-websockets, ffmpeg, BlackHole.
"""

import asyncio
import os
import re
import shutil
import ssl
import subprocess
import sys

import websockets

# ---------------------------------------------------------------------------
# Configuration (override via environment variables)
# ---------------------------------------------------------------------------
WS_HOST = os.environ.get("AUDIO_WS_HOST", "0.0.0.0")
WS_PORT = int(os.environ.get("AUDIO_WS_PORT", "8088"))
SAMPLE_RATE = int(os.environ.get("AUDIO_SAMPLE_RATE", "48000"))
CHANNELS = int(os.environ.get("AUDIO_CHANNELS", "2"))
CHUNK_MS = int(os.environ.get("AUDIO_CHUNK_MS", "30"))  # milliseconds per frame

# Captura: dispositivo de entrada AVFoundation a capturar.
#   AUDIO_DEVICE      -> índice o nombre exacto (ej: "3" o "BlackHole 2ch")
#   AUDIO_DEVICE_HINT -> subcadena para auto-detectarlo (default "BlackHole")
AUDIO_DEVICE = os.environ.get("AUDIO_DEVICE", "")
AUDIO_DEVICE_HINT = os.environ.get("AUDIO_DEVICE_HINT", "BlackHole")

# TLS opcional: el cliente macOS fuerza wss:// (la página se sirve por HTTPS con
# certificado auto-firmado). Si AUDIO_TLS_CERT y AUDIO_TLS_KEY están definidos,
# este servidor acepta conexiones cifradas; si no, queda en ws:// sin cifrar.
TLS_CERT = os.environ.get("AUDIO_TLS_CERT", "")
TLS_KEY = os.environ.get("AUDIO_TLS_KEY", "")

FFMPEG_CMD = None
CHUNK = None


def discover_avfoundation_device(hint):
    """Return the AVFoundation audio device index whose name contains `hint`.

    Parses `ffmpeg -f avfoundation -list_devices true -i ""` (the listing is
    printed on stderr). Returns None when no device matches.
    """
    ffmpeg = shutil.which("ffmpeg")
    if not ffmpeg:
        return None
    try:
        proc = subprocess.run(
            [ffmpeg, "-f", "avfoundation", "-list_devices", "true", "-i", ""],
            capture_output=True,
            text=True,
            timeout=10,
        )
        output = proc.stderr
    except Exception:
        return None

    # Lineas del tipo: [AVFoundation indev @ 0x...] [6] Microsoft Teams Audio
    for line in output.splitlines():
        match = re.search(r"\[\s*(\d+)\]\s*(.+?)\s*$", line.strip())
        if not match:
            continue
        index, name = int(match.group(1)), match.group(2).strip()
        if hint.lower() in name.lower():
            return index
    return None


def build_ffmpeg_command():
    """Build the ffmpeg command that captures the BlackHole device."""
    global CHUNK, FFMPEG_CMD
    ffmpeg = shutil.which("ffmpeg")
    if not ffmpeg:
        print("[FATAL] ffmpeg no encontrado. Instálalo con: brew install ffmpeg", file=sys.stderr)
        sys.exit(1)

    bytes_per_sample = 4  # float32
    CHUNK = int(SAMPLE_RATE * bytes_per_sample * CHANNELS * CHUNK_MS / 1000)

    device = AUDIO_DEVICE.strip() or discover_avfoundation_device(AUDIO_DEVICE_HINT)
    if device is None:
        print(
            "[FATAL] No se encontró ningún dispositivo de audio (BlackHole).\n"
            "         Instálalo con: brew install blackhole\n"
            "         y enruta la salida del sistema hacia BlackHole (o un Multi-Output\n"
            "         Device si quieres seguir oyendo en los altavoces).\n"
            "         También puedes forzarlo con AUDIO_DEVICE=<índice|nombre>.",
            file=sys.stderr,
        )
        sys.exit(1)

    FFMPEG_CMD = [
        ffmpeg,
        "-f", "avfoundation",
        "-i", f":{device}",
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
    print(f"[INFO] ffmpeg arrancado PID: {process.pid} (device :{AUDIO_DEVICE.strip() or 'auto'}, {SAMPLE_RATE}Hz)")
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

    serve_kwargs = {}
    scheme = "ws"
    if TLS_CERT and TLS_KEY:
        ssl_ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        ssl_ctx.load_cert_chain(TLS_CERT, TLS_KEY)
        serve_kwargs["ssl"] = ssl_ctx
        scheme = "wss"
        print(f"[INFO] TLS habilitado: {TLS_CERT}")

    async with websockets.serve(handler, WS_HOST, WS_PORT, **serve_kwargs):
        print(f"[INFO] WebSocket {scheme} en {WS_HOST}:{WS_PORT}")
        await asyncio.Future()  # run forever


if __name__ == "__main__":
    asyncio.run(main())