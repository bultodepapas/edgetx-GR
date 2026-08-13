"""Post-run verification: find screenshots that are byte-identical to a
DIFFERENT case's screenshot -- the signature of the batch-boundary reset
race observed empirically (the first capture right after a new model's
reset() occasionally still shows the previous batch's last frame), and also
of the harness silently defeating a case's own point (docs/visual-kit/
INFORME-DEFECTOS.md H-01: several cases whose test IS their size or their
ColorMode used to render byte-identical because the harness ignored the
zone they declared). Distinct cases legitimately rendering identical pixels
is possible but rare given the option space size, so this is a strong,
cheap signal worth acting on.

find_duplicate_groups() is the reusable half report.py imports to fold this
check into CATALOG.md/RUN_SUMMARY.md generation. main() is the standalone
CLI entry point, unchanged.

Usage: python verify_dupes.py
"""

import hashlib
import json
import os
import re
import sys

SHOTS_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                          "..", "..", "WIDGETS", "GaugePro", "docs",
                          "visual-kit", "screenshots")
RUNLOG_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                           "..", "..", "WIDGETS", "GaugePro", "dev",
                           "visual-kit-run", "run.log.jsonl")

# Case-name pairs that SHOULD render identically, with the reason. Everything
# else in a duplicate group is signal.
#
# Without this split the check reported 48 undifferentiated warnings, which is
# the same as reporting none: three real defects (an option with no effect on
# either family, a surface that painted nothing, three dial ColorModes that
# collapsed into one) sat in that list for a full run, indistinguishable from
# "Medium IS the default thickness".
EXPECTED_IDENTICAL = [
    # (regex over the pair of case names, why)
    (r"^br-(normal|auto|medium|end-round)$",
     "Medium thickness and Round ends ARE the defaults"),
    (r"^(st-normal|color-rail-ok|op-style-needle|zone-\d+x\d+)$",
     "Rail and Needle ARE the dial defaults, so these restate st-normal"),
    (r"^(st-crit|color-rail-crit|op-chip-off-crit)$",
     "same, in the critical state; CRIT keeps its pill with the chip off"),
    (r"^br-(crit|narrow|short|nochip)$",
     "same reading; the two size cases render full-screen here, and CRIT "
     "keeps its pill with the chip off by design"),
    (r"^br-(mode-gradient|gradient-compact)$",
     "compact differs only in a canvas size this track renders full-screen"),
    (r"^zone-\d+x\d+$",
     "zone sizes that map onto the same real EdgeTX layout zone"),
    (r"^(st-nolink|op-chip-on)$",
     "ShowChip defaults to On, so the explicit On case intentionally "
     "restates the same NO LINK state"),
    (r"^(ac-default|color-sections-ok)$",
     "the default accent case IS the Sections case: identical option sets"),
    (r"^(op-mm-text|tx-scalelabels|zone-\d+x\d+)$",
     "identical option sets at the same real zone (all three set "
     "ShowMinMax = Markers + text)"),
    (r"^(br-warn|pal-classic|br-surface-clear|br-mode-rail)$",
     "Classic palette, Transparent surface and Rail colour mode ARE the "
     "bar defaults, so these four restate br-warn"),
    (r"^(f4-auto-rssi|f4-preset-hex|pal-preset-auto)$",
     "BarPreset = Auto resolves to the Hex face for this source, by design"),
]


def _case_of(filename):
    """`012_color_color-gradient-crit.png` -> `color-gradient-crit`."""
    stem = re.sub(r"\.png$", "", filename)
    stem = re.sub(r"__[a-z0-9-]+$", "", stem)      # theme suffix
    parts = stem.split("_", 2)
    return parts[2] if len(parts) == 3 else stem


def classify_group(names):
    """(expected_reason, None) when every case in the group is covered by one
    EXPECTED_IDENTICAL rule; (None, cases) otherwise."""
    cases = sorted({_case_of(n) for n in names})
    if len(cases) == 1:
        return "the same case captured in more than one theme", None
    for pattern, reason in EXPECTED_IDENTICAL:
        if all(re.match(pattern, c) for c in cases):
            return reason, None
    return None, cases


def find_duplicate_groups(shots_dir=SHOTS_DIR, only_unexpected=False,
                          allowed_files=None):
    """{sha1: [filename, ...]} for every group of 2+ byte-identical PNGs in
    `shots_dir`, filenames sorted for determinism. Empty dict if the
    directory doesn't exist yet (a fresh checkout before the first run).

    With `only_unexpected`, groups covered by EXPECTED_IDENTICAL are dropped,
    which is what makes the remainder worth reading."""
    if not os.path.isdir(shots_dir):
        return {}
    by_hash = {}
    files = sorted(f for f in os.listdir(shots_dir)
                   if f.endswith(".png") and
                   (allowed_files is None or f in allowed_files))
    for f in files:
        path = os.path.join(shots_dir, f)
        with open(path, "rb") as fh:
            h = hashlib.sha1(fh.read()).hexdigest()
        by_hash.setdefault(h, []).append(f)
    groups = {h: names for h, names in by_hash.items() if len(names) > 1}
    if not only_unexpected:
        return groups
    return {h: names for h, names in groups.items()
            if classify_group(names)[0] is None}


def main():
    rows = []
    if os.path.isfile(RUNLOG_PATH):
        with open(RUNLOG_PATH, "r", encoding="utf-8") as f:
            rows = [json.loads(line) for line in f if line.strip()]
    expected = {r["file"] for r in rows if r.get("file")}
    actual = ({f for f in os.listdir(SHOTS_DIR) if f.endswith(".png")}
              if os.path.isdir(SHOTS_DIR) else set())
    missing = sorted(expected - actual)
    unreferenced = sorted(actual - expected)
    capture_rows = [r for r in rows if r.get("file")]
    run_ids = {r.get("run_id") for r in capture_rows}
    provenance_error = (not capture_rows or len(run_ids) != 1 or None in run_ids or
                        any(not r.get("fresh") for r in capture_rows))

    dupes = find_duplicate_groups(allowed_files=expected)
    total = len(expected)
    unique = total - sum(len(v) - 1 for v in dupes.values())
    print("%d files, %d unique, %d duplicate groups" %
          (total, unique, len(dupes)))
    if missing:
        print("  ERROR: %d referenced PNG(s) missing" % len(missing))
    if unreferenced:
        print("  ERROR: %d unreferenced PNG(s) present" % len(unreferenced))
    if provenance_error:
        print("  ERROR: run log is missing a single all-fresh run provenance")
    unexpected = 0
    for _h, names in sorted(dupes.items(), key=lambda kv: kv[1][0]):
        reason, cases = classify_group(names)
        if reason:
            print("  expected  :", ", ".join(sorted({_case_of(n)
                                                     for n in names})),
                  "--", reason)
        else:
            unexpected += 1
            print("  UNEXPECTED:", ", ".join(cases))
    print("%d unexpected duplicate group(s)" % unexpected)
    return 1 if missing or unreferenced or provenance_error or unexpected else 0


if __name__ == "__main__":
    sys.exit(main())
