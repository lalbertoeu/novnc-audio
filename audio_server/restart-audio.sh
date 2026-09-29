#!/bin/bash
# restart-audio.sh - Reinicia solo el servicio de audio sin cascada.
# Usado por novnc-audio-restart.timer para evitar reiniciar noVNC.

systemctl --user restart novnc-audio.service