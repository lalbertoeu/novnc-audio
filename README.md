# noVNC Audio Bridge

Transmite el **audio del sistema remoto** a tu navegador mientras usas noVNC.
El servidor captura el sink de PulseAudio y lo envía como PCM Float32 por
WebSocket; el navegador lo reproduce con la Web Audio API.

> **Sin IPs ni credenciales en el código.** Todo se configura con variables de
> entorno y el cliente deriva la URL del WebSocket de la propia página.

## Quick path

1. **Instala** dependencias y servicios:

   ```bash
   ./install.sh /ruta/a/tu/fork/de/noVNC
   ```

2. **Parchea `vnc.html`** de tu noVNC: añade justo antes de `</body>`

   ```html
   <script src="vnc-audio-client.js"></script>
   ```

   y copia `web/vnc-audio-client.js` junto a `vnc.html`.

3. **Abre noVNC** en el navegador y haz clic una vez dentro de la página
   (los navegadores exigen un gesto del usuario antes de reproducir audio).

4. **Verifica**:

   ```bash
   systemctl --user status novnc-audio.service    # debe estar Active (running)
   pactl list short sinks                          # distro_sink debe existir
   ```

5. **Prueba el audio suelto** (sin abrir noVNC): abre `web/testaudio.html` en el
   navegador. Debe mostrar `CONECTADO ✓` y `Recibiendo audio (N bytes/frame) ✓`.

## Cómo decide ws:// o wss://

El cliente **no fija un esquema**: lo deriva de cómo cargaste noVNC.

| Serviste noVNC por... | WebSocket del audio |
|---|---|
| `http://...` | `ws://mismo-host:8088` |
| `https://...` | `wss://mismo-host:8088` |

En `web/vnc-audio-client.js`:

```js
const scheme = window.location.protocol === 'https:' ? 'wss' : 'ws';
return scheme + '://' + window.location.hostname + ':' + AUDIO_PORT;
```

El host siempre es el mismo desde el que abres noVNC (`window.location.hostname`).

> ⚠️ **wss:// solo funciona si además hay TLS en el puerto 8088.** Si no tienes
> un proxy con certificado delante de `audio_server_ws.py`, usa `http://` para
> noVNC y el audio irá por `ws://` sin conflictos de mixed-content.

## Configuración (variables de entorno)

| Variable | Default | Descripción |
|---|---|---|
| `AUDIO_SINK` | `distro_sink` | Nombre del null sink de PulseAudio |
| `AUDIO_WS_HOST` | `0.0.0.0` | Dirección donde escucha el WebSocket |
| `AUDIO_WS_PORT` | `8088` | Puerto del WebSocket |
| `AUDIO_SAMPLE_RATE` | `48000` | Hz de captura |
| `AUDIO_CHANNELS` | `2` | Canales |
| `AUDIO_CHUNK_MS` | `30` | Tamaño de frame en ms |

## distro_sink: la tarjeta virtual de audio

**`distro_sink`** es un *null sink* de PulseAudio: una tarjeta de sonido
virtual que no tiene salida física. El servidor de audio captura de su monitor
(`distro_sink.monitor`) todo lo que se envíe ahí, y eso es exactamente lo que
oye el cliente noVNC. Si una app **no** está ruteada a `distro_sink`, su audio
nunca llega al navegador.

> **▶ [Ver la demo en acción (30 s)](docs/demo-audio-novnc.mp4)** — un video de
> animación con sonido: los primeros 14 s el audio va a los altavoces (noVNC
> mudo) y a partir de ahí el stream se mueve a `distro_sink` y **se empieza a
> oír en el navegador**. Es la forma más rápida de entender el routing.
> Detalles al final del README, en [Demo](#demo).

### Montar la tarjeta

```bash
pactl load-module module-null-sink \
    sink_name=distro_sink \
    sink_properties=device.description=DistroSink
```

Idempotente (no falla si ya existe). También lo hace automáticamente el
servicio en cada arranque (`novnc-audio-start.sh`) o con:

```bash
./audio_server/start_virtual_soundcard.sh
```

### Configurarla como sink por defecto

```bash
pactl set-default-sink distro_sink
```

Con esto, **toda app nueva** (video de YouTube, música, etc.) enruta su audio a
`distro_sink` automáticamente y suena en noVNC.

### Conectar streams existentes a la tarjeta

Las apps ya abiertas conservan su sink anterior. Múdelas en caliente:

```bash
# Listar streams de audio activos
pactl list short sink-inputs

# Mover uno concreto a distro_sink (<idx> es la primera columna)
pactl move-sink-input <idx> distro_sink
```

### Verificar el flujo

```bash
pactl list short sinks                # distro_sink debe aparecer como RUNNING
pactl get-default-sink                # debe decir: distro_sink
pactl list short sink-inputs          # el stream de la app debe apuntar a distro_sink
```

> El script `novnc-audio-start.sh` hace los tres pasos (montar → default →
> mover streams) en cada arranque, así no tienes que repetirlo a mano.
> El timer systemd `novnc-audio-restart.timer` lo re-aplica cada 5 min.

## Arquitectura

```
PulseAudio (distro_sink.monitor)
        │  ffmpeg (-f f32le)
        ▼
audio_server_ws.py :8088  ──WS──►  navegador (Web Audio API)
        ▲
     noVNC viewer
```

## Servicios systemd

| Servicio | Puerto | Rol |
|---|---|---|
| `novnc-audio.service` | 8088 | ffmpeg + servidor WebSocket |
| `novnc.service` | 6080 | proxy WebSocket VNC |
| `x11vnc.service` | 5900 | servidor VNC |
| `novnc-audio-restart.timer` | — | reinicia audio cada 5 min |

```bash
systemctl --user status novnc-audio.service
journalctl --user -u novnc-audio.service -f
```

## Dependencias

- ffmpeg
- python3 + `websockets`
- PulseAudio (`pactl`)
- x11vnc
- Fork de noVNC (ver repo `noVNC-audio-fork`)

## Requisitos y limitaciones

- Requiere una sesión gráfica local (GNOME/etc.) con PulseAudio en el servidor.
- El `-ncache` de x11vnc **no es compatible** con noVNC: no lo uses, produce
  una ventana gris. Usa en su lugar `-threads` y X DAMAGE (así viene el
  `x11vnc.service` de este repo).
- Con un compositor de escritorio (GNOME/Mutter, etc.) **quita X DAMAGE**:
  `x11vnc -noxdamage` (ya va así en el `x11vnc.service` de este repo). Con el
  compositor activo, X DAMAGE falla y la pantalla noVNC **se queda congelada**
  (no llega ningún update), aunque Sunshine y otros capturen bien.
- Para reproducción de video fluida, baja *Quality* y sube *Compression* en el
  panel de ajustes de noVNC.

## Demo

▶ [`docs/demo-audio-novnc.mp4`](docs/demo-audio-novnc.mp4) — 30 s: los primeros
14 s sin audio (stream en los altavoces) y de 14 s en adelante con audio
(stream en `distro_sink`).

La pista de audio del video sale de `distro_sink.monitor`, es decir **exactamente
lo que recibe el cliente noVNC** — si el stream no está en `distro_sink`, el
audio del video no existe; cuando lo mueves, suena.

Durante la grabación se ve **pavucontrol en primer plano** mostrando el destino
del stream (altavoces → `distro_sink`), tal como lo vería quien usa noVNC.

### Regenerarla

El video fuente es un **clip de animación generado por ffmpeg** con una melodía
sintetizada: **sin derechos de autor**, 30 s exactos y reproducible de forma
determinista (el clip se crea automáticamente la primera vez, ~23 MB en
`docs/demo-assets/demo-clip.mp4`, excluido de git). Se usa en lugar de un video
de YouTube porque así no hay auto-pausa por foco ni problemas de licencia.

```bash
./docs/grabar_demo.sh docs/demo-audio-novnc.mp4
```

El script abre el clip en el navegador, lo rutea primero a los altavoces
(Fase 1) y a los 14 s lo mueve a `distro_sink` (Fase 2), con pavucontrol
trayéndose al primer plano. Requiere `xdotool`, `ffmpeg` y `python3`.

## Licencia

MIT. El código es independiente de noVNC (MPL-2.0) — ver el repo `noVNC-audio-fork`.