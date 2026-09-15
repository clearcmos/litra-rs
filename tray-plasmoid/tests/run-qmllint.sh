#!/usr/bin/env bash
# Lint the plasmoid's QML and JS with the Qt 6 qmllint.
#
# Finding the right binary is the whole point of this script. There is no
# portable name for it: Arch ships Qt 6's as /usr/lib/qt6/bin/qmllint and keeps
# the Qt 5 one at /usr/bin/qmllint, some distributions use qmllint6, and Ubuntu
# runners have neither on PATH. Worse, the Qt 5 binary accepts Plasma 6 QML and
# exits 0 without reading it, so guessing wrong does not fail loudly, it passes
# silently. Resolve explicitly, then assert the major version.

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)

# --no-imports is for machines that have qmllint but not the QtQuick and Plasma
# 6 QML modules, which is every GitHub runner. There it degrades to a parse
# check: syntax in both the QML and the JS, and the structural categories that
# need no type information. It cannot check anything else, because with no
# modules to resolve against, `PlasmoidItem` and every Plasma property are
# simply unknown names. Disabling those categories is not hiding findings, it
# is declining to report the same missing-modules fact 26 times.
#
# The flags below are exactly what CI runs, `--bare` included, so this mode
# reproduces the runner locally on a machine that does have Plasma. Use it to
# debug a CI-only qmllint failure.
#
# Without the flag, on a machine with Plasma installed, the full check runs and
# types do resolve. That is the real lint and it is the default.
check_imports=1
if [ "${1:-}" = "--no-imports" ]; then
    check_imports=0
    shift
fi

find_qmllint() {
    if [ -n "${QMLLINT:-}" ]; then
        echo "$QMLLINT"
        return
    fi

    local bindir
    for qtpaths in qtpaths6 qtpaths; do
        if command -v "$qtpaths" >/dev/null 2>&1; then
            bindir=$("$qtpaths" --query QT_INSTALL_BINS 2>/dev/null || true)
            if [ -n "$bindir" ] && [ -x "$bindir/qmllint" ]; then
                echo "$bindir/qmllint"
                return
            fi
        fi
    done

    local candidate
    for candidate in /usr/lib/qt6/bin/qmllint /usr/lib/x86_64-linux-gnu/qt6/bin/qmllint; do
        if [ -x "$candidate" ]; then
            echo "$candidate"
            return
        fi
    done

    for candidate in qmllint6 qmllint; do
        if command -v "$candidate" >/dev/null 2>&1; then
            command -v "$candidate"
            return
        fi
    done
}

qmllint=$(find_qmllint)

if [ -z "$qmllint" ]; then
    echo "FAIL: no qmllint found. Install qt6-declarative (Arch) or" >&2
    echo "      qt6-declarative-dev-tools (Debian/Ubuntu), or set QMLLINT." >&2
    exit 1
fi

version=$("$qmllint" --version 2>&1 | head -1)
major=$(echo "$version" | grep -oE '[0-9]+' | head -1)

if [ "${major:-0}" -lt 6 ]; then
    echo "FAIL: $qmllint is $version, which is Qt 5." >&2
    echo "      It exits 0 on Plasma 6 QML without checking it. Set QMLLINT to" >&2
    echo "      the Qt 6 binary (Arch: /usr/lib/qt6/bin/qmllint)." >&2
    exit 1
fi

# `unqualified` is off because i18n() is injected into the QML engine by Plasma
# at runtime and cannot be resolved by any linter. Every other qmllint category
# stays on, which is where the findings worth having come from.
args=(--unqualified disable)

if [ "$check_imports" -eq 1 ]; then
    echo "using $qmllint ($version): full check, types resolved"
else
    args+=(--bare --import disable --unresolved-type disable --missing-property disable)
    echo "using $qmllint ($version): parse check only, no QML modules available"
fi

exec "$qmllint" "${args[@]}" \
    "$repo_root/tray-plasmoid/package/contents/ui/main.qml" \
    "$repo_root/tray-plasmoid/package/contents/code/litra.mjs"
