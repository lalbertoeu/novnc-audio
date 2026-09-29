#!/bin/bash
# start_virtual_soundcard.sh - Crea un null sink en PulseAudio y lo deja
# como sink por defecto. El servidor de audio captura de su .monitor.

sink_name="${AUDIO_SINK:-distro_sink}"

if pactl list short sinks 2>/dev/null | grep -q "$sink_name"; then
    echo "[audio] Null sink '$sink_name' ya existe"
else
    pactl load-module module-null-sink \
        sink_name="$sink_name" \
        sink_properties=device.description=DistroSink
    echo "[audio] Null sink '$sink_name' creado"
fi

pactl set-default-sink "$sink_name"
echo "[audio] Default sink fijado a '$sink_name'"