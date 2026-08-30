#!/usr/bin/env bash
#
# install.sh -- set up everything airspy_scan.grc needs, on a Debian/Ubuntu box.
#
#   ./install.sh           install dependencies, build the venv, verify
#   ./install.sh --check   verify only, change nothing
#   ./install.sh --yes     don't prompt before apt-get
#
# Verified against Ubuntu 24.04.4 LTS with GNU Radio 3.10.9.2 and an
# AirSpy R2 (USB 1d50:60a1).

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV="$REPO/.airspyvenv"
CHECK_ONLY=0
ASSUME_YES=0

for arg in "$@"; do
    case "$arg" in
        --check) CHECK_ONLY=1 ;;
        --yes|-y) ASSUME_YES=1 ;;
        -h|--help) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "unknown option: $arg (try --help)" >&2; exit 2 ;;
    esac
done

# ---------------------------------------------------------------- output --
if [ -t 1 ]; then B=$'\033[1m'; G=$'\033[32m'; Y=$'\033[33m'; R=$'\033[31m'; N=$'\033[0m'
else B=''; G=''; Y=''; R=''; N=''; fi
step() { printf '\n%s==> %s%s\n' "$B" "$*" "$N"; }
ok()   { printf '  %s[ ok ]%s %s\n'   "$G" "$N" "$*"; }
warn() { printf '  %s[warn]%s %s\n'   "$Y" "$N" "$*"; }
die()  { printf '  %s[fail]%s %s\n'   "$R" "$N" "$*" >&2; exit 1; }

PROBLEMS=0
note_problem() { PROBLEMS=$((PROBLEMS + 1)); }

# ------------------------------------------------------------------ distro --
step "Checking the platform"
if [ ! -r /etc/os-release ]; then die "no /etc/os-release; cannot identify this system"; fi
# shellcheck disable=SC1091
. /etc/os-release
ok "$PRETTY_NAME"
if ! command -v apt-get >/dev/null 2>&1; then
    warn "This installer drives apt-get and so targets Debian/Ubuntu."
    warn "On another distro install the equivalents by hand, then re-run with --check:"
    warn "  gnuradio (>=3.10), gr-osmosdr built with AirSpy support, libairspy,"
    warn "  the airspy command-line tools, PyQt5 and numpy 1.x for python3."
    [ "$CHECK_ONLY" -eq 1 ] || exit 1
fi

# ---------------------------------------------------------------- packages --
PKGS=(
    gnuradio            # GNU Radio 3.10 runtime + gnuradio-companion + grcc
    gr-osmosdr          # osmocom Source; must be built with AirSpy support
    airspy              # airspy_info / airspy_rx command-line tools
    libairspy0          # AirSpy USB library + udev rules
    libairspy-dev       # headers (only needed if you rebuild gr-osmosdr)
    python3-pyqt5       # Qt bindings used by the GUI sinks
    python3-numpy       # MUST be 1.x -- see the numpy note below
    python3-venv        # to build .airspyvenv
)

missing=()
for p in "${PKGS[@]}"; do
    dpkg -s "$p" >/dev/null 2>&1 || missing+=("$p")
done

step "Checking distribution packages"
if [ ${#missing[@]} -eq 0 ]; then
    ok "all ${#PKGS[@]} packages already installed"
else
    printf '  missing: %s\n' "${missing[*]}"
    if [ "$CHECK_ONLY" -eq 1 ]; then
        warn "--check: not installing"; note_problem
    else
        if [ "$ASSUME_YES" -eq 0 ]; then
            read -r -p "  Install these with sudo apt-get? [y/N] " reply
            [[ "$reply" =~ ^[Yy]$ ]] || die "declined; nothing installed"
        fi
        sudo apt-get update
        sudo apt-get install -y "${missing[@]}"
        ok "packages installed"
    fi
fi

# ------------------------------------------------------- gr-osmosdr/AirSpy --
step "Checking gr-osmosdr was built with AirSpy support"
# NB: use plain grep, never 'grep -q', on the output of a large producer.
# grep -q exits at the first match, SIGPIPEs the producer, and with
# 'set -o pipefail' that turns a successful match into a failed test.
# Probe the shared library directly: this needs no hardware attached, unlike
# constructing an osmosdr.source, which prints its device-type list on open.
osmo_lib=""
for cand in /usr/lib/*/libgnuradio-osmosdr.so* /usr/lib/libgnuradio-osmosdr.so* \
            /usr/local/lib/*/libgnuradio-osmosdr.so* /usr/local/lib/libgnuradio-osmosdr.so*; do
    [ -e "$cand" ] && { osmo_lib="$cand"; break; }
done
if [ -n "$osmo_lib" ] && strings "$osmo_lib" 2>/dev/null | grep -x 'airspy_open' >/dev/null; then
    ok "gr-osmosdr exposes the AirSpy backend  ($osmo_lib)"
else
    warn "could not confirm AirSpy support in gr-osmosdr."
    warn "If 'airspy=0' fails at runtime, rebuild gr-osmosdr against libairspy-dev."
    note_problem
fi

# --------------------------------------------------------------- numpy ABI --
#
# GNU Radio 3.10's Python bindings are pybind11 modules compiled against the
# numpy 1.x C ABI. A numpy 2.x in ~/.local/lib/pythonX.Y/site-packages takes
# precedence over the system copy and makes "from gnuradio import gr" fail with
# a bare "ImportError: initialization failed". The venv below is created with
# --system-site-packages, which re-enables the user site directory, so the venv
# alone does NOT fix it -- PYTHONNOUSERSITE=1 is what does.
#
step "Checking the numpy ABI"
sys_np=$(PYTHONNOUSERSITE=1 python3 -c "import numpy; print(numpy.__version__)" 2>/dev/null || echo "none")
usr_np=$(python3 -c "import numpy; print(numpy.__version__)" 2>/dev/null || echo "none")
ok "system numpy: $sys_np"
if [ "$usr_np" != "$sys_np" ]; then
    warn "a different numpy ($usr_np) shadows it from your user site directory"
    warn "the venv sets PYTHONNOUSERSITE=1 so GNU Radio sees $sys_np instead"
fi
case "$sys_np" in
    1.*) ok "numpy 1.x -- compatible with GNU Radio 3.10 bindings" ;;
    none) die "no system numpy found; install python3-numpy" ;;
    *)   warn "system numpy is $sys_np, not 1.x; GNU Radio's bindings may fail to import"
         note_problem ;;
esac

# ----------------------------------------------------------------- the venv --
step "Preparing the Python environment (.airspyvenv)"
if [ "$CHECK_ONLY" -eq 1 ] && [ ! -d "$VENV" ]; then
    warn "--check: .airspyvenv does not exist"; note_problem
else
    if [ ! -d "$VENV" ]; then
        python3 -m venv --system-site-packages "$VENV"
        ok "created $VENV"
    else
        ok "$VENV already exists"
    fi
    if ! grep -q PYTHONNOUSERSITE "$VENV/bin/activate"; then
        cat >> "$VENV/bin/activate" <<'EOF'

# GNU Radio 3.10 pybind11 modules are built against the numpy 1.x C ABI.
# A numpy 2.x under ~/.local would shadow the system copy and break
# "from gnuradio import gr". --system-site-packages re-enables the user
# site directory, so this is what actually keeps it out.
PYTHONNOUSERSITE=1
export PYTHONNOUSERSITE
EOF
        ok "pinned PYTHONNOUSERSITE=1 in the venv"
    else
        ok "PYTHONNOUSERSITE already pinned"
    fi
fi

# ---------------------------------------------------------------- imports ---
step "Verifying the Python imports the flowgraph needs"
if [ -x "$VENV/bin/python" ]; then PY="$VENV/bin/python"; else PY="python3"; fi
if PYTHONNOUSERSITE=1 "$PY" - <<'EOF'
import numpy
from gnuradio import gr, qtgui, eng_notation
from gnuradio.fft import logpwrfft, window
from gnuradio.filter import firdes
from PyQt5 import Qt
import osmosdr, sip
print(f"    numpy {numpy.__version__}, GNU Radio {gr.version()}, PyQt5, osmosdr, sip")
EOF
then ok "all imports succeed"
else die "imports failed -- the flowgraph will not run; see the numpy note above"; fi

# ------------------------------------------------------------------- udev ---
step "Checking USB permissions"
if ls /lib/udev/rules.d/*airspy* /etc/udev/rules.d/*airspy* >/dev/null 2>&1; then
    ok "AirSpy udev rules present"
else
    warn "no AirSpy udev rule found; you may need root to open the device"
    if [ "$CHECK_ONLY" -eq 0 ]; then
        echo 'SUBSYSTEM=="usb", ATTR{idVendor}=="1d50", ATTR{idProduct}=="60a1", SYMLINK+="airspy-%k", GROUP="plugdev", TAG+="uaccess"' \
            | sudo tee /etc/udev/rules.d/60-libairspy0.rules >/dev/null
        sudo udevadm control --reload-rules && sudo udevadm trigger
        ok "installed a udev rule (replug the AirSpy for it to take effect)"
    fi
fi
if id -nG | tr ' ' '\n' | grep -x plugdev >/dev/null; then
    ok "you are in the plugdev group"
else
    warn "you are not in 'plugdev'; run: sudo usermod -aG plugdev $USER   (then log out and back in)"
    note_problem
fi

# ----------------------------------------------------------------- device ---
step "Looking for the AirSpy"
if lsusb 2>/dev/null | grep -i '1d50:60a1' >/dev/null; then
    ok "AirSpy present on the USB bus"
    if command -v airspy_info >/dev/null && timeout 10 airspy_info 2>&1 | grep 'Found AirSpy' >/dev/null; then
        timeout 10 airspy_info 2>/dev/null | sed -n '/Found AirSpy/,/^$/p' | sed 's/^/    /'
        ok "device opens cleanly"
    else
        warn "the AirSpy is on the bus but will not open."
        warn "This usually means it was left wedged by a flowgraph that died mid-stream."
        warn "Unplug it and plug it back in, then re-run: ./install.sh --check"
        note_problem
    fi
else
    warn "no AirSpy detected (1d50:60a1). Plug it in; everything else is still set up."
    note_problem
fi

# ------------------------------------------------------------------ verdict --
step "Result"
if [ "$PROBLEMS" -eq 0 ]; then
    ok "ready"
    cat <<EOF

  Run it with:

      source .airspyvenv/bin/activate
      gnuradio-companion airspy_scan.grc      # open in the editor, press Run

  or headless:

      source .airspyvenv/bin/activate
      grcc -o . airspy_scan.grc && python3 airspy_scan.py
EOF
else
    warn "$PROBLEMS item(s) above need attention; re-run './install.sh --check' after fixing them"
    exit 1
fi
