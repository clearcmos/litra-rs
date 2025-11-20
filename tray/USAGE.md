# Quick Start Guide

## Running the Application

### Option 1: Direct Run (Development)
```bash
cd /home/nicholas/git/litra-rs/tray
nix develop
python src/litra_tray.py
```

### Option 2: Build and Run
```bash
cd /home/nicholas/git/litra-rs/tray
nix build
./result/bin/litra-tray
```

### Option 3: Run with Flakes
```bash
cd /home/nicholas/git/litra-rs/tray
nix run
```

## Features Overview

### System Tray Icon
- **Left Click**: Open/close control panel
- **Right Click**: Context menu with quick actions

### Control Panel
```
┌─────────────────────────┐
│  Litra Glow Control     │
├─────────────────────────┤
│  [Turn On/Off Button]   │
├─────────────────────────┤
│  Brightness: 50%        │
│  [=========|==========] │
├─────────────────────────┤
│  Temperature: 4500K     │
│  [=========|==========] │
│  Warm (2700K)  Cool...  │
└─────────────────────────┘
```

### Quick Presets (Right-click menu)
1. **Bright & Cool**: 100% brightness @ 6500K
2. **Medium & Neutral**: 50% brightness @ 4500K
3. **Warm & Dim**: 30% brightness @ 2700K

## Keyboard Shortcuts
- **Ctrl+Q**: Quit (when control panel is focused)

## Autostart Setup

The application will NOT start automatically by default. To enable autostart:

```bash
mkdir -p ~/.config/autostart
cp /home/nicholas/git/litra-rs/tray/litra-tray.desktop ~/.config/autostart/
```

## Troubleshooting

### "litra command not found"
```bash
# Check if litra is installed
which litra

# On NixOS, ensure the litra-glow module is enabled
# (should be in /etc/nixos/modules/desktop/litra-glow.nix)
```

### Device not detected
```bash
# Check USB connection
lsusb | grep -i logitech

# Check device permissions
litra devices

# Verify you're in the video group
groups | grep video
```

### Application doesn't appear in system tray
```bash
# Force Wayland mode
QT_QPA_PLATFORM=wayland litra-tray

# Or try X11 fallback
QT_QPA_PLATFORM=xcb litra-tray
```

## Advanced Configuration

### Custom Icon
Replace the system icon by editing `src/litra_tray.py`:
```python
self.setIcon(QIcon.fromTheme("your-icon-name"))
# or
self.setIcon(QIcon("/path/to/custom/icon.png"))
```

### Modify Presets
Edit the `apply_preset` calls in `src/litra_tray.py`:
```python
# Example: Add a "Reading" preset
reading_action = QAction("Reading (70%, 3500K)", self)
reading_action.triggered.connect(lambda: self.apply_preset(70, 3500))
preset_menu.addAction(reading_action)
```

## Integration with NixOS

Add to `/etc/nixos/modules/desktop/packages.nix`:

```nix
{ pkgs, ... }:

{
  environment.systemPackages = [
    # ... existing packages ...
    (pkgs.callPackage /home/nicholas/git/litra-rs/tray {})
  ];
}
```

Then rebuild:
```bash
cd /etc/nixos
git add /home/nicholas/git/litra-rs/tray
nixos-rebuild switch --flake .#cmos
```
