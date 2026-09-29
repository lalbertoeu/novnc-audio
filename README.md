# noVNC Audio Bridge

> **[English](README.md) · [Español](README.es.md)**

Streams the **remote system's audio** to your browser while you use noVNC.
The server captures the PulseAudio sink and streams it as Float32 PCM over a
WebSocket; the browser plays it back with the Web Audio API.

> **No IPs or credentials in the code.** Everything is configured through
> environment variables, and the client derives the WebSocket URL from the page
> it is served from.

## Quick start

1. **Install** dependencies and services:

   ```bash
   ./install.sh /path/to/your/noVNC/fork
   ```

2. **Patch your noVNC `vnc.html`**: add right before `</body>`

   ```html
   <script src="vnc-audio-client.js"></script>
   ```

   and copy `web/vnc-audio-client.js` next to `vnc.html`.

3. **Open noVNC** in the browser and click once inside the page
   (browsers require a user gesture before playing audio).

4. **Verify**:

   ```bash
   systemctl --user status novnc-audio.service    # must be Active (running)
   pactl list short sinks                          # distro_sink must exist
   ```

5. **Test the audio on its own** (without opening noVNC): open
   `web/testaudio.html` in the browser. It should show `CONECTADO ✓` and
   `Recibiendo audio (N bytes/frame) ✓`.

## How it picks ws:// or wss://

The client **does not hardcode a scheme**: it derives it from how you loaded noVNC.

| You served noVNC over... | Audio WebSocket |
|---|---|
| `http://...` | `ws://same-host:8088` |
| `https://...` | `wss://same-host:8088` |

In `web/vnc-audio-client.js`:

```js
const scheme = window.location.protocol === 'https:' ? 'wss' : 'ws';
return scheme + '://' + window.location.hostname + ':' + AUDIO_PORT;
```

The host is always the one you loaded noVNC from (`window.location.hostname`).

> ⚠️ **wss:// only works if there is also TLS on port 8088.** If you don't have a
> proxy with a certificate in front of `audio_server_ws.py`, serve noVNC over
> `http://` and the audio will go over `ws://` with no mixed-content conflicts.

## Configuration (environment variables)

| Variable | Default | Description |
|---|---|---|
| `AUDIO_SINK` | `distro_sink` | Name of the PulseAudio null sink |
| `AUDIO_WS_HOST` | `0.0.0.0` | Address the WebSocket listens on |
| `AUDIO_WS_PORT` | `8088` | WebSocket port |
| `AUDIO_SAMPLE_RATE` | `48000` | Capture rate in Hz |
| `AUDIO_CHANNELS` | `2` | Channels |
| `AUDIO_CHUNK_MS` | `30` | Frame size in ms |

## distro_sink: the virtual sound card

**`distro_sink`** is a PulseAudio *null sink*: a virtual sound card with no
physical output. The audio server captures from its monitor
(`distro_sink.monitor`) everything sent there, and that is exactly what the
noVNC client hears. If an app is **not** routed to `distro_sink`, its audio
never reaches the browser.

> **▶ [Watch the demo in action (30 s)](docs/demo-audio-novnc.mp4)** — an
> animation clip with sound: for the first 14 s the audio goes to the speakers
> (noVNC is silent), and from then on the stream is moved to `distro_sink` and
> **you start hearing it in the browser**. The fastest way to understand the
> routing. More details at the end of this README, in [Demo](#demo).

### Mount the card

```bash
pactl load-module module-null-sink \
    sink_name=distro_sink \
    sink_properties=device.description=DistroSink
```

Idempotent (it does not fail if it already exists). The service also does this
automatically on every start (`novnc-audio-start.sh`), or you can run:

```bash
./audio_server/start_virtual_soundcard.sh
```

### Set it as the default sink

```bash
pactl set-default-sink distro_sink
```

With this, **every new app** (video playback, music, etc.) routes its audio to
`distro_sink` automatically and is heard in noVNC.

### Connect existing streams to the card

Apps that are already open keep their previous sink. Move them on the fly:

```bash
# List active audio streams
pactl list short sink-inputs

# Move one to distro_sink (<idx> is the first column)
pactl move-sink-input <idx> distro_sink
```

### Verify the flow

```bash
pactl list short sinks                # distro_sink should show up as RUNNING
pactl get-default-sink                # should say: distro_sink
pactl list short sink-inputs          # the app's stream should point to distro_sink
```

> The `novnc-audio-start.sh` script does all three steps (mount → default →
> move streams) on every start, so you do not have to repeat them by hand.
> The `novnc-audio-restart.timer` systemd timer re-applies them every 5 min.

## Architecture

```
PulseAudio (distro_sink.monitor)
        │  ffmpeg (-f f32le)
        ▼
audio_server_ws.py :8088  ──WS──►  browser (Web Audio API)
        ▲
     noVNC viewer
```

## systemd services

| Service | Port | Role |
|---|---|---|
| `novnc-audio.service` | 8088 | ffmpeg + WebSocket server |
| `novnc.service` | 6080 | VNC WebSocket proxy |
| `x11vnc.service` | 5900 | VNC server |
| `novnc-audio-restart.timer` | — | restarts audio every 5 min |

```bash
systemctl --user status novnc-audio.service
journalctl --user -u novnc-audio.service -f
```

## Dependencies

- ffmpeg
- python3 + `websockets`
- PulseAudio (`pactl`)
- x11vnc
- A noVNC fork (see the `noVNC-audio-fork` repo)

## Requirements and limitations

- Requires a local graphical session (GNOME/etc.) with PulseAudio on the server.
- x11vnc's `-ncache` is **not compatible** with noVNC: do not use it, it
  produces a grey window. Use `-threads` instead (as in this repo's
  `x11vnc.service`).
- With a desktop compositor (GNOME/Mutter, etc.) **disable X DAMAGE**:
  `x11vnc -noxdamage` (already set in this repo's `x11vnc.service`). With the
  compositor active, X DAMAGE fails and the noVNC screen **freezes** (no
  updates get through), even though Sunshine and other capture tools work fine.
- For smooth video playback, lower *Quality* and raise *Compression* in the
  noVNC settings panel.

## Demo

▶ [`docs/demo-audio-novnc.mp4`](docs/demo-audio-novnc.mp4) — 30 s: the first
14 s without audio (stream on the speakers), and from 14 s on with audio (stream
on `distro_sink`).

The video's audio track comes from `distro_sink.monitor` — that is **exactly
what the noVNC client receives**. If the stream is not on `distro_sink`, the
video's audio does not exist; when you move it, you hear it.

During the recording you can see **pavucontrol in the foreground** showing the
stream's destination (speakers → `distro_sink`), just as someone using noVNC
would see it.

### Regenerating it

The source video is an **animation clip generated by ffmpeg** with a synthesized
melody: **no copyright**, exactly 30 s, and deterministically reproducible (the
clip is created automatically the first time, ~23 MB at
`docs/demo-assets/demo-clip.mp4`, excluded from git). It is used instead of a
YouTube video so there is no focus auto-pause and no licensing issue.

```bash
./docs/grabar_demo.sh docs/demo-audio-novnc.mp4
```

The script opens the clip in the browser, routes it to the speakers first
(Phase 1) and at 14 s moves it to `distro_sink` (Phase 2), bringing pavucontrol
to the foreground. Requires `xdotool`, `ffmpeg` and `python3`.

## License

MIT. The code is independent from noVNC (MPL-2.0) — see the
`noVNC-audio-fork` repo.
