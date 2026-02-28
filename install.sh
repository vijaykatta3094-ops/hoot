#!/usr/bin/env bash
# install.sh — Install voice-to-text on Linux (GNOME Wayland + PipeWire)
# Usage: bash install.sh
#
# What this does:
#   1. Checks system requirements
#   2. Copies scripts to ~/bin/
#   3. Installs systemd user service
#   4. Creates persistent log directory
#   5. Prints next steps (Python env + model download)

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$HOME/bin"
SYSTEMD_DIR="$HOME/.config/systemd/user"

RED='\033[91m'
GREEN='\033[92m'
YELLOW='\033[93m'
BOLD='\033[1m'
RESET='\033[0m'

ok()   { echo -e "  ${GREEN}✓${RESET} $1"; }
warn() { echo -e "  ${YELLOW}⚠${RESET}  $1"; }
fail() { echo -e "  ${RED}✗${RESET} $1"; }
step() { echo -e "\n${BOLD}$1${RESET}"; }

echo ""
echo -e "${BOLD}Voice-to-Text Installer${RESET}"
echo "========================"

# ── Step 1: Check requirements ──────────────────────────────────────────────
step "1. Checking requirements"

MISSING=0

# Desktop / audio
if [ "${WAYLAND_DISPLAY:-}" != "" ] || [ "${XDG_SESSION_TYPE:-}" = "wayland" ]; then
    ok "Wayland detected"
else
    warn "Wayland not detected — paste via ydotool may not work as expected"
fi

if command -v pactl &>/dev/null; then
    ok "PipeWire/PulseAudio (pactl found)"
else
    fail "pactl not found — install pulseaudio-utils"
    MISSING=$((MISSING+1))
fi

# Required tools
for tool in ydotool wl-copy notify-send; do
    if command -v "$tool" &>/dev/null; then
        ok "$tool"
    else
        fail "$tool not found"
        MISSING=$((MISSING+1))
        case "$tool" in
            ydotool) echo "       Install: sudo apt install ydotool  (or build from source)" ;;
            wl-copy) echo "       Install: sudo apt install wl-clipboard" ;;
            notify-send) echo "       Install: sudo apt install libnotify-bin" ;;
        esac
    fi
done

# uinput access (needed for ydotool)
if [ -w /dev/uinput ]; then
    ok "/dev/uinput writable (ydotool will work)"
else
    warn "/dev/uinput not writable — paste may fail"
    echo "       Fix: sudo setfacl -m u:\$USER:rw /dev/uinput"
    echo "       Or add udev rule for persistence (see docs/SETUP.md)"
fi

# Python
if command -v python3 &>/dev/null; then
    PY_VER=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
    ok "Python $PY_VER"
else
    fail "python3 not found"
    MISSING=$((MISSING+1))
fi

if [ "$MISSING" -gt 0 ]; then
    echo ""
    fail "$MISSING required tool(s) missing. Install them and re-run."
    exit 1
fi

# ── Step 2: Install scripts ──────────────────────────────────────────────────
step "2. Installing scripts to $BIN_DIR"

mkdir -p "$BIN_DIR"

for script in voice-to-text voice-recorder-daemon voice-transcribe-engine voice-transcribe-server transcribe; do
    if [ -f "$REPO_DIR/src/$script" ]; then
        cp "$REPO_DIR/src/$script" "$BIN_DIR/$script"
        chmod +x "$BIN_DIR/$script"
        ok "$script"
    else
        fail "src/$script not found in repo"
    fi
done

# Ensure ~/bin is in PATH
if ! echo "$PATH" | grep -q "$BIN_DIR"; then
    warn "$BIN_DIR is not in PATH — add to ~/.bashrc:"
    echo "       export PATH=\"\$HOME/bin:\$PATH\""
fi

# ── Step 3: Install systemd service ─────────────────────────────────────────
step "3. Installing systemd user service"

mkdir -p "$SYSTEMD_DIR"

# Substitute actual home path into service file
sed "s|/home/vijay-katta|$HOME|g" \
    "$REPO_DIR/systemd/voice-transcribe-server.service" \
    > "$SYSTEMD_DIR/voice-transcribe-server.service"

systemctl --user daemon-reload
systemctl --user enable voice-transcribe-server
ok "voice-transcribe-server.service installed and enabled"

# ── Step 4: Set up log directory ─────────────────────────────────────────────
step "4. Setting up persistent log directory"
mkdir -p "$HOME/voice-to-text/logs"
ok "~/voice-to-text/logs/ created"

# ── Step 5: Print next steps ─────────────────────────────────────────────────
step "5. Next steps (manual)"

echo ""
echo "  The scripts are installed, but you still need:"
echo ""
echo "  a) Python virtual environment with dependencies:"
echo "     python3 -m venv ~/faster-whisper-env"
echo "     source ~/faster-whisper-env/bin/activate"
echo "     pip install faster-whisper sounddevice"
echo "     pip install nemo-toolkit  # for Parakeet GPU engine"
echo "     # For RTX 5090 (sm_120): use PyTorch nightly cu128"
echo "     # See docs/REQUIREMENTS.md for GPU-specific instructions"
echo ""
echo "  b) Set up the keyboard shortcut (GNOME):"
echo "     Settings → Keyboard → Custom Shortcuts → Add:"
echo "     Name: Voice to Text"
echo "     Command: /bin/bash -c '\$HOME/bin/voice-to-text'"
echo "     Shortcut: Ctrl+Space"
echo ""
echo "  c) Start the model server:"
echo "     systemctl --user start voice-transcribe-server"
echo "     # (auto-starts on next login)"
echo ""
echo "  d) Test the installation:"
echo "     bash $REPO_DIR/testing/scripts/quick-test.sh"
echo ""
echo -e "${GREEN}Installation complete.${RESET}"
echo ""
