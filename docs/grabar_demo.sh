#!/bin/bash
# grabar_demo.sh - Graba la demo "audio en noVNC" (30s)
#
# Fase 1 (0-14s)  SIN AUDIO:  el stream de Firefox va a los altavoces → noVNC mudo
# Fase 2 (14-30s) CON AUDIO:  el stream se mueve a distro_sink → noVNC con sonido
#
# El audio grabado sale de distro_sink.monitor = EXACTAMENTE lo que envía el
# audio server al cliente noVNC.
#
# Abre previamente pavucontrol con la pantalla dividida para que la demo
# muestre, en vivo, el destino del stream (altavoces → distro_sink).
#
# El video fuente es un clip local de animación con melodía sintetizada
# (sin derechos: se genera con ffmpeg, ver README). Se abre en bucle desde
# ./demo-assets/index.html para no depender de YouTube (auto-pausa, copyright).

set -euo pipefail

OUT="${1:-demo-audio-novnc.mp4}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ASSETS="$SCRIPT_DIR/demo-assets/index.html"
CLIP="$SCRIPT_DIR/demo-assets/demo-clip.mp4"

# 0a) Generar el clip de animación si no existe (sin derechos: ffmpeg + tono
#     sintetizado). Una sola vez; ~23MB y 30s.
if [ ! -f "$CLIP" ]; then
    echo "[OK] Generando clip de animación (30s, música sintetizada)..."
    python3 - "$CLIP" <<'PYEOF'
import numpy as np, wave, sys, subprocess
sr=44100; dur=32.0; n=int(sr*dur)
t=np.arange(n)/sr; sig=np.zeros(n,dtype=np.float32)
pattern=[261.63,293.66,329.63,349.23,392.00,440.00,523.25,587.33]
for rep in range(2):
    for j,f in enumerate(pattern):
        st=rep*16.0+j*2.0
        i0=int(st*sr); i1=int((st+0.9)*sr)
        tt=t[i0:i1]-t[i0]; env=np.exp(-2.5*tt)
        seg=0.45*env*np.sin(2*np.pi*f*tt)+0.12*env*np.sin(2*np.pi*f*2*tt)
        sig[i0:i1]+=seg
    for st in np.arange(rep*16.0,(rep+1)*16.0,0.5):
        i0=int(st*sr); i1=int((st+0.22)*sr)
        tt=t[i0:i1]-t[i0]
        sig[i0:i1]+=0.28*np.exp(-9*tt)*np.sin(2*np.pi*170*tt)
stereo=np.stack([sig,sig],axis=1)
pcm=(stereo*32767).astype(np.int16)
wav=sys.argv[1]+".wav"
w=wave.open(wav,'wb'); w.setnchannels(2); w.setsampwidth(2); w.setframerate(sr)
w.writeframes(pcm.tobytes()); w.close()
subprocess.run(["ffmpeg","-y","-f","lavfi","-i",
    "color=c=0x2b3a67:s=1920x1080:d=32:r=25",
    "-f","lavfi","-i","testsrc2=s=1920x1080:r=25:d=32",
    "-i",wav,"-t","30",
    "-filter_complex",
    "[1:v]eq=gamma=1.2:saturation=2.2[anim];[0:v][anim]overlay=W/2-w/2:H/2-h/2:shortest=1[bg];"
    "[bg]drawbox=x=0:y=0:w=iw:h=ih:color=black@0.15:t=fill[out]",
    "-map","[out]","-map","2:a","-c:v","libx264","-preset","veryfast",
    "-crf","20","-pix_fmt","yuv420p","-c:a","aac","-b:a","160k","-shortest",
    sys.argv[1]],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
PYEOF
    rm -f "$CLIP.wav"
fi

# 0b) Abrir (o reusar) el clip local de animación en Firefox y darle play
export LANG=C
if ! pgrep -f "file://$ASSETS" >/dev/null; then
    setsid firefox --new-instance "file://$ASSETS" >/dev/null 2>&1 &
    sleep 10
fi
CLIP_WIN="$(xdotool search --onlyvisible --name "noVNC Audio Demo Clip" | head -1 || true)"
if [ -n "$CLIP_WIN" ]; then
    xdotool windowactivate "$CLIP_WIN" 2>/dev/null || xdotool windowfocus "$CLIP_WIN"
    xdotool mousemove 960 540 click 1
    sleep 3
fi

# El usuario exige: con el video ya sonando, pavucontrol al frente para que se
# vea el destino del stream (altavoces → distro_sink) durante toda la demo.
# Layout: video a la izquierda (1420px) y pavucontrol a la derecha (500px),
# encima, para que ambos sean visibles y pavucontrol quede en primer plano.
PAVCONTROL_WIN="$(xdotool search --name "Volume Control" | head -1 || true)"
if [ -z "$PAVCONTROL_WIN" ]; then
    setsid pavucontrol >/dev/null 2>&1 &
    sleep 3
    PAVCONTROL_WIN="$(xdotool search --name "Volume Control" | head -1 || true)"
fi
if [ -n "$PAVCONTROL_WIN" ]; then
    xdotool windowactivate "$CLIP_WIN" 2>/dev/null || true
    xdotool windowsize "$CLIP_WIN" 1420 1080 windowmove "$CLIP_WIN" 0 0 2>/dev/null || true
    xdotool windowsize "$PAVCONTROL_WIN" 500 1080 windowmove "$PAVCONTROL_WIN" 1420 0 2>/dev/null || true
    xdotool windowactivate "$PAVCONTROL_WIN" 2>/dev/null || true
fi

# 1) Localizar TODOS los sink-input de Firefox
mapfile -t FIREFOX_STREAMS < <(pactl list sink-inputs | awk '
    /Sink Input #[0-9]+/{gsub(/[^0-9]/,""); id=$0}
    /application.name = "Firefox"/{print id}')

if [ "${#FIREFOX_STREAMS[@]}" -eq 0 ]; then
    echo "[ERR] No hay stream de Firefox reproduciendo" >&2
    exit 1
fi
echo "[OK] Streams Firefox: ${FIREFOX_STREAMS[*]}"

ALSA_SINK="$(pactl list short sinks | awk '/analog-stereo/{print $2}')"
VIDEO_SINK="$(pactl list short sinks | awk '/distro_sink/{print $2}')"

if [ -z "$ALSA_SINK" ] || [ -z "$VIDEO_SINK" ]; then
    echo "[ERR] Faltan sinks (analog + distro_sink)" >&2
    exit 1
fi

# 2) Fase 1: enviar el audio a los altavoces (noVNC queda mudo).
#    También la default -> así los streams que cree el navegador van a altavoces.
pactl set-default-sink "$ALSA_SINK"
for s in "${FIREFOX_STREAMS[@]}"; do
    pactl move-sink-input "$s" "$ALSA_SINK"
done
echo "[OK] Fase 1 (SIN AUDIO): stream -> altavoces ($ALSA_SINK)"

# 3) Grabar
ffmpeg -y \
    -f x11grab -video_size 1920x1080 -framerate 25 -i :0.0 \
    -f pulse -i distro_sink.monitor \
    -t 30 \
    -c:v libx264 -preset veryfast -crf 23 -pix_fmt yuv420p \
    -c:a aac -b:a 128k \
    -vf "drawtext=fontsize=48:fontcolor=white:borderw=3:bordercolor=black:x=(w-text_w)/2:y=40:enable='between(t,0,14)':text='SIN AUDIO (noVNC mudo) — stream en altavoces',\
         drawtext=fontsize=48:fontcolor=lime:borderw=3:bordercolor=black:x=(w-text_w)/2:y=40:enable='between(t,14,30)':text='CON AUDIO (noVNC con sonido) — stream en distro_sink'" \
    -threads 0 "$OUT" \
    &
FFMPEG_PID=$!

# 4) A los 14s: fase 2, mover el stream a distro_sink
sleep 14
# re-capturar streams (Firefox pudo crear nuevos) y mudar todos a distro_sink
mapfile -t LIVE < <(pactl list sink-inputs | awk '
    /Sink Input #[0-9]+/{gsub(/[^0-9]/,""); id=$0}
    /application.name = "Firefox"/{print id}')
pactl set-default-sink "$VIDEO_SINK"
for s in "${LIVE[@]}"; do
    pactl move-sink-input "$s" "$VIDEO_SINK"
done
echo "[OK] Fase 2 (CON AUDIO): stream -> distro_sink ($VIDEO_SINK)"

wait "$FFMPEG_PID"
echo "[OK] Video generado: $OUT"
ls -lh "$OUT"