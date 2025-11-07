#!/bin/bash

# WiFi Access Point Reset Script (Sudo Wrapper)
# Automatically handles sudo privileges for the reset operation

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAIN_SCRIPT="$SCRIPT_DIR/wifi-ap.sh"

echo "WiFi Access Point reset requires administrator privileges."
echo "Requesting sudo access..."
echo ""

# Pass all arguments to the main script with sudo
exec sudo "$MAIN_SCRIPT" --reset "$@"