#!/usr/bin/env bash
# Static checks for the plasmoid's QML and JS, in two modes.
#
#   (no arguments)   Full qmllint. Needs the QtQuick and Plasma 6 QML modules
#                    installed, so types actually resolve. This is the real
#                    check. Run it on a workstation with Plasma before trusting
#                    that the QML is clean.
#
#   --parse-only     Parse check with qmlformat. For machines that have the Qt
#                    tools but none of the QML modules, which is every GitHub
#                    runner. It only answers "does this file parse", but a
#                    syntax error in main.qml breaks the widget outright, so it
#                    is worth gating.
#
# Why two tools rather than qmllint in both modes: with no modules to resolve
# against, PlasmoidItem and every Plasma property are unknown names, and
# qmllint reports that once per use. Silencing those categories is possible but
# not portable, because the category flags differ between Qt versions: 6.11
# has --unresolved-type and --missing-property, 6.4 on ubuntu-latest rejects
# both as unknown options. qmlformat has no warning categories at all, so it
# cannot drift that way. It exits 1 on a syntax error and 0 otherwise.
#
# Finding the binaries is its own problem. There is no portable name for the
# Qt 6 tools: Arch ships them under /usr/lib/qt6/bin and keeps the Qt 5
# qmllint at /usr/bin/qmllint, some distributions use a 6 suffix, and Ubuntu
# runners have none of them on PATH. Worse, the Qt 5 qmllint accepts Plasma 6
# QML and exits 0 without reading it, so guessing wrong passes silently rather
# than failing. Resolve explicitly, then assert the major version.

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)

parse_only=0
if [ "${1:-}" = "--parse-only" ]; then
    parse_only=1
    shift
fi

qml_file="$repo_root/tray-plasmoid/package/contents/ui/main.qml"
js_file="$repo_root/tray-plasmoid/package/contents/code/litra.mjs"

# find_qt_tool <name> <env-override-value>
find_qt_tool() {
    local tool=$1 override=$2

    if [ -n "$override" ]; then
        echo "$override"
        return
    fi

    local bindir candidate
    for qtpaths in qtpaths6 qtpaths; do
        if command -v "$qtpaths" >/dev/null 2>&1; then
            bindir=$("$qtpaths" --query QT_INSTALL_BINS 2>/dev/null || true)
            if [ -n "$bindir" ] && [ -x "$bindir/$tool" ]; then
                echo "$bindir/$tool"
                return
            fi
        fi
    done

    for candidate in "/usr/lib/qt6/bin/$tool" "/usr/lib/x86_64-linux-gnu/qt6/bin/$tool"; do
        if [ -x "$candidate" ]; then
            echo "$candidate"
            return
        fi
    done

    for candidate in "${tool}6" "$tool"; do
        if command -v "$candidate" >/dev/null 2>&1; then
            command -v "$candidate"
            return
        fi
    done
}

require_qt6() {
    local binary=$1 label=$2 version major

    if [ -z "$binary" ]; then
        echo "FAIL: no $label found. Install qt6-declarative (Arch) or" >&2
        echo "      qt6-declarative-dev-tools (Debian/Ubuntu)." >&2
        exit 1
    fi

    version=$("$binary" --version 2>&1 | head -1)
    major=$(echo "$version" | grep -oE '[0-9]+' | head -1)

    if [ "${major:-0}" -lt 6 ]; then
        echo "FAIL: $binary is $version, which is Qt 5." >&2
        echo "      It does not understand Plasma 6 QML. Point at the Qt 6 one" >&2
        echo "      (Arch: /usr/lib/qt6/bin/$label)." >&2
        exit 1
    fi

    echo "$version"
}

if [ "$parse_only" -eq 1 ]; then
    qmlformat=$(find_qt_tool qmlformat "${QMLFORMAT:-}")
    version=$(require_qt6 "$qmlformat" qmlformat)
    echo "using $qmlformat ($version): parse check only, no QML modules available"

    status=0
    for file in "$qml_file" "$js_file"; do
        if ! "$qmlformat" "$file" >/dev/null; then
            echo "FAIL: $file does not parse" >&2
            status=1
        fi
    done
    exit "$status"
fi

qmllint=$(find_qt_tool qmllint "${QMLLINT:-}")
version=$(require_qt6 "$qmllint" qmllint)
echo "using $qmllint ($version): full check, types resolved"

# `unqualified` is off because i18n() is injected into the QML engine by Plasma
# at runtime and cannot be resolved by any linter. Every other category stays
# on, which is where the findings worth having come from.
exec "$qmllint" --unqualified disable "$qml_file" "$js_file"
