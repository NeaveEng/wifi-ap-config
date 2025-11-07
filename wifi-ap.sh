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

# Function to display usage information
show_usage() {
    echo "Usage: sudo $0 <SSID> <PASSWORD> [INTERFACE] [CHANNEL] [IP_ADDRESS]"
    echo ""
    echo "Note: This script requires root privileges (sudo)"
    echo ""
    echo "Arguments:"
    echo "  SSID        - Name of the WiFi access point (required)"
    echo "  PASSWORD    - Password for the access point (required, min 8 characters)"
    echo "  INTERFACE   - WiFi interface to use (optional, default: auto-detect)"
    echo "  CHANNEL     - WiFi channel (optional, default: 7)"
    echo "  IP_ADDRESS  - IP address for the access point (optional, default: 192.168.4.1/24)"
    echo ""
    echo "Options:"
    echo "  --force     - Skip confirmation prompts (for scripted usage)"
    echo "  --replace   - Automatically replace existing connections"
    echo "  --reset     - Remove all AP connections and restore client mode"
    echo ""
    echo "Examples:"
    echo "  sudo $0 MyJetsonAP mypassword123"
    echo "  sudo $0 JetsonNetwork secretpass wlan0 11 192.168.10.1/24"
    echo "  sudo $0 \"My Jetson AP\" \"my secure password\" wlan1 6 --force"
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

# Check minimum required arguments (unless using --reset)
if [ $# -lt 2 ] && [[ "$1" != "--reset" ]]; then
    echo "Error: Missing required arguments"
    echo ""
    show_usage
fi

# Parse options
FORCE_MODE=""
REPLACE_MODE=""
ARGS=()

for arg in "$@"; do
    case $arg in
        --force)
            FORCE_MODE="yes"
            ;;
        --replace)
            REPLACE_MODE="yes"
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
CHANNEL="${ARGS[3]:-7}"
IP_ADDRESS="${ARGS[4]:-192.168.4.1/24}"

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

# Validate channel (1-14 for 2.4GHz)
if ! [[ "$CHANNEL" =~ ^[0-9]+$ ]] || [ "$CHANNEL" -lt 1 ] || [ "$CHANNEL" -gt 14 ]; then
    echo "Error: Channel must be a number between 1 and 14"
    exit 1
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
echo "Channel: $CHANNEL"
echo "IP Address: $IP_ADDRESS"
echo "Connection Name: $CONNECTION_NAME"
echo ""

# Check what will happen
CONNECTION_EXISTS=""
if nmcli con show "$CONNECTION_NAME" >/dev/null 2>&1; then
    CONNECTION_EXISTS="yes"
    CURRENT_STATE=$(nmcli -t -f STATE con show "$CONNECTION_NAME")
    echo "STATUS: Connection '$CONNECTION_NAME' already exists (State: $CURRENT_STATE)"
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
    CURRENT_STATE=$(nmcli -t -f STATE con show "$CONNECTION_NAME")
    if [ "$CURRENT_STATE" = "activated" ]; then
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
nmcli con modify "$CONNECTION_NAME" 802-11-wireless.band bg
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
    echo "  Password: $PASSWORD"
    echo "  Channel: $CHANNEL"
    echo "  IP Address: $IP_ADDRESS"
    echo "  Connection Name: $CONNECTION_NAME"
    echo ""
    echo "Clients can now connect to your access point."
    
    # Show connection status
    echo "Connection status:"
    nmcli con show "$CONNECTION_NAME" | grep -E "(connection.id|connection.interface-name|802-11-wireless.ssid|802-11-wireless.channel|ipv4.addresses)"
else
    echo "FAILED: Failed to start access point"
    echo "You may need to check if the wireless interface supports AP mode or if there are conflicting connections."
    echo ""
    echo "Interface capabilities:"
    iw phy | grep -A 20 "Supported interface modes" | head -15 2>/dev/null || echo "iw command not available"
    exit 1
fi