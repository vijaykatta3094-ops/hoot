#!/usr/bin/env python3
"""
analyze-audio.py — Diagnose a voice-to-text WAV recording.

Usage:
    python3 analyze-audio.py [wav_file]
    python3 analyze-audio.py            # defaults to /tmp/voice-to-text-last.wav

Checks for:
  - BT dropout (consecutive zero-frame blocks)
  - Near-silence (mic too quiet or wrong source)
  - Clipping (mic too loud)
  - Suspiciously short speech windows vs recording duration
"""

import sys
import wave
import array
import os

WAV_FILE = sys.argv[1] if len(sys.argv) > 1 else "/tmp/voice-to-text-last.wav"
CHUNK_MS = 250  # analysis window size

RED   = "\033[91m"
GREEN = "\033[92m"
YELLOW = "\033[93m"
RESET = "\033[0m"

def colored(text, color):
    return f"{color}{text}{RESET}"

def main():
    if not os.path.exists(WAV_FILE):
        print(f"File not found: {WAV_FILE}")
        sys.exit(1)

    with wave.open(WAV_FILE, "rb") as wf:
        rate = wf.getframerate()
        n_frames = wf.getnframes()
        n_channels = wf.getnchannels()
        sampwidth = wf.getsampwidth()
        data = wf.readframes(n_frames)

    if n_channels != 1 or sampwidth != 2:
        print(f"Warning: expected mono int16, got {n_channels}ch {sampwidth*8}bit")

    samples = array.array("h", data)
    duration = len(samples) / rate
    chunk_size = int(rate * CHUNK_MS / 1000)

    print(f"\n{'='*60}")
    print(f"File:      {WAV_FILE}")
    print(f"Duration:  {duration:.2f}s  |  Rate: {rate}Hz  |  Frames: {n_frames}")
    print(f"{'='*60}\n")

    # --- Global stats ---
    max_amp = max(abs(s) for s in samples)
    avg_amp = sum(abs(s) for s in samples) / len(samples)
    print(f"Global max amplitude: {max_amp:5d} / 32767  ({max_amp/327.67:.1f}%)")
    print(f"Global avg amplitude: {avg_amp:6.1f}")

    if max_amp < 100:
        print(colored("  !! SILENCE: max < 100 — mic disconnected or wrong source", RED))
    elif max_amp < 500:
        print(colored("  !! VERY QUIET: max < 500 — check mic volume", YELLOW))
    elif max_amp >= 32700:
        print(colored("  !! CLIPPING: mic too loud, distortion likely", YELLOW))
    else:
        print(colored("  ✓ Amplitude range looks normal", GREEN))

    # --- Chunk analysis ---
    n_chunks = len(samples) // chunk_size
    speech_chunks = 0
    zero_chunks = 0
    max_consecutive_zeros = 0
    current_zeros = 0
    dropout_time = None

    print(f"\n{'─'*60}")
    print(f"{'Time':>10}  {'Max':>6}  {'Avg':>7}  Label")
    print(f"{'─'*60}")

    for i in range(n_chunks):
        chunk = samples[i * chunk_size : (i + 1) * chunk_size]
        mx = max(abs(s) for s in chunk)
        avg = sum(abs(s) for s in chunk) / len(chunk)
        t_start = i * CHUNK_MS / 1000
        t_end = (i + 1) * CHUNK_MS / 1000

        if mx == 0:
            label = colored("[ ZERO — possible dropout ]", RED)
            zero_chunks += 1
            current_zeros += 1
            max_consecutive_zeros = max(max_consecutive_zeros, current_zeros)
            if dropout_time is None and speech_chunks > 0 and current_zeros >= 4:
                dropout_time = t_start - (3 * CHUNK_MS / 1000)
        elif mx < 200:
            label = colored("[ near-silence ]", YELLOW)
            current_zeros = 0
        elif avg > 300:
            label = colored("speech", GREEN)
            speech_chunks += 1
            current_zeros = 0
        else:
            label = "quiet"
            current_zeros = 0

        print(f"  {t_start:5.2f}–{t_end:.2f}s  {mx:6d}  {avg:7.1f}  {label}")

    print(f"{'─'*60}\n")

    # --- Summary ---
    speech_duration = speech_chunks * CHUNK_MS / 1000
    zero_duration = zero_chunks * CHUNK_MS / 1000

    print("Summary:")
    print(f"  Speech chunks:       {speech_chunks:3d}  ({speech_duration:.2f}s)")
    print(f"  Zero chunks:         {zero_chunks:3d}  ({zero_duration:.2f}s)")
    print(f"  Max consecutive zeros: {max_consecutive_zeros} chunks  "
          f"({max_consecutive_zeros * CHUNK_MS / 1000:.2f}s)")

    # --- Diagnosis ---
    print(f"\nDiagnosis:")
    issues = 0

    if dropout_time is not None:
        print(colored(f"  !! BT DROPOUT detected at ~{dropout_time:.1f}s — "
                      f"SCO link dropped mid-recording (see BUG-005)", RED))
        issues += 1

    if zero_chunks > n_chunks * 0.8 and speech_chunks == 0:
        print(colored("  !! COMPLETE SILENCE — mic was not recording. "
                      "Wrong source or BT not connected.", RED))
        issues += 1
    elif zero_chunks > n_chunks * 0.5 and speech_chunks > 0:
        pct = zero_chunks / n_chunks * 100
        print(colored(f"  !! {pct:.0f}% of recording is zeros — likely BT dropout (BUG-005)", RED))
        issues += 1

    if max_amp < 500 and speech_chunks == 0:
        print(colored("  !! No speech detected and very low amplitude — "
                      "mic muted or disconnected?", RED))
        issues += 1

    if speech_chunks > 0 and zero_chunks == 0:
        print(colored("  ✓ Clean recording — no dropouts detected", GREEN))

    if issues == 0 and speech_chunks > 0:
        print(colored("  ✓ Recording looks healthy", GREEN))
    elif issues > 0:
        print(f"\n  {issues} issue(s) found. Check testing/bugs/ for root causes.")

    print()


if __name__ == "__main__":
    main()
