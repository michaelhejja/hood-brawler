"""Builds the weapon drawing template: one cell per held weapon, at the same scale as the character sheets (0.128 pt/px).
Writes templates/weapon_sheet.png (white bg), templates/weapon_guides.png (transparent) and templates/weapon_spec.json.
Slice a finished sheet with: python3 slice_sheet.py weapons.png weapon templates/weapon_spec.json   ->  Brawler/Sprites/weapon_<name>.png"""
import json
from PIL import Image, ImageDraw, ImageFont
W, H = 2560, 1640
PPP = 0.128
# name: (x, y, w, h, pivot_x, pivot_y, current tip height in points above the grip, note)  pivot = the grip, from the cell's top-left
LAYOUT = {
    "spear":       (40,   40, 260, 1200, 130, 1010, 110, "SPEAR - tip up"),
    "staff":       (340,  40, 240, 1140, 120,  900,  98, "STAFF - orb at the very top (the game adds the glow)"),
    "ice_staff":   (620,  40, 240, 1140, 120,  900, 104, "ICE STAFF - crystal at the very top (the game adds the glow)"),
    "hammer":      (940,  40, 360,  820, 180,  700,  82, "HAMMER - head up"),
    "shield":      (1340, 40, 300,  780, 150,  570,  65, "SHIELD - face toward you, cross in the middle (the game adds the guard glow)"),
    "bow":         (1680, 40, 360,  700, 110,  350,  32, "BOW - belly bulges RIGHT, cross on the string line, NO string (the game adds it)"),
    "axe":         (2080, 40, 340,  700, 110,  580,  58, "AXE - blade on the RIGHT"),
    "sword":       (940,  930, 280, 640, 140,  520,  56, "SWORD"),
    "light_blade": (1260, 930, 280, 640, 140,  520,  60, "LIGHT BLADE - no glow needed (the game adds it)"),
    "rusty_blade": (1580, 930, 260, 640, 130,  520,  42, "RUSTY BLADE"),
    "rock":        (1880, 930, 300, 300, 150,  150,  10, "ROCK - cross in the middle"),
    "bomb":        (2220, 930, 300, 400, 150,  280,  28, "BOMB - fuse up, no spark (the game adds it at the very top)"),
}
cells = {n: dict(x=v[0], y=v[1], w=v[2], h=v[3], pivot=[v[4], v[5]], tip=v[6], note=v[7]) for n, v in LAYOUT.items()}
# sanity: inside the canvas, no overlaps (label strip below each cell counts as part of it)
rects = {n: (c["x"], c["y"], c["x"] + c["w"], c["y"] + c["h"] + 30) for n, c in cells.items()}
for n, r in rects.items():
    assert r[2] <= W and r[3] <= H, f"{n} is off the canvas"
    for m, q in rects.items():
        if n < m: assert r[2] <= q[0] or q[2] <= r[0] or r[3] <= q[1] or q[3] <= r[1], f"{n} overlaps {m}"
def draw(bg):
    im = Image.new("RGBA", (W, H), bg); d = ImageDraw.Draw(im)
    f = ImageFont.truetype("/System/Library/Fonts/Menlo.ttc", 15)
    for n, c in cells.items():
        x, y, w, h = c["x"], c["y"], c["w"], c["h"]
        d.rectangle([x, y, x + w, y + h], outline=(150, 150, 150, 255), width=3)
        px, py = x + c["pivot"][0], y + c["pivot"][1]
        d.line([px - 26, py, px + 26, py], fill=(255, 0, 0, 255), width=4); d.line([px, py - 26, px, py + 26], fill=(255, 0, 0, 255), width=4)
        ty = py - c["tip"] / PPP                                   # blue tick: how long the current code-drawn weapon is
        d.line([x, ty, x + 40, ty], fill=(60, 120, 255, 255), width=3)
        d.text((x + 4, y + h + 6), c["note"], fill=(90, 90, 90, 255), font=f)
    d.text((40, H - 40), "Draw each weapon INSIDE its cell, upright, on a transparent layer. Red cross = the hand's grip. Blue tick = how long the current weapon is. Hide this layer before exporting.", fill=(90, 90, 90, 255), font=f)
    return im
draw((255, 255, 255, 255)).convert("RGB").save("templates/weapon_sheet.png"); draw((0, 0, 0, 0)).save("templates/weapon_guides.png")
json.dump(dict(canvas=[W, H], meta=True, cells=cells), open("templates/weapon_spec.json", "w"), indent=2)
print("ok", W, H, len(cells), "cells")
