#!/bin/bash
# install.sh - Instalador del puente de audio para noVNC.
#
# 1. Instala dependencias (ffmpeg + python websockets).
# 2. Coloca los ficheros systemd con el usuario/rutas reales.
# 3. Habilita y arranca los servicios.
#
# Uso: ./install.sh [ruta_fork_noVNC]
#   Si no pasas ruta, se detecta un fork de noVNC en el mismo directorio.

set -euo pipefail

INSTALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

NOVNC_DIR="${1:-}"
if [ -z "$NOVNC_DIR" ]; then
    if [ -d "$INSTALL_DIR/../noVNC" ]; then
        NOVNC_DIR="$INSTALL_DIR/../noVNC"
    else
        echo "[ERROR] Indica la ruta al fork de noVNC: ./install.sh /ruta/noVNC" >&2
        exit 1
    fi
fi

# --- 1. Dependencias ---
echo "==> Instalando dependencias (ffmpeg, python3-websockets)..."
sudo apt-get update
sudo apt-get install -y ffmpeg python3 python3-websockets x11vnc

# --- 2. Variables de entorno ---
USER_UID="$(id -u)"
USER_HOME="$HOME"
export AUDIO_SINK="${AUDIO_SINK:-distro_sink}"
export AUDIO_WS_PORT="${AUDIO_WS_PORT:-8088}"

# --- 3. Instalar servicios systemd (reemplaza placeholders) ---
SYSTEMD_DIR="$HOME/.config/systemd/user"
mkdir -p "$SYSTEMD_DIR"

for unit in systemd/*.service systemd/*.timer; do
    name="$(basename "$unit")"
    echo "==> Generando $SYSTEMD_DIR/$name"
    sed -e "s|__INSTALL_DIR__|$INSTALL_DIR|g" \
        -e "s|__USER_HOME__|$USER_HOME|g" \
        -e "s|__USER_UID__|$USER_UID|g" \
        "$unit" > "$SYSTEMD_DIR/$name"
done

# --- 4. Permisos de scripts ---
chmod +x audio_server/*.sh

# --- 5. Activar servicios ---
echo "==> Activando servicios..."
systemctl --user daemon-reload
systemctl --user enable novnc-audio.service
systemctl --user start novnc-audio.service
systemctl --user enable x11vnc.service
systemctl --user start x11vnc.service
systemctl --user enable novnc.service
systemctl --user start novnc.service

# El timer de reinicio es opcional pero recomendado
systemctl --user enable novnc-audio-restart.timer
systemctl --user start novnc-audio-restart.timer

# Logins persistentes (sin sesión iniciada)
loginctl enable-linger "$USER" 2>/dev/null || true

echo ""
echo "✅ Instalación completada."
echo "   Audio:  ws://$HOSTNAME:${AUDIO_WS_PORT}"
echo "   noVNC:  http://localhost:6080"
echo ""
echo "   IMPORTANTE: en el cliente del navegador el WebSocket usa ws:// en redes"
echo "   HTTP y wss:// en HTTPS. El cliente JS derivado en vnc.html se ajusta solo."
echo ""
echo "   Ver estado: systemctl --user status novnc-audio.service"