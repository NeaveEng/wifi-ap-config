#!/bin/bash

# Smart WiFi AP control wrapper that handles sudo automatically
# This script detects if sudo is needed and requests it automatically

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTROL_SCRIPT="$SCRIPT_DIR/wifi-ap-control.sh"

# Check if the main script exists
if [ ! -f "$CONTROL_SCRIPT" ]; then
    echo "Error: wifi-ap-control.sh not found in $SCRIPT_DIR"
    exit 1
fi

COMMAND="${1:-status}"

# Commands that need sudo
case "$COMMAND" in
    "start"|"stop"|"restart"|"delete")
        if [ "$EUID" -ne 0 ]; then
            echo "WiFi Access Point control requires administrator privileges for '$COMMAND'."
            echo "Requesting sudo access..."
            echo ""
            exec sudo "$CONTROL_SCRIPT" "$@"
        else
            exec "$CONTROL_SCRIPT" "$@"
        fi
        ;;
    "status"|"list"|"interfaces"|"-h"|"--help")
        # These can run without sudo
        exec "$CONTROL_SCRIPT" "$@"
        ;;
    *)
        # Unknown command, let the main script handle it
        if [ "$EUID" -ne 0 ]; then
            echo "Requesting sudo access for command '$COMMAND'..."
            exec sudo "$CONTROL_SCRIPT" "$@"
        else
            exec "$CONTROL_SCRIPT" "$@"
        fi
        ;;
esac