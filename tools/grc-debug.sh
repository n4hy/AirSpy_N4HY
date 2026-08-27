#!/usr/bin/env bash
# Run gnuradio-companion under gdb and capture a native backtrace on crash.
#
# Faster than tools/grc-valgrind.sh, but it only shows where the process
# died, not what corrupted the heap. Note MALLOC_CHECK_=3 perturbs allocation
# timing and can mask an intermittent fault; drop it if the crash stops
# reproducing under this script.
#
# Usage:  tools/grc-debug.sh [flowgraph.grc]
set -u
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO" || exit 1

if [ -f "$REPO/.airspyvenv/bin/activate" ]; then
    # shellcheck disable=SC1091
    source "$REPO/.airspyvenv/bin/activate"
fi

export PYTHONNOUSERSITE=1
export MALLOC_CHECK_=3         # abort AT the corrupting free, not later
export G_SLICE=always-malloc   # GLib slice allocator -> plain malloc
export G_DEBUG=gc-friendly

LOG="${GRC_DEBUG_LOG:-$REPO/grc-crash.log}"

gdb -q -batch \
    -ex "set debuginfod enabled off" \
    -ex "handle SIG32 SIG33 nostop noprint pass" \
    -ex run \
    -ex "printf \"\n===== FAULTING THREAD =====\n\"" \
    -ex "bt full" \
    -ex "printf \"\n===== ALL THREADS =====\n\"" \
    -ex "thread apply all bt" \
    --args python3 /usr/bin/gnuradio-companion "$@" 2>&1 | tee "$LOG"

echo
echo "backtrace saved to $LOG"
