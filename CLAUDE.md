# litra-rs (clearcmos fork)

Personal fork of [`timrogers/litra-rs`](https://github.com/timrogers/litra-rs), a Rust library, CLI, and MCP server for controlling Logitech Litra lights over USB HID. This fork adds two GUI front-ends on top of the upstream library: a native macOS menubar app and a Linux KDE Plasma system tray app.

## Project structure

- `src/lib.rs` - public Rust API around the `hidapi` device. Power, brightness, temperature, back-light, RGB. Re-exported as the `litra` crate.
- `src/main.rs` - `litra` CLI binary. Subcommands for `on`/`off`/`toggle`/`brightness*`/`temperature*`/`devices`/`mcp`, plus `--serial-number`/`--device-path`/`--device-type` device filters.
- `src/mcp.rs` - MCP server (`litra mcp`) implemented with `rmcp`. Exposes the same operations as tools for AI clients.
- `src/menubar.rs` - **fork addition.** `litra-menubar` binary (egui + `tray-icon`). macOS menu bar icon with a popup window for power/brightness/temperature control of the selected device.
- `tray/` - **fork addition.** Python GTK3 + `AppIndicator3` system tray app for KDE Plasma. Shells out to the `litra` CLI; does not link against the Rust library.
  - `tray/src/litra_tray.py` - the app
  - `tray/flake.nix`, `tray/default.nix`, `tray/shell.nix` - Nix packaging
  - `tray/litra-tray.desktop` - autostart entry
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

# KDE tray (Python, separate)
cd tray && nix run        # or: nix build && ./result/bin/litra-tray
```

The Rust toolchain is pinned via `rust-toolchain.toml`. Linux builds require `libudev-dev` (and `libhidapi-dev` upstream, though hidapi is currently vendored in this fork).

## Code style

- Upstream uses `cargo fmt` and `cargo clippy`. Match that. Pre-commit workflow runs both.
- Don't introduce em dashes or double dashes in new prose (project rule).
- The Python tray app follows standard PEP 8; keep changes there self-contained since it doesn't share a build with the Rust crate.

## Fork changes (relative to `timrogers/litra-rs:main`)

As of the last sync the fork is up to date with upstream (merged through upstream's `47e838c`, v3.3.0 + post-release dep bumps) and adds the changes below on top.

### Added by this fork

1. **macOS menubar app** (`11ebd19`, refined in `cbaafc6`)
   - New file `src/menubar.rs` (~400 lines).
   - New `litra-menubar` binary entry in `Cargo.toml`, gated behind the `menubar` feature.
   - New optional deps: `eframe = "0.29"`, `tray-icon = "0.19"`.
   - `cbaafc6` improved device state handling when the device is in USB standby and added value clamping on the brightness/temperature sliders.
   - README section "macOS Menubar Application" added.

2. **KDE Plasma system tray app** (`11ebd19`)
   - New `tray/` directory with a Python GTK app, Nix flake/shell/derivation, `.desktop` autostart file, and its own `README.md` + `USAGE.md`.
   - The tray app is a CLI consumer; it shells out to `litra` rather than linking the library, so it's intentionally independent of the Rust build.
   - README section "KDE Plasma System Tray Application (Linux)" added.

3. CI workflow tweaks in `.github/workflows/build_and_release.yml` and `pre-commit.yml` to accommodate the new feature flag.

### Pulling future upstream changes

The library code in `src/lib.rs` / `src/main.rs` / `src/mcp.rs` does not overlap with `src/menubar.rs` or `tray/`, so future upstream merges should typically only conflict in `Cargo.toml` (when both sides change `[dependencies]`) and `Cargo.lock` (regenerate with `cargo build`, don't hand-merge). Keep both upstream's deps and the fork's `eframe`/`tray-icon` lines, and ensure the `[features]` block keeps `menubar = ["dep:eframe", "dep:tray-icon"]` plus the `[[bin]]` entry for `litra-menubar`.

## Useful references

- Upstream: https://github.com/timrogers/litra-rs
- crates.io (upstream package): https://crates.io/crates/litra
- Logitech Litra HID protocol notes live in `src/lib.rs` constants/comments.
