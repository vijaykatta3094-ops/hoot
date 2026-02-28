# Changelog

All significant changes documented here. Format: `[date] — description (BUG-NNN)`

---

## 2026-02-28

### Fixed
- **BT HFP SCO link drops mid-recording** (BUG-005)
  - Added `start_sco_keepalive()` — plays silence to BT HFP earpiece sink during
    recording to maintain bidirectional SCO link. Without this, headsets drop the
    SCO link after ~3-5s (no earpiece audio → assumes call ended).
  - Added dropout detection in `voice-recorder-daemon` — 1.5s of consecutive
    zero frames after speech = BT dropped; writes dropout marker and self-stops.
  - Fixed toggle logic: dead daemon + PID file now triggers transcription of
    partial audio instead of starting a new recording.

### Fixed
- **sounddevice callback errors silently ignored** (BUG-004)
  - `voice-recorder-daemon` now logs non-zero `status` from sounddevice callback
    (previously all errors were invisible in the log).

### Added
- **Persistent daily logging** — every invocation now writes to both
  `/tmp/voice-to-text.log` (ephemeral) and `~/voice-to-text/logs/YYYY-MM-DD.log`
  (survives reboots). Enables pattern analysis across sessions.

---

## 2026-01

### Fixed
- **CUDA graph decoder crashes on RTX 5090 + PyTorch nightly** (BUG-003)
  - Disabled `use_cuda_graph_decoder` after model load in both server and
    direct-load fallback paths.

### Fixed
- **lhotse incompatible with Python 3.12** (BUG-002)
  - Manual patch: `collections.Callable` → `collections.abc.Callable` in
    `lhotse/dataset/sampling/base.py` line 77.

---

## 2025-12

### Added
- Initial implementation: push-to-talk voice transcription for GNOME Wayland
- Parakeet TDT 0.6B v3 as primary engine (GPU, ~0.2s)
- faster-whisper as CPU fallback
- Persistent model server via systemd for instant transcription
- Bluetooth HFP/mSBC mic support with profile auto-switching

### Fixed
- **Paste fails in GNOME Wayland** (BUG-001)
  - Switched from `xdotool`/`wtype` to `ydotool` (kernel-level uinput).
  - Changed from Ctrl+V to Ctrl+Shift+V for terminal compatibility.
