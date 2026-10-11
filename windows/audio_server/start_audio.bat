@echo off
REM start_audio.bat - Windows: arranca el bridge de audio noVNC.
REM No hay PulseAudio ni pactl en Windows: se captura VB-CABLE con ffmpeg
REM (DirectShow). Este script solo ejecuta el servidor en foreground.
REM Requisitos previos: instalar VB-CABLE, ffmpeg y Python; fijar
REM "CABLE Input" como dispositivo de reproduccion por defecto.

setlocal
cd /d "%~dp0"

echo [audio] Comprobando ffmpeg...
where ffmpeg >nul 2>&1
if errorlevel 1 (
    echo [audio] ERROR: ffmpeg no instalado. Descarga un build desde
    echo        https://www.gyan.dev/ffmpeg/builds/ y agregalo al PATH.
    exit /b 1
)

echo [audio] Comprobando Python...
where python >nul 2>&1
if errorlevel 1 (
    echo [audio] ERROR: python no instalado o no esta en el PATH.
    exit /b 1
)

echo [audio] Arrancando audio_server_ws.py...
cd audio_server
python audio_server_ws.py
endlocal