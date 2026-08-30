#!/usr/bin/env bash
#
# Run the whole suite. Needs no AirSpy attached.
#
#     tests/run_tests.sh
#
# Generates the flowgraph (and its hardware-free clone) into a temporary
# directory with grcc, then runs each test against the generated code, so the
# tests exercise what actually ships rather than a copy of it.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO" || exit 1
[ -f "$REPO/.airspyvenv/bin/activate" ] && . "$REPO/.airspyvenv/bin/activate"
export PYTHONNOUSERSITE=1

GENDIR="$(mktemp -d)"
export GENDIR
cleanup() { rm -rf "$GENDIR"; }
trap cleanup EXIT

echo "==> Generating flowgraphs into $GENDIR"
grcc -o "$GENDIR" "$REPO/airspy_scan.grc" >/dev/null 2>&1 \
    || { echo "grcc failed on airspy_scan.grc"; exit 1; }
python3 "$REPO/tools/hw_free_clone.py" "$REPO/airspy_scan.grc" "$GENDIR/gui_clone.grc" >/dev/null \
    || { echo "could not build the hardware-free clone"; exit 1; }
grcc -o "$GENDIR" "$GENDIR/gui_clone.grc" >/dev/null 2>&1 \
    || { echo "grcc failed on the clone"; exit 1; }
echo "    ok"

rc=0
for t in test_sweep_plan test_painter test_gui; do
    echo
    echo "==> $t"
    if python3 "$REPO/tests/$t.py" 2>&1 | grep -vE "^Using avx|^CPU Features|xtrxdsp|This plugin does not support setParent"; then :; fi
    if [ "${PIPESTATUS[0]}" -ne 0 ]; then rc=1; fi
done

echo
if [ "$rc" -eq 0 ]; then echo "ALL TESTS PASSED"; else echo "SOME TESTS FAILED"; fi
exit "$rc"
