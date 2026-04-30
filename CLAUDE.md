# litra-rs (clearcmos fork)

Personal fork of [`timrogers/litra-rs`](https://github.com/timrogers/litra-rs), a Rust library, CLI, and MCP server for controlling Logitech Litra lights over USB HID. This fork adds two GUI front-ends on top of the upstream library: a native macOS menubar app and a KDE Plasma 6 plasmoid for Linux, plus an Arch `PKGBUILD` to build and install the CLI + plasmoid.

## Project structure

- `src/lib.rs` - public Rust API around the `hidapi` device. Power, brightness, temperature, back-light, RGB. Re-exported as the `litra` crate.
- `src/main.rs` - `litra` CLI binary. Subcommands for `on`/`off`/`toggle`/`brightness*`/`temperature*`/`devices`/`mcp`, plus `--serial-number`/`--device-path`/`--device-type` device filters.
- `src/mcp.rs` - MCP server (`litra mcp`) implemented with `rmcp`. Exposes the same operations as tools for AI clients.
- `src/menubar.rs` - **fork addition.** `litra-menubar` binary (egui + `tray-icon`). macOS menu bar icon with a popup window for power/brightness/temperature control of the selected device.
- `tray-plasmoid/` - **fork addition.** KDE Plasma 6 plasmoid (QML, `PlasmoidItem`). Shells out to the `litra` CLI; gets popup positioning automatically from Plasma's systray.
  - `tray-plasmoid/package/metadata.json` - plasmoid manifest (`X-Plasma-API-Minimum-Version: 6.0`).
  - `tray-plasmoid/package/contents/ui/main.qml` - the plasmoid (compact + full representations, throttled slider commands at ~12 Hz).
  - `tray-plasmoid/package/contents/icons/lightbulb-{on,off}.svg` - custom tray icons (the on-icon is a warm-yellow bulb with a glow halo, the off-icon is an outline that follows the panel's `currentColor`).
  - `tray-plasmoid/install.sh` - dev-mode installer; uses `kpackagetool6` to install/upgrade into `~/.local/share/plasma/plasmoids/`. The `PKGBUILD` does the same job system-wide.
- `PKGBUILD` - **fork addition.** Arch package (`litra-custom`) that builds the `litra` CLI, drops the udev rule into `/usr/lib/udev/rules.d/`, and installs the plasmoid system-wide to `/usr/share/plasma/plasmoids/io.github.clearcmos.litra/`. `optdepends` plasma-workspace.
- `99-litra.rules` - udev rules for non-root USB access on Linux (upstream).

## Build

Cargo features gate the optional binaries and integrations:

- `default = ["cli", "mcp"]`
- `cli` - enables `clap`/`serde`/`tabled` (the `litra` binary)
- `mcp` - enables `rmcp`/`tokio`/`tracing`/`schemars` (`litra mcp`); requires `cli`
- `menubar` - **fork-only.** Enables `eframe`/`tray-icon` (`litra-menubar` binary)

Common commands:

```bash
# CLI + MCP (default)
cargo build --release

# Library only (no CLI)
cargo build --no-default-features

# macOS menubar app
cargo build --bin litra-menubar --features menubar --release

# Arch package (builds CLI + installs udev rule + plasmoid system-wide)
makepkg -si

# KDE plasmoid (manual install for dev / non-Arch)
cd tray-plasmoid && ./install.sh
kquitapp6 plasmashell && (setsid plasmashell &) >/dev/null 2>&1
```

The Rust toolchain is pinned via `rust-toolchain.toml`. Linux builds require `libudev-dev` (and `libhidapi-dev` upstream, though hidapi is currently vendored in this fork).

## Code style

- Upstream uses `cargo fmt` and `cargo clippy`. Match that. Pre-commit workflow runs both.
- Don't introduce em dashes or double dashes in new prose (project rule).
- Plasmoid QML keeps imports versionless (Plasma 6 / Qt6 style) and uses `Plasma5Support.DataSource` with the `executable` engine for shell calls. Slider-driven commands are throttled (`sliderThrottleMs = 80`) with a trailing fire to avoid flooding the device.

## Fork changes (relative to `timrogers/litra-rs:main`)

As of the last sync the fork is up to date with upstream (merged through upstream's `47e838c`, v3.3.0 + post-release dep bumps) and adds the changes below on top.

### Added by this fork

1. **macOS menubar app** (`11ebd19`, refined in `cbaafc6`)
   - New file `src/menubar.rs` (~400 lines).
   - New `litra-menubar` binary entry in `Cargo.toml`, gated behind the `menubar` feature.
   - New optional deps: `eframe = "0.29"`, `tray-icon = "0.19"`.
   - `cbaafc6` improved device state handling when the device is in USB standby and added value clamping on the brightness/temperature sliders.
   - README section "macOS Menubar Application" added.

2. **KDE Plasma 6 plasmoid**
   - New `tray-plasmoid/` directory with a QML plasmoid (`PlasmoidItem` with compact + full representations), custom lightbulb SVGs, and a `kpackagetool6`-based installer.
   - Replaces an earlier Python+PyQt6 system tray app (deleted) that couldn't anchor its popup to the panel because StatusNotifierItem doesn't expose icon geometry to non-plasmoid clients.
   - The plasmoid shells out to `litra` rather than linking the library, so it's independent of the Rust build.

3. **Arch `PKGBUILD`** for the fork
   - Builds `litra` from `git+https://github.com/clearcmos/litra-rs.git`, ships the udev rule, and installs the plasmoid system-wide.
   - `options=(!lto)` because makepkg's default `-flto=auto` breaks the cc-rs archive step for hidapi's vendored C source (`libhidapi.a` ends up missing entirely, link fails with undefined `hid_*`).

4. CI workflow tweaks in `.github/workflows/build_and_release.yml` and `pre-commit.yml` to accommodate the `menubar` feature flag.

### Pulling future upstream changes

The library code in `src/lib.rs` / `src/main.rs` / `src/mcp.rs` does not overlap with `src/menubar.rs` or `tray-plasmoid/`, so future upstream merges should typically only conflict in `Cargo.toml` (when both sides change `[dependencies]`) and `Cargo.lock` (regenerate with `cargo build`, don't hand-merge). Keep both upstream's deps and the fork's `eframe`/`tray-icon` lines, and ensure the `[features]` block keeps `menubar = ["dep:eframe", "dep:tray-icon"]` plus the `[[bin]]` entry for `litra-menubar`.

## Useful references

- Upstream: https://github.com/timrogers/litra-rs
- crates.io (upstream package): https://crates.io/crates/litra
- Logitech Litra HID protocol notes live in `src/lib.rs` constants/comments.
- Plasma 6 plasmoid setup docs: https://develop.kde.org/docs/plasma/widget/setup/
