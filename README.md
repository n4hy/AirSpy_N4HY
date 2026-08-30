# AirSpy Scanner

A GNU Radio flowgraph that sweeps an **AirSpy R2** across a selectable frequency
range and paints each dwell's FFT onto a single fixed frequency axis — **ALF**
(scan low frequency) on the left, **AHF** (scan high frequency) on the right.

The axis never moves while it scans. It is rewritten only when you move ALF or
AHF.

```
┌──────────────────────────────────────────────────────┐
│    0 dB ┤                                            │
│         │        ╷                    ╷              │
│         │   ╷   ╷│╷        ╷        ╷ │╷             │
│         │╷ ╷│╷ ╷││││╷ ╷  ╷╷│╷╷  ╷ ╷╷│╷│││╷           │
│  -120 dB┤└─┴─┴─┴─┴┴┴┴─┴──┴┴┴┴┴──┴─┴┴┴┴┴┴┴┴┴──────    │
│          24.000 MHz ── Frequency ── 1800.000 MHz     │
├───────────────────────────┬──────────────────────────┤
│ ALF  24.000 MHz           │ AHF  1800.000 MHz        │
│ ALF slider                │ AHF slider               │
│ Dwell per slice           │ Sweep running            │
│ LNA gain     │ MIX gain   │ VGA gain                 │
└──────────────┴────────────┴──────────────────────────┘
```

## Why it has to sweep

The AirSpy R2's maximum sample rate is **10 MSPS**, so it can see 10 MHz at a
time. Its tuning range is **24–1800 MHz**, a span of 1776 MHz. No single capture
can show the whole range, so the scanner steps the local oscillator across it and
assembles the picture slice by slice.

Steps overlap (`overlap = 0.8`, i.e. 8 MHz apart) so the analogue filter roll-off
at each slice edge does not leave a gap. Covering 24–1800 MHz takes **222
slices**:

| dwell per slice | full 24–1800 MHz revisit |
|---|---|
| 0.05 s | 11.1 s |
| 0.10 s | 22.2 s |
| 0.20 s (default) | 44.4 s |
| 0.50 s | 111 s |

Narrow the range and it gets far quicker — the FM broadcast band (88–108 MHz) is
3 slices, about 0.6 s per sweep at the default dwell.

Display resolution is 4096 bins across whatever span you select: 433.6 kHz/bin
over the full range, 4.9 kHz/bin over the FM band.

## Hardware

Developed against an **AirSpy R2** (USB ID `1d50:60a1`). The limits below are
read from the device itself, not from a datasheet:

| | |
|---|---|
| Tuning range | 24 – 1800 MHz |
| Sample rates | **10 and 2.5 MSPS only** — no other value is legal |
| Gain stages | LNA, MIX, VGA — 0–15 dB each |
| Antenna port | RX |

An AirSpy Mini should work (same `airspy` driver). The **AirSpy HF+** will not:
it is a different device with a different tuning range and needs the
`airspyhf` driver.

## Quick start

```bash
git clone https://github.com/n4hy/AirSpy.git
cd AirSpy
./install.sh                       # installs deps, builds the venv, verifies
source .airspyvenv/bin/activate
gnuradio-companion airspy_scan.grc # opens the editor; press Run (F6)
```

To run it without the editor:

```bash
source .airspyvenv/bin/activate
grcc -o . airspy_scan.grc
python3 airspy_scan.py
```

`./install.sh --check` verifies an existing setup and changes nothing.
`./install.sh --yes` skips the confirmation prompt before `apt-get`.

## What install.sh does

It targets Debian/Ubuntu (verified on Ubuntu 24.04.4 LTS) and is safe to re-run.

1. Installs `gnuradio`, `gr-osmosdr`, `airspy`, `libairspy0`, `libairspy-dev`,
   `python3-pyqt5`, `python3-numpy`, `python3-venv`.
2. Confirms `gr-osmosdr` was actually built with the AirSpy backend.
3. Checks the numpy ABI (see below).
4. Creates `.airspyvenv` and pins `PYTHONNOUSERSITE=1` inside it.
5. Verifies every import the flowgraph needs.
6. Checks the AirSpy udev rule and your `plugdev` membership.
7. Opens the radio and prints what it reports.

On a non-apt distro, install the equivalents by hand — GNU Radio ≥ 3.10,
gr-osmosdr with AirSpy support, libairspy, the airspy CLI tools, PyQt5, and
**numpy 1.x** — then run `./install.sh --check`.

## Controls

| Control | Meaning |
|---|---|
| **ALF** | Scan low frequency, decimal MHz. Left edge of the graph. |
| **AHF** | Scan high frequency, decimal MHz. Right edge of the graph. |
| Dwell per slice | Seconds spent on each 10 MHz slice. Longer = better sensitivity, slower revisit. |
| Sweep running | Uncheck to hold on the current slice. |
| LNA / MIX / VGA | The three gain stages, 0–15 dB each. |

ALF and AHF are order-independent: drag ALF above AHF and the readouts, the
axis and the sweep all still treat the lower one as the low edge.

The dB limits are the `ymin_db` (−120) and `ymax_db` (0) variables, edited in
GRC. They are deliberately not sliders, to keep the control strip uncluttered.

## How it works

```
osmocom Source ──▶ Log Power FFT ──▶ Scan Painter ──▶ QT GUI Vector Sink
  (airspy=0)        1024 bins,        (embedded          4096 bins,
                    shift=True         Python)           fixed dB axis
        ▲                                  ▲
        └────────── sweep thread ──────────┘
              retunes the LO, tells the
              painter where it went
```

A Python snippet thread steps the LO from ALF to AHF and, on each hop, does two
things only: retune the radio, and tell the painter the new centre frequency.
It never touches either display axis — that is what keeps the numbers still.

The **Scan Painter** maps each FFT frame onto the fixed ALF..AHF axis. Two
details matter:

- **Settling.** Frames captured while the tuner is still moving would carry the
  previous slice's energy under the new centre-frequency label, placing signals
  at frequencies where they are not. The first 2 frames after each retune are
  discarded.
- **No floor holes.** The vector starts at `ymin_db` and each dwell *overwrites*
  its own bins on its first accepted frame, then max-holds within that dwell. A
  bin always carries the newest measurement of that frequency and never drops
  off the bottom of the plot. (An earlier version cleared each slice to −160 dB
  on retune, which drew vertical spikes wherever a slice was unpainted or
  mid-refresh.)

## Troubleshooting

**`ImportError: initialization failed` from `from gnuradio import gr`**

GNU Radio 3.10's Python bindings are pybind11 modules compiled against the
**numpy 1.x C ABI**. A numpy 2.x in `~/.local/lib/pythonX.Y/site-packages` takes
precedence over the system copy and breaks them. Note that `python3 -m venv
--system-site-packages` *re-enables* the user site directory, so a venv alone
does not fix this — `PYTHONNOUSERSITE=1` is what does, and `install.sh` pins it
inside `.airspyvenv/bin/activate`. Always `source` the venv before running.

**`airspy_open() board 1 failed: AIRSPY_ERROR_NOT_FOUND (-5)` with the radio
plugged in**

Almost always another process still holds the device — most often a flowgraph
that did not exit. Check and stop it:

```bash
pgrep -af airspy_scan.py
kill -INT <pid>          # SIGINT, so it closes the radio properly
```

Avoid `kill -9` on a running flowgraph: it skips the shutdown path that releases
the USB device.

**The window opens tiny, or the plot is a sliver**

GRC 3.10.9.2 emits no `resize()` call for the options block's `window_size`; the
window falls back to the layout size hint and collapses. The flowgraph carries a
`main_after_init` snippet that calls `resize()` and `setMinimumSize()` to fix
this. Measured: 270×166 without it, 1628×1066 with it.

**Overruns (`O` printed repeatedly)**

The source is producing faster than the graph consumes. Raise the dwell, or drop
`samp_rate` to `2.5e6` — but remember only **10e6 and 2.5e6** are legal for this
radio.

## Repository layout

| Path | |
|---|---|
| `airspy_scan.grc` | The flowgraph. The only thing you need to run. |
| `install.sh` | Dependency install, venv setup and verification. |
| `tools/grc-valgrind.sh` | Runs `gnuradio-companion` under valgrind memcheck. |
| `tools/grc-debug.sh` | Runs it under gdb for a backtrace on crash. |

`airspy_scan.py` and `airspy_scan_stitcher.py` are generated by `grcc` and are
git-ignored; regenerate them with `grcc -o . airspy_scan.grc`.

The two `tools/` scripts exist because `gnuradio-companion` aborted once with
`corrupted double-linked list` inside GTK's main loop. That was never reproduced
— six clean runs and 90 s under memcheck showed nothing — so they are kept for
the next occurrence rather than as a fix for a known bug. Use them on the GRC
*editor* only; running the flowgraph under memcheck is not practical.

## Status

Verified on Ubuntu 24.04.4 LTS, GNU Radio 3.10.9.2, AirSpy R2:

- runs against the radio: window renders, no errors, clean SIGINT shutdown
- sweep plan covers ALF..AHF with no gaps, over full-range, narrow-span,
  band-edge and inverted ALF/AHF cases
- a full 222-slice sweep paints all 4096 bins; a partial sweep leaves no bin
  below the graph floor
- tuner-settling frames are discarded; revisiting a slice replaces its old
  values rather than holding a stale peak
- ALF/AHF readouts stay truthful when the sliders are dragged past each other

Long-run stability and sensitivity across the full range have not been
characterised.
