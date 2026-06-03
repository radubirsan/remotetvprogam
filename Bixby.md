# Samsung TV Voice (Bixby) — Send Audio Over LAN

Protocol for streaming microphone audio to a Samsung Tizen TV's voice assistant
over its already-open remote-control WebSocket (`.../channels/samsung.remote.control`).

**Precondition:** you already have an open, authenticated WebSocket to the TV
(`wss://<TV-IP>:8002/api/v2/channels/samsung.remote.control?name=<base64name>&token=<token>`,
TLS with the TV's self-signed cert accepted). This document starts *after* that
connection is established.

All messages below are sent on that same WebSocket. Text steps are UTF-8 JSON
text frames; audio is sent as binary frames.

---

## Step 1 — Press the voice (mic) key

Send two **text** frames: a Press then a Release.

```json
{"method":"ms.remote.control","params":{"Cmd":"Press","TypeOfRemote":"SendRemoteKey","DataOfCmd":"KEY_BT_VOICE","Option":false}}
```
```json
{"method":"ms.remote.control","params":{"Cmd":"Release","TypeOfRemote":"SendRemoteKey","DataOfCmd":"KEY_BT_VOICE","Option":false}}
```

## Step 2 — Wait for the TV to start listening

The TV sends a **text** frame:

```json
{"event":"ms.voiceApp.recording"}
```

Begin streaming audio only after receiving this.

## Step 3 — Stream microphone audio as binary frames

**Audio format:** raw PCM, signed 16-bit little-endian, **mono**, **16000 Hz**.

Split the PCM into chunks (~14 KB each works; ~0.45 s of audio) and send each
chunk as one **binary** WebSocket frame with this layout:

```
┌──────────────┬──────────────────────────────┬───────────────────┐
│ 2 bytes      │ JSON header (header_len bytes)│ raw PCM audio      │
│ uint16 BE    │ (UTF-8, exactly the string    │ chunk (16-bit LE,  │
│ = header_len │  below = 84 bytes)            │  mono, 16 kHz)     │
└──────────────┴──────────────────────────────┴───────────────────┘
```

- Bytes 0–1: big-endian uint16 = length of the JSON header that follows (84).
- Next `header_len` bytes: the UTF-8 JSON header string:
  ```json
  {"method":"ms.voice.control","params":{"to":"broadcast","event":"ms.voice.control"}}
  ```
- Remaining bytes: the raw PCM audio chunk.

Send these binary frames continuously for the duration of the spoken command.

## Step 4 — End of utterance

Send one final binary frame built the same way (same 2-byte length + same JSON
header) but with a tiny/empty audio payload (e.g. 4 zero bytes) to mark the end
of the audio stream.

Optionally toggle the mic off by repeating Step 1 (another `KEY_BT_VOICE`
Press + Release).

## Step 5 — TV finishes

The TV emits:

```json
{"event":"ms.voiceApp.hide"}
```

---

## Frame-builder pseudocode

```
HEADER = '{"method":"ms.voice.control","params":{"to":"broadcast","event":"ms.voice.control"}}'
hbytes = utf8(HEADER)                 # 84 bytes
prefix = uint16_be(len(hbytes))       # 0x00 0x54

function voiceFrame(pcmChunk):
    return prefix + hbytes + pcmChunk  # send as ONE binary websocket frame

# usage:
send_text(pressJSON); send_text(releaseJSON)
wait_for_text_event("ms.voiceApp.recording")
for chunk in split(pcm16k_mono_s16le, ~14000):
    send_binary(voiceFrame(chunk))
send_binary(voiceFrame(b"\x00\x00\x00\x00"))   # end marker
```
