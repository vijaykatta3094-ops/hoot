# Bug Index

All known bugs, their status, and root cause summary.
Each bug has a dedicated file with full diagnosis, root cause, and fix.

## Summary Table

| ID | Title | Status | Component | Date |
|----|-------|--------|-----------|------|
| [BUG-001](BUG-001-paste-wayland.md) | Paste fails in GNOME Wayland | ✅ Fixed | `voice-to-text` | 2025-12 |
| [BUG-002](BUG-002-lhotse-python312.md) | lhotse incompatible with Python 3.12 | ✅ Fixed (manual patch) | `voice-transcribe-server` | 2026-01 |
| [BUG-003](BUG-003-cuda-graphs.md) | CUDA graph decoder crashes on PyTorch nightly + RTX 5090 | ✅ Fixed (workaround) | `voice-transcribe-server` | 2026-01 |
| [BUG-004](BUG-004-sounddevice-status.md) | sounddevice callback errors silently ignored | ✅ Fixed | `voice-recorder-daemon` | 2026-02-28 |
| [BUG-005](BUG-005-bt-sco-dropout.md) | Bluetooth HFP SCO link drops mid-recording | ✅ Fixed | `voice-to-text`, `voice-recorder-daemon` | 2026-02-28 |

## Open / Suspected

| ID | Title | Status |
|----|-------|--------|
| SUSPECTED-001 | Parakeet may fail on very long (4+ min) audio | Unconfirmed — test after BUG-005 fix |
| SUSPECTED-002 | WirePlumber 5s idle node suspension during recording | Unconfirmed — likely resolved by BUG-005 keepalive |

## Adding a New Bug

1. Create `BUG-NNN-short-title.md` in this folder using the template below
2. Add a row to the summary table above
3. Commit with message: `bug: document BUG-NNN — short title`

### Template

```markdown
# BUG-NNN — Title

| Field | Value |
|-------|-------|
| **Status** | Open / Closed — Fixed / Closed — Workaround |
| **Date found** | YYYY-MM-DD |
| **Affected component** | src/script-name |
| **Symptom** | One-line user-visible description |

## Symptom
## Root Cause
## Fix
## Files Changed
```
