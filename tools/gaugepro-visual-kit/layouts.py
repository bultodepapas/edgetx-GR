"""Real EdgeTX screen layouts: normalized zone maps transcribed from
radio/src/gui/colorlcd/layouts/*.cpp's zmap[] arrays via the existing,
already-audited WIDGETS/GaugePro/dev/zone_atlas.lua tool (its "Source layout
maps" table) -- not re-derived, so this can never silently disagree with
what that tool already parses from the real firmware source.

Regenerate by running (from WIDGETS/GaugePro):
  lua dev/zone_atlas.lua ./ /tmp/zone_atlas.md
and diffing its "## Source layout maps" table against ZMAP below.
"""

# file stem (radio/src/gui/colorlcd/layouts) -> real YAML LayoutId, from the
# BaseLayoutFactory<...> registrations (grep'd against the .cpp files).
LAYOUT_ID = {
    "layout1+2": "Layout1P2", "layout1+3": "Layout1P3",
    "layout1+4": "Layout1P4", "layout1x1": "Layout1x1",
    "layout1x2": "Layout1x2", "layout1x3": "Layout1x3",
    "layout1x4": "Layout1x4", "layout1x6": "Layout1x6",
    "layout2+1": "Layout2P1", "layout2+3": "Layout2P3",
    "layout2x1": "Layout2x1", "layout2x2": "Layout2x2",
    "layout2x3": "Layout2x3", "layout2x4": "Layout2x4",
    "layout4+2": "Layout4P2", "layout4+2b": "Layout4P2B",
    # layout1x1AppMode deliberately excluded (app-mode, not a home screen).
}

# Normalized (x, y, w, h) tuples over a 0..60 grid, one list per file stem --
# straight transcription of zone_atlas.lua's "Source layout maps" table.
ZMAP = {
    "layout1+2": [(0, 0, 60, 30), (0, 30, 60, 15), (0, 45, 60, 15)],
    "layout1+3": [(0, 0, 30, 60), (30, 0, 30, 20), (30, 20, 30, 20),
                  (30, 40, 30, 20)],
    "layout1+4": [(0, 0, 30, 60), (30, 0, 30, 15), (30, 15, 30, 15),
                  (30, 30, 30, 15), (30, 45, 30, 15)],
    "layout1x1": [(0, 0, 60, 60)],
    "layout1x2": [(0, 0, 60, 30), (0, 30, 60, 30)],
    "layout1x3": [(0, 0, 60, 20), (0, 20, 60, 20), (0, 40, 60, 20)],
    "layout1x4": [(0, 0, 60, 15), (0, 15, 60, 15), (0, 30, 60, 15),
                  (0, 45, 60, 15)],
    "layout1x6": [(0, 0, 60, 10), (0, 10, 60, 10), (0, 20, 60, 10),
                  (0, 30, 60, 10), (0, 40, 60, 10), (0, 50, 60, 10)],
    "layout2+1": [(30, 0, 30, 60), (0, 0, 30, 30), (0, 30, 30, 30)],
    "layout2+3": [(0, 0, 30, 30), (0, 30, 30, 30), (30, 0, 30, 20),
                  (30, 20, 30, 20), (30, 40, 30, 20)],
    "layout2x1": [(0, 0, 30, 60), (30, 0, 30, 60)],
    "layout2x2": [(0, 0, 30, 30), (0, 30, 30, 30), (30, 0, 30, 30),
                  (30, 30, 30, 30)],
    "layout2x3": [(0, 0, 30, 20), (0, 20, 30, 20), (0, 40, 30, 20),
                  (30, 20, 30, 20), (30, 40, 30, 20), (30, 0, 30, 20)],
    "layout2x4": [(0, 0, 30, 15), (0, 15, 30, 15), (0, 30, 30, 15),
                  (0, 45, 30, 15), (30, 0, 30, 15), (30, 15, 30, 15),
                  (30, 30, 30, 15), (30, 45, 30, 15)],
    "layout4+2": [(0, 0, 30, 15), (0, 15, 30, 15), (0, 30, 30, 15),
                  (0, 45, 30, 15), (30, 0, 30, 30), (30, 30, 30, 30)],
    "layout4+2b": [(0, 0, 30, 15), (0, 15, 30, 15), (0, 30, 30, 15),
                   (0, 45, 30, 15), (30, 0, 30, 45), (30, 45, 30, 15)],
}


def pixel_rect(stem, zone_index, screen_w=480, screen_h=272):
    """Pixel (x, y, w, h) for a layout zone against the undecorated
    full-screen root (no topbar/sliders/trims) -- matches
    zone_atlas.lua's resolveZone() formula exactly (floor division)."""
    x, y, w, h = ZMAP[stem][zone_index]
    return (
        (screen_w * x) // 60, (screen_h * y) // 60,
        (screen_w * w) // 60, (screen_h * h) // 60,
    )


def all_zones(screen_w=480, screen_h=272):
    """(stem, zone_index, LayoutId, (x, y, w, h)) for every real zone."""
    out = []
    for stem, zones in ZMAP.items():
        layout_id = LAYOUT_ID.get(stem)
        if not layout_id:
            continue
        for zi in range(len(zones)):
            out.append((stem, zi, layout_id,
                        pixel_rect(stem, zi, screen_w, screen_h)))
    return out


def nearest_zone(target_w, target_h, screen_w=480, screen_h=272):
    """The real (LayoutId, zone_index, (x,y,w,h)) whose size best matches
    (target_w, target_h) -- used for the 'zonas' zone-size matrix, whose
    whole point is real EdgeTX zone sizes (plan Sec 4 Track 1)."""
    best = None
    best_score = None
    for stem, zi, layout_id, (x, y, w, h) in all_zones(screen_w, screen_h):
        if w <= 0 or h <= 0:
            continue
        # Size-distance first (what the section is testing), aspect-ratio
        # distance as a tiebreaker.
        size_d = abs(w - target_w) + abs(h - target_h)
        aspect_d = abs((w / h) - (target_w / target_h))
        score = (size_d, aspect_d)
        if best_score is None or score < best_score:
            best_score = score
            best = (layout_id, zi, (x, y, w, h))
    return best
