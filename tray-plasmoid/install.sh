#!/usr/bin/env bash
# Install/upgrade the Litra plasmoid into the user's local plasma share.
# Requires `kpackagetool6` (Plasma 6) and the `litra` CLI in PATH.

set -euo pipefail

cd "$(dirname "$0")"

PLUGIN_ID="io.github.clearcmos.litra"
PKG_DIR="$PWD/package"

if ! command -v kpackagetool6 >/dev/null 2>&1; then
    echo "kpackagetool6 not found - install plasma-workspace / kpackage" >&2
    exit 1
fi

if ! command -v litra >/dev/null 2>&1; then
    echo "warning: litra CLI not in PATH; the plasmoid will fail at runtime" >&2
fi

# Upgrade if already installed, otherwise install.
if kpackagetool6 -t Plasma/Applet -l 2>/dev/null | grep -qx "$PLUGIN_ID"; then
    echo "Upgrading $PLUGIN_ID..."
    kpackagetool6 -t Plasma/Applet -u "$PKG_DIR"
else
    echo "Installing $PLUGIN_ID..."
    kpackagetool6 -t Plasma/Applet -i "$PKG_DIR"
fi

echo
echo "Restart plasmashell to pick up changes:"
echo "  kquitapp6 plasmashell && (setsid plasmashell &) >/dev/null 2>&1"
echo
echo "Then add the widget by right-clicking the panel/system tray > 'Add or Manage Widgets'"
echo "and search for 'Litra Glow Control'."
