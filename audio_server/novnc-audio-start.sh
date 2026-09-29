#!/bin/bash
# novnc-audio-start.sh - Wrapper para el servicio de audio noVNC.
# Crea la tarjeta de sonido virtual (null sink) y arranca el servidor WebSocket.
# Corre en foreground para que systemd lo controle.

set -euo pipefail

# --- Rutas relativas a este script ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Tarjeta de sonido virtual (idempotente) ---
SINK_NAME="${AUDIO_SINK:-distro_sink}"

if ! pactl list short sinks 2>/dev/null | grep -q "$SINK_NAME"; then
    pactl load-module module-null-sink \
        sink_name="$SINK_NAME" \
        sink_properties=device.description=DistroSink
    echo "[audio] Null sink '$SINK_NAME' creado"
else
    echo "[audio] Null sink '$SINK_NAME' ya existe, omitiendo creación"
fi

# Siempre forzar el default sink (se pierde en reinicios de PulseAudio)
pactl set-default-sink "$SINK_NAME"
echo "[audio] Default sink fijado a '$SINK_NAME'"

# Mover todos los sink-inputs activos al sink de captura
for idx in $(pactl list short sink-inputs 2>/dev/null | awk '{print $1}'); do
    pactl move-sink-input "$idx" "$SINK_NAME" 2>/dev/null && \
        echo "[audio] Sink-input $idx movido a '$SINK_NAME'"
done

# --- Servidor de audio WebSocket ---
echo "[audio] Arrancando audio_server_ws.py..."
cd "$SCRIPT_DIR"
exec python3 audio_server_ws.py