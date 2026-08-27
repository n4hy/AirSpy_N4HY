#!/usr/bin/env bash
# Memcheck gnuradio-companion to find the invalid write behind a
# "corrupted double-linked list" abort.
#
# glibc reports that message when it notices damaged heap metadata, which is
# generally long after the code that caused the damage has returned. Memcheck
# catches the offending write itself.
#
# Expect a 20-50x slowdown: GRC may take minutes to draw its window.
# That is normal, not a hang.
#
# Usage:  tools/grc-valgrind.sh [flowgraph.grc]
set -u
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO" || exit 1

if [ -f "$REPO/.airspyvenv/bin/activate" ]; then
    # shellcheck disable=SC1091
    source "$REPO/.airspyvenv/bin/activate"
else
    echo "warning: $REPO/.airspyvenv not found; recreate with" >&2
    echo "         python3 -m venv --system-site-packages .airspyvenv" >&2
fi

# GNU Radio 3.10.9.2 is built against numpy 1.x; a numpy 2.x in ~/.local
# would shadow the system 1.26.4 and break "from gnuradio import gr".
export PYTHONNOUSERSITE=1

# Without these three, memcheck sees pool allocators rather than real
# malloc/free and reports nothing useful.
export PYTHONMALLOC=malloc     # bypass pymalloc arenas
export G_SLICE=always-malloc   # bypass the GLib slice allocator
export G_DEBUG=gc-friendly     # GLib zeroes freed memory

LOG="${GRC_VALGRIND_LOG:-$REPO/grc-valgrind.log}"

SUPP=()
for s in /usr/lib/valgrind/python3.supp \
         /usr/lib/valgrind/debian.supp \
         /usr/share/glib-2.0/valgrind/glib.supp; do
    [ -f "$s" ] && SUPP+=("--suppressions=$s")
done

valgrind \
    --tool=memcheck \
    --leak-check=no \
    --track-origins=yes \
    --num-callers=40 \
    --error-limit=no \
    "${SUPP[@]}" \
    --log-file="$LOG" \
    python3 /usr/bin/gnuradio-companion "$@"

echo
echo "=== memcheck log: $LOG ==="
grep -nE "Invalid (write|read|free)|Mismatched|double free|Process terminating" "$LOG" | head -20 \
    || echo "(no heap-corruption errors recorded in this run)"
