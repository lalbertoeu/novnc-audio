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
- Para reproducción de video fluida, baja *Quality* y sube *Compression* en el
  panel de ajustes de noVNC.

## Licencia

MIT. El código es independiente de noVNC (MPL-2.0) — ver el repo `noVNC-audio-fork`.