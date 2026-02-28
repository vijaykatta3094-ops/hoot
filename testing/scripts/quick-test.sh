#!/usr/bin/env bash
# quick-test.sh — End-to-end smoke test for voice-to-text
# Records 5 seconds of audio from the default mic and transcribes it.
# Use this to verify the whole pipeline works after changes.

set -euo pipefail

VENV="$HOME/faster-whisper-env"
PYTHON="$VENV/bin/python3"
TEST_WAV="/tmp/voice-to-text-test.wav"

RED='\033[91m'
GREEN='\033[92m'
YELLOW='\033[93m'
RESET='\033[0m'

echo ""
echo "Voice-to-Text Quick Test"
echo "========================"
echo "This will record 5 seconds from your default mic and transcribe it."
echo "Speak something after the prompt."
echo ""

# Check server
echo -n "  Checking transcription server... "
PONG=$(echo "PING" | timeout 3 python3 -c "
import socket
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.settimeout(3)
s.connect('/tmp/voice-transcribe.sock')
s.sendall(b'PING')
print(s.recv(64))
s.close()
" 2>/dev/null || echo "ERROR")
if echo "$PONG" | grep -q "PONG"; then
    echo -e "${GREEN}OK${RESET}"
else
    echo -e "${YELLOW}not running — will use direct load (slower)${RESET}"
fi

echo ""
echo -e "  ${YELLOW}▶ Speak now — recording for 5 seconds...${RESET}"

# Record 5 seconds
"$PYTHON" - <<'EOF'
import sounddevice as sd
import wave, sys, time

RATE = 16000
DURATION = 5
OUTPUT = "/tmp/voice-to-text-test.wav"

print("  ", end="", flush=True)
recording = sd.rec(int(RATE * DURATION), samplerate=RATE, channels=1, dtype='int16')
for i in range(DURATION):
    time.sleep(1)
    print(f"{DURATION - i - 1}... " if i < DURATION - 1 else "done.", end="", flush=True)
sd.wait()
print()

with wave.open(OUTPUT, 'wb') as wf:
    wf.setnchannels(1)
    wf.setsampwidth(2)
    wf.setframerate(RATE)
    wf.writeframes(recording.tobytes())
    # Pad with silence for Parakeet
    wf.writeframes(b'\x00\x00' * int(1.5 * RATE))
EOF

echo ""
echo -n "  Analyzing audio quality... "
"$PYTHON" - <<'EOF'
import wave, array
with wave.open("/tmp/voice-to-text-test.wav", "rb") as wf:
    data = wf.readframes(wf.getnframes())
samples = array.array('h', data)
mx = max(abs(s) for s in samples)
avg = sum(abs(s) for s in samples) / len(samples)
if mx < 100:
    print(f"\033[91mSILENCE (max={mx}) — wrong mic source or disconnected\033[0m")
elif avg < 50:
    print(f"\033[93mVERY QUIET (max={mx}, avg={avg:.0f}) — check mic volume\033[0m")
else:
    print(f"\033[92mOK (max={mx}/32767, avg={avg:.0f})\033[0m")
EOF

echo ""
echo -n "  Transcribing... "
START=$(date +%s%N)

RESULT=$("$PYTHON" "$HOME/bin/voice-transcribe-engine" "$TEST_WAV" 2>/dev/null || true)

END=$(date +%s%N)
ELAPSED=$(( (END - START) / 1000000 ))

rm -f "$TEST_WAV"

if [ -n "$RESULT" ]; then
    echo -e "${GREEN}OK${RESET} (${ELAPSED}ms)"
    echo ""
    echo "  Transcription: \"$RESULT\""
    echo ""
    echo -e "${GREEN}  ✓ Pipeline working correctly${RESET}"
else
    echo -e "${YELLOW}no speech detected (${ELAPSED}ms)${RESET}"
    echo ""
    echo "  Either you didn't speak, or the mic isn't capturing correctly."
    echo "  Run: bash ~/voice-to-text/testing/scripts/check-system.sh"
fi

echo ""
