"""Builds the part-slicing template for the custom humanoid rig. Pixel sizes = points / 0.128 (the 2048x1536 template scale)."""
import json
from PIL import Image, ImageDraw, ImageFont
W, H, PAD = 2048, 1536, 30
K = 1 / 0.128
def font(n):
    try: return ImageFont.truetype("/System/Library/Fonts/Menlo.ttc", n)
    except Exception: return ImageFont.load_default()

# name: (cell x, y, w, h, pivot x, pivot y inside the cell, art w, art h, shape)
parts = {
 "head":       (40,   40, 708, 708, 354, 354, 648, 648, "circle"),
 "torso":      (790,  40, 412, 451, 206, 242, 352, 391, "ellipse"),
 "arm_weapon": (1244, 40, 224, 396, 140, 60,  171, 351, "arm"),
 "arm_off":    (1510, 40, 224, 396, 75,  58,  168, 332, "arm"),
 "leg_back":   (22,  790, 256, 295, 128, 30,  236, 125, "foot"),
 "leg_front":  (278, 790, 256, 295, 128, 30,  236, 125, "foot"),
}
notes = {"head": "HEAD  648x648 - hood + face, sits straight on the body (no neck). Pivot = centre.",
         "torso": "TORSO  352x391 - egg shape, belt near the bottom. Pivot = body origin (a little below centre).",
         "arm_weapon": "WEAPON ARM 164x336. Hangs almost to the ground. Pivot = shoulder.",
         "arm_off": "OFF-HAND ARM. Same size; the game draws it at 88%.",
         "leg_back": "BACK LEG 236x125 foot. Pivot = hip.",
         "leg_front": "FRONT LEG. Same as the back leg."}

def guides(bg):
    im = Image.new("RGBA", (W, H), bg); d = ImageDraw.Draw(im)
    for name, (x, y, w, h, px, py, aw, ah, shape) in parts.items():
        d.rectangle([x, y, x + w, y + h], outline=(150, 150, 150, 255), width=3)                       # cell
        ax, ay = x + (w - aw) // 2, y + PAD
        if shape == "circle":   box = [x + PAD, y + PAD, x + PAD + aw, y + PAD + ah]; d.ellipse(box, outline=(120, 170, 255, 255), width=3)
        elif shape == "ellipse": d.ellipse([x + PAD, y + PAD, x + PAD + aw, y + PAD + ah], outline=(120, 170, 255, 255), width=3)
        elif shape == "arm":    d.rounded_rectangle([x + PAD, y + PAD, x + PAD + aw, y + PAD + ah], radius=aw // 2, outline=(120, 170, 255, 255), width=3)
        elif shape == "foot":
            top = y + py + 112                                                                            # foot top sits 112 px below the hip
            fx = x + (w - aw) // 2
            d.rounded_rectangle([fx, top, fx + aw, top + ah], radius=40, outline=(120, 170, 255, 255), width=3)
            d.line([x + px, y + py, x + px, top], fill=(255, 140, 140, 255), width=2)
        cx, cy = x + px, y + py                                                                           # pivot crosshair
        d.line([cx - 26, cy, cx + 26, cy], fill=(255, 0, 0, 255), width=4); d.line([cx, cy - 26, cx, cy + 26], fill=(255, 0, 0, 255), width=4)
        d.ellipse([cx - 7, cy - 7, cx + 7, cy + 7], outline=(255, 0, 0, 255), width=3)
        import textwrap
        for i, ln in enumerate(textwrap.wrap(notes[name], max(12, w // 9))): d.text((x + 4, y + h + 6 + i * 20), ln, fill=(90, 90, 90, 255), font=font(15))
    # assembled reference: the parts at their rig positions (ground-centre origin), half scale
    ox, oy, s = 1550, 1400, 0.5
    def pt(gx, gy): return ox + gx * s, oy - gy * s
    d.line([ox - 330, oy, ox + 330, oy], fill=(120, 120, 120, 255), width=2)
    head_c = (23, 570); wsh = (-148, 367); osh = (109, 359); hips = [(-78, 234), (90, 234)]
    d.ellipse([*pt(head_c[0] - 324, head_c[1] + 324), *pt(head_c[0] + 324, head_c[1] - 324)], outline=(120, 170, 255, 255), width=3)
    d.ellipse([*pt(-176, 234 + 195 + 16), *pt(176, 234 - 195 + 16)], outline=(120, 170, 255, 255), width=3)
    for (sx, sy), k in ((wsh, 1), (osh, 0.88)):
        d.rounded_rectangle([*pt(sx - 82 * k, sy), *pt(sx + 82 * k, sy - 336 * k)], radius=int(82 * k * s), outline=(120, 170, 255, 255), width=3)
    for hx, hy in hips: d.rounded_rectangle([*pt(hx - 118, hy - 112), *pt(hx + 118, hy - 237)], radius=20, outline=(120, 170, 255, 255), width=3)
    for p in (head_c, wsh, osh, *hips):
        cx, cy = pt(*p); d.ellipse([cx - 6, cy - 6, cx + 6, cy + 6], outline=(255, 0, 0, 255), width=3)
    d.text((ox - 330, oy + 8), "ASSEMBLED (half scale): how the parts sit on the rig. Red = joints.", fill=(90, 90, 90, 255), font=font(15))
    d.text((40, 1480), "Draw each part INSIDE its cell, facing right, on a transparent layer. Keep the red pivot on the joint. Hide this layer before exporting.", fill=(90, 90, 90, 255), font=font(18))
    return im

guides((0, 0, 0, 0)).save("template_guides.png")                                                          # transparent: use as a top layer
sheet = guides((255, 255, 255, 255)); sheet.convert("RGB").save("template_sheet.png")
json.dump({"scale_pt_per_px": 0.128, "padding": PAD,
           "cells": {n: {"x": v[0], "y": v[1], "w": v[2], "h": v[3], "pivot": [v[4], v[5]], "art": [v[6], v[7]]} for n, v in parts.items()},
           "rig_joints_px_from_ground_centre": {"head": [23, 570], "weapon_shoulder": [-148, 367], "off_shoulder": [109, 359], "hip_back": [-78, 234], "hip_front": [90, 234]}},
          open("template_spec.json", "w"), indent=2)
print("ok")
