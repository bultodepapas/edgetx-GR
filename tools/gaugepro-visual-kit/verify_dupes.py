"""Post-run verification: find screenshots that are byte-identical to a
DIFFERENT case's screenshot -- the signature of the batch-boundary reset
race observed empirically (the first capture right after a new model's
reset() occasionally still shows the previous batch's last frame). Distinct
cases legitimately rendering identical pixels is possible but rare given
the option space size, so this is a strong, cheap signal worth acting on.

Usage: python verify_dupes.py
"""

import hashlib
import os

SHOTS_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                          "..", "..", "WIDGETS", "GaugePro", "docs",
                          "visual-kit", "screenshots")


def main():
    by_hash = {}
    files = sorted(f for f in os.listdir(SHOTS_DIR) if f.endswith(".png"))
    for f in files:
        path = os.path.join(SHOTS_DIR, f)
        with open(path, "rb") as fh:
            h = hashlib.sha1(fh.read()).hexdigest()
        by_hash.setdefault(h, []).append(f)

    dupes = {h: names for h, names in by_hash.items() if len(names) > 1}
    print("%d files, %d unique, %d duplicate groups" %
          (len(files), len(by_hash), len(dupes)))
    for h, names in sorted(dupes.items(), key=lambda kv: kv[1][0]):
        print("  DUPLICATE:", names)
    return dupes


if __name__ == "__main__":
    main()
