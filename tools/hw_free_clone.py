#!/usr/bin/env python3
"""Build a copy of airspy_scan.grc that needs no radio.

Swaps the osmocom Source for a signal source and a throttle, leaving every
other block -- the FFT, the painter, the display, the controls, the sweep
thread -- exactly as shipped. Used by the test suite so the GUI and the
signal path can be exercised on a machine with no AirSpy attached.

    python3 tools/hw_free_clone.py airspy_scan.grc /tmp/gui_clone.grc
"""
import sys

FAKE_SOURCE = """- name: analog_sig_source_x_0
  id: analog_sig_source_x
  parameters: {amp: '0.5', freq: '1.2e6', samp_rate: samp_rate, type: complex,
    waveform: analog.GR_COS_WAVE}
  states: {coordinate: [200, 452], rotation: 0, state: enabled}

- name: blocks_throttle_0
  id: blocks_throttle
  parameters: {samples_per_second: samp_rate, type: complex}
  states: {coordinate: [440, 452], rotation: 0, state: enabled}

"""


def clone(src_text, new_id="gui_clone", new_title="GuiClone"):
    i = src_text.index("- name: osmosdr_source_0")
    j = src_text.index("- name: logpwrfft_x_0")
    out = src_text[:i] + FAKE_SOURCE + src_text[j:]
    out = out.replace(
        "- [osmosdr_source_0, '0', logpwrfft_x_0, '0']",
        "- [analog_sig_source_x_0, '0', blocks_throttle_0, '0']\n"
        "- [blocks_throttle_0, '0', logpwrfft_x_0, '0']")
    # the sweep thread retunes a radio that is not in this graph
    out = out.replace(
        "tb.osmosdr_source_0.set_center_freq(fc, 0)",
        "getattr(tb, 'osmosdr_source_0', None) and "
        "tb.osmosdr_source_0.set_center_freq(fc, 0)")
    out = out.replace("id: airspy_scan", "id: %s" % new_id)
    out = out.replace("title: AirSpy Scanner (ALF - AHF)", "title: %s" % new_title)
    return out


def main(argv):
    if len(argv) != 3:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    with open(argv[1], encoding="utf-8") as fh:
        text = fh.read()
    with open(argv[2], "w", encoding="utf-8") as fh:
        fh.write(clone(text))
    print("wrote %s" % argv[2])
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
