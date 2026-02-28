# BUG-001 — Paste fails in GNOME Wayland

| Field | Value |
|-------|-------|
| **Status** | Closed — Fixed |
| **Date found** | ~2025-12 |
| **Affected component** | `src/voice-to-text` — paste step |
| **Symptom** | Transcribed text is not pasted into the active window |

## Symptom

After transcription, the text was copied to clipboard but never appeared in the
active window. Various synthetic-input tools were tried.

## Root Cause

GNOME Wayland's security model blocks synthetic keyboard input from most tools.
`xdotool` only works under X11. `wtype` is Wayland-native but blocked by GNOME's
compositor security policy. Neither can inject keystrokes into other apps.

## Solution

Use `ydotool` — it operates at the kernel level via `/dev/uinput`, bypassing the
compositor entirely. Requires the `/dev/uinput` device to be accessible by the user.

```bash
# One-time setup: give user access to uinput
sudo setfacl -m u:$USER:rw /dev/uinput
# (or add udev rule for persistence)
```

Then in `voice-to-text`:
```bash
ydotool key ctrl+shift+v
```

`Ctrl+Shift+V` (not `Ctrl+V`) is used because terminals intercept `Ctrl+V` as a
literal character — `Ctrl+Shift+V` is the universal paste in all GNOME apps
including terminals.

## Non-Solutions Tried

| Tool | Why it failed |
|------|--------------|
| `xdotool key ctrl+v` | X11 only — no-op under Wayland |
| `wtype -k ctrl+v` | Wayland-native but GNOME blocks external compositor clients |
| `xdg-clipboard` tricks | Clipboard access only, no keystroke injection |

## Files Changed

- `src/voice-to-text`: paste line changed to `ydotool key ctrl+shift+v`
