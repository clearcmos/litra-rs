# litra-rs (clearcmos fork)

Personal fork of [`timrogers/litra-rs`](https://github.com/timrogers/litra-rs), a Rust library, CLI, and MCP server for controlling Logitech Litra lights over USB HID. This fork adds two GUI front-ends on top of the upstream library: a native macOS menubar app and a KDE Plasma 6 plasmoid for Linux, plus an Arch `PKGBUILD` to build and install the CLI + plasmoid.

## Project structure

- `src/lib.rs` - public Rust API around the `hidapi` device. Power, brightness, temperature, back-light, RGB. Re-exported as the `litra` crate.
- `src/main.rs` - `litra` CLI binary. Subcommands for `on`/`off`/`toggle`/`brightness*`/`temperature*`/`devices`/`mcp`, plus `--serial-number`/`--device-path`/`--device-type` device filters.
- `src/mcp.rs` - MCP server (`litra mcp`) implemented with `rmcp`. Exposes the same operations as tools for AI clients.
- `src/menubar.rs` - **fork addition.** `litra-menubar` binary (egui + `tray-icon`). macOS menu bar icon with a popup window for power/brightness/temperature control of the selected device.
- `tray-plasmoid/` - **fork addition.** KDE Plasma 6 plasmoid (QML, `PlasmoidItem`). Shells out to the `litra` CLI; gets popup positioning automatically from Plasma's systray.
  - `tray-plasmoid/package/metadata.json` - plasmoid manifest (`X-Plasma-API-Minimum-Version: 6.0`).
  - `tray-plasmoid/package/contents/ui/main.qml` - the plasmoid (compact + full representations, throttled slider commands at ~12 Hz, device polled on a timer).
  - `tray-plasmoid/package/contents/code/litra.mjs` - pure parsing and unit-conversion helpers. An ES module so QML (`import "../code/litra.mjs" as Litra`, Qt 6 treats `.mjs` as ECMAScript) and `node --test` load the identical file. Keep it free of Qt and Plasma references; it is the only part of the widget that is unit-testable.
  - `tray-plasmoid/package/contents/icons/lightbulb-{on,off}.svg` - custom tray icons (the on-icon is a warm-yellow bulb with a glow halo, the off-icon is an outline that follows the panel's `currentColor`).
  - `tray-plasmoid/tests/litra.test.mjs` - unit tests for the helpers above; no Qt, no device.
  - `tray-plasmoid/tests/check-packaging.sh` - runs the real `package()` from `PKGBUILD` against a scratch tree and asserts every file under `tray-plasmoid/package/` reaches the installed widget.
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

## Checks

Every one of these runs in `.github/workflows/fork-ci.yml`. One line each:

```bash
cargo fmt --all -- --check
cargo clippy --locked --workspace --all-features --all-targets -- -D warnings
cargo test --locked --workspace --all-features
node --test tray-plasmoid/tests/*.test.mjs
bash tray-plasmoid/tests/run-qmllint.sh
shellcheck tray-plasmoid/install.sh
shellcheck --shell=bash --exclude=SC2034,SC2154,SC2164 PKGBUILD
bash tray-plasmoid/tests/check-packaging.sh
```

Notes:

- `--all-features` is what pulls `src/menubar.rs` into scope. Without it the fork's own Rust file is compiled by nothing.
- Do not call `qmllint` directly. There is no portable name for the Qt 6 binary: it is `/usr/lib/qt6/bin/qmllint` on Arch, where plain `/usr/bin/qmllint` is Qt 5 and exits 0 on Plasma 6 QML without reading it; Ubuntu runners have neither on PATH under any name. `run-qmllint.sh` resolves it and asserts the major version. Override with `QMLLINT=/path/to/qmllint` if needed.
- `src/menubar.rs` has no tests by choice. It is a macOS-oriented egui/`tray-icon` event loop, it is not run on the Linux workstation this fork is maintained from, and fabricating tests for a GUI loop would be filler. CI compiles, formats and clippy-lints it so it cannot rot silently.

## Code style

- Upstream uses `cargo fmt` and `cargo clippy`. Match that. Pre-commit workflow runs both.
- Don't introduce em dashes or double dashes in new prose (project rule).
- Plasmoid QML keeps imports versionless (Plasma 6 / Qt6 style) and uses `Plasma5Support.DataSource` with the `executable` engine for shell calls. Slider-driven commands are throttled (`sliderThrottleMs = 80`) with a trailing fire to avoid flooding the device.
- `main.qml` carries `pragma ComponentBehavior: Bound` so `root` resolves inside the representation Components. Without it qmllint reports every such access as unqualified, which buries real findings.
- New plasmoid logic that can be written as a pure function belongs in `contents/code/litra.mjs` with a test, not inline in `main.qml`. QML in a Plasma widget is only testable by installing it and looking at the panel.

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

5. **`.github/workflows/fork-ci.yml`** - fork-only CI covering the additions above. Kept as a separate file so upstream changes to its own workflows never conflict, and guarded `if: github.repository != 'timrogers/litra-rs'` so it no-ops if upstream ever inherits a copy.

6. `.editorconfig`.

## Decision log

### 2026-09-14 - the tray icon lied about the light

The plasmoid showed a lit bulb over a light that was off. `main.qml` held `lightOn` as a local boolean initialised `false` and only ever flipped by `togglePower()`; nothing ever read the hardware. Any out-of-band change (`litra off` from a shell or keybinding, the MCP server, the button on the light, a second machine) desynced the widget permanently, and a plasmashell restart reset it to "off" no matter what the light was doing. Brightness and temperature had the same problem: they started at a hardcoded 50% / 4500K rather than the device's real values.

Fixed by making the device authoritative. `main.qml` now polls `litra devices --json` (1.5 s expanded, 5 s collapsed, plus an immediate read at load via `triggeredOnStart`) and drives every property from the reply.

Things that fix depends on, learned the hard way:

- **Per-field settle windows, not a global one.** A poll issued just before a command lands reports the pre-command state and undoes the user's own click. Power, brightness and temperature each hold their own 900 ms window, so an out-of-band power change still lands while a slider is being dragged.
- **Drag state lives on `root`.** The sliders are inside `fullRepresentation`, which Plasma destroys when the popup closes, so the poll handler cannot reach `brightnessSlider.pressed`. The flags are hoisted to `root` and cleared on collapse.
- **One chained shell command, not three sources.** `Plasma5Support.DataSource` runs separate sources concurrently, so the old `litra on` + `brightness` + `temperature` triple raced three processes for the same HID handle. They are now `&&`-chained into one.
- **Sliders stay live while the light is off.** Verified against the hardware: the device stores brightness and temperature while off and stays off. The old code gated them on `lightOn`, which with polling would make the control appear to do nothing and then snap back.
- **`LITRA_DISABLE_UPDATE_CHECK=1` on the poll.** The CLI otherwise makes a daily network call, from inside plasmashell.
- **Self-healing in-flight guard.** One read at a time, but a source that never returns must not wedge polling for the session, so the guard expires after 10 s.

### 2026-09-14 - the plasmoid shipped without a file it imports

Extracting the helpers into `contents/code/litra.mjs` exposed a packaging defect: `PKGBUILD`'s `package()` named each plasmoid file individually, so a new file is shipped only if someone remembers to add a line. A plasmoid missing an imported module does not degrade, it fails to load outright. `package()` now copies the package tree wholesale, and `tray-plasmoid/tests/check-packaging.sh` runs the real `package()` and fails if any source file goes missing. The gate was confirmed to fail against the old per-file version before being wired into CI.

### 2026-09-14 - fork CI ran no tests at all

`build_and_release.yml` carries `if: github.repository == 'timrogers/litra-rs'`, a deliberate upstream fork guard so forks do not get failure mail for unsignable macOS release jobs. The side effect was that `cargo test` never ran on this fork; only `pre-commit.yml` (fmt, cargo-check, clippy) did, and `src/menubar.rs` had drifted out of `cargo fmt` compliance unnoticed. Rather than loosen upstream's guard, which would conflict on every upstream merge, the fork got its own `fork-ci.yml`.

### Pulling future upstream changes

The library code in `src/lib.rs` / `src/main.rs` / `src/mcp.rs` does not overlap with `src/menubar.rs` or `tray-plasmoid/`, so future upstream merges should typically only conflict in `Cargo.toml` (when both sides change `[dependencies]`) and `Cargo.lock` (regenerate with `cargo build`, don't hand-merge). Keep both upstream's deps and the fork's `eframe`/`tray-icon` lines, and ensure the `[features]` block keeps `menubar = ["dep:eframe", "dep:tray-icon"]` plus the `[[bin]]` entry for `litra-menubar`.

## Useful references

- Upstream: https://github.com/timrogers/litra-rs
- crates.io (upstream package): https://crates.io/crates/litra
- Logitech Litra HID protocol notes live in `src/lib.rs` constants/comments.
- Plasma 6 plasmoid setup docs: https://develop.kde.org/docs/plasma/widget/setup/
