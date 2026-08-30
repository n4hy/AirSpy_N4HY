#!/usr/bin/env python3
"""Check the Scan Painter puts energy at the right frequency and never
drops a bin off the bottom of the graph.

Imports the embedded Python block exactly as grcc generates it.
"""
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.environ.get("GENDIR", "."))
import airspy_scan_stitcher as painter          # noqa: E402

VLEN, NBINS, SR = 1024, 4096, 10e6
ALF, AHF, FLOOR = 24e6, 1800e6, -120.0
STEP = (AHF - ALF) / NBINS

fails = 0


def check(desc, ok, extra=""):
    global fails
    fails += not ok
    print("%s  %s%s" % ("PASS" if ok else "FAIL", desc,
                        "  " + extra if extra else ""))


def mk(settle=0):
    return painter.blk(vlen=VLEN, nbins=NBINS, alf_hz=ALF, ahf_hz=AHF,
                       samp_rate=SR, settle=settle, floor_db=FLOOR)


def push(b, frames):
    out = np.zeros((len(frames), NBINS), dtype=np.float32)
    b.work([np.asarray(frames, dtype=np.float32)], [out])
    return out[-1]


def tone(k, peak=-10.0, base=-160.0):
    f = np.full(VLEN, base, dtype=np.float32)
    f[k] = peak
    return f


print("axis %.3f..%.3f MHz, %.3f kHz/bin\n" % (ALF / 1e6, AHF / 1e6, STEP / 1e3))

# --- frequency mapping ---------------------------------------------------
for fc, k in ((100e6, 512), (100e6, 100), (1000e6, 900), (500e6, 200)):
    b = mk(); b.set_center(fc)
    spec = push(b, [tone(k)])
    f_true = fc - SR / 2 + k * (SR / VLEN)
    want = int(math.floor((f_true - ALF) / STEP))
    got = int(np.argmax(spec))
    check("tone at %9.3f MHz -> bin %d" % (f_true / 1e6, got),
          got == want and abs(spec[got] + 10.0) < 1e-5, "want bin %d" % want)

# --- band edges ----------------------------------------------------------
b = mk(); b.set_center(28e6)                 # slice spans 23..33 MHz
check("energy below ALF is discarded, not clamped into bin 0",
      bool(np.all(push(b, [tone(0)]) == FLOOR)))

b = mk(); b.set_center(28e6)
spec = push(b, [tone(700)])
f_true = 28e6 - SR / 2 + 700 * (SR / VLEN)
check("in-band part of a boundary slice is kept",
      int(np.argmax(spec)) == int(math.floor((f_true - ALF) / STEP))
      and spec.max() > FLOOR)

# --- settling ------------------------------------------------------------
b = mk(settle=2); b.set_center(500e6)
stale = np.full(VLEN, -10.0, dtype=np.float32)
check("settle=2 discards the 2 frames after a retune",
      bool(np.all(push(b, [stale, stale]) == FLOOR)))
check("the 3rd frame is accepted", push(b, [stale]).max() > FLOOR)

# --- the vertical-spike regression --------------------------------------
b = mk()
check("startup trace is flat along the bottom",
      bool(np.all(push(b, [np.full(VLEN, -70.0, np.float32)]) == FLOOR)))

n = int(math.ceil((AHF - ALF - SR) / (SR * 0.8))) + 1
centers = [min(ALF + SR / 2 + i * SR * 0.8, AHF - SR / 2) for i in range(n)]
sig = tone(512, peak=-25.0, base=-70.0)
b = mk()
for fc in centers[:40]:                       # deliberately partial
    b.set_center(fc); spec = push(b, [sig])
check("mid-sweep: no bin below the graph floor",
      int(np.sum(spec < FLOOR)) == 0, "min %.1f dB" % spec.min())

# --- refresh semantics ---------------------------------------------------
b = mk(); b.set_center(500e6)
loud = tone(512, peak=-20.0, base=-70.0)
quiet = tone(512, peak=-60.0, base=-70.0)
push(b, [loud]); was = push(b, [loud]).max()
b.set_center(500e6)
now = push(b, [quiet]).max()
check("revisiting a slice replaces its old peak", now < was - 20.0,
      "%.1f -> %.1f dB" % (was, now))

b = mk(); b.set_center(500e6)
push(b, [quiet])
check("within one dwell, frames max-hold", push(b, [loud]).max() > -25.0)

# --- coverage ------------------------------------------------------------
b = mk()
for fc in centers:
    b.set_center(fc); push(b, [sig])
unpainted = int(np.sum(np.asarray(b._spec) == FLOOR))
check("a full %d-slice sweep paints all %d bins" % (len(centers), NBINS),
      unpainted == 0, "unpainted %d" % unpainted)

# --- inverted ALF/AHF ----------------------------------------------------
b = mk(); b.alf_hz, b.ahf_hz = 200e6, 100e6
b.set_center(150e6)
spec = push(b, [tone(512)])
f_true = 150e6 - SR / 2 + 512 * (SR / VLEN)
check("inverted ALF/AHF still maps correctly",
      int(np.argmax(spec)) == int(math.floor((f_true - 100e6) / ((200e6 - 100e6) / NBINS))))

print("\n=== %d failure(s) ===" % fails)
sys.exit(1 if fails else 0)
