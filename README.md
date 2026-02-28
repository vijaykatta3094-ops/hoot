<p align="center">
  <img src="logo.png" width="380" alt="Hoot logo"/>
</p>

# Hoot

> Push-to-talk voice transcription for Linux. Press a hotkey to start recording, press again to stop — transcribed text is instantly pasted into any active window.

**Status**: Alpha — works daily on GNOME Wayland + NVIDIA RTX 5090. Not yet packaged for general distribution (see [Roadmap](ROADMAP.md)).

---

## How It Works

1. Press **Ctrl+Space** → recording starts (notification confirms)
2. Speak naturally
3. Press **Ctrl+Space** again → recording stops, text is transcribed and pasted

First transcription after boot: ~10-15s (model loading). All subsequent: **~0.2s**.

---

## Engines

| Engine | Speed | GPU Required | Notes |
|--------|-------|-------------|-------|
| **Parakeet TDT 0.6B v3** (default) | ~0.2s | Yes (NVIDIA) | Best accuracy, English-only |
| **Whisper base** (fallback) | ~5-15s | No | Multilingual, CPU int8 |

Switch engine: `VOICE_ENGINE=whisper ~/bin/voice-to-text`

---

## Requirements

- Linux + PipeWire audio (Ubuntu 22.04+, Fedora 38+)
- GNOME Wayland (tested) — KDE Wayland and X11 untested
- NVIDIA GPU for Parakeet (CPU fallback available)
- `ydotool`, `wl-clipboard`, `pactl`, `notify-send`

Full details: [docs/REQUIREMENTS.md](docs/REQUIREMENTS.md)

---

## Installation

```bash
git clone https://github.com/vijaykatta3094-ops/hoot
cd hoot
bash install.sh
```

Then follow the printed next-steps (Python env + model download + keyboard shortcut).

---

## Project Structure

```
hoot/
├── README.md          ← you are here
├── CHANGELOG.md       ← what changed and when
├── ROADMAP.md         ← future plans
├── install.sh         ← installer
├── logo.png           ← project logo
│
├── src/               ← all source scripts
│   ├── voice-to-text              # main toggle (bash)
│   ├── voice-recorder-daemon      # audio capture (python)
│   ├── voice-transcribe-engine    # transcription client (python)
│   ├── voice-transcribe-server    # persistent model server (python)
│   └── transcribe                 # CLI file transcription tool
│
├── systemd/
│   └── voice-transcribe-server.service
│
├── docs/
│   ├── REQUIREMENTS.md    ← hardware/software requirements
│   ├── ARCHITECTURE.md    ← how it works, design decisions
│   ├── SETUP.md           ← detailed installation guide
│   └── TROUBLESHOOTING.md ← common issues
│
├── branding/archive/  ← SVG logo explorations (archived)
│
└── testing/
    ├── README.md          ← debug checklist
    ├── bugs/              ← one file per known bug (index: testing/bugs/README.md)
    ├── scripts/           ← diagnostic tools (analyze-audio.py, check-system.sh)
    └── logs/              ← log format guide + reference samples
```

---

## Debugging

```bash
# System health check
bash testing/scripts/check-system.sh

# Analyze last recording for BT dropouts
python3 testing/scripts/analyze-audio.py /tmp/voice-to-text-last.wav

# Today's persistent log
cat ~/voice-to-text/logs/$(date +%Y-%m-%d).log

# Known bugs index
cat testing/bugs/README.md
```

---

## Known Issues

See [testing/bugs/README.md](testing/bugs/README.md) for the full index.

| Bug | Status |
|-----|--------|
| BT HFP SCO dropout (audio cuts after 3-5s) | ✅ Fixed 2026-02-28 |
| CUDA graphs crash on RTX 5090 + PyTorch nightly | ✅ Fixed (workaround) |
| lhotse incompatible with Python 3.12 | ✅ Fixed (manual patch) |
| Paste fails on GNOME Wayland | ✅ Fixed (ydotool) |

---

## Architecture

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the full pipeline diagram and design decisions.

---

## Roadmap

See [ROADMAP.md](ROADMAP.md) — short-term stability fixes, medium-term UX improvements, and long-term public Linux distribution plans.
