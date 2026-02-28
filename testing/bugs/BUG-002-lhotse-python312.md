# BUG-002 — lhotse incompatible with Python 3.12

| Field | Value |
|-------|-------|
| **Status** | Closed — Patched (manual, re-apply after upgrades) |
| **Date found** | ~2026-01 |
| **Affected component** | `voice-transcribe-server` startup |
| **Symptom** | ImportError or AttributeError at server startup |

## Symptom

```
AttributeError: module 'collections' has no attribute 'Callable'
```

Server fails to start; transcription falls back to slow direct-load path (~11s).

## Root Cause

Python 3.10 removed `collections.Callable` (moved to `collections.abc.Callable`).
lhotse's dataset sampling module still used the old path, causing a crash on
Python 3.12.

**File**: `~/faster-whisper-env/lib/python3.12/site-packages/lhotse/dataset/sampling/base.py`, line 77

## Fix

Patch the file directly:

```python
# Before (broken on 3.10+)
isinstance(x, collections.Callable)

# After
isinstance(x, collections.abc.Callable)
```

Quick one-liner:
```bash
LHOTSE_BASE=~/faster-whisper-env/lib/python3.12/site-packages/lhotse/dataset/sampling/base.py
sed -i 's/collections\.Callable/collections.abc.Callable/g' "$LHOTSE_BASE"
```

## Warning

This patch is **lost if you `pip install --upgrade lhotse`**. Re-run the sed
command after any lhotse upgrade.

Long-term fix: wait for lhotse to release a version with the fix, or pin lhotse
to a version that includes it.

## Files Changed

- Manual patch to venv (not in repo — patch command documented above)
