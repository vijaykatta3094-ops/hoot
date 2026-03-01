import St from 'gi://St';
import GLib from 'gi://GLib';
import Gio from 'gi://Gio';
import GObject from 'gi://GObject';
import Clutter from 'gi://Clutter';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as PanelMenu from 'resource:///org/gnome/shell/ui/panelMenu.js';

// hoot writes this file when recording starts, removes it when done
const STATE_FILE = '/tmp/hoot.state';
const HOOT_BIN   = `${GLib.get_home_dir()}/bin/hoot`;

const HootIndicator = GObject.registerClass(
class HootIndicator extends PanelMenu.Button {

    _init() {
        super._init(0.0, 'Hoot');

        this._recording = false;
        this._blink     = false;

        this._icon = new St.Icon({
            icon_name:   'audio-input-microphone-muted-symbolic',
            style_class: 'system-status-icon',
        });
        this.add_child(this._icon);

        // Poll state file every 300ms
        this._timer = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 300, () => {
            this._updateState();
            return GLib.SOURCE_CONTINUE;
        });

        // Click → toggle recording
        this.connect('button-press-event', (_actor, event) => {
            if (event.get_button() === Clutter.BUTTON_PRIMARY) {
                try {
                    GLib.spawn_command_line_async(HOOT_BIN);
                } catch (e) {
                    logError(e, 'Hoot: failed to launch');
                }
            }
            return Clutter.EVENT_PROPAGATE;
        });

        this._updateState();
    }

    _updateState() {
        const file    = Gio.File.new_for_path(STATE_FILE);
        const isRec   = file.query_exists(null);

        if (isRec !== this._recording) {
            this._recording = isRec;

            if (isRec) {
                // Recording: show solid red mic, start blinking
                this._icon.icon_name = 'audio-input-microphone-symbolic';
                this._startBlink();
            } else {
                // Idle: muted grey mic, stop blinking
                this._stopBlink();
                this._icon.icon_name = 'audio-input-microphone-muted-symbolic';
                this._icon.set_opacity(255);
            }
        }
    }

    _startBlink() {
        if (this._blinkTimer) return;
        // Pulse opacity to signal active recording
        this._blinkTimer = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 600, () => {
            if (!this._recording) return GLib.SOURCE_REMOVE;
            this._blink = !this._blink;
            this._icon.set_opacity(this._blink ? 255 : 130);
            // Tint red using style
            this._icon.style = this._blink
                ? 'color: #ff4444;'
                : 'color: #cc2222;';
            return GLib.SOURCE_CONTINUE;
        });
    }

    _stopBlink() {
        if (this._blinkTimer) {
            GLib.source_remove(this._blinkTimer);
            this._blinkTimer = null;
        }
        this._icon.style = '';
    }

    destroy() {
        if (this._timer) {
            GLib.source_remove(this._timer);
            this._timer = null;
        }
        this._stopBlink();
        super.destroy();
    }
});

let _indicator = null;

export function enable() {
    _indicator = new HootIndicator();
    // Place it just left of the system indicators (clock area)
    Main.panel.addToStatusArea('hoot', _indicator, 1, 'right');
}

export function disable() {
    _indicator?.destroy();
    _indicator = null;
}
