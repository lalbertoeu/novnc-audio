# noVNC Audio Bridge — macOS

Versión para macOS del bridge de audio noVNC ([repo original](https://github.com/lalbertoeu/novnc-audio)).
Mismo protocolo y mismo cliente web que la versión Linux; cambia **solo la
captura**: en lugar de PulseAudio + `pactl` se captura la tarjeta virtual
**BlackHole** con ffmpeg (AVFoundation).

```
macOS (BlackHole / Multi-Output Device)
        │  ffmpeg (-f avfoundation -f f32le)
        ▼
audio_server_ws.py :8088  ──WS──►  browser (Web Audio API)
```

## Requisitos

```bash
brew install ffmpeg python3 blackhole
pip3 install websockets
```

Opcional (para cambiar la salida por defecto desde CLI):

```bash
brew install switchaudio-osx
```

## Puesta en marcha

1. **Instala BlackHole** (`brew install blackhole`). Reinicia si no aparece
   en *Utilidad Audio MIDI* (Applications > Utilities > Audio MIDI Setup).
2. **(Recomendado) Crea un Multi-Output Device**: en Audio MIDI Setup, botón
   `+` → *Create Multi-Output Device* → marca tus altavoces **y** BlackHole.
   Así sigues oyendo en local mientras transmites. Si no lo creas, el script
   puede dejar BlackHole como única salida (dejarás de oír en local).
3. **Enruta el audio** al Multi-Output (o a BlackHole): menú de sonido de
   macOS o `SwitchAudioSource -s "Multi-Output Device"` / `-s "BlackHole 2ch"`.
4. **Concede permiso de micrófono**: BlackHole aparece como dispositivo de
   *entrada*, así que Terminal.app (o la app que ejecute el servidor) debe
   tener permiso en *System Settings > Privacy & Security > Microphone*.
   Sin esto ffmpeg no puede abrir el dispositivo.
5. **Arranca el servidor**:

   ```bash
   ./start_audio.sh
   # o con configuración explícita:
   AUDIO_DEVICE="BlackHole 2ch" AUDIO_WS_PORT=8088 ./start_audio.sh
   ```

6. **Parchea tu noVNC**: añade antes de `</body>` en `vnc.html`

   ```html
   <script src="vnc-audio-client.js"></script>
   ```

   y copia `web/vnc-audio-client.js` junto a `vnc.html`.
7. **Prueba aislada** (sin abrir noVNC): abre `web/testaudio.html`. Debe
   mostrar `CONECTADO ✓` y `Recibiendo audio (N bytes/frame) ✓`.

## Configuración (variables de entorno)

| Variable | Default | Descripción |
|---|---|---|
| `AUDIO_WS_HOST` | `0.0.0.0` | Dirección del WebSocket |
| `AUDIO_WS_PORT` | `8088` | Puerto del WebSocket |
| `AUDIO_SAMPLE_RATE` | `48000` | Frecuencia de salida (ffmpeg remuestrea) |
| `AUDIO_CHANNELS` | `2` | Canales |
| `AUDIO_CHUNK_MS` | `30` | Tamaño de frame en ms |
| `AUDIO_DEVICE` | *(auto)* | Índice o nombre exacto del dispositivo (`"3"` o `"BlackHole 2ch"`) |
| `AUDIO_DEVICE_HINT` | `BlackHole` | Subcadena para auto-detectar el dispositivo |

La auto-detección ejecuta `ffmpeg -f avfoundation -list_devices true -i ""`
y elige el primer dispositivo cuyo nombre contenga `AUDIO_DEVICE_HINT`.
Puedes ver el listado manualmente con el mismo comando.

## Identificar dispositivo manualmente

```bash
ffmpeg -f avfoundation -list_devices true -i ""
# [AVFoundation audio devices:] [6] BlackHole 2ch ...
# Captura con el índice: AUDIO_DEVICE=6 ./start_audio.sh
```

## Limitaciones y troubleshooting

- **Sin sonido en el navegador**: comprueba que la salida del sistema apunta
  al Multi-Output / BlackHole y que el permiso de micrófono está concedido.
- **"No se encontró ningún dispositivo"**: BlackHole no instalado, o el
  proceso no tiene permiso de micrófono, o el nombre no coincide
  (`AUDIO_DEVICE_HINT`).
- **Audible localmente y en noVNC**: usa *Multi-Output Device*, no BlackHole
  como única salida.
- A diferencia de PulseAudio, macOS no expone un `.monitor`: **todo** lo que
  suene en los altavoces del sistema se transmite. Para aislar apps concretas
  necesitarías enrutado por app (p.ej. `SoundSource`, comercial).