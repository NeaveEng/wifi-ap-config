#!/bin/bash

# WiFi Access Point Setup Script for Jetson Orin Nano
# Usage: ./wifi-ap.sh <SSID> <PASSWORD> [INTERFACE] [CHANNEL] [IP_ADDRESS]

# Check if running as root or with sudo
check_privileges() {
    if [ "$EUID" -ne 0 ]; then
        echo "Error: This script requires root privileges to configure network connections."
        echo ""
        echo "Please run with sudo:"
        echo "  sudo $0 $*"
        echo ""
        echo "Or if you prefer to be prompted for sudo when needed:"
        echo "  sudo -v && $0 $*"
        exit 1
    fi
}

# Check privileges first
check_privileges "$@"

# Function to check if interface supports a specific band
check_band_support() {
    local interface=$1
    local band=$2  # "2.4" or "5"
    
    # Get the physical device (phy) for this interface
    local phy=$(iw dev "$interface" info 2>/dev/null | grep wiphy | awk '{print "phy"$2}')
    
    if [ -z "$phy" ]; then
        echo "Warning: Could not determine physical device for $interface" >&2
        return 0  # Assume supported if we can't check
    fi
    
    if [ "$band" == "2.4" ]; then
        # Check for Band 1 (2.4GHz) - look for 2.4GHz frequencies
        if iw phy "$phy" info 2>/dev/null | grep -q "2[0-9][0-9][0-9] MHz"; then
            return 0  # Supported
        else
            return 1  # Not supported
        fi
    elif [ "$band" == "5" ]; then
        # Check for Band 2 (5GHz) - look for 5GHz frequencies
        if iw phy "$phy" info 2>/dev/null | grep -q "5[0-9][0-9][0-9] MHz"; then
            return 0  # Supported
        else
            return 1  # Not supported
        fi
    fi
    
    return 1
}

# Function to find best channel for given band
find_best_channel() {
    local band=$1
    local interface=$2
    local exclude_ssid=$3  # Optional: SSID to exclude from scan results
    
    echo "Scanning for nearby access points to find best channel..." >&2
    
    # Ensure WiFi is on and scan
    nmcli radio wifi on 2>/dev/null
    nmcli dev wifi rescan ifname "$interface" 2>/dev/null || true
    sleep 2
    
    # Get all scan results, optionally excluding our own SSID
    local wifi_list
    if [ -n "$exclude_ssid" ]; then
        wifi_list=$(nmcli -f SSID,CHAN dev wifi list ifname "$interface" 2>/dev/null | grep -v "^${exclude_ssid} " | grep -v "^SSID")
        echo "  (Excluding own AP: $exclude_ssid)" >&2
    else
        wifi_list=$(nmcli -f SSID,CHAN dev wifi list ifname "$interface" 2>/dev/null | grep -v "^SSID")
    fi
    
    if [ "$band" == "2.4" ]; then
        # For 2.4GHz, count APs on each channel (1-11 are most common)
        local channel_usage=$(echo "$wifi_list" | awk '{print $NF}' | grep -E "^[0-9]+$" | awk '$1 <= 14' | sort -n | uniq -c | sort -k2 -n)
        
        # Find least used channel among 1, 6, 11 (non-overlapping channels)
        local best_channel=6
        local min_count=999
        
        for ch in 1 6 11; do
            local count=$(echo "$channel_usage" | awk -v ch="$ch" '$2 == ch {print $1}')
            if [ -z "$count" ]; then
                count=0
            fi
            if [ "$count" -lt "$min_count" ]; then
                min_count=$count
                best_channel=$ch
            fi
        done
        
        echo "  2.4GHz channel usage:" >&2
        echo "$channel_usage" | head -10 >&2
        echo "  Recommended channel: $best_channel (least congested among non-overlapping channels 1, 6, 11)" >&2
        echo "$best_channel"
        
    elif [ "$band" == "5" ]; then
        # For 5GHz, find least used channel
        local channel_usage=$(echo "$wifi_list" | awk '{print $NF}' | grep -E "^[0-9]+$" | awk '$1 >= 36' | sort -n | uniq -c | sort -k2 -n)
        
        local best_channel=36
        local min_count=999
        
        # Check common 5GHz channels
        for ch in 36 40 44 48 149 153 157 161 165; do
            local count=$(echo "$channel_usage" | awk -v ch="$ch" '$2 == ch {print $1}')
            if [ -z "$count" ]; then
                count=0
            fi
            if [ "$count" -lt "$min_count" ]; then
                min_count=$count
                best_channel=$ch
            fi
        done
        
        echo "  5GHz channel usage:" >&2
        echo "$channel_usage" | head -10 >&2
        echo "  Recommended channel: $best_channel (least congested)" >&2
        echo "$best_channel"
    fi
}

# Function to check if interface supports a specific band
check_band_support() {
    local interface=$1
    local band=$2
    
    # Get the phy device for this interface
    local phy=$(iw dev "$interface" info 2>/dev/null | grep wiphy | awk '{print "phy" $2}')
    
    if [ -z "$phy" ]; then
        echo "Warning: Could not determine phy device for interface $interface" >&2
        return 0  # Allow to proceed if we can't determine
    fi
    
    if [ "$band" == "2.4" ]; then
        # Check for 2.4GHz support (Band 1, around 2.4 GHz frequencies)
        if iw phy "$phy" info 2>/dev/null | grep -q "Band 1:"; then
            return 0  # Supported
        else
            return 1  # Not supported
        fi
    elif [ "$band" == "5" ]; then
        # Check for 5GHz support (Band 2, around 5 GHz frequencies)
        if iw phy "$phy" info 2>/dev/null | grep -q "Band 2:"; then
            return 0  # Supported
        else
            return 1  # Not supported
        fi
    fi
    
    return 1
}

# Function to display usage information
show_usage() {
    echo "Usage: sudo $0 <SSID> <PASSWORD> [INTERFACE] [CHANNEL] [IP_ADDRESS] [BAND]"
    echo ""
    echo "Note: This script requires root privileges (sudo)"
    echo ""
    echo "Arguments:"
    echo "  SSID        - Name of the WiFi access point (required)"
    echo "  PASSWORD    - Password for the access point (required, min 8 characters)"
    echo "  INTERFACE   - WiFi interface to use (optional, default: auto-detect)"
    echo "  CHANNEL     - WiFi channel or 'auto' (optional, default: 7 for 2.4GHz, 36 for 5GHz)"
    echo "                Use 'auto' to scan and select the least congested channel"
    echo "  IP_ADDRESS  - IP address for the access point (optional, default: 192.168.4.1/24)"
    echo "  BAND        - WiFi band: 2.4 or 5 (optional, default: 2.4)"
    echo ""
    echo "Options:"
    echo "  --force        - Skip confirmation prompts (for scripted usage)"
    echo "  --replace      - Automatically replace existing connections"
    echo "  --reset        - Remove all AP connections and restore client mode"
    echo "  --band=2.4     - Use 2.4GHz band (channels 1-14)"
    echo "  --band=5       - Use 5GHz band (channels 36-165)"
    echo "  --update-band=<CONNECTION_NAME> <BAND> [CHANNEL]"
    echo "                 - Update band/channel of existing AP without recreating it"
    echo "                   CHANNEL can be a number or 'auto' for automatic selection"
    echo ""
    echo "Examples:"
    echo "  sudo $0 MyJetsonAP mypassword123"
    echo "  sudo $0 MyAP password123 wlan0 auto                  # Auto-select best channel"
    echo "  sudo $0 JetsonNetwork secretpass wlan0 36 192.168.10.1/24 5"
    echo "  sudo $0 \"My Jetson AP\" \"my secure password\" wlan1 auto --band=5"
    echo "  sudo $0 FastAP password123 wlan0 --band=5"
    echo "  sudo $0 --update-band PinPoint-AP 5 149    # Switch existing AP to 5GHz"
    echo "  sudo $0 --update-band PinPoint-AP 2.4      # Switch back to 2.4GHz"
    echo "  sudo $0 --reset                    # Remove all AP configs and restore client mode"
    echo ""
    echo "Alternative: Use the wrapper script that handles sudo automatically:"
    echo "  ./wifi-ap-sudo.sh MyJetsonAP mypassword123"
    echo ""
    echo "Available WiFi interfaces:"
    nmcli dev status | grep wifi | awk '{print "  " $1 " (" $2 ")"}'
    echo ""
    exit 1
}

# Check if help is requested
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    show_usage
fi

# Check if reset is requested
if [[ "$1" == "--reset" ]]; then
    echo "=== WiFi Access Point Reset Mode ==="
    echo "This will:"
    echo "1. Stop all active access points"
    echo "2. Delete all AP connection profiles"
    echo "3. Restore interfaces to client mode"
    echo ""
    
    if [[ "$2" != "--force" ]]; then
        read -p "Continue with reset? (y/N): " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            echo "Reset cancelled."
            exit 0
        fi
    fi
    
    # Find and stop all AP connections
    echo "Searching for access point connections..."
    AP_CONNECTIONS=$(nmcli -t -f NAME,TYPE con show | grep ":802-11-wireless" | cut -d: -f1 | grep -E ".*-AP$|.*AP$" 2>/dev/null || true)
    
    if [ -z "$AP_CONNECTIONS" ]; then
        echo "No access point connections found."
    else
        echo "Found AP connections:"
        echo "$AP_CONNECTIONS" | while read conn; do
            echo "  - $conn"
        done
        echo ""
        
        # Stop and delete each AP connection
        echo "$AP_CONNECTIONS" | while read conn; do
            if [ -n "$conn" ]; then
                echo "Stopping and deleting: $conn"
                nmcli con down "$conn" 2>/dev/null || true
                nmcli con delete "$conn" 2>/dev/null || echo "  Warning: Could not delete $conn"
            fi
        done
    fi
    
    # Re-enable WiFi and scan for networks
    echo ""
    echo "Re-enabling WiFi interfaces for client mode..."
    for interface in $(nmcli dev status | grep wifi | grep -v wifi-p2p | awk '{print $1}'); do
        echo "Enabling interface: $interface"
        nmcli radio wifi on
        nmcli dev set "$interface" managed yes
        nmcli dev wifi rescan ifname "$interface" 2>/dev/null || true
    done
    
    echo ""
    echo "SUCCESS: Access point reset complete!"
    echo "WiFi interfaces are now ready for client connections."
    echo ""
    echo "Available networks:"
    nmcli dev wifi list | head -10
    echo ""
    echo "To connect to a network, use:"
    echo "  nmcli dev wifi connect \"NETWORK_NAME\" password \"PASSWORD\""
    exit 0
fi

# Check if update-band is requested
if [[ "$1" == "--update-band" ]]; then
    if [ $# -lt 3 ]; then
        echo "Error: --update-band requires CONNECTION_NAME and BAND"
        echo "Usage: sudo $0 --update-band <CONNECTION_NAME> <BAND> [CHANNEL]"
        echo "Example: sudo $0 --update-band PinPoint-AP 5 149"
        exit 1
    fi
    
    UPDATE_CONNECTION="$2"
    UPDATE_BAND="$3"
    UPDATE_CHANNEL="$4"
    
    echo "=== WiFi Access Point Band Update Mode ==="
    echo "Connection: $UPDATE_CONNECTION"
    echo "New Band: ${UPDATE_BAND}GHz"
    
    # Check if connection exists
    if ! nmcli con show "$UPDATE_CONNECTION" >/dev/null 2>&1; then
        echo "Error: Connection '$UPDATE_CONNECTION' not found"
        echo ""
        echo "Available AP connections:"
        nmcli -t -f NAME,TYPE con show | grep ":802-11-wireless" | cut -d: -f1 | grep -E ".*-AP$|.*AP$" || echo "  None found"
        exit 1
    fi
    
    # Validate and normalize band
    if [[ "$UPDATE_BAND" == "2.4" || "$UPDATE_BAND" == "2" || "$UPDATE_BAND" == "bg" ]]; then
        UPDATE_BAND="2.4"
        UPDATE_BAND_VALUE="bg"
        if [ -z "$UPDATE_CHANNEL" ]; then
            UPDATE_CHANNEL="7"
        fi
    elif [[ "$UPDATE_BAND" == "5" || "$UPDATE_BAND" == "a" ]]; then
        UPDATE_BAND="5"
        UPDATE_BAND_VALUE="a"
        if [ -z "$UPDATE_CHANNEL" ]; then
            UPDATE_CHANNEL="36"
        fi
    else
        echo "Error: Invalid band '$UPDATE_BAND'. Must be 2.4 or 5"
        exit 1
    fi
    
    # Get interface from connection
    UPDATE_INTERFACE=$(nmcli -t -f connection.interface-name con show "$UPDATE_CONNECTION" 2>/dev/null | cut -d: -f2)
    
    # Check if hardware supports the requested band
    if ! check_band_support "$UPDATE_INTERFACE" "$UPDATE_BAND"; then
        echo ""
        echo "Error: Interface '$UPDATE_INTERFACE' does not support ${UPDATE_BAND}GHz band"
        echo ""
        echo "Supported bands for $UPDATE_INTERFACE:"
        phy=$(iw dev "$UPDATE_INTERFACE" info 2>/dev/null | grep wiphy | awk '{print "phy"$2}')
        if [ -n "$phy" ]; then
            if iw phy "$phy" info 2>/dev/null | grep -q "2[0-9][0-9][0-9] MHz"; then
                echo "  - 2.4GHz"
            fi
            if iw phy "$phy" info 2>/dev/null | grep -q "5[0-9][0-9][0-9] MHz"; then
                echo "  - 5GHz"
            fi
        fi
        exit 1
    fi
    
    # Get SSID from connection to exclude it from scan
    UPDATE_SSID=$(nmcli -t -f 802-11-wireless.ssid con show "$UPDATE_CONNECTION" 2>/dev/null | cut -d: -f2)
    
    # Handle auto channel selection
    if [[ "$UPDATE_CHANNEL" == "auto" ]]; then
        echo ""
        echo "Auto channel selection requested..."
        UPDATE_CHANNEL=$(find_best_channel "$UPDATE_BAND" "$UPDATE_INTERFACE" "$UPDATE_SSID")
        echo "Selected channel: $UPDATE_CHANNEL"
        echo ""
    fi
    
    # Validate channel based on band
    if ! [[ "$UPDATE_CHANNEL" =~ ^[0-9]+$ ]]; then
        echo "Error: Channel must be a number or 'auto'"
        exit 1
    fi
    
    if [ "$UPDATE_BAND" == "2.4" ]; then
        if [ "$UPDATE_CHANNEL" -lt 1 ] || [ "$UPDATE_CHANNEL" -gt 14 ]; then
            echo "Error: For 2.4GHz band, channel must be between 1 and 14"
            exit 1
        fi
    elif [ "$UPDATE_BAND" == "5" ]; then
        VALID_5GHZ_CHANNELS="36 40 44 48 52 56 60 64 100 104 108 112 116 120 124 128 132 136 140 144 149 153 157 161 165"
        if ! echo "$VALID_5GHZ_CHANNELS" | grep -q "\b$UPDATE_CHANNEL\b"; then
            echo "Error: Invalid 5GHz channel. Common valid channels are: 36, 40, 44, 48, 149, 153, 157, 161, 165"
            exit 1
        fi
    fi
    
    echo "New Channel: $UPDATE_CHANNEL"
    echo ""
    
    # Get current state - check if connection is active
    WAS_ACTIVE=""
    if nmcli -t -f NAME,DEVICE connection show --active | grep -q "^${UPDATE_CONNECTION}:"; then
        WAS_ACTIVE="yes"
        echo "Connection is currently active. It will be restarted with new settings."
    fi
    
    echo ""
    read -p "Update band and channel for '$UPDATE_CONNECTION'? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "Update cancelled."
        exit 0
    fi
    
    # Stop connection if active
    if [ "$WAS_ACTIVE" == "yes" ]; then
        echo "Stopping connection..."
        nmcli con down "$UPDATE_CONNECTION" 2>/dev/null || true
    fi
    
    # Update band and channel together (must be done in one step to avoid conflicts)
    echo "Updating band to ${UPDATE_BAND}GHz and channel to $UPDATE_CHANNEL..."
    nmcli con modify "$UPDATE_CONNECTION" \
        802-11-wireless.band "$UPDATE_BAND_VALUE" \
        802-11-wireless.channel "$UPDATE_CHANNEL"
    
    # Restart if it was active
    if [ "$WAS_ACTIVE" == "yes" ]; then
        echo "Restarting connection..."
        if nmcli con up "$UPDATE_CONNECTION"; then
            echo ""
            echo "SUCCESS: Access point band updated!"
            echo "  Connection: $UPDATE_CONNECTION"
            echo "  Band: ${UPDATE_BAND}GHz"
            echo "  Channel: $UPDATE_CHANNEL"
            echo ""
            echo "Connection status:"
            nmcli con show "$UPDATE_CONNECTION" | grep -E "(connection.id|802-11-wireless.ssid|802-11-wireless.band|802-11-wireless.channel)"
        else
            echo ""
            echo "FAILED: Could not restart connection with new settings"
            echo "The connection settings have been updated but failed to activate."
            echo "You may need to check if your hardware supports ${UPDATE_BAND}GHz band."
            exit 1
        fi
    else
        echo ""
        echo "SUCCESS: Access point band updated!"
        echo "  Connection: $UPDATE_CONNECTION"
        echo "  Band: ${UPDATE_BAND}GHz"
        echo "  Channel: $UPDATE_CHANNEL"
        echo ""
        echo "Connection was not active. Start it with:"
        echo "  sudo nmcli con up \"$UPDATE_CONNECTION\""
    fi
    
    exit 0
fi

# Check minimum required arguments (unless using --reset or --update-band)
if [ $# -lt 2 ] && [[ "$1" != "--reset" ]] && [[ "$1" != "--update-band" ]]; then
    echo "Error: Missing required arguments"
    echo ""
    show_usage
fi

# Parse options
FORCE_MODE=""
REPLACE_MODE=""
BAND=""
ARGS=()

for arg in "$@"; do
    case $arg in
        --force)
            FORCE_MODE="yes"
            ;;
        --replace)
            REPLACE_MODE="yes"
            ;;
        --band=*)
            BAND="${arg#*=}"
            ;;
        -*)
            echo "Error: Unknown option $arg"
            show_usage
            ;;
        *)
            ARGS+=("$arg")
            ;;
    esac
done

# Parse command line arguments from cleaned args
SSID="${ARGS[0]}"
PASSWORD="${ARGS[1]}"
INTERFACE="${ARGS[2]}"
CHANNEL="${ARGS[3]}"
IP_ADDRESS="${ARGS[4]:-192.168.4.1/24}"
BAND="${ARGS[5]:-${BAND}}"

# Set default band to 2.4 if not specified
if [ -z "$BAND" ]; then
    BAND="2.4"
fi

# Validate and normalize band
if [[ "$BAND" == "2.4" || "$BAND" == "2" || "$BAND" == "bg" ]]; then
    BAND="2.4"
    BAND_VALUE="bg"
    if [ -z "$CHANNEL" ]; then
        CHANNEL="7"
    fi
elif [[ "$BAND" == "5" || "$BAND" == "a" ]]; then
    BAND="5"
    BAND_VALUE="a"
    if [ -z "$CHANNEL" ]; then
        CHANNEL="36"
    fi
else
    echo "Error: Invalid band '$BAND'. Must be 2.4 or 5"
    exit 1
fi

# Auto-detect WiFi interface if not specified
if [ -z "$INTERFACE" ]; then
    echo "No interface specified, auto-detecting..."
    
    # Get all regular WiFi interfaces (not p2p) that are managed
    ALL_WIFI_INTERFACES=$(nmcli dev status | grep "wifi " | grep -v "p2p" | grep -v "unmanaged" | awk '{print $1}')
    WIFI_COUNT=$(echo "$ALL_WIFI_INTERFACES" | grep -c . || echo "0")
    
    # Check for existing AP connections and their interfaces
    EXISTING_AP_INTERFACE=""
    AP_CONNECTIONS=$(nmcli -t -f NAME,TYPE con show | grep ":802-11-wireless" | cut -d: -f1 | grep -E ".*-AP$|.*AP$" 2>/dev/null || true)
    
    if [ -n "$AP_CONNECTIONS" ]; then
        # Find which interface is running an AP
        while read -r ap_conn; do
            if [ -n "$ap_conn" ]; then
                ACTIVE_AP_INTERFACE=$(nmcli -t -f connection.interface-name con show "$ap_conn" 2>/dev/null | cut -d: -f2)
                if [ -n "$ACTIVE_AP_INTERFACE" ]; then
                    EXISTING_AP_INTERFACE="$ACTIVE_AP_INTERFACE"
                    break
                fi
            fi
        done <<< "$AP_CONNECTIONS"
    fi
    
    # Decision logic
    if [ -n "$EXISTING_AP_INTERFACE" ]; then
        # If there's already an AP running, default to updating that interface
        INTERFACE="$EXISTING_AP_INTERFACE"
        echo "Found existing access point on interface: $INTERFACE"
        echo "Defaulting to update existing AP configuration"
    elif [ "$WIFI_COUNT" -gt 1 ]; then
        # Multiple interfaces available, force user to choose
        echo "Multiple WiFi interfaces detected. Please specify which one to use:"
        echo ""
        echo "Available WiFi interfaces:"
        nmcli dev status | grep wifi | grep -v p2p | awk '{print "  " $1 " (" $3 ")"}'
        echo ""
        echo "Usage: sudo $0 $SSID $PASSWORD <INTERFACE>"
        echo "Example: sudo $0 $SSID $PASSWORD wlan0"
        exit 1
    elif [ "$WIFI_COUNT" -eq 1 ]; then
        # Only one interface, use it
        INTERFACE="$ALL_WIFI_INTERFACES"
        echo "Using only available interface: $INTERFACE"
    else
        # No suitable interfaces found
        echo "Error: No suitable WiFi interfaces found"
        echo ""
        echo "Available network interfaces:"
        nmcli dev status | grep -E "(DEVICE|wifi)"
        echo ""
        echo "Note: P2P interfaces are not suitable for access points"
        exit 1
    fi
fi

# Validate interface exists and is WiFi (but not p2p)
if ! nmcli dev status | grep -q "^$INTERFACE.*wifi"; then
    echo "Error: Interface '$INTERFACE' not found or is not a WiFi interface"
    echo ""
    echo "Available WiFi interfaces:"
    nmcli dev status | grep wifi
    exit 1
fi

# Check if it's a p2p interface
if echo "$INTERFACE" | grep -q "p2p"; then
    echo "Error: P2P interface '$INTERFACE' cannot be used for access points"
    echo "Please specify a regular WiFi interface (e.g., wlan0, wlan1)"
    exit 1
fi

# Check if hardware supports the requested band
if ! check_band_support "$INTERFACE" "$BAND"; then
    echo ""
    echo "Error: Interface '$INTERFACE' does not support ${BAND}GHz band"
    echo ""
    echo "Supported bands for $INTERFACE:"
    phy=$(iw dev "$INTERFACE" info 2>/dev/null | grep wiphy | awk '{print "phy"$2}')
    if [ -n "$phy" ]; then
        if iw phy "$phy" info 2>/dev/null | grep -q "2[0-9][0-9][0-9] MHz"; then
            echo "  - 2.4GHz"
        fi
        if iw phy "$phy" info 2>/dev/null | grep -q "5[0-9][0-9][0-9] MHz"; then
            echo "  - 5GHz"
        fi
    fi
    echo ""
    echo "Please specify a supported band with --band=2.4 or --band=5"
    exit 1
fi

# Check if interface is busy
INTERFACE_STATE=$(nmcli dev status | grep "^$INTERFACE" | awk '{print $3}')
if [ "$INTERFACE_STATE" = "connected" ]; then
    echo "Warning: Interface $INTERFACE is currently connected"
    echo "This will disconnect any existing connection. Continue? (y/N)"
    read -r response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        echo "Aborted"
        exit 1
    fi
fi

# Validate SSID
if [ -z "$SSID" ]; then
    echo "Error: SSID cannot be empty"
    exit 1
fi

if [ ${#SSID} -gt 32 ]; then
    echo "Error: SSID cannot be longer than 32 characters"
    exit 1
fi

# Validate password
if [ -z "$PASSWORD" ]; then
    echo "Error: Password cannot be empty"
    exit 1
fi

if [ ${#PASSWORD} -lt 8 ]; then
    echo "Error: Password must be at least 8 characters long"
    exit 1
fi

if [ ${#PASSWORD} -gt 63 ]; then
    echo "Error: Password cannot be longer than 63 characters"
    exit 1
fi

# Handle auto channel selection
if [[ "$CHANNEL" == "auto" ]]; then
    echo ""
    echo "Auto channel selection requested..."
    CHANNEL=$(find_best_channel "$BAND" "$INTERFACE" "$SSID")
    echo "Selected channel: $CHANNEL"
    echo ""
fi

# Validate channel based on band
if ! [[ "$CHANNEL" =~ ^[0-9]+$ ]]; then
    echo "Error: Channel must be a number or 'auto'"
    exit 1
fi

if [ "$BAND" == "2.4" ]; then
    if [ "$CHANNEL" -lt 1 ] || [ "$CHANNEL" -gt 14 ]; then
        echo "Error: For 2.4GHz band, channel must be between 1 and 14"
        exit 1
    fi
elif [ "$BAND" == "5" ]; then
    # Valid 5GHz channels: 36, 40, 44, 48, 52, 56, 60, 64, 100, 104, 108, 112, 116, 120, 124, 128, 132, 136, 140, 144, 149, 153, 157, 161, 165
    VALID_5GHZ_CHANNELS="36 40 44 48 52 56 60 64 100 104 108 112 116 120 124 128 132 136 140 144 149 153 157 161 165"
    if ! echo "$VALID_5GHZ_CHANNELS" | grep -q "\b$CHANNEL\b"; then
        echo "Error: Invalid 5GHz channel. Common valid channels are: 36, 40, 44, 48, 149, 153, 157, 161, 165"
        echo "Full list: $VALID_5GHZ_CHANNELS"
        exit 1
    fi
fi

# Generate connection name based on SSID (replace spaces with underscores)
CONNECTION_NAME=$(echo "$SSID" | tr ' ' '_' | tr -cd '[:alnum:]_-')
CONNECTION_NAME="${CONNECTION_NAME}-AP"

# Show configuration summary
echo ""
echo "=== WiFi Access Point Configuration ==="
echo "SSID: $SSID"
echo "Password: $PASSWORD"
echo "Interface: $INTERFACE"
echo "Band: ${BAND}GHz"
echo "Channel: $CHANNEL"
echo "IP Address: $IP_ADDRESS"
echo "Connection Name: $CONNECTION_NAME"
echo ""

# Check what will happen
CONNECTION_EXISTS=""
if nmcli con show "$CONNECTION_NAME" >/dev/null 2>&1; then
    CONNECTION_EXISTS="yes"
    # Check if connection is active
    if nmcli -t -f NAME,DEVICE connection show --active | grep -q "^${CONNECTION_NAME}:"; then
        echo "STATUS: Connection '$CONNECTION_NAME' already exists (State: active)"
    else
        echo "STATUS: Connection '$CONNECTION_NAME' already exists (State: inactive)"
    fi
else
    echo "STATUS: Will create new connection '$CONNECTION_NAME'"
fi

# Confirm before proceeding
if [ -z "$FORCE_MODE" ]; then
    echo ""
    echo "Proceed with this configuration? (y/N)"
    read -r response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        echo "Aborted"
        exit 0
    fi
fi

echo ""
echo "Setting up WiFi Access Point..."

# Disconnect interface if currently connected
if [ "$INTERFACE_STATE" = "connected" ]; then
    echo "Disconnecting interface $INTERFACE..."
    nmcli dev disconnect "$INTERFACE" || true
fi

# Check if connection already exists
CONNECTION_EXISTS=""
if nmcli con show "$CONNECTION_NAME" >/dev/null 2>&1; then
    CONNECTION_EXISTS="yes"
    echo "Connection '$CONNECTION_NAME' already exists"
    
    # Check if it's currently active
    if nmcli -t -f NAME,DEVICE connection show --active | grep -q "^${CONNECTION_NAME}:"; then
        echo "Connection is currently active. It will be stopped and reconfigured."
        nmcli con down "$CONNECTION_NAME" 2>/dev/null || true
    fi
    
    echo "Do you want to:"
    echo "  1) Replace the existing configuration (recommended)"
    echo "  2) Keep existing and just restart it"
    echo "  3) Abort"
    
    if [ -n "$REPLACE_MODE" ]; then
        choice="1"
        echo "Auto-selecting option 1 (--replace mode)"
    elif [ -n "$FORCE_MODE" ]; then
        choice="2"
        echo "Auto-selecting option 2 (--force mode)"
    else
        echo -n "Choose (1/2/3): "
        read -r choice
    fi
    
    case "$choice" in
        1)
            echo "Deleting existing connection..."
            nmcli con delete "$CONNECTION_NAME" 2>/dev/null || true
            CONNECTION_EXISTS=""
            ;;
        2)
            echo "Keeping existing configuration, just restarting..."
            if nmcli con up "$CONNECTION_NAME"; then
                echo ""
                echo "SUCCESS: Existing WiFi Access Point restarted!"
                echo "  Connection Name: $CONNECTION_NAME"
                echo ""
                echo "Connection status:"
                nmcli con show "$CONNECTION_NAME" | grep -E "(connection.id|connection.interface-name|802-11-wireless.ssid|802-11-wireless.channel|ipv4.addresses)"
                exit 0
            else
                echo "FAILED: Could not restart existing connection"
                exit 1
            fi
            ;;
        3|*)
            echo "Aborted"
            exit 0
            ;;
    esac
else
    echo "Creating new connection..."
fi

# Delete any remaining connection (in case of cleanup)
if [ -z "$CONNECTION_EXISTS" ]; then
    echo "Removing any existing connection..."
    nmcli con delete "$CONNECTION_NAME" 2>/dev/null || true
fi

# Create new access point connection
if [ -z "$CONNECTION_EXISTS" ]; then
    echo "Creating access point connection..."
    nmcli con add type wifi ifname "$INTERFACE" mode ap con-name "$CONNECTION_NAME" ssid "$SSID"
else
    echo "Updating existing connection configuration..."
fi

# Configure wireless settings
echo "Configuring wireless settings..."
nmcli con modify "$CONNECTION_NAME" 802-11-wireless.band "$BAND_VALUE"
nmcli con modify "$CONNECTION_NAME" 802-11-wireless.channel "$CHANNEL"

# Configure IP settings
echo "Configuring IP settings..."
nmcli con modify "$CONNECTION_NAME" ipv4.method shared
nmcli con modify "$CONNECTION_NAME" ipv4.address "$IP_ADDRESS"
nmcli con modify "$CONNECTION_NAME" ipv6.method disabled

# Configure security settings
echo "Configuring security settings..."
nmcli con modify "$CONNECTION_NAME" wifi-sec.key-mgmt wpa-psk
nmcli con modify "$CONNECTION_NAME" wifi-sec.psk "$PASSWORD"
nmcli con modify "$CONNECTION_NAME" wifi-sec.proto rsn
nmcli con modify "$CONNECTION_NAME" wifi-sec.pairwise ccmp
nmcli con modify "$CONNECTION_NAME" wifi-sec.group ccmp
nmcli con modify "$CONNECTION_NAME" 802-11-wireless-security.wps-method disabled

# Bring up the connection
echo "Starting access point..."
if nmcli con up "$CONNECTION_NAME"; then
    echo ""
    echo "SUCCESS: WiFi Access Point successfully created!"
    echo "  SSID: $SSID"
    echo "  Interface: $INTERFACE"
    echo "  Band: ${BAND}GHz"
    echo "  Password: $PASSWORD"
    echo "  Channel: $CHANNEL"
    echo "  IP Address: $IP_ADDRESS"
    echo "  Connection Name: $CONNECTION_NAME"
    echo ""
    echo "Clients can now connect to your access point."
    
    # Show connection status
    echo "Connection status:"
    nmcli con show "$CONNECTION_NAME" | grep -E "(connection.id|connection.interface-name|802-11-wireless.ssid|802-11-wireless.band|802-11-wireless.channel|ipv4.addresses)"
else
    echo "FAILED: Failed to start access point"
    echo "You may need to check if the wireless interface supports AP mode or if there are conflicting connections."
    echo ""
    echo "Interface capabilities:"
    iw phy | grep -A 20 "Supported interface modes" | head -15 2>/dev/null || echo "iw command not available"
    exit 1
fi