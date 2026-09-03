#!/usr/bin/env bash
#
# Dynamisland installer
#
# Copies the shell into ~/.config/quickshell/dynamisland, then detects
# whichever Wayland compositor is ACTUALLY RUNNING (not just installed)
# and offers to wire up autostart + the ghost-mode keybind for it.
#
# By default this asks before touching any compositor config file — it
# shows you exactly what line it wants to add and waits for a yes/no.
# Pass --yes (or run non-interactively, e.g. via `curl | bash`) to skip
# the prompts and apply everything automatically.
#
# Safe to re-run either way: every edit is guarded so nothing gets
# duplicated on a second pass.

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

info()  { echo -e "${BLUE}[+] $1${NC}"; }
ok()    { echo -e "${GREEN}[✓] $1${NC}"; }
warn()  { echo -e "${YELLOW}[!] $1${NC}"; }
err()   { echo -e "${RED}[x] $1${NC}"; }

# -----------------------------------------------------------------------
# --yes / -y: skip all confirmation prompts.
# Also auto-detected: if stdin isn't a terminal (piped install, CI, a
# script calling this script), there's nobody to prompt, so we behave
# as if --yes was passed rather than hanging or silently skipping.
# -----------------------------------------------------------------------
ASSUME_YES=false
for arg in "$@"; do
    case "$arg" in
        --yes|-y) ASSUME_YES=true ;;
    esac
done
if [ ! -t 0 ]; then
    ASSUME_YES=true
fi

echo -e "${BLUE}=== Dynamisland Installer ===${NC}"

if ! command -v quickshell &> /dev/null && ! command -v qs &> /dev/null; then
    warn "QuickShell is not installed. Please install it before running Dynamisland."
fi

TARGET_DIR="$HOME/.config/quickshell/dynamisland"
CONFIG_DIR="$HOME/.config/dynamisland"

info "Copying files to $TARGET_DIR..."

mkdir -p "$HOME/.config/quickshell"
mkdir -p "$CONFIG_DIR"

cp -r . "$TARGET_DIR"

if [ -f "$TARGET_DIR/config.json" ]; then
    cp "$TARGET_DIR/config.json" "$CONFIG_DIR/config.json"
fi

IPC_CMD="quickshell ipc -p $TARGET_DIR call pill"

# -----------------------------------------------------------------------
# Compositor detection — RUNNING session, not just "is it installed".
#
# Every Wayland compositor sets some marker in the environment of the
# session it owns. We check those first since they're the most reliable
# signal, then fall back to XDG hints, then to a plain process scan as a
# last resort so this still works on setups/compositors we don't know
# about by name.
# -----------------------------------------------------------------------
detect_compositor() {
    if [ -n "$HYPRLAND_INSTANCE_SIGNATURE" ]; then
        echo "hyprland"; return
    fi
    if [ -n "$NIRI_SOCKET" ]; then
        echo "niri"; return
    fi
    if [ -n "$SWAYSOCK" ]; then
        echo "sway"; return
    fi
    if [ -n "$MANGOWC_SOCKET" ] || pgrep -x mangowc &> /dev/null; then
        echo "mango"; return
    fi
    if pgrep -x river &> /dev/null; then
        echo "river"; return
    fi

    # XDG hints — set by the session/display manager, not the compositor
    # itself, so they're a step less reliable but still useful.
    case "${XDG_CURRENT_DESKTOP,,}${XDG_SESSION_DESKTOP,,}" in
        *hyprland*) echo "hyprland"; return ;;
        *niri*)     echo "niri"; return ;;
        *sway*)     echo "sway"; return ;;
        *river*)    echo "river"; return ;;
    esac

    # Last resort: scan for any known compositor process regardless of
    # how the session variables were (or weren't) set.
    for proc in hyprland niri sway river mangowc; do
        if pgrep -x "$proc" &> /dev/null; then
            echo "$proc"; return
        fi
    done

    echo "unknown"
}

COMPOSITOR=$(detect_compositor)

if [ "$COMPOSITOR" = "unknown" ]; then
    warn "Could not detect a running Wayland compositor."
    warn "Autostart and the ghost-mode keybind must be set up manually."
    warn "See README.md for the IPC commands to bind yourself."
else
    ok "Detected running compositor: $COMPOSITOR"
fi

AUTOSTART_ADDED=false
BIND_ADDED=false
SKIPPED_LINES=()   # anything the user said no to, echoed back at the end

# -----------------------------------------------------------------------
# confirm_and_append: shows the exact line that would be added to $file,
# asks y/N (unless ASSUME_YES), then appends it — idempotently, so a
# re-run (or answering "yes" twice) never duplicates the line.
#
# Returns 0 only if the line was actually added this run.
# -----------------------------------------------------------------------
confirm_and_append() {
    local file="$1" line="$2" label="$3"

    mkdir -p "$(dirname "$file")"
    touch "$file"

    if grep -qF "$line" "$file"; then
        warn "$label already present in $file"
        return 1
    fi

    if [ "$ASSUME_YES" = false ]; then
        echo ""
        echo -e "  ${BOLD}$label${NC}"
        echo -e "  file: $file"
        echo -e "  line: ${BLUE}$line${NC}"
        read -r -p "  Add this? [Y/n] " reply
        case "$reply" in
            [nN]*)
                warn "Skipped: $label"
                SKIPPED_LINES+=("$file: $line")
                return 1
                ;;
        esac
    fi

    printf '\n%s\n' "$line" >> "$file"
    ok "$label added to $file"
    return 0
}

case "$COMPOSITOR" in

    hyprland)
        # Hyprland reloads hyprland.conf on save/`hyprctl reload`, and
        # supports separate press (bind) / release (bindr) execs, which
        # maps perfectly onto ghost mode's hold-to-peek behaviour.
        HYPR_CONFIG="$HOME/.config/hypr/hyprland.conf"

        confirm_and_append "$HYPR_CONFIG" \
            "exec-once = quickshell -c dynamisland" \
            "Autostart" && AUTOSTART_ADDED=true

        confirm_and_append "$HYPR_CONFIG" \
            "bind = SUPER, ALT, exec, $IPC_CMD ghost true" \
            "Ghost mode (press)" && BIND_ADDED=true
        confirm_and_append "$HYPR_CONFIG" \
            "bindr = SUPER, ALT, exec, $IPC_CMD ghost false" \
            "Ghost mode (release)" && BIND_ADDED=true
        ;;

    niri)
        NIRI_CONFIG="$HOME/.config/niri/config.kdl"

        confirm_and_append "$NIRI_CONFIG" \
            'spawn-at-startup "quickshell" "-c" "dynamisland"' \
            "Autostart" && AUTOSTART_ADDED=true

        # niri has no native release-hook for a plain modifier combo on a
        # normal bind, so we wire the toggle IPC instead of hold-to-peek.
        confirm_and_append "$NIRI_CONFIG" \
            "binds { Mod+Alt { spawn \"quickshell\" \"ipc\" \"-p\" \"$TARGET_DIR\" \"call\" \"pill\" \"ghostToggle\"; } }" \
            "Ghost mode (toggle)" && BIND_ADDED=true
        ;;

    sway)
        SWAY_CONFIG="$HOME/.config/sway/config"

        confirm_and_append "$SWAY_CONFIG" \
            "exec quickshell -c dynamisland" \
            "Autostart" && AUTOSTART_ADDED=true

        confirm_and_append "$SWAY_CONFIG" \
            "bindsym \$mod+Alt exec $IPC_CMD ghost true" \
            "Ghost mode (press)" && BIND_ADDED=true
        confirm_and_append "$SWAY_CONFIG" \
            "bindsym --release \$mod+Alt exec $IPC_CMD ghost false" \
            "Ghost mode (release)" && BIND_ADDED=true
        ;;

    river)
        # river has no persistent config file by default — it's driven by
        # an executable init script (usually ~/.config/river/init).
        RIVER_INIT="$HOME/.config/river/init"
        if [ -f "$RIVER_INIT" ]; then
            confirm_and_append "$RIVER_INIT" \
                "riverctl spawn \"quickshell -c dynamisland\"" \
                "Autostart" && AUTOSTART_ADDED=true

            confirm_and_append "$RIVER_INIT" \
                "riverctl map normal Super+Alt spawn '$IPC_CMD ghostToggle'" \
                "Ghost mode (toggle)" && BIND_ADDED=true
        else
            warn "No river init script found at $RIVER_INIT — skipping autostart/bind."
        fi
        ;;

    mango)
        # mangowc config layout varies by version; try the common spot,
        # otherwise bail out to the manual instructions below.
        MANGO_CONFIG="$HOME/.config/mango/config.conf"
        if [ -f "$MANGO_CONFIG" ] || [ -d "$(dirname "$MANGO_CONFIG")" ]; then
            confirm_and_append "$MANGO_CONFIG" \
                "exec-once = quickshell -c dynamisland" \
                "Autostart" && AUTOSTART_ADDED=true

            confirm_and_append "$MANGO_CONFIG" \
                "bind = SUPER, ALT, exec, $IPC_CMD ghost true" \
                "Ghost mode (press)" && BIND_ADDED=true
            confirm_and_append "$MANGO_CONFIG" \
                "bindr = SUPER, ALT, exec, $IPC_CMD ghost false" \
                "Ghost mode (release)" && BIND_ADDED=true
        else
            warn "Could not find a mango config directory — skipping autostart/bind."
        fi
        ;;

esac

# Generic XDG autostart .desktop entry as a universal fallback/extra —
# picked up by most desktop environments and some compositors. Only
# offered when we couldn't do anything compositor-specific.
DESKTOP_AUTOSTART_DIR="$HOME/.config/autostart"
DESKTOP_FILE="$DESKTOP_AUTOSTART_DIR/dynamisland.desktop"
if [ "$AUTOSTART_ADDED" = false ] && [ "$COMPOSITOR" = "unknown" ]; then
    write_desktop_file=true
    if [ "$ASSUME_YES" = false ]; then
        echo ""
        echo -e "  ${BOLD}XDG autostart entry${NC}"
        echo -e "  file: $DESKTOP_FILE"
        echo -e "  ${BLUE}Exec=quickshell -c dynamisland${NC}"
        read -r -p "  Create this? [Y/n] " reply
        case "$reply" in
            [nN]*) write_desktop_file=false ;;
        esac
    fi
    if [ "$write_desktop_file" = true ]; then
        mkdir -p "$DESKTOP_AUTOSTART_DIR"
        cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Type=Application
Name=Dynamisland
Exec=quickshell -c dynamisland
X-GNOME-Autostart-enabled=true
EOF
        ok "XDG autostart entry written to $DESKTOP_FILE"
        AUTOSTART_ADDED=true
    fi
fi

if [ "$AUTOSTART_ADDED" = false ]; then
    warn "Autostart was not configured. Add it manually:"
    warn "  quickshell -c dynamisland"
fi

if [ "$BIND_ADDED" = false ] && [ "$COMPOSITOR" != "unknown" ]; then
    warn "Ghost-mode keybind was not added (already present, declined, or unsupported layout)."
fi

if [ "$COMPOSITOR" = "unknown" ] || [ ${#SKIPPED_LINES[@]} -gt 0 ]; then
    echo ""
    warn "Manual setup reference — ghost mode IPC calls:"
    echo "    $IPC_CMD ghost true    # hold-start: fade out + click-through"
    echo "    $IPC_CMD ghost false   # hold-end:   fade back in"
    echo "    $IPC_CMD ghostToggle   # single-press alternative"
fi

if [ ${#SKIPPED_LINES[@]} -gt 0 ]; then
    echo ""
    warn "You skipped the following — add them yourself if you change your mind:"
    for skipped in "${SKIPPED_LINES[@]}"; do
        echo "    $skipped"
    done
fi

echo -e "${GREEN}=== Installation finished! ===${NC}"
echo -e "Testing launch with: ${BLUE}qs -c dynamisland${NC}"

if command -v qs &> /dev/null; then
    qs -c dynamisland &
elif command -v quickshell &> /dev/null; then
    quickshell -c dynamisland &
fi
