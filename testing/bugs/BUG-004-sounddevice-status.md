# BUG-004 — sounddevice callback errors silently ignored

| Field | Value |
|-------|-------|
| **Status** | Closed — Fixed |
| **Date found** | 2026-02-28 |
| **Affected component** | `src/voice-recorder-daemon` |
| **Symptom** | Audio overflows/underflows produce no log output |

## Symptom

When the audio buffer has issues (overflow, underflow, device error), the recording
continues silently with no indication anything went wrong. Impossible to distinguish
a clean recording from one with dropped frames just by looking at the log.

## Root Cause

The `sounddevice` callback signature includes a `status` parameter that carries
error flags. The original callback ignored it completely:

```python
def callback(indata, frames, time_info, status):
    audio_queue.put(bytes(indata))  # status never checked
```

## Fix

Log the status if non-zero:

```python
def callback(indata, frames, time_info, status):
    if status:
        with open("/tmp/voice-to-text.log", "a") as f:
            f.write(f"[recorder] sounddevice status error: {status}\n")
    audio_queue.put(bytes(indata))
```

## What the Status Codes Mean

| Status flag | Meaning |
|-------------|---------|
| `input_overflow` | CPU too slow to process audio — frames dropped |
| `input_underflow` | No input data available — silence inserted |
| `priming_output` | Not an error, just initial state |

## Files Changed

- `src/voice-recorder-daemon`: callback now logs non-zero status to log file
