#!/bin/bash

# WiFi Access Point Management Script for Jetson Orin Nano
# Usage: ./wifi-ap-control.sh [start|stop|restart|status|list|interfaces|delete]

# Check if running as root for operations that need it
check_privileges_if_needed() {
    local command="$1"
    
    # Commands that need root privileges
    case "$command" in
        "start"|"stop"|"restart"|"delete")
            if [ "$EUID" -ne 0 ]; then
                echo "Error: The '$command' operation requires root privileges."
                echo ""
                echo "Please run with sudo:"
                echo "  sudo $0 $*"
                exit 1
            fi
            ;;
        "status"|"list"|"interfaces")
            # These commands can run without root
            ;;
    esac
}

show_usage() {
    echo "Usage: $0 [COMMAND] [CONNECTION_NAME] [INTERFACE]"
    echo ""
    echo "Commands:"
    echo "  start [name] [interface]   - Start access point connection"
    echo "  stop [name]               - Stop access point connection (default: all APs)"
    echo "  restart [name] [interface] - Restart access point connection"
    echo "  status [name]             - Show status of access point(s)"
    echo "  list                      - List all WiFi connections"
    echo "  delete [name]             - Delete access point connection"
    echo "  interfaces                - Show available WiFi interfaces"
    echo ""
    echo "Examples:"
    echo "  $0 status"
    echo "  $0 start MyJetsonAP-AP wlan1"
    echo "  $0 stop MyJetsonAP-AP"
    echo "  $0 restart"
    echo "  $0 interfaces"
    exit 1
}

# Function to find AP connections
find_ap_connections() {
    nmcli -t -f NAME,TYPE con show | grep ":802-11-wireless" | cut -d: -f1 | grep -E ".*-AP$|.*AP$" 2>/dev/null || true
}

# Function to get active AP connections
get_active_ap_connections() {
    nmcli -t -f NAME,TYPE,STATE con show | grep ":802-11-wireless:activated" | cut -d: -f1 | grep -E ".*-AP$|.*AP$" 2>/dev/null || true
}

COMMAND="${1:-status}"
CONNECTION_NAME="$2"
INTERFACE="$3"

# Check privileges for operations that need them
check_privileges_if_needed "$COMMAND"

case "$COMMAND" in
    "start")
        if [ -n "$CONNECTION_NAME" ]; then
            echo "Starting access point: $CONNECTION_NAME"
            if nmcli con up "$CONNECTION_NAME"; then
                echo "SUCCESS: Access point started successfully"
            else
                echo "FAILED: Failed to start access point"
                exit 1
            fi
        else
            # Find first AP connection
            AP_CONNECTIONS=$(find_ap_connections)
            if [ -z "$AP_CONNECTIONS" ]; then
                echo "No access point connections found"
                echo "Create one first with: ./wifi-ap.sh <SSID> <PASSWORD>"
                exit 1
            fi
            
            FIRST_AP=$(echo "$AP_CONNECTIONS" | head -n1)
            echo "Starting access point: $FIRST_AP"
            if nmcli con up "$FIRST_AP"; then
                echo "SUCCESS: Access point started successfully"
            else
                echo "FAILED: Failed to start access point"
                exit 1
            fi
        fi
        ;;
        
    "stop")
        if [ -n "$CONNECTION_NAME" ]; then
            echo "Stopping access point: $CONNECTION_NAME"
            if nmcli con down "$CONNECTION_NAME"; then
                echo "SUCCESS: Access point stopped successfully"
            else
                echo "FAILED: Failed to stop access point (may not be active)"
            fi
        else
            # Stop all active AP connections
            ACTIVE_APS=$(get_active_ap_connections)
            if [ -z "$ACTIVE_APS" ]; then
                echo "No active access points found"
            else
                echo "Stopping all active access points..."
                for ap in $ACTIVE_APS; do
                    echo "  Stopping: $ap"
                    nmcli con down "$ap" || true
                done
                echo "SUCCESS: All access points stopped"
            fi
        fi
        ;;
        
    "restart")
        if [ -n "$CONNECTION_NAME" ]; then
            echo "Restarting access point: $CONNECTION_NAME"
            nmcli con down "$CONNECTION_NAME" 2>/dev/null || true
            sleep 2
            if nmcli con up "$CONNECTION_NAME"; then
                echo "SUCCESS: Access point restarted successfully"
            else
                echo "FAILED: Failed to restart access point"
                exit 1
            fi
        else
            # Restart first AP found
            AP_CONNECTIONS=$(find_ap_connections)
            if [ -z "$AP_CONNECTIONS" ]; then
                echo "No access point connections found"
                exit 1
            fi
            
            FIRST_AP=$(echo "$AP_CONNECTIONS" | head -n1)
            echo "Restarting access point: $FIRST_AP"
            nmcli con down "$FIRST_AP" 2>/dev/null || true
            sleep 2
            if nmcli con up "$FIRST_AP"; then
                echo "SUCCESS: Access point restarted successfully"
            else
                echo "FAILED: Failed to restart access point"
                exit 1
            fi
        fi
        ;;
        
    "status")
        echo "=== WiFi Access Point Status ==="
        echo ""
        
        if [ -n "$CONNECTION_NAME" ]; then
            # Show specific connection
            if nmcli con show "$CONNECTION_NAME" >/dev/null 2>&1; then
                echo "Connection: $CONNECTION_NAME"
                STATE=$(nmcli -t -f STATE con show "$CONNECTION_NAME")
                echo "State: $STATE"
                
                if [ "$STATE" = "activated" ]; then
                    echo ""
                    echo "Configuration:"
                    nmcli con show "$CONNECTION_NAME" | grep -E "(connection.interface-name|802-11-wireless.ssid|802-11-wireless.channel|ipv4.addresses|wifi-sec.key-mgmt)"
                    
                    echo ""
                    echo "Interface status:"
                    nmcli dev status | grep wlan
                fi
            else
                echo "Connection '$CONNECTION_NAME' not found"
                exit 1
            fi
        else
            # Show all AP connections
            AP_CONNECTIONS=$(find_ap_connections)
            ACTIVE_APS=$(get_active_ap_connections)
            
            if [ -z "$AP_CONNECTIONS" ]; then
                echo "No access point connections configured"
                echo ""
                echo "Create one with: ./wifi-ap.sh <SSID> <PASSWORD>"
            else
                echo "Available access point connections:"
                for ap in $AP_CONNECTIONS; do
                    STATE=$(nmcli -t -f STATE con show "$ap")
                    if echo "$ACTIVE_APS" | grep -q "^$ap$"; then
                        echo "  [ACTIVE] $ap"
                    else
                        echo "  [INACTIVE] $ap"
                    fi
                done
                
                echo ""
                echo "WiFi interface status:"
                nmcli dev status | grep -E "(DEVICE|wifi)" || echo "No WiFi interfaces found"
                
                if [ -n "$ACTIVE_APS" ]; then
                    echo ""
                    echo "Active access point details:"
                    for ap in $ACTIVE_APS; do
                        echo ""
                        echo "Connection: $ap"
                        nmcli con show "$ap" | grep -E "(connection.interface-name|802-11-wireless.ssid|802-11-wireless.channel|ipv4.addresses)"
                    done
                fi
            fi
        fi
        ;;
        
    "interfaces")
        echo "=== Available WiFi Interfaces ==="
        echo ""
        nmcli dev status | grep wifi | while read interface type state connection; do
            echo "Interface: $interface"
            echo "  Type: $type"
            echo "  State: $state"
            if [ "$connection" != "--" ]; then
                echo "  Connection: $connection"
            fi
            
            # Check AP mode capability if iw is available
            if command -v iw >/dev/null 2>&1; then
                phy=$(iw dev "$interface" info 2>/dev/null | grep wiphy | awk '{print $2}')
                if [ -n "$phy" ]; then
                    if iw phy "phy$phy" info 2>/dev/null | grep -q "AP"; then
                        echo "  AP Mode: Supported"
                    else
                        echo "  AP Mode: Not supported"
                    fi
                fi
            fi
            echo ""
        done
        ;;
        
    "list")
        echo "=== All WiFi Connections ==="
        nmcli con show | grep -E "(NAME|wifi)"
        ;;
        
    "delete")
        if [ -z "$CONNECTION_NAME" ]; then
            echo "Error: Connection name required for delete command"
            echo "Usage: $0 delete <CONNECTION_NAME>"
            exit 1
        fi
        
        echo "Deleting access point connection: $CONNECTION_NAME"
        if nmcli con delete "$CONNECTION_NAME"; then
            echo "SUCCESS: Connection deleted successfully"
        else
            echo "FAILED: Failed to delete connection"
            exit 1
        fi
        ;;
        
    "-h"|"--help")
        show_usage
        ;;
        
    *)
        echo "Error: Unknown command '$COMMAND'"
        echo ""
        show_usage
        ;;
esac