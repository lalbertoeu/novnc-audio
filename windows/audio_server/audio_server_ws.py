#!/usr/bin/env python3
"""noVNC Audio Bridge - WebSocket audio server (Windows).

Streams the Windows system audio (via the VB-CABLE virtual device) as raw
Float32 PCM over a WebSocket so a browser can play it through the Web Audio
API. Same protocol as the Linux version; only the capture source changes:
ffmpeg with DirectShow (dshow) instead of PulseAudio, and there is no pactl.

NOTE: ffmpeg has no native WASAPI input on Windows. Capturing the system
mix requires a virtual cable exposed as a DirectShow capture device
(VB-CABLE: https://vb-audio.com/Cable/). Its dshow pin is capped at
44.1 kHz / 16-bit; ffmpeg resamples to AUDIO_SAMPLE_RATE afterwards.

Requires: python3-websockets, ffmpeg (Windows build), VB-CABLE.
"""

import asyncio
import os
import re
import shutil
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

# Captura: dispositivo DirectShow a capturar.
#   AUDIO_DEVICE      -> nombre exacto (ej: "CABLE Output (VB-Audio Virtual Cable)")
#   AUDIO_DEVICE_HINT -> subcadena para auto-detectarlo (default "CABLE Output")
AUDIO_DEVICE = os.environ.get("AUDIO_DEVICE", "")
AUDIO_DEVICE_HINT = os.environ.get("AUDIO_DEVICE_HINT", "CABLE Output")

FFMPEG_CMD = None
CHUNK = None


def discover_dshow_device(hint):
    """Return the DirectShow audio device name whose name contains `hint`.

    Parses `ffmpeg -list_devices -f dshow -i dummy` (the listing is printed
    on stderr). Returns None when no device matches.
    """
    ffmpeg = shutil.which("ffmpeg")
    if not ffmpeg:
        return None
    try:
        proc = subprocess.run(
            [ffmpeg, "-list_devices", "true", "-f", "dshow", "-i", "dummy"],
            capture_output=True,
            text=True,
            timeout=10,
        )
        output = proc.stderr
    except Exception:
        return None

    # Lineas del tipo: [dshow @ ...] "CABLE Output (VB-Audio Virtual Cable)"
    for line in output.splitlines():
        match = re.search(r'"([^"]+)"', line)
        if match and hint.lower() in match.group(1).lower():
            return match.group(1)
    return None


def build_ffmpeg_command():
    """Build the ffmpeg command that captures the VB-CABLE device."""
    global CHUNK, FFMPEG_CMD
    ffmpeg = shutil.which("ffmpeg")
    if not ffmpeg:
        print("[FATAL] ffmpeg no encontrado. Descarga un build para Windows en https://www.gyan.dev/ffmpeg/builds/", file=sys.stderr)
        sys.exit(1)

    bytes_per_sample = 4  # float32
    CHUNK = int(SAMPLE_RATE * bytes_per_sample * CHANNELS * CHUNK_MS / 1000)

    device = AUDIO_DEVICE.strip() or discover_dshow_device(AUDIO_DEVICE_HINT)
    if device is None:
        print(
            "[FATAL] No se encontró ningún dispositivo de captura (VB-CABLE).\n"
            "         Instala VB-CABLE: https://vb-audio.com/Cable/  (ejecuta vbcable_setup)\n"
            "         y fija 'CABLE Input' como dispositivo de reproducción por defecto\n"
            "         (Configuración de sonido > Salida).\n"
            "         También puedes forzarlo con AUDIO_DEVICE=<nombre exacto>.",
            file=sys.stderr,
        )
        sys.exit(1)

    FFMPEG_CMD = [
        ffmpeg,
        "-f", "dshow",
        "-i", f"audio={device}",
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
    print(f"[INFO] ffmpeg arrancado PID: {process.pid} (device '{AUDIO_DEVICE.strip() or 'auto'}', {SAMPLE_RATE}Hz)")
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