# WiFi Access Point Scripts for Jetson Orin Nano

A collection of scripts to easily set up, manage, and reset WiFi access points on NVIDIA Jetson Orin Nano devices.

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
sudo ./wifi-ap.sh "MyJetsonAP" "mypassword123"

# Specify interface explicitly
sudo ./wifi-ap.sh "MyJetsonAP" "mypassword123" wlan0

# Advanced configuration
sudo ./wifi-ap.sh "MyNetwork" "securepass" wlan1 11 192.168.10.1/24

# Skip confirmation prompts (for scripting)
sudo ./wifi-ap.sh "MyAP" "password" wlan0 --force

# Replace existing configuration automatically
sudo ./wifi-ap.sh "UpdatedAP" "newpass" --replace
```

### Using Sudo Wrappers (Recommended)

```bash
# Automatically handles sudo privileges
./wifi-ap-sudo.sh "MyJetsonAP" "mypassword123"
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

## 📖 Detailed Usage

### Main Script: `wifi-ap.sh`

```bash
sudo ./wifi-ap.sh <SSID> <PASSWORD> [INTERFACE] [CHANNEL] [IP_ADDRESS] [OPTIONS]
```

#### Parameters

- **SSID** (required): Name of the WiFi access point
- **PASSWORD** (required): Password for the access point (minimum 8 characters)
- **INTERFACE** (optional): WiFi interface to use (wlan0, wlan1, etc.)
- **CHANNEL** (optional): WiFi channel (default: 7)
- **IP_ADDRESS** (optional): IP address for the access point (default: 192.168.4.1/24)

#### Options

- `--force`: Skip confirmation prompts (useful for scripted usage)
- `--replace`: Automatically replace existing connections
- `--reset`: Remove all AP connections and restore client mode

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
sudo ./wifi-ap-control.sh start MyJetsonAP-AP wlan1

# Stop all access points
sudo ./wifi-ap-control.sh stop

# Delete a specific AP configuration
sudo ./wifi-ap-control.sh delete MyJetsonAP-AP
```

## 🔧 Requirements

- NVIDIA Jetson Orin Nano (or compatible device)
- NetworkManager (`nmcli` command)
- Root privileges (sudo)
- At least one WiFi interface

## ⚠️ Important Notes

### Security Considerations

- Access point passwords must be at least 8 characters long
- WPA2 security is automatically configured
- Consider using strong, unique passwords for production use

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
sudo ./wifi-ap.sh "MyAP" "password"
# OR
./wifi-ap-sudo.sh "MyAP" "password"
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
sudo ./wifi-ap.sh "MyAP" "password" --replace

# Or manually delete existing connection
sudo ./wifi-ap-control.sh delete "MyAP-AP"
```

**Interface Busy**
```bash
# Reset to clean state
sudo ./wifi-ap.sh --reset

# Then recreate your access point
sudo ./wifi-ap.sh "MyAP" "password"
```

## 📝 Examples

### Basic Home Network

```bash
# Create a simple home access point
./wifi-ap-sudo.sh "JetsonHome" "familypassword123"
```

### Development Network

```bash
# Create development AP with custom settings
sudo ./wifi-ap.sh "JetsonDev" "devpassword" wlan1 6 192.168.100.1/24 --force
```

### Temporary Testing

```bash
# Quick test setup
sudo ./wifi-ap.sh "TestAP" "testpass123" --force

# Clean up when done
sudo ./wifi-ap.sh --reset --force
```

### Production Deployment

```bash
# Scripted deployment with error handling
if sudo ./wifi-ap.sh "ProductionAP" "$(cat /secure/ap_password)" wlan0 --force; then
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