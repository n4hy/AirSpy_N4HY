#!/usr/bin/env python3
"""Check the ALF/AHF labels and readouts, with no radio attached.

Instantiates the hardware-free clone of the flowgraph under an offscreen Qt
platform and reads the text out of the real widgets.
"""
import os
import sys

sys.path.insert(0, os.environ.get("GENDIR", "."))
os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

from PyQt5 import Qt                                    # noqa: E402

app = Qt.QApplication(sys.argv)
import gui_clone                                        # noqa: E402

tb = gui_clone.gui_clone()
fails = 0


def check(desc, got, want):
    global fails
    ok = got == want
    fails += not ok
    print("%s  %s\n      got=%r want=%r" % ("PASS" if ok else "FAIL", desc, got, want))


def readouts():
    return tb._alf_readout_label.text(), tb._ahf_readout_label.text()


captions = sorted({w.text() for w in tb.findChildren(Qt.QLabel)
                   if w.text().startswith(("ALF", "AHF"))})
print("captions on screen:")
for c in captions:
    print("    %r" % c)
print()

check("an ALF caption is present", any(c.startswith("ALF") for c in captions), True)
check("an AHF caption is present", any(c.startswith("AHF") for c in captions), True)
check("defaults are the AirSpy R2 band edges", readouts(), ("24.000 MHz", "1800.000 MHz"))

tb.set_alf_mhz(88.5); tb.set_ahf_mhz(108.25)
check("readouts follow the sliders", readouts(), ("88.500 MHz", "108.250 MHz"))

tb.set_alf_mhz(900.0); tb.set_ahf_mhz(100.0)
check("dragging ALF above AHF keeps the readouts truthful",
      readouts(), ("100.000 MHz", "900.000 MHz"))

print("\n=== %d failure(s) ===" % fails)
sys.exit(1 if fails else 0)
