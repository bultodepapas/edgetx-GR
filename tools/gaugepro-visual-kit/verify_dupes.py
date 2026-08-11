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
import os

SHOTS_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                          "..", "..", "WIDGETS", "GaugePro", "docs",
                          "visual-kit", "screenshots")


def find_duplicate_groups(shots_dir=SHOTS_DIR):
    """{sha1: [filename, ...]} for every group of 2+ byte-identical PNGs in
    `shots_dir`, filenames sorted for determinism. Empty dict if the
    directory doesn't exist yet (a fresh checkout before the first run)."""
    if not os.path.isdir(shots_dir):
        return {}
    by_hash = {}
    files = sorted(f for f in os.listdir(shots_dir) if f.endswith(".png"))
    for f in files:
        path = os.path.join(shots_dir, f)
        with open(path, "rb") as fh:
            h = hashlib.sha1(fh.read()).hexdigest()
        by_hash.setdefault(h, []).append(f)
    return {h: names for h, names in by_hash.items() if len(names) > 1}


def main():
    dupes = find_duplicate_groups()
    total = sum(1 for f in os.listdir(SHOTS_DIR) if f.endswith(".png")) \
        if os.path.isdir(SHOTS_DIR) else 0
    unique = total - sum(len(v) - 1 for v in dupes.values())
    print("%d files, %d unique, %d duplicate groups" %
          (total, unique, len(dupes)))
    for h, names in sorted(dupes.items(), key=lambda kv: kv[1][0]):
        print("  DUPLICATE:", names)
    return dupes


if __name__ == "__main__":
    main()
