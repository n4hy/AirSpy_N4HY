#!/usr/bin/env python3
"""Check the sweep plan covers ALF..AHF with no gaps and never tunes out of band.

This does not re-implement the planner. It lifts the actual _plan() function out
of the flowgraph grcc generates, so a change to the .grc that breaks coverage
fails here.
"""
import ast
import math
import os
import sys

GEN = os.environ.get("GENDIR", ".")
F_MIN, F_MAX = 24e6, 1800e6          # AirSpy R2, as the device reports itself
SR = 10e6


def load_plan():
    """Extract _plan() from the generated flowgraph and make it callable.

    _plan lives inside snipfcn_sweep_start and closes over the _F_MIN/_F_MAX
    constants defined beside it, so both the constants and the function have
    to come across for it to run.
    """
    path = os.path.join(GEN, "airspy_scan.py")
    tree = ast.parse(open(path, encoding="utf-8").read())
    snippet = next((n for n in ast.walk(tree)
                    if isinstance(n, ast.FunctionDef)
                    and n.name == "snipfcn_sweep_start"), None)
    if snippet is None:
        raise SystemExit("no snipfcn_sweep_start in %s" % path)

    def is_const(node):
        # _F_MIN = 24e6 etc. -- plain-name assignments only, so that
        # "self._sweep_thread = threading.Thread(...)" is not dragged in.
        return (isinstance(node, ast.Assign)
                and all(isinstance(t, ast.Name) for t in node.targets))

    body = [n for n in snippet.body
            if is_const(n)
            or (isinstance(n, ast.FunctionDef) and n.name == "_plan")]
    if not any(isinstance(n, ast.FunctionDef) for n in body):
        raise SystemExit("no _plan() inside snipfcn_sweep_start in %s" % path)

    mod = ast.Module(body=body, type_ignores=[])
    ns = {"math": math}
    exec(compile(ast.fix_missing_locations(mod), path, "exec"), ns)
    return ns["_plan"]


class TB:
    """Stands in for the flowgraph: _plan only reads these attributes."""
    def __init__(self, alf, ahf, samp_rate=SR, overlap=0.8):
        self.alf_mhz, self.ahf_mhz = alf, ahf
        self.samp_rate, self.overlap = samp_rate, overlap


def main():
    plan = load_plan()
    fails = 0

    cases = [(24, 1800), (24, 30), (88, 108), (100, 1000),
             (1795, 1800), (1800, 24), (24, 24.5), (400, 401)]
    for alf, ahf in cases:
        centers = plan(TB(alf, ahf))
        lo = max(min(alf, ahf) * 1e6, F_MIN)
        hi = min(max(alf, ahf) * 1e6, F_MAX)

        in_band = all(F_MIN - 1 <= c <= F_MAX + 1 for c in centers)

        cov_lo, cov_hi, gap = centers[0] - SR / 2, centers[0] + SR / 2, None
        for c in centers[1:]:
            if c - SR / 2 > cov_hi + 1e-6:
                gap = (cov_hi, c - SR / 2)
                break
            cov_hi = max(cov_hi, c + SR / 2)

        if hi - lo > SR:
            covered = cov_lo <= lo + 1e-6 and cov_hi >= hi - 1e-6 and gap is None
        else:
            covered = lo <= centers[0] <= hi

        ok = covered and in_band
        fails += not ok
        print("%s  ALF=%-8s AHF=%-8s slices=%-4d %.3f..%.3f MHz  gap=%s"
              % ("PASS" if ok else "FAIL", alf, ahf, len(centers),
                 centers[0] / 1e6, centers[-1] / 1e6, gap))

    # every legal sample rate for this radio
    for sr in (10e6, 2.5e6):
        centers = plan(TB(24, 1800, samp_rate=sr))
        ok = all(F_MIN - 1 <= c <= F_MAX + 1 for c in centers)
        fails += not ok
        print("%s  samp_rate=%-8s slices=%d, all centres in band"
              % ("PASS" if ok else "FAIL", sr, len(centers)))

    print("\n=== %d failure(s) ===" % fails)
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
