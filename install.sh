#!/usr/bin/env bash
# install.sh — Install Hoot on Linux (GNOME Wayland + PipeWire)
# Usage: bash install.sh
#
# What this does:
#   1. Checks system requirements
#   2. Copies scripts to ~/bin/
#   3. Installs systemd user service
#   4. Creates persistent log directory
#   5. Sets up keyboard shortcut (auto via gsettings, or prints manual steps)
#   6. Prints next steps (Python env + model download)

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$HOME/bin"
SYSTEMD_DIR="$HOME/.config/systemd/user"

RED='\\033[91m'
GREEN='\\033[92m'
YELLOW='\\033[93m'
BOLD='\\033[1m'
RESET='\\033[0m'

ok()   { echo -e "  ${GREEN}✓${RESET} $1"; }
warn() { echo -e "  ${YELLOW}⚠${RESET}  $1"; }
fail() { echo -e "  ${RED}✗${RESET} $1"; }
step() { echo -e "\n${BOLD}$1${RESET}"; }

echo ""
echo -e "${BOLD}Hoot Installer${RESET}"
echo "==============="

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
            ydotool)     echo "       Install: sudo apt install ydotool  (or build from source)" ;;
            wl-copy)     echo "       Install: sudo apt install wl-clipboard" ;;
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

for script in hoot hoot-recorder hoot-transcribe; do
    if [ -f "$REPO_DIR/src/$script" ]; then
        cp "$REPO_DIR/src/$script" "$BIN_DIR/$script"
        chmod +x "$BIN_DIR/$script"
        ok "$script"
    else
        fail "src/$script not found in repo"
    fi
done

# Python scripts: substitute HOME path in shebang before copying
for script in hoot-engine hoot-server; do
    if [ -f "$REPO_DIR/src/$script" ]; then
        sed "s|/home/vijay-katta|$HOME|g" "$REPO_DIR/src/$script" > "$BIN_DIR/$script"
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

sed "s|/home/vijay-katta|$HOME|g" \
    "$REPO_DIR/systemd/hoot-server.service" \
    > "$SYSTEMD_DIR/hoot-server.service"

systemctl --user daemon-reload
systemctl --user enable hoot-server
ok "hoot-server.service installed and enabled"

# ── Step 4: Set up log directory ─────────────────────────────────────────────
step "4. Setting up persistent log directory"
mkdir -p "$HOME/hoot/logs"
ok "~/hoot/logs/ created"

# ── Step 5: Set up keyboard shortcut ─────────────────────────────────────────
step "5. Keyboard shortcut"

echo ""
echo "  Hoot is triggered by a keyboard shortcut."
echo "  Default: Ctrl+Space  (gsettings format: <Primary>space)"
echo ""
echo "  Other examples:"
echo "    Super+H          →  <Super>h"
echo "    Ctrl+Alt+Space   →  <Primary><Alt>space"
echo "    Ctrl+Shift+H     →  <Primary><Shift>h"
echo ""
read -rp "  Enter shortcut [press Enter for Ctrl+Space]: " USER_HOTKEY
HOTKEY="${USER_HOTKEY:-<Primary>space}"

if command -v gsettings &>/dev/null; then
    BINDING_BASE="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings"

    # Find existing 'Hoot' slot or first free slot
    BINDING_PATH=""
    for i in $(seq 0 9); do
        SLOT_PATH="$BINDING_BASE/custom$i/"
        SLOT_NAME=$(gsettings get \
            "org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$SLOT_PATH" \
            name 2>/dev/null | tr -d "'" || true)
        if [ "$SLOT_NAME" = "Hoot" ] || [ -z "$SLOT_NAME" ]; then
            BINDING_PATH="$SLOT_PATH"
            break
        fi
    done
    BINDING_PATH="${BINDING_PATH:-$BINDING_BASE/custom0/}"

    gsettings set \
        "org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$BINDING_PATH" \
        name "Hoot"
    gsettings set \
        "org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$BINDING_PATH" \
        command "/bin/bash -c '\$HOME/bin/hoot'"
    gsettings set \
        "org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$BINDING_PATH" \
        binding "$HOTKEY"

    # Add to keybindings list if not already present
    CURRENT=$(gsettings get org.gnome.settings-daemon.plugins.media-keys custom-keybindings)
    if [[ "$CURRENT" != *"$BINDING_PATH"* ]]; then
        if [ "$CURRENT" = "@as []" ] || [ "$CURRENT" = "[]" ]; then
            gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings \
                "['$BINDING_PATH']"
        else
            NEW_LIST="${CURRENT%]}, '$BINDING_PATH']"
            gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings \
                "$NEW_LIST"
        fi
    fi

    ok "Shortcut set: $HOTKEY → hoot"
    echo "       (Change anytime: Settings → Keyboard → Custom Shortcuts)"
else
    warn "gsettings not found — set shortcut manually:"
    echo "       Settings → Keyboard → Custom Shortcuts → Add:"
    echo "       Name:     Hoot"
    echo "       Command:  /bin/bash -c '\$HOME/bin/hoot'"
    echo "       Shortcut: $HOTKEY"
fi

# ── Step 6: Print next steps ─────────────────────────────────────────────────
step "6. Next steps (manual)"

echo ""
echo "  The scripts are installed, but you still need:"
echo ""
echo "  a) Python virtual environment with dependencies:"
echo "     python3 -m venv ~/hoot-env"
echo "     source ~/hoot-env/bin/activate"
echo "     pip install faster-whisper sounddevice"
echo "     pip install nemo-toolkit  # for Parakeet GPU engine"
echo "     # For RTX 5090 (sm_120): use PyTorch nightly cu128"
echo "     # See docs/REQUIREMENTS.md for GPU-specific instructions"
echo ""
echo "  b) Start the model server:"
echo "     systemctl --user start hoot-server"
echo "     # (auto-starts on next login)"
echo ""
echo "  c) Test the installation:"
echo "     bash $REPO_DIR/testing/scripts/quick-test.sh"
echo ""
echo -e "${GREEN}Installation complete. Press $HOTKEY to start hooting.${RESET}"
echo ""
