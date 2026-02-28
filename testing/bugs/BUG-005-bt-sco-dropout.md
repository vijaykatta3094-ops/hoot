# BUG-005 — Bluetooth HFP SCO link drops mid-recording

| Field | Value |
|-------|-------|
| **Status** | Closed — Fixed (2026-02-28) |
| **Date found** | 2026-02-28 |
| **Affected component** | `src/voice-to-text`, `src/voice-recorder-daemon` |
| **Symptom** | Transcription cuts off mid-sentence; long recordings return empty |

## Symptom

- Recording a sentence produces only the first 2–4 seconds of speech
- Long recordings (4+ minutes) sometimes return "No speech detected"
- `voice-to-text.log` shows: `Transcribed text: [So I think we previously built uh]`
  — speech clearly cut off mid-word

## Diagnosis

Analyzed `/tmp/voice-to-text-last.wav` in 250ms amplitude chunks:

```
0.00s-0.25s: max=    0 avg=   0.0  [ SILENCE ]   ← waiting for speech
0.75s-1.00s: max= 8569 avg= 594.8  speech?
1.00s-1.25s: max= 5519 avg= 923.2  speech?
...
3.25s-3.50s: max= 4246 avg= 103.5  quiet
3.50s-3.75s: max=    0 avg=   0.0  [ SILENCE ]   ← BT DROPPED HERE
4.00s-4.25s: max=    0 avg=   0.0  [ SILENCE ]
...
13.00s-13.50s: max=   0 avg=   0.0  [ SILENCE ]  ← zeros for 10+ seconds
```

Key observation: **exact zeros**, not background noise. Zero bytes = the audio
source disconnected, not just quiet. sounddevice via ALSA/PipeWire bridge
returns zeros when the underlying audio source goes away — no error, no warning.

## Root Cause

Bluetooth HFP uses a **SCO (Synchronous Connection Oriented) link** for
bidirectional audio. BT headsets maintain this link only as long as **both
directions** are active. When only the mic is recording and nothing plays
back to the earpiece, the headset concludes the "call" ended and drops the
SCO link after ~3–5 seconds.

Once the SCO link drops:
- `bluez_input` source still exists in PipeWire
- sounddevice ALSA stream stays open
- But all frames are zeros — the hardware is gone

### Why `sounddevice` gives no error

`sounddevice` uses PortAudio → ALSA → PipeWire-ALSA bridge. When the BT node
loses its underlying SCO connection, PipeWire provides silence (zeros) to the
ALSA client rather than raising an error. This is intentional PipeWire behavior
to avoid crashing ALSA clients.

## Fix

Three changes:

### 1. SCO keepalive in `voice-to-text`
Play silence to the BT HFP earpiece sink during recording to maintain
bidirectional SCO link:

```bash
start_sco_keepalive() {
    BT_SINK=$(pactl list sinks short | grep "bluez_output" | grep -v "monitor" | awk '{print $2}' | head -1)
    if [ -n "$BT_SINK" ]; then
        cat /dev/zero | pacat --playback --device="$BT_SINK" \
            --channels=1 --rate=16000 --format=s16le 2>/dev/null &
        echo $! > /tmp/voice-to-text-sco-keepalive.pid
    fi
}
```

Called after `setup_audio()`, killed in `restore_audio()` before profile restore.

### 2. Dropout detection in `voice-recorder-daemon`
Detect consecutive zero frames after speech has started:

```python
ZERO_BLOCK_DROPOUT_THRESHOLD = 30  # 30 × 50ms = 1.5s of zeros after speech

def callback(indata, frames, time_info, status):
    data = bytes(indata)
    if all(b == 0 for b in data):
        consecutive_zero_blocks[0] += 1
        if had_speech[0] and consecutive_zero_blocks[0] >= ZERO_BLOCK_DROPOUT_THRESHOLD:
            open(DROPOUT_FILE, "w").write("BT dropout detected")
            stopped.set()   # stop recording early
            return
    else:
        consecutive_zero_blocks[0] = 0
        had_speech[0] = True
    audio_queue.put(data)
```

### 3. Stale PID handling in `voice-to-text`
If daemon self-stopped due to dropout (dead PID but file + dropout marker exist),
next Ctrl+Space transcribes partial audio instead of starting a new recording:

```bash
elif [ -f "$PIDFILE" ] && { [ -f /tmp/voice-to-text.dropout ] || [ -f "$AUDIO_FILE" ]; }; then
    log "Daemon died early (BT dropout?), transcribing partial audio"
    stop_and_transcribe
```

## How to Verify Fix Is Working

Check the log after a recording session:
```
grep "SCO keepalive" ~/voice-to-text/logs/$(date +%Y-%m-%d).log
```
Should show: `SCO keepalive started (sink=bluez_output.XX_XX_XX_XX_XX_XX.1)`

And the audio should now have speech throughout instead of zeros after 3.5s.

## Related / Still Open

- **SUSPECTED-001**: Very long (4+ min) recordings may produce empty Parakeet
  transcription even when audio is good. Now that BUG-005 is fixed, genuine
  long recordings can be tested to confirm or close SUSPECTED-001.
- **SUSPECTED-002**: WirePlumber's 5s idle node suspension may also contribute.
  The SCO keepalive likely prevents this too, but not confirmed.

## Files Changed

- `src/voice-to-text`: `start_sco_keepalive()`, `stop_sco_keepalive()`, stale PID logic, persistent logging
- `src/voice-recorder-daemon`: zero-frame dropout detection, status error logging
