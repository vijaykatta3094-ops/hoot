# Testing & Debugging

This directory contains everything needed to diagnose, reproduce, and verify
bugs in the voice-to-text tool.

## Directory Structure

```
testing/
├── bugs/           ← one file per known bug (index in bugs/README.md)
├── scripts/        ← diagnostic and test helper scripts
└── logs/
    ├── README.md   ← how to read logs, key patterns to look for
    └── samples/    ← reference log snippets showing known failure modes
```

## Quick Debug Checklist

Run these in order when something seems wrong:

```bash
# 1. Check server health
systemctl --user status voice-transcribe-server

# 2. Check today's persistent log for patterns
cat ~/voice-to-text/logs/$(date +%Y-%m-%d).log

# 3. Check if BT mic is active and not muted
pactl get-source-mute @DEFAULT_SOURCE@
pactl get-source-volume @DEFAULT_SOURCE@
pactl info | grep "Default Source"

# 4. Analyze last recording for dropouts
python3 ~/voice-to-text/testing/scripts/analyze-audio.py /tmp/voice-to-text-last.wav

# 5. Full system health check
bash ~/voice-to-text/testing/scripts/check-system.sh
```

## After a Bug Session

1. Check `testing/bugs/README.md` — was this a known root cause?
2. If new: create `testing/bugs/BUG-NNN-title.md`, update the index
3. Commit: `git add -A && git commit -m "bug: document BUG-NNN"`
4. If fixed: update status in bug file and add commit reference
5. Sync `src/` from `~/bin/`: `cp ~/bin/voice-* ~/voice-to-text/src/`

## Log Locations

| Log | Location | Persists? |
|-----|----------|-----------|
| Current session | `/tmp/voice-to-text.log` | No (cleared on reboot) |
| Daily persistent | `~/voice-to-text/logs/YYYY-MM-DD.log` | Yes |
| Server log | `/tmp/voice-transcribe-server.log` | No |
| Last recording | `/tmp/voice-to-text-last.wav` | Until next recording |
