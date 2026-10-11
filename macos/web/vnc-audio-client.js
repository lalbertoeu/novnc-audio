/* noVNC Audio Bridge - client side
 *
 * Reproduce el audio de la máquina remota (capturado por audio_server_ws.py)
 * en el navegador usando la Web Audio API.
 *
 * Este cliente del kit macOS usa SIEMPRE wss:// porque tanto la página noVNC
 * como el bridge de audio se sirven por HTTPS/TLS (certificado auto-firmado).
 * Si quisieras volver a servir por HTTP, cambia audioWsUrl() a la derivación
 * por protocolo:  const scheme = window.location.protocol === 'https:' ? 'wss' : 'ws';
 *
 * El host se toma de window.location.hostname (el mismo desde donde abres noVNC).
 * Solo edita el PUERTO si cambiaste AudioAudioWS_PORT en el servidor.
 */

(function () {
    'use strict';

    const AUDIO_PORT = 8088;

    let audioCtx = null;
    let gainNode = null;
    let ws = null;
    let nextPlayTime = 0;
    let started = false;

    function audioWsUrl() {
        // Kit macOS: el bridge de audio SIEMPRE corre con TLS (wss), igual que
        // la página (HTTPS con certificado auto-firmado). Ver cabecera del archivo.
        const scheme = 'wss';
        return scheme + '://' + window.location.hostname + ':' + AUDIO_PORT;
    }

    function startAudio() {
        audioCtx = new (window.AudioContext || window.webkitAudioContext)();
        gainNode = audioCtx.createGain();
        gainNode.connect(audioCtx.destination);
        connectWebSocket();
    }

    function connectWebSocket() {
        ws = new WebSocket(audioWsUrl());
        ws.binaryType = 'arraybuffer';

        ws.onopen = () => console.log('[audio] WebSocket conectado:', audioWsUrl());

        ws.onmessage = (event) => {
            const floatArray = new Float32Array(event.data);
            const numChannels = 2;
            const sampleRate = audioCtx.sampleRate;
            const frameCount = floatArray.length / numChannels;

            const audioBuffer = audioCtx.createBuffer(numChannels, frameCount, sampleRate);

            for (let ch = 0; ch < numChannels; ch++) {
                const channelData = audioBuffer.getChannelData(ch);
                for (let i = 0; i < frameCount; i++) {
                    channelData[i] = floatArray[i * numChannels + ch];
                }
            }

            const source = audioCtx.createBufferSource();
            source.buffer = audioBuffer;
            source.connect(gainNode);

            if (nextPlayTime < audioCtx.currentTime + 0.05) {
                nextPlayTime = audioCtx.currentTime + 0.05;
            }
            source.start(nextPlayTime);
            nextPlayTime += audioBuffer.duration;
        };

        ws.onclose = (e) => {
            console.log('[audio] WebSocket cerrado, reconectando en 2s...', e.code, e.reason);
            setTimeout(connectWebSocket, 2000);
        };

        ws.onerror = (err) => {
            console.error('[audio] Error WebSocket', err);
            ws.close();
        };
    }

    // Control de volumen (exponer en window para debug o UI)
    window.setAudioVolume = (v) => {
        if (gainNode) gainNode.gain.value = v;
    };
    window.muteAudio = (m) => {
        if (gainNode) gainNode.gain.value = m ? 0 : 1;
    };

    // AudioContext requiere un gesto del usuario (política del navegador)
    window.addEventListener('click', () => {
        if (!started) {
            started = true;
            startAudio();
        }
    }, { once: true });

    console.log('[audio] Cliente listo. Audio por wss:// (HTTPS + certificado auto-firmado)');
})();