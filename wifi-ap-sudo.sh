#!/bin/bash

# Smart WiFi AP wrapper that handles sudo automatically
# This script detects if sudo is needed and requests it automatically

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WIFI_AP_SCRIPT="$SCRIPT_DIR/wifi-ap.sh"

# Check if the main script exists
if [ ! -f "$WIFI_AP_SCRIPT" ]; then
    echo "Error: wifi-ap.sh not found in $SCRIPT_DIR"
    exit 1
fi

# Check if we need sudo
if [ "$EUID" -ne 0 ]; then
    echo "WiFi Access Point setup requires administrator privileges."
    echo "Requesting sudo access..."
    echo ""
    
    # Request sudo and run the main script
    exec sudo "$WIFI_AP_SCRIPT" "$@"
else
    # Already running as root, just execute
    exec "$WIFI_AP_SCRIPT" "$@"
fi