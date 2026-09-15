pkgname=litra-custom
pkgdesc='CLI, MCP server, and KDE Plasma plasmoid for Logitech Litra lights (clearcmos fork)'
pkgver=3.3.0.r306.762ee60
pkgrel=1
arch=('x86_64')
url='https://github.com/clearcmos/litra-rs'
license=('MIT')
makedepends=(git
             rust
             cargo
             pkgconf)
optdepends=('plasma-workspace: KDE Plasma 6 plasmoid integration (Litra widget in panel/system tray)')
provides=('litra')
conflicts=('litra')
# `-flto=auto` (makepkg's default LTOFLAGS) breaks the cc-rs archive step for
# the bundled hidapi C source: `hid.o` is built but `libhidapi.a` is never
# created, so the final `litra` link fails with undefined `hid_*` symbols.
options=(!lto)
source=("$pkgname::git+https://github.com/clearcmos/litra-rs.git")
sha256sums=('SKIP')

pkgver() {
    cd "$pkgname"
    printf "3.3.0.r%s.%s" "$(git rev-list --count HEAD)" "$(git rev-parse --short HEAD)"
}

prepare() {
    cd "$pkgname"
    export RUSTUP_TOOLCHAIN=stable
    cargo fetch --locked --target "$(rustc -vV | sed -n 's/host: //p')"
}

build() {
    cd "$pkgname"
    export RUSTUP_TOOLCHAIN=stable
    export CARGO_TARGET_DIR=target
    # Default features (cli + mcp) build just the `litra` binary.
    # The `menubar` feature is macOS-only and intentionally skipped here.
    cargo build --frozen --release
}

package() {
    cd "$pkgname"

    # litra CLI / MCP binary
    install -Dm755 target/release/litra "$pkgdir/usr/bin/litra"

    # udev rule for non-root USB access (members of the `video` group)
    install -Dm644 99-litra.rules "$pkgdir/usr/lib/udev/rules.d/99-litra.rules"

    # KDE Plasma 6 plasmoid (system-wide). Plasmoid files are inert without
    # plasma-workspace, so this is safe to ship unconditionally.
    local plasmoid_dir="$pkgdir/usr/share/plasma/plasmoids/io.github.clearcmos.litra"
    # Copy the package tree wholesale rather than naming each file. An earlier
    # per-file list silently dropped a JS module that main.qml imports, which
    # installs a widget that will not load at all.
    install -d "$plasmoid_dir"
    cp -r tray-plasmoid/package/. "$plasmoid_dir/"
    find "$plasmoid_dir" -type d -exec chmod 755 {} +
    find "$plasmoid_dir" -type f -exec chmod 644 {} +

    # License
    install -Dm644 LICENSE.md "$pkgdir/usr/share/licenses/$pkgname/LICENSE.md"
}
