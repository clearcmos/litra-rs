#!/usr/bin/env bash
# Assert that PKGBUILD's package() installs every file of the plasmoid source
# package.
#
# Regression pin: package() used to name each plasmoid file individually, so
# adding contents/code/litra.mjs shipped a widget whose main.qml imported a
# file that was not there. A plasmoid missing an imported module does not
# degrade, it fails to load, and nothing in CI noticed.
#
# This runs the real package() rather than a copy of its logic, against a
# scratch source tree and a stub binary, so a future edit that goes back to
# naming files one by one fails here.

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source_package="$repo_root/tray-plasmoid/package"
plugin_id="io.github.clearcmos.litra"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# package() starts with `cd "$pkgname"` under $srcdir and installs into $pkgdir.
# Build a scratch copy holding only what it reads, so the real target/ tree and
# the repo itself are never touched.
staged="$work/src/litra-custom"
mkdir -p "$staged/target/release"
cp -r "$source_package" "$staged/tray-plasmoid-package-tmp"
mkdir -p "$staged/tray-plasmoid"
mv "$staged/tray-plasmoid-package-tmp" "$staged/tray-plasmoid/package"
cp "$repo_root/99-litra.rules" "$repo_root/LICENSE.md" "$staged/"
: > "$staged/target/release/litra"

(
    # package() opens with `cd "$pkgname"`, so start where makepkg would: in
    # $srcdir, with the source directory alongside.
    cd "$work/src"
    # shellcheck disable=SC1090,SC1091
    source "$repo_root/PKGBUILD"
    srcdir="$work/src"
    pkgdir="$work/pkg"
    export srcdir pkgdir
    package
)

installed="$work/pkg/usr/share/plasma/plasmoids/$plugin_id"

if [ ! -d "$installed" ]; then
    echo "FAIL: package() installed no plasmoid at $installed" >&2
    exit 1
fi

missing=0
while IFS= read -r relative; do
    if [ ! -f "$installed/$relative" ]; then
        echo "FAIL: package() does not ship tray-plasmoid/package/$relative" >&2
        missing=1
    fi
done < <(cd "$source_package" && find . -type f -printf '%P\n' | sort)

if [ "$missing" -ne 0 ]; then
    echo >&2
    echo "Every file under tray-plasmoid/package/ must reach the installed widget." >&2
    exit 1
fi

shipped=$(cd "$source_package" && find . -type f | wc -l)
echo "ok: package() ships all $shipped plasmoid files"
