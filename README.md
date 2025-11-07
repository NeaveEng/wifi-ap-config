# WiFi Access Point Scripts for Linux Devices

A collection of scripts to easily set up, manage, and reset WiFi access points on Linux devices. Only tested on Jetson Orin Nano but should work on any machine running Network Manager.

## 📋 Overview

These scripts provide a simple command-line interface for creating and managing WiFi access points using NetworkManager. The scripts handle interface detection, configuration validation, and provide safety features like confirmation prompts and clean reset functionality.

## 📁 Files

| Script | Purpose |
|--------|---------|
| `wifi-ap.sh` | Main script for creating access points and resetting configurations |
| `wifi-ap-sudo.sh` | Sudo wrapper for automatic privilege escalation |
| `wifi-ap-reset.sh` | Dedicated reset script for cleaning up AP configurations |
| `wifi-ap-control.sh` | Management script for start/stop/status operations |
| `wifi-ap-control-sudo.sh` | Sudo wrapper for the control script |

## 🚀 Quick Start

### Creating an Access Point

```bash
# Basic usage (will prompt to choose interface if multiple available)
sudo ./wifi-ap.sh "MyAP" "mypassword123"

# Specify interface explicitly
sudo ./wifi-ap.sh "MyAP" "mypassword123" wlan0

# Use 5GHz band (if hardware supports it)
sudo ./wifi-ap.sh "MyAP" "mypassword123" wlan0 36 5

# Auto-select best channel (scans for least congested)
sudo ./wifi-ap.sh "MyAP" "mypassword123" wlan0 auto

# 5GHz with auto channel selection
sudo ./wifi-ap.sh "MyAP" "mypassword123" wlan0 auto --band=5

# Skip confirmation prompts (for scripting)
sudo ./wifi-ap.sh "MyAP" "mypassword123" wlan0 --force

# Replace existing configuration automatically
sudo ./wifi-ap.sh "MyAP" "mypassword123" --replace
```

### Using Sudo Wrappers (Recommended)

```bash
# Automatically handles sudo privileges
./wifi-ap-sudo.sh "MyAP" "mypassword123"
```

### Resetting to Client Mode

```bash
# Remove all AP configurations and restore client mode
sudo ./wifi-ap.sh --reset

# Silent reset (no confirmation)
sudo ./wifi-ap.sh --reset --force

# Using dedicated reset script
./wifi-ap-reset.sh
```

### Updating Existing Access Point

```bash
# Switch band from 2.4GHz to 5GHz
sudo ./wifi-ap.sh --update-band MyAP-AP 5 149

# Switch to 2.4GHz with auto channel selection
sudo ./wifi-ap.sh --update-band MyAP-AP 2.4 auto

# Change band while keeping AP running (preserves SSID, password, etc.)
sudo ./wifi-ap.sh --update-band MyAP-AP 5
```

## 📖 Detailed Usage

### Main Script: `wifi-ap.sh`

```bash
sudo ./wifi-ap.sh <SSID> <PASSWORD> [INTERFACE] [CHANNEL] [IP_ADDRESS] [BAND] [OPTIONS]
```

#### Parameters

- **SSID** (required): Name of the WiFi access point
- **PASSWORD** (required): Password for the access point (minimum 8 characters)
- **INTERFACE** (optional): WiFi interface to use (wlan0, wlan1, etc.)
- **CHANNEL** (optional): WiFi channel or 'auto' for automatic selection (default: 7 for 2.4GHz, 36 for 5GHz)
- **IP_ADDRESS** (optional): IP address for the access point (default: 192.168.4.1/24)
- **BAND** (optional): WiFi band - 2.4 or 5 (default: 2.4)

#### Options

- `--force`: Skip confirmation prompts (useful for scripted usage)
- `--replace`: Automatically replace existing connections
- `--reset`: Remove all AP connections and restore client mode
- `--band=2.4` or `--band=5`: Specify WiFi band
- `--update-band=<CONNECTION_NAME> <BAND> [CHANNEL]`: Update band/channel of existing AP

#### New Features

**Automatic Channel Selection**
- Use `auto` as the channel parameter to scan nearby networks
- Automatically selects the least congested channel
- For 2.4GHz: Chooses among non-overlapping channels 1, 6, 11
- For 5GHz: Selects from common channels (36, 40, 44, 48, 149, 153, 157, 161, 165)
- Excludes your own AP from interference calculations

**Dual-Band Support (2.4GHz / 5GHz)**
- Hardware capability checking ensures compatibility
- Automatic validation of channel numbers for selected band
- 2.4GHz channels: 1-14
- 5GHz channels: 36, 40, 44, 48, 52-64, 100-144, 149-165 (varies by region)

**Band Switching**
- Update existing AP's band without recreating it
- Preserves SSID, password, and other settings
- Automatically restarts AP with new configuration

**WPS Disabled**
- WPS (PIN authentication) is explicitly disabled
- Uses standard WPA2-PSK with password authentication
- Improved security with WPA2-AES (CCMP) encryption

**DHCP Server**
- Automatically runs dnsmasq for client IP assignment
- NetworkManager's shared connection mode handles NAT/forwarding
- No manual configuration required

#### Interface Auto-Detection Logic

The script uses intelligent interface detection:

1. **Existing AP**: If an interface is already running an AP, defaults to updating that interface
2. **Multiple Interfaces**: Forces user to specify which interface to use
3. **Single Interface**: Automatically selects the only available managed interface
4. **Filters**: Excludes P2P interfaces (`p2p-dev-*`) and unmanaged interfaces

### Control Script: `wifi-ap-control.sh`

```bash
sudo ./wifi-ap-control.sh [COMMAND] [CONNECTION_NAME] [INTERFACE]
```

#### Commands

- `start [name] [interface]`: Start access point connection
- `stop [name]`: Stop access point connection (default: all APs)
- `restart [name] [interface]`: Restart access point connection
- `status [name]`: Show status of access point(s)
- `list`: List all WiFi connections
- `delete [name]`: Delete access point connection
- `interfaces`: Show available WiFi interfaces

#### Examples

```bash
# Show status of all access points
sudo ./wifi-ap-control.sh status

# Start a specific AP
sudo ./wifi-ap-control.sh start MyAP-AP wlan1

# Stop all access points
sudo ./wifi-ap-control.sh stop

# Delete a specific AP configuration
sudo ./wifi-ap-control.sh delete MyAP-AP
```

## 🔧 Requirements

- NVIDIA Jetson Orin Nano (or compatible device)
- NetworkManager (`nmcli` command)
- Root privileges (sudo)
- At least one WiFi interface

## ⚠️ Important Notes

### Security Considerations

- Access point passwords must be at least 8 characters long
- WPA2-PSK security with AES-CCMP encryption is automatically configured
- WPS (WiFi Protected Setup) is explicitly disabled for better security
- DHCP server automatically assigns IP addresses to clients
- Consider using strong, unique passwords for production use

### Hardware Compatibility

- **Band Support**: Script automatically checks if your WiFi adapter supports the requested band
- **2.4GHz Only**: Some adapters only support 2.4GHz (channels 1-14)
- **Dual-Band**: Modern adapters support both 2.4GHz and 5GHz
- The script will display an error if you try to use an unsupported band
- Use `iw phy` to check your hardware capabilities

### Interface Management

- The scripts work with regular WiFi interfaces (`wlan0`, `wlan1`)
- P2P interfaces (`p2p-dev-*`) are not suitable for access points
- Unmanaged interfaces are ignored during auto-detection

### Connection Behavior

- Creating an AP will disconnect the interface from any existing client connections
- The reset function cleanly removes all AP configurations
- Multiple APs can run simultaneously on different interfaces

## 🐛 Troubleshooting

### Common Issues

**Permission Denied**
```bash
# Solution: Use sudo or the wrapper scripts
sudo ./wifi-ap.sh "MyAP" "mypassword123"
# OR
./wifi-ap-sudo.sh "MyAP" "mypassword123"
```

**No WiFi Interfaces Found**
```bash
# Check available interfaces
nmcli dev status | grep wifi

# Ensure NetworkManager is running
sudo systemctl status NetworkManager
```

**Connection Already Exists**
```bash
# Use --replace flag to automatically replace
sudo ./wifi-ap.sh "MyAP" "mypassword123" --replace

# Or manually delete existing connection
sudo ./wifi-ap-control.sh delete "MyAP-AP"
```

**Unsupported Band**
```bash
# Error: Interface 'wlan1' does not support 5GHz band
# Solution: Check supported bands
iw phy | grep -A 5 "Band"

# Use a dual-band adapter or switch to 2.4GHz
sudo ./wifi-ap.sh "MyAP" "mypassword123" wlan0 --band=5  # Use wlan0 instead
# OR
sudo ./wifi-ap.sh "MyAP" "mypassword123" wlan1 --band=2.4  # Use 2.4GHz
```

**Clients Can't Connect (PIN Required)**
```bash
# This has been fixed - WPS is now disabled by default
# If using an older version, update to the latest script
# The script now uses WPA2-PSK with password authentication
```

**Interface Busy**
```bash
# Reset to clean state
sudo ./wifi-ap.sh --reset

# Then recreate your access point
sudo ./wifi-ap.sh "MyAP" "mypassword123"
```

## 📝 Examples

### Basic Home Network

```bash
# Create a simple home access point (2.4GHz)
./wifi-ap-sudo.sh "MyAP" "mypassword123"

# 5GHz for better performance (if supported)
sudo ./wifi-ap.sh "MyAP" "mypassword123" wlan0 --band=5
```

### Auto Channel Selection

```bash
# Let the script find the best 2.4GHz channel
sudo ./wifi-ap.sh "MyAP" "mypassword123" wlan0 auto

# Best 5GHz channel
sudo ./wifi-ap.sh "MyAP" "mypassword123" wlan0 auto --band=5
```

### Development Network

```bash
# Create development AP with custom settings
sudo ./wifi-ap.sh "MyAP" "mypassword123" wlan1 6 192.168.100.1/24 2.4 --force

# High-speed 5GHz development network
sudo ./wifi-ap.sh "MyAP" "mypassword123" wlan0 149 192.168.100.1/24 5
```

### Switching Bands

```bash
# Switch existing AP from 2.4GHz to 5GHz
sudo ./wifi-ap.sh --update-band MyAP-AP 5 149

# Switch to 2.4GHz with automatic channel selection
sudo ./wifi-ap.sh --update-band MyAP-AP 2.4 auto

# Quick switch to 5GHz with default channel
sudo ./wifi-ap.sh --update-band MyAP-AP 5
```

### Temporary Testing

```bash
# Quick test setup
sudo ./wifi-ap.sh "MyAP" "mypassword123" --force

# Clean up when done
sudo ./wifi-ap.sh --reset --force
```

### Production Deployment

```bash
# Scripted deployment with error handling
if sudo ./wifi-ap.sh "MyAP" "$(cat /secure/ap_password)" wlan0 --force; then
    echo "Access point deployed successfully"
    sudo ./wifi-ap-control.sh status
else
    echo "Deployment failed"
    exit 1
fi
```

## 🔄 Script Workflow

1. **Privilege Check**: Verifies sudo/root access
2. **Parameter Validation**: Checks SSID, password length, and options
3. **Interface Detection**: Smart auto-detection or validation of specified interface
4. **Conflict Resolution**: Handles existing connections with user confirmation
5. **Configuration**: Creates NetworkManager connection with proper settings
6. **Activation**: Starts the access point and reports status

## 📚 Additional Resources

- [NetworkManager Documentation](https://networkmanager.dev/)
- [NVIDIA Jetson Orin Nano Developer Kit User Guide](https://developer.nvidia.com/embedded/jetson-orin-nano-developer-kit)
- [WiFi Access Point Configuration Guide](https://ubuntu.com/server/docs/network-configuration)

## ⚖️ Disclaimer

**This code was generated by AI (GitHub Copilot/Claude)** and should be reviewed and tested thoroughly before use in production environments. While the scripts include safety measures and error handling, users are responsible for:

- Testing in non-production environments first
- Understanding the security implications of running WiFi access points
- Ensuring compliance with local wireless regulations
- Monitoring and maintaining the access point configurations
- Backing up existing network configurations before use

The AI-generated code is provided "as-is" without warranties. Users should validate the functionality and security for their specific use cases.

## 📄 License

This project is provided for educational and development purposes. Please ensure compliance with your organization's policies and local regulations regarding WiFi access point deployment.

---

*Generated with AI assistance - Always review and test before production use*
