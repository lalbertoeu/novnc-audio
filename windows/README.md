# noVNC Audio Bridge — Windows

Versión para Windows del bridge de audio noVNC ([repo original](https://github.com/lalbertoeu/novnc-audio)).
Mismo protocolo y mismo cliente web que la versión Linux; cambia **solo la
captura**: en lugar de PulseAudio + `pactl` se captura una tarjeta virtual
**VB-CABLE** con ffmpeg (DirectShow).

```
Windows (VB-CABLE)
        │  ffmpeg (-f dshow -f f32le)
        ▼
audio_server_ws.py :8088  ──WS──►  browser (Web Audio API)
```

## Por qué VB-CABLE

ffmpeg **no tiene captura WASAPI nativa** en Windows (`-f wasapi` no existe;
es una feature request abierta). Para capturar la mezcla del sistema hace
falta una tarjeta virtual expuesta como dispositivo DirectShow. VB-CABLE es
gratis y la opción estándar.

**Limitación conocida**: el pin DirectShow de VB-CABLE está capado a
44.1 kHz / 16-bit independientemente de la configuración del dispositivo.
El servidor remuestrea a `AUDIO_SAMPLE_RATE` (48000) después de capturar, así
que el navegador recibe siempre 48 kHz / float32; la pérdida de calidad queda
en la captura original.

> Alternativa de mayor fidelidad (fuera de este paquete): capturar WASAPI
> loopback de forma nativa en Python (p.ej. `pyaudiowpatch` / `soundcard`) y
> alimentar el servidor con PCM directo, saltando ffmpeg — el enfoque de OBS.

## Requisitos

- **VB-CABLE**: https://vb-audio.com/Cable/ → descarga `vbcable_setup`, instala
  como administrador y **reinicia**.
- **ffmpeg** (build de Windows): https://www.gyan.dev/ffmpeg/builds/ → añade la
  carpeta `bin` al PATH.
- **Python 3** desde python.org → marca *Add python.exe to PATH*.
- `pip install websockets`

## Puesta en marcha

1. Instala VB-CABLE, reinicia, y **listo**: el cable aparece como dos
   dispositivos — *CABLE Input* (reproducción) y *CABLE Output* (captura).
2. **Fija CABLE Input como salida por defecto**: *Configuración de sonido >
   Salida > CABLE Input*. Todo el audio del sistema pasa por el cable.
   (Si quieres seguir oyendo en los altavoces, deja *CABLE Input* como salida
   y usa el mezclador de la tarjeta o configura *Listen to this device* —
   ver sección inferior.)
3. **Arranca el servidor**:

   ```bat
   start_audio.bat
   REM o con configuración explícita:
   set AUDIO_DEVICE=CABLE Output (VB-Audio Virtual Cable)
   set AUDIO_WS_PORT=8088
   start_audio.bat
   ```

4. **Parchea tu noVNC**: añade antes de `</body>` en `vnc.html`

   ```html
   <script src="vnc-audio-client.js"></script>
   ```

   y copia `web/vnc-audio-client.js` junto a `vnc.html`.
5. **Prueba aislada** (sin abrir noVNC): abre `web/testaudio.html`. Debe
   mostrar `CONECTADO ✓` y `Recibiendo audio (N bytes/frame) ✓`.

## Configuración (variables de entorno)

| Variable | Default | Descripción |
|---|---|---|
| `AUDIO_WS_HOST` | `0.0.0.0` | Dirección del WebSocket |
| `AUDIO_WS_PORT` | `8088` | Puerto del WebSocket |
| `AUDIO_SAMPLE_RATE` | `48000` | Frecuencia de salida (ffmpeg remuestrea) |
| `AUDIO_CHANNELS` | `2` | Canales |
| `AUDIO_CHUNK_MS` | `30` | Tamaño de frame en ms |
| `AUDIO_DEVICE` | *(auto)* | Nombre exacto del dispositivo DirectShow |
| `AUDIO_DEVICE_HINT` | `CABLE Output` | Subcadena para auto-detectar el dispositivo |

La auto-detección ejecuta `ffmpeg -list_devices true -f dshow -i dummy` y
elige el primer dispositivo cuyo nombre contenga `AUDIO_DEVICE_HINT`.

## Identificar dispositivo manualmente

```bash
ffmpeg -list_devices true -f dshow -i dummy
# [dshow @ ...] "CABLE Output (VB-Audio Virtual Cable)" ...
# Captura con el nombre exacto: set AUDIO_DEVICE=CABLE Output (VB-Audio Virtual Cable)
```

## Oír localmente mientras transmites

Windows no enruta "todo a la vez" de serie. Soluciones típicas:

1. En *Configuración de sonido > CABLE Input > Propiedades > Escuchar*,
   marca **Listen to this device** y elige tus altavoces. Rápido, pero añade
   latencia.
2. Mezclador externo (VB-Audio ofrece *Voicemeeter*, gratuito) para enrutado
   fino a CABLE + altavoces.
3. Si tu tarjeta expone *Stereo Mix*, puedes capturar esa directamente con
   `AUDIO_DEVICE=Stereo Mix (...)` — depende del driver, no siempre existe.

## Limitaciones y troubleshooting

- **Sin sonido en el navegador**: comprueba que la *salida* por defecto es
  CABLE Input y que la app que reproduce suena (mira el mezclador de Windows).
- **"No se encontró ningún dispositivo"**: VB-CABLE no instalado o no
  reiniciado, o el nombre no coincide (`AUDIO_DEVICE_HINT`).
- **Calidad**: la captura dshow de VB-CABLE está en 44.1 kHz / 16-bit
  (limitación del pin DirectShow, no de este código). Para 48 kHz nativos usa
  la alternativa WASAPI nativa descrita arriba.