# Litra Tray

A KDE Plasma system tray application for controlling Logitech Litra Glow lights with real-time control.

![License](https://img.shields.io/badge/license-MIT-blue.svg)
![Platform](https://img.shields.io/badge/platform-Linux-lightgrey.svg)

## Features

- **System Tray Integration** - Lives in your KDE Plasma system tray
- **Real-time Control** - Adjust brightness and temperature on the fly
- **Power Toggle** - Quick on/off switching
- **Brightness Control** - Slider for 0-100% brightness adjustment
- **Temperature Control** - Color temperature from 2700K (warm) to 6500K (cool)
- **Presets** - Quick access to common configurations:
  - Bright & Cool (100%, 6500K)
  - Medium & Neutral (50%, 4500K)
  - Warm & Dim (30%, 2700K)
- **Wayland Support** - Works perfectly on KDE Plasma Wayland

## Prerequisites

This application requires the [litra](https://github.com/timrogers/litra-rs) CLI tool to be installed and accessible in your PATH.

On NixOS, this is typically configured via the `modules/desktop/litra-glow.nix` module.

## Installation

### Method 1: Using Flakes (Recommended)

```bash
# From the tray directory
cd /home/nicholas/git/litra-rs/tray

# Run directly
nix run

# Or build and install
nix build
./result/bin/litra-tray
```

### Method 2: Traditional Nix

```bash
# Build the package
nix-build

# Run the application
./result/bin/litra-tray
```

### Method 3: Development Mode

```bash
# Enter development shell (flakes)
nix develop

# Or with traditional nix
nix-shell

# Run the application
python src/litra_tray.py
```

## Integration with NixOS

Add this to your NixOS configuration:

### Using Flake Input

Add to your `/etc/nixos/flake.nix`:

```nix
inputs = {
  litra-tray.url = "git+file:///home/nicholas/git/litra-rs?dir=tray";
  # Or from GitHub after publishing:
  # litra-tray.url = "github:yourusername/litra-rs?dir=tray";
};

outputs = { self, nixpkgs, litra-tray, ... }: {
  nixosConfigurations.cmos = {
    modules = [
      ({ pkgs, ... }: {
        environment.systemPackages = [
          litra-tray.packages.${pkgs.system}.default
        ];
      })
    ];
  };
};
```

### Using Direct Import

Add to your `/etc/nixos/modules/desktop/packages.nix`:

```nix
{
  environment.systemPackages = [
    (pkgs.callPackage /home/nicholas/git/litra-rs/tray {})
  ];
}
```

## Usage

### Starting the Application

```bash
litra-tray
```

The application will:
1. Show an icon in your system tray
2. Open a control panel on first launch
3. Stay running in the background

### Controls

**System Tray Icon:**
- **Left Click** - Show/hide control panel
- **Right Click** - Open context menu with quick actions

**Control Panel:**
- **Power Button** - Toggle light on/off
- **Brightness Slider** - Adjust brightness (0-100%)
- **Temperature Slider** - Adjust color temperature (2700K-6500K)

**Context Menu:**
- **Toggle Light** - Quick on/off without opening panel
- **Show Controls** - Open the control panel
- **Presets** - Apply predefined configurations
- **Quit** - Exit the application

### Autostart

To start automatically with KDE Plasma:

```bash
# Create autostart directory
mkdir -p ~/.config/autostart

# Create desktop entry
cat > ~/.config/autostart/litra-tray.desktop <<EOF
[Desktop Entry]
Type=Application
Name=Litra Tray
Exec=litra-tray
X-KDE-autostart-after=panel
EOF
```

Or declaratively in NixOS (recommended):

```nix
# In your home-manager or system configuration
xdg.configFile."autostart/litra-tray.desktop" = {
  text = ''
    [Desktop Entry]
    Type=Application
    Name=Litra Tray
    Exec=litra-tray
    X-KDE-autostart-after=panel
  '';
};
```

## Development

### Requirements

- Python 3.11+
- PyQt6
- Qt6 Wayland support
- litra CLI tool

### Project Structure

```
tray/
├── src/
│   └── litra_tray.py      # Main application
├── flake.nix              # Nix flake for modern builds
├── shell.nix              # Development shell
├── default.nix            # Package definition
└── README.md              # This file
```

### Building from Source

```bash
# Enter development environment
nix develop

# Run with debugging
python src/litra_tray.py

# Build package
nix build

# Test the built package
./result/bin/litra-tray
```

### Testing

```bash
# Test litra CLI is available
litra --version

# Test litra device detection
litra devices

# Test basic commands
litra on
litra brightness 50
litra temperature 4500
litra off
```

## Troubleshooting

### Application doesn't start

1. Check if litra CLI is available:
   ```bash
   which litra
   litra --version
   ```

2. Verify device permissions (you should be in the `video` group):
   ```bash
   groups | grep video
   ```

3. Test device detection:
   ```bash
   litra devices
   ```

### Wayland issues

If the window doesn't appear correctly:

```bash
# Try forcing Wayland
export QT_QPA_PLATFORM=wayland
litra-tray

# Or force X11 as fallback
export QT_QPA_PLATFORM=xcb
litra-tray
```

### Controls don't work

1. Ensure the Litra device is connected:
   ```bash
   lsusb | grep -i logitech
   ```

2. Check permissions:
   ```bash
   ls -la /dev/hidraw*
   ```

3. Test manual control:
   ```bash
   litra on
   litra brightness 100
   ```

## License

MIT License - See LICENSE file for details

## Credits

- Uses [litra-rs](https://github.com/timrogers/litra-rs) by Tim Rogers for device control
- Built with PyQt6 for KDE Plasma integration
- Packaged with Nix for reproducible builds

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## Roadmap

- [ ] Custom preset management
- [ ] Device auto-detection and selection
- [ ] Settings persistence
- [ ] Keyboard shortcuts
- [ ] Multiple device support
- [ ] Scheduling/automation
- [ ] Desktop notification integration
