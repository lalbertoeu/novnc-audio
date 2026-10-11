#!/bin/bash
# start_audio.sh - macOS: arranca el bridge de audio noVNC.
# No hay PulseAudio ni pactl en macOS: se captura BlackHole con ffmpeg
# (AVFoundation). Este script solo comprueba los requisitos y ejecuta
# el servidor en foreground.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Requisitos ---
if ! command -v ffmpeg >/dev/null 2>&1; then
    echo "[audio] ERROR: ffmpeg no instalado. Ejecuta: brew install ffmpeg" >&2
    exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
    echo "[audio] ERROR: python3 no instalado. Ejecuta: brew install python3" >&2
    exit 1
fi

if ! system_profiler SPAudioDataType 2>/dev/null | grep -qi "BlackHole"; then
    echo "[audio] ERROR: BlackHole no está instalado. Ejecuta: brew install blackhole" >&2
    echo "        Después crea un 'Multi-Output Device' (altavoces + BlackHole) en" >&2
    echo "        Utilidad Audio MIDI para seguir oyendo en los altavoces." >&2
    exit 1
fi

# --- Salida por defecto (opcional, solo si SwitchAudioSource está instalado) ---
# Si ya tienes un Multi-Output Device configurado y activo, este paso se omite.
if command -v SwitchAudioSource >/dev/null 2>&1; then
    current="$(SwitchAudioSource -c 2>/dev/null || true)"
    if ! echo "$current" | grep -qi "Multi-Output\|BlackHole"; then
        echo "[audio] Definiendo salida por defecto: BlackHole 2ch (deja de oírse local;"
        echo "        usa un Multi-Output Device para oír y transmitir a la vez)"
        SwitchAudioSource -s "BlackHole 2ch" >/dev/null 2>&1 || \
            echo "[audio] Aviso: no se pudo cambiar la salida (¿nombre distinto?)"
    fi
fi

# --- Servidor de audio WebSocket ---
echo "[audio] Arrancando audio_server_ws.py..."
cd "$SCRIPT_DIR"
exec python3 audio_server_ws.py