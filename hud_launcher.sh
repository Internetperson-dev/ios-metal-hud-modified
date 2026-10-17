#!/usr/bin/env bash
#
# iOS Metal HUD Launcher — automatic dependency setup and USB recovery
# Usage: ./hud_launcher.sh [--wifi]
#   (no flag)  RemotePairing tunnel mode (needs sudo for tunnel creation)
#   --wifi     Wireless/userspace launch mode (after device pairing)

set -o pipefail

PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="$PROJECT_DIR/.venv"
LOCAL_PMD="$VENV_DIR/bin/pymobiledevice3"
PMD=()
PAIR_MARKER="$PROJECT_DIR/.remote_pairing_initialized"

LOG_DIR="$PROJECT_DIR/logs"
mkdir -p "$LOG_DIR" || {
    echo "✗ Could not create log directory: $LOG_DIR" >&2
    exit 1
}
LOG_FILE="$LOG_DIR/launch_$(date +%Y%m%d_%H%M%S).log"

log()  { printf '  [%s] %s\n' "$(date +%H:%M:%S)" "$*" >> "$LOG_FILE"; }
info() { printf '  %s\n' "$*"; log "$*"; }
err()  { printf '  ✗ %s\n' "$*" | tee -a "$LOG_FILE" >&2; }

# ── Ensure pymobiledevice3 is installed and working ──
ensure_pymobiledevice3() {
    local system_pmd=""

    if [[ -x "$LOCAL_PMD" ]] && "$LOCAL_PMD" --help >/dev/null 2>&1; then
        PMD=("$LOCAL_PMD")
        info "Using pymobiledevice3: $LOCAL_PMD"
        return 0
    fi

    if [[ -x "$VENV_DIR/bin/python" ]] && "$VENV_DIR/bin/python" -m pymobiledevice3 --help >/dev/null 2>&1; then
        PMD=("$VENV_DIR/bin/python" -m pymobiledevice3)
        info "Using pymobiledevice3 from project venv (python -m)"
        return 0
    fi

    system_pmd="$(command -v pymobiledevice3 2>/dev/null || true)"
    if [[ -n "$system_pmd" && "$system_pmd" != "$LOCAL_PMD" ]] && "$system_pmd" --help >/dev/null 2>&1; then
        PMD=("$system_pmd")
        info "Using system pymobiledevice3: $system_pmd"
        return 0
    fi

    if ! command -v uv >/dev/null 2>&1; then
        err "pymobiledevice3 is missing or not working, and uv is not installed."
        err "Install uv: https://docs.astral.sh/uv/getting-started/installation/"
        return 1
    fi

    info "pymobiledevice3 is missing or not working; preparing it with uv..."
    if [[ ! -x "$VENV_DIR/bin/python" ]]; then
        uv venv "$VENV_DIR" >> "$LOG_FILE" 2>&1 || {
            err "uv could not create the virtual environment. See $LOG_FILE"
            return 1
        }
    fi

    uv pip install --python "$VENV_DIR/bin/python" --upgrade pymobiledevice3 \
        >> "$LOG_FILE" 2>&1 || {
        err "uv could not install pymobiledevice3. See $LOG_FILE"
        return 1
    }

    if [[ -x "$LOCAL_PMD" ]] && "$LOCAL_PMD" --help >/dev/null 2>&1; then
        PMD=("$LOCAL_PMD")
    elif [[ -x "$VENV_DIR/bin/python" ]] && "$VENV_DIR/bin/python" -m pymobiledevice3 --help >/dev/null 2>&1; then
        PMD=("$VENV_DIR/bin/python" -m pymobiledevice3)
    else
        err "pymobiledevice3 installed, but its CLI did not start. See $LOG_FILE"
        return 1
    fi

    info "pymobiledevice3 is ready."
}

# ── Ensure usbmuxd is running ──
ensure_usbmuxd() {
    if pgrep -x usbmuxd >/dev/null 2>&1; then
        return 0
    fi

    info "Starting usbmuxd..."
    if command -v systemctl >/dev/null 2>&1; then
        sudo systemctl start usbmuxd.service >> "$LOG_FILE" 2>&1 || true
    fi
    if ! pgrep -x usbmuxd >/dev/null 2>&1; then
        sudo usbmuxd >> "$LOG_FILE" 2>&1 || true
    fi
    sleep 2

    if pgrep -x usbmuxd >/dev/null 2>&1; then
        return 0
    fi

    err "usbmuxd failed to start. Check $LOG_FILE"
    return 1
}

# Get the first currently-connected UDID. Do not use old pair records as a
# fallback: a saved record does not prove that the phone is currently present.
list_connected_udid() {
    local raw=""
    raw="$(timeout 12 "${PMD[@]}" usbmux list --simple 2>> "$LOG_FILE" || true)"
    raw="$(printf '%s' "$raw" | tr -d '[:space:]' | sed 's/^\[//; s/\]$//' | cut -d, -f1 | tr -d '"')"
    [[ -n "$raw" && "$raw" != "[]" ]] && printf '%s\n' "$raw"
}

# Recover stale usbmuxd discovery state without asking the user to replug.
refresh_usbmuxd() {
    info "Phone not visible yet; refreshing usbmuxd and retrying (no replug needed)..."

    if command -v systemctl >/dev/null 2>&1 && sudo systemctl restart usbmuxd.service >> "$LOG_FILE" 2>&1; then
        :
    else
        # Fallback for systems without a working systemd unit.
        sudo pkill -TERM -x usbmuxd >> "$LOG_FILE" 2>&1 || true
        sleep 1
        sudo usbmuxd >> "$LOG_FILE" 2>&1 || true
    fi

    sleep 2
}

# ── Auto-detect device with automatic usbmuxd recovery ──
detect_device() {
    ensure_usbmuxd || return 1

    local udid=""
    local attempt
    for attempt in {1..5}; do
        udid="$(list_connected_udid)"
        if [[ -n "$udid" ]]; then
            printf '%s\n' "$udid"
            return 0
        fi
        sleep 1
    done

    refresh_usbmuxd
    for attempt in {1..12}; do
        udid="$(list_connected_udid)"
        if [[ -n "$udid" ]]; then
            printf '%s\n' "$udid"
            return 0
        fi
        sleep 1
    done

    err "No connected device found after refreshing usbmuxd."
    err "Check that the phone is unlocked, trusted, and the USB cable/data port works."
    return 1
}

# ── Pair only when needed ──
# Successful RemotePairing bootstrap is remembered in this project directory.
# Re-running it on every launch can churn the device connection and is unnecessary.
do_pair() {
    if [[ -f "$PAIR_MARKER" ]]; then
        info "RemotePairing was initialized previously; skipping repeat pairing."
        return 0
    fi

    info "Initializing RemotePairing over USB (accept any trust prompt on the phone)..."
    local pair_rc=0
    timeout 30 "${PMD[@]}" lockdown remotepairing --pair 2>&1 | tee -a "$LOG_FILE"
    pair_rc=${PIPESTATUS[0]}

    info "Enabling Wi-Fi connections..."
    timeout 15 "${PMD[@]}" lockdown wifi-connections on 2>&1 | tee -a "$LOG_FILE"
    local wifi_rc=${PIPESTATUS[0]}

    if [[ "$pair_rc" -eq 0 ]]; then
        touch "$PAIR_MARKER" 2>/dev/null || true
        info "RemotePairing initialized; future attempts will reuse the pairing."
    else
        info "Pairing command returned exit $pair_rc; will retry pairing on a later attempt if needed."
    fi
    if [[ "$wifi_rc" -ne 0 ]]; then
        info "Wi-Fi connection setting returned exit $wifi_rc; continuing."
    fi
}

# ── App Menu ──
clear
echo "=============================================="
echo "       iOS Metal HUD Game Launcher           "
echo "=============================================="
echo
echo "  1) Clash of Clans"
echo "  2) PUBG Mobile"
echo "  3) Fortnite"
echo "  4) Exit"
echo
read -r -p "  Select an option [1-4]: " choice

case "$choice" in
    1) BUNDLE="com.supercell.magic" ;;
    2) BUNDLE="com.tencent.ig" ;;
    3) BUNDLE="com.epicgames.FortniteGame" ;;
    4) exit 0 ;;
    *) err "Invalid choice."; exit 1 ;;
esac

ensure_pymobiledevice3 || exit 1

info "Detecting device..."
UDID="$(detect_device)" || exit 1
info "Device: $UDID"

do_pair "$UDID"

info "Launching $BUNDLE with Metal HUD..."
echo

if [[ "${1:-}" == "--wifi" ]]; then
    "${PMD[@]}" developer dvt launch "$BUNDLE" --env MTL_HUD_ENABLED=1 \
        --userspace 2>&1 | tee -a "$LOG_FILE" | grep -v "LSSupportsGameMode"
    LAUNCH_EXIT=${PIPESTATUS[0]}
else
    TUNNEL_OUT="$(mktemp)" || {
        err "Could not create a temporary file for tunnel output."
        exit 1
    }
    TUNNEL_PID=""
    TUNNEL_WRAPPER_PID=""

    cleanup_tunnel() {
        local saved_status=$?
        trap - EXIT INT TERM

        # The privileged shell prints its session PID to the tunnel output using
        # an already-open descriptor. Avoid reopening a user-owned mktemp PID file
        # as root; that was failing with Permission denied on this system.
        if [[ -z "${TUNNEL_PID:-}" && -s "${TUNNEL_OUT:-}" ]]; then
            TUNNEL_PID="$(sed -n 's/^TUNNEL_PID: *//p' "$TUNNEL_OUT" | head -n 1 | tr -cd '0-9')"
        fi
        if [[ -n "${TUNNEL_PID:-}" && "$TUNNEL_PID" =~ ^[0-9]+$ ]]; then
            sudo -n bash -c 'kill -TERM -- "-$1"' _ "$TUNNEL_PID" 2>/dev/null || true
            sleep 1
            if sudo -n bash -c 'kill -0 -- "-$1"' _ "$TUNNEL_PID" 2>/dev/null; then
                sudo -n bash -c 'kill -KILL -- "-$1"' _ "$TUNNEL_PID" 2>/dev/null || true
            fi
        fi

        if [[ -n "${TUNNEL_WRAPPER_PID:-}" ]]; then
            if kill -0 "$TUNNEL_WRAPPER_PID" 2>/dev/null; then
                kill -TERM "$TUNNEL_WRAPPER_PID" 2>/dev/null || true
            fi
            wait "$TUNNEL_WRAPPER_PID" 2>/dev/null || true
        fi
        rm -f "$TUNNEL_OUT"
        return "$saved_status"
    }
    trap cleanup_tunnel EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM

    # Authenticate while this script still has an interactive terminal. Running
    # sudo for the first time inside the background tunnel job cannot prompt, and
    # was the cause of: "sudo: a terminal is required to read the password".
    info "Checking sudo credentials before starting the tunnel..."
    if ! sudo -v; then
        err "sudo authentication failed; cannot create the RemotePairing tunnel."
        exit 1
    fi

    if ! command -v setsid >/dev/null 2>&1; then
        err "The setsid command is required for reliable tunnel cleanup (install util-linux)."
        exit 1
    fi

    info "Creating RemotePairing tunnel..."
    # sudo authenticates in the foreground first. The process/session PID is
    # printed into the already-open output file descriptor, so root does not have
    # to reopen a file created by the unprivileged shell.
    sudo -n setsid --wait bash -c '
        printf "TUNNEL_PID: %s\n" "$$" >&2
        exec "$@"
    ' _ "${PMD[@]}" remote start-tunnel -t wifi --protocol tcp \
        --udid "$UDID" > "$TUNNEL_OUT" 2>&1 &
    TUNNEL_WRAPPER_PID=$!

    # Wait up to 16 seconds for tunnel details, but stop early if startup exits.
    for _ in {1..16}; do
        if grep -q "RSD Address:" "$TUNNEL_OUT" && grep -q "RSD Port:" "$TUNNEL_OUT"; then
            break
        fi
        if ! kill -0 "$TUNNEL_WRAPPER_PID" 2>/dev/null; then
            break
        fi
        sleep 1
    done

    TUNNEL_PID="$(sed -n 's/^TUNNEL_PID: *//p' "$TUNNEL_OUT" | head -n 1 | tr -cd '0-9')"
    RSD_ADDR="$(grep "RSD Address:" "$TUNNEL_OUT" | tail -1 | awk '{print $NF}')"
    RSD_PORT="$(grep "RSD Port:" "$TUNNEL_OUT" | tail -1 | awk '{print $NF}')"

    if [[ -z "$RSD_ADDR" || -z "$RSD_PORT" ]]; then
        err "Tunnel failed to start. Captured output follows:"
        if [[ -s "$TUNNEL_OUT" ]]; then
            cat "$TUNNEL_OUT" | tee -a "$LOG_FILE" >&2
        else
            err "The tunnel process produced no output."
        fi
        exit 1
    fi

    info "Tunnel established: $RSD_ADDR:$RSD_PORT"
    info "Launching the app through the active tunnel..."

    "${PMD[@]}" developer dvt launch "$BUNDLE" --env MTL_HUD_ENABLED=1 \
        --rsd "$RSD_ADDR" "$RSD_PORT" 2>&1 | tee -a "$LOG_FILE" | grep -v "LSSupportsGameMode"
    LAUNCH_EXIT=${PIPESTATUS[0]}
fi

if [[ "${LAUNCH_EXIT:-1}" -eq 0 ]]; then
    info "✓ App launched successfully!"
    echo "  ✓ App launched successfully!"
    # A successful launch confirms the pairing state is usable on this host.
    touch "$PAIR_MARKER" 2>/dev/null || true
else
    err "Launch failed (exit ${LAUNCH_EXIT:-1})"
    err "Check the log: $LOG_FILE"
fi

info "Log saved to $LOG_FILE"
exit "${LAUNCH_EXIT:-1}"
