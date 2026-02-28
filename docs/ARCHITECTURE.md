# Architecture

## Overview

```
Ctrl+Space
    │
    ▼
voice-to-text (bash)          ← toggle script
    ├── setup_audio()          ← switch BT to HFP, set default source
    ├── start_sco_keepalive()  ← play silence to BT sink (keeps SCO alive)
    ├── voice-recorder-daemon  ← launched via nohup, records until SIGTERM
    │       └── sounddevice RawInputStream → callback → queue → WAV file
    │
    └── [on stop]
        ├── stop_sco_keepalive()
        ├── voice-transcribe-engine  ← sends WAV path to server
        │       └── Unix socket → voice-transcribe-server
        │               └── model.transcribe([wav_file]) → text
        ├── wl-copy + ydotool key ctrl+shift+v  ← paste to active window
        └── restore_audio()    ← restore BT to A2DP profile
```

## Key Components

### `voice-to-text` (bash)
The toggle script. Invoked on every Ctrl+Space press.
- **Start press**: sets up audio, launches recorder as background daemon
- **Stop press**: kills recorder, invokes transcription engine, pastes result

State machine is simple: if PID file exists and process is alive → stop mode;
otherwise → start mode.

### `voice-recorder-daemon` (Python)
Captures audio with zero loss using `sounddevice`'s callback API.

**Why not `parec` or `ffmpeg`?** They buffer aggressively and lose the last
frames when killed. sounddevice's callback → queue → WAV approach captures
every block and drains the queue cleanly on SIGTERM.

**BT dropout detection**: monitors for consecutive zero-frame blocks after
speech has started. If 1.5 continuous seconds of zeros arrive, writes
`/tmp/voice-to-text.dropout` and self-stops.

### `voice-transcribe-server` (Python)
Persistent process that keeps the Parakeet TDT model loaded in GPU VRAM.
Listens on a Unix socket (`/tmp/voice-transcribe.sock`).

**Why persistent?** Model load time is ~11s. Keeping it loaded means each
transcription takes ~0.2s instead.

Managed by systemd: `~/.config/systemd/user/voice-transcribe-server.service`

### `voice-transcribe-engine` (Python)
Thin client. Sends the WAV file path over the Unix socket, reads back the
transcribed text. If the server is not running, starts it (first use is slow).
Falls back to Whisper (CPU) if Parakeet is unavailable.

## Audio Pipeline Detail

```
Bluetooth Headset (HFP/mSBC)
    │  SCO link (bidirectional — CRITICAL)
    │  ← silence from pacat keepalive (keeps SCO alive)
    │  → mic audio via bluez_input source
    │
PipeWire → ALSA bridge
    │
sounddevice RawInputStream (16kHz, mono, int16, 50ms blocks)
    │
callback() → Queue → WAV writer thread
    │
/tmp/voice-to-text-recording.wav
    │
voice-transcribe-server (Parakeet TDT 0.6B v3 on GPU)
    │
transcribed text → clipboard → ydotool paste
```

## Audio Profile Management

The Bluetooth headset has two profiles:
- **A2DP**: high-quality stereo playback, no mic
- **HFP/mSBC**: lower-quality mono, but provides bidirectional mic+earpiece

The script temporarily switches to HFP for recording, then restores A2DP.
If A2DP was active before (music playing), the user will briefly lose music
quality during recording — this is expected.

## Paste Mechanism

**GNOME Wayland constraint**: most synthetic input tools are blocked by the
compositor. `ydotool` bypasses this using the kernel's `uinput` subsystem.

Ctrl+Shift+V is used (not Ctrl+V) because:
- Standard terminals intercept Ctrl+V as a literal character
- Ctrl+Shift+V is recognized by all GNOME apps as "paste from clipboard"

## File Layout

```
/tmp/
  voice-to-text.pid               ← recorder daemon PID (exists while recording)
  voice-to-text.log               ← current session log (ephemeral)
  voice-to-text.ready             ← signal: daemon has started stream
  voice-to-text.dropout           ← signal: BT dropout detected by daemon
  voice-to-text-sco-keepalive.pid ← pacat keepalive PID
  voice-to-text-recording.wav     ← current recording (deleted after transcription)
  voice-to-text-last.wav          ← copy of last recording (kept for debugging)
  voice-to-text-bt-state          ← saved BT profile/source for restore
  voice-transcribe.sock           ← Unix socket for server communication
  voice-transcribe-server.pid     ← server PID
  voice-transcribe-server.log     ← server log

~/voice-to-text/logs/
  YYYY-MM-DD.log                  ← persistent daily log (survives reboots)
```
