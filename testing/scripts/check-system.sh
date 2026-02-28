#!/usr/bin/env bash
# check-system.sh — Full system health check for voice-to-text
# Run this when something seems wrong before digging into logs.

set -uo pipefail

RED='\033[91m'
GREEN='\033[92m'
YELLOW='\033[93m'
RESET='\033[0m'

ok()   { echo -e "  ${GREEN}✓${RESET} $1"; }
warn() { echo -e "  ${YELLOW}⚠${RESET}  $1"; }
fail() { echo -e "  ${RED}✗${RESET} $1"; }
header() { echo -e "\n${1}"; echo "─────────────────────────────────────"; }

ISSUES=0

header "1. Transcription Server"
if systemctl --user is-active --quiet voice-transcribe-server 2>/dev/null; then
    ok "systemd service is running"
    UPTIME=$(systemctl --user show voice-transcribe-server --property=ActiveEnterTimestamp --value 2>/dev/null || echo "unknown")
    ok "started: $UPTIME"
else
    fail "voice-transcribe-server is NOT running"
    echo "     Fix: systemctl --user start voice-transcribe-server"
    ISSUES=$((ISSUES+1))
fi

if [ -S /tmp/voice-transcribe.sock ]; then
    # Ping the server
    PONG=$(echo "PING" | timeout 3 python3 -c "
import socket, sys
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.settimeout(3)
s.connect('/tmp/voice-transcribe.sock')
s.sendall(b'PING')
print(s.recv(64))
s.close()
" 2>/dev/null || echo "ERROR")
    if echo "$PONG" | grep -q "PONG"; then
        ok "server socket responding to PING"
    else
        fail "server socket exists but not responding ($PONG)"
        ISSUES=$((ISSUES+1))
    fi
else
    warn "server socket /tmp/voice-transcribe.sock not found"
    ISSUES=$((ISSUES+1))
fi

header "2. GPU / CUDA"
if command -v nvidia-smi &>/dev/null; then
    GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)
    GPU_MEM=$(nvidia-smi --query-gpu=memory.used,memory.total --format=csv,noheader 2>/dev/null | head -1)
    ok "GPU: $GPU_NAME"
    ok "VRAM: $GPU_MEM"
else
    warn "nvidia-smi not found — GPU status unknown"
fi

header "3. Audio — Default Source"
DEFAULT_SOURCE=$(pactl info 2>/dev/null | awk '/Default Source:/{print $3}')
if [ -n "$DEFAULT_SOURCE" ]; then
    ok "Default source: $DEFAULT_SOURCE"
else
    fail "Could not get default audio source"
    ISSUES=$((ISSUES+1))
fi

MUTE=$(pactl get-source-mute @DEFAULT_SOURCE@ 2>/dev/null | awk '{print $2}')
if [ "$MUTE" = "no" ]; then
    ok "Mic is not muted"
elif [ "$MUTE" = "yes" ]; then
    fail "Mic is MUTED — run: pactl set-source-mute @DEFAULT_SOURCE@ 0"
    ISSUES=$((ISSUES+1))
else
    warn "Could not check mute status"
fi

VOL=$(pactl get-source-volume @DEFAULT_SOURCE@ 2>/dev/null | grep -oP '\d+(?=%)' | head -1)
if [ -n "$VOL" ]; then
    if [ "$VOL" -lt 50 ]; then
        warn "Mic volume low: ${VOL}% (recommend 80%+)"
    else
        ok "Mic volume: ${VOL}%"
    fi
fi

header "4. Bluetooth"
BT_CARD=$(pactl list cards short 2>/dev/null | grep bluez | awk '{print $2}' | head -1)
if [ -n "$BT_CARD" ]; then
    BT_PROFILE=$(pactl list cards 2>/dev/null | awk "/Name: $BT_CARD/{f=1} f && /Active Profile:/{print \$3; exit}")
    ok "BT card: $BT_CARD"
    ok "Active profile: $BT_PROFILE"
    BT_INPUT=$(pactl list sources short 2>/dev/null | grep bluez_input | awk '{print $2}' | head -1)
    if [ -n "$BT_INPUT" ]; then
        ok "BT mic source available: $BT_INPUT"
    else
        warn "No BT input source (profile may not be HFP) — switch with:"
        echo "     pactl set-card-profile $BT_CARD headset-head-unit-msbc"
    fi
    BT_OUTPUT=$(pactl list sinks short 2>/dev/null | grep "bluez_output" | grep -v "monitor" | awk '{print $2}' | head -1)
    if [ -n "$BT_OUTPUT" ]; then
        ok "BT output sink available: $BT_OUTPUT (needed for SCO keepalive)"
    else
        warn "No BT output sink — SCO keepalive will not work (BUG-005 risk)"
    fi
else
    warn "No Bluetooth card found — using built-in mic"
fi

header "5. Required Tools"
for tool in ydotool wl-copy wl-paste pacat; do
    if command -v "$tool" &>/dev/null; then
        ok "$tool found"
    else
        fail "$tool NOT found"
        ISSUES=$((ISSUES+1))
    fi
done

# Check ydotool can actually write to uinput
if [ -w /dev/uinput ]; then
    ok "/dev/uinput is writable (ydotool will work)"
else
    fail "/dev/uinput is not writable — paste will fail (BUG-001)"
    echo "     Fix: sudo setfacl -m u:$USER:rw /dev/uinput"
    ISSUES=$((ISSUES+1))
fi

header "6. Last Recording"
if [ -f /tmp/voice-to-text-last.wav ]; then
    SIZE=$(wc -c < /tmp/voice-to-text-last.wav)
    MODIFIED=$(stat -c '%y' /tmp/voice-to-text-last.wav | cut -d. -f1)
    ok "Last recording: ${SIZE} bytes, modified $MODIFIED"
    echo "     Run to analyze: python3 ~/voice-to-text/testing/scripts/analyze-audio.py"
else
    warn "No last recording at /tmp/voice-to-text-last.wav"
fi

header "7. Persistent Logs"
LOG_DIR="$HOME/voice-to-text/logs"
TODAY_LOG="$LOG_DIR/$(date +%Y-%m-%d).log"
if [ -f "$TODAY_LOG" ]; then
    LINES=$(wc -l < "$TODAY_LOG")
    ok "Today's log: $TODAY_LOG ($LINES lines)"
    echo ""
    echo "  Last 5 entries:"
    tail -5 "$TODAY_LOG" | sed 's/^/    /'
else
    warn "No log for today at $TODAY_LOG"
fi

# Final summary
echo ""
echo "═══════════════════════════════════════"
if [ "$ISSUES" -eq 0 ]; then
    echo -e "${GREEN}All checks passed — system looks healthy${RESET}"
else
    echo -e "${RED}${ISSUES} issue(s) found — see output above${RESET}"
fi
echo "═══════════════════════════════════════"
echo ""
