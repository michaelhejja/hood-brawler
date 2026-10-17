"""Slicing templates for the non-Cloak rigs. Sizes come from the code-drawn skins in Brawler/Skin.swift; 7.8125 px per point,
the same as the Cloak template. Output: templates/<rig>_sheet.png (view), _guides.png (transparent, lock on top), _spec.json."""
import json, textwrap
from PIL import Image, ImageDraw, ImageFont
W, H, PAD, S, M = 2048, 1536, 30, 1 / 0.128, 40
def font(n):
    try: return ImageFont.truetype("/System/Library/Fonts/Menlo.ttc", n)
    except Exception: return ImageFont.load_default()
BLUE, RED, GREY, TXT = (120, 170, 255, 255), (255, 0, 0, 255), (150, 150, 150, 255), (90, 90, 90, 255)

# bbox = (xmin, xmax, ymin, ymax) in points relative to the pivot (y up); shape = what the main mass looks like
RIGS = {
 "necromancer": dict(title="NECROMANCER (also the Lantern Wraith: same parts, tinted pale cyan in code)", restY=28, legX=(-7, 7), shoulders=((-14, 44), (15, 44)), headPivot=(2, 64), armLength=26, scale=1.7,
   parts=dict(head=((-19, 19, -19, 36), "circle", "Hood with a tall point, bone-white face inside. Pivot = hood centre."),
              torso=((-25, 25, -20, 48), "trap", "Long robe, narrow shoulders, wide hem. Pivot = where the body meets the hips; the robe hangs 20 pt below it."),
              arm_weapon=((-5.5, 5.5, -26, 0), "arm", "Sleeve. Pivot = shoulder. The staff attaches at the bottom."),
              arm_off=((-5.5, 5.5, -26, 0), "arm", "Off-hand sleeve (drawn at 88% in game)."),
              leg_back=((-5, 5, -28, 0), "arm", "Mostly hidden by the robe. Pivot = hip."),
              leg_front=((-5, 5, -28, 0), "arm", "Same."))),
 "forge_king": dict(title="FORGE KING (goblin proportions, plus crown and armour)", restY=28, legX=(-7, 7), shoulders=((-14, 44), (15, 44)), headPivot=(2, 64), armLength=26, scale=2.4,
   parts=dict(head=((-32, 32, -16, 38), "circle", "Round head, big pointed ears out to the sides, crown on top. Pivot = head centre."),
              torso=((-16, 16, 0, 46), "rect", "Stocky torso, chest plate and apron. Pivot = bottom centre (the hips)."),
              arm_weapon=((-4, 4, -26, 0), "arm", "Arm. Pivot = shoulder. The hammer attaches at the bottom."),
              arm_off=((-4, 4, -26, 0), "arm", "Off-hand arm (drawn at 88% in game)."),
              leg_back=((-4.5, 4.5, -28, 0), "arm", "Leg. Pivot = hip."),
              leg_front=((-4.5, 4.5, -28, 0), "arm", "Same."))),
 "bat": dict(title="BAT (also the Bat King: add the crown on the head, scaled 3.2x in game)", restY=20, legX=(-4, 4), shoulders=((-6, 30), (7, 30)), headPivot=(3, 44), armLength=20, scale=1.25,
   parts=dict(head=((-13, 13, -16, 31), "circle", "Fanged head with pointed ears; the top 6 pt is room for the Bat King's crown. Pivot = head centre."),
              torso=((-14, 14, -2, 38), "ellipse", "Round furry body. Pivot = hips (the body sits 2 pt above it)."),
              arm_weapon=((-15, 9, -44, 0), "wing", "WING, not an arm: it flaps. Pivot = the shoulder joint, top. Draw it spread and hanging."),
              arm_off=((-15, 9, -44, 0), "wing", "Second wing (the far one)."),
              leg_back=((-2.5, 2.5, -14, 0), "arm", "Tiny claw leg. Pivot = hip."),
              leg_front=((-2.5, 2.5, -14, 0), "arm", "Same."))),
}

def layout(rig):
    cells, x, y, rowh = {}, M, M, 0
    for name, (bb, shape, note) in rig["parts"].items():
        w, h = round((bb[1] - bb[0]) * S) + 2 * PAD, round((bb[3] - bb[2]) * S) + 2 * PAD
        if x + w > W - M: x, y, rowh = M, y + rowh + 80, 0
        cells[name] = dict(x=x, y=y, w=w, h=h, pivot=[round(-bb[0] * S) + PAD, round(bb[3] * S) + PAD], art=[round((bb[1] - bb[0]) * S), round((bb[3] - bb[2]) * S)])
        x += w + M; rowh = max(rowh, h)
    return cells

def draw(rig, cells, bg):
    im = Image.new("RGBA", (W, H), bg); d = ImageDraw.Draw(im)
    for name, c in cells.items():
        bb, shape, note = rig["parts"][name]
        x, y, w, h = c["x"], c["y"], c["w"], c["h"]; ax, ay, aw, ah = x + PAD, y + PAD, c["art"][0], c["art"][1]
        d.rectangle([x, y, x + w, y + h], outline=GREY, width=3)
        d.rectangle([ax, ay, ax + aw, ay + ah], outline=(190, 215, 255, 255), width=2)                        # art bounds
        if shape in ("circle", "ellipse"):
            r = min(aw, ah) if shape == "circle" else None
            if shape == "circle": cx, cy = x + c["pivot"][0], y + c["pivot"][1]; rr = (bb[1] - bb[0] if name != "head" else min(abs(bb[0]), bb[1])*2) * S / 2; rr = {"necromancer": 19, "forge_king": 16, "bat": 13}[rig["key"]] * S; d.ellipse([cx - rr, cy - rr, cx + rr, cy + rr], outline=BLUE, width=3)
            else: d.ellipse([ax, ay, ax + aw, ay + ah], outline=BLUE, width=3)
        elif shape == "trap": d.polygon([(ax + aw * 0.14, ay), (ax + aw * 0.86, ay), (ax + aw, ay + ah), (ax, ay + ah)], outline=BLUE, width=3)
        elif shape == "rect": d.rounded_rectangle([ax, ay, ax + aw, ay + ah], radius=60, outline=BLUE, width=3)
        elif shape == "arm": d.rounded_rectangle([ax, ay, ax + aw, ay + ah], radius=aw // 2, outline=BLUE, width=3)
        elif shape == "wing":
            px, py = x + c["pivot"][0], y + c["pivot"][1]
            pts = [(0, 0), (-15, -12), (-11, -20), (-15, -34), (-6, -27), (-2, -44), (5, -26), (9, -10)]
            d.polygon([(px + a * S, py - b * S) for a, b in pts], outline=BLUE, width=3)
        px, py = x + c["pivot"][0], y + c["pivot"][1]
        d.line([px - 26, py, px + 26, py], fill=RED, width=4); d.line([px, py - 26, px, py + 26], fill=RED, width=4); d.ellipse([px - 7, py - 7, px + 7, py + 7], outline=RED, width=3)
        for i, ln in enumerate(textwrap.wrap(f"{name.upper()}  {c['art'][0]}x{c['art'][1]}.  {note}", max(14, w // 9))): d.text((x + 4, y + h + 6 + i * 19), ln, fill=TXT, font=font(15))
    # assembled reference
    s, ox, oy = 0.55, 1560, 1440
    P = lambda gx, gy: (ox + gx * S * s, oy - gy * S * s)
    d.line([ox - 380, oy, ox + 380, oy], fill=(120, 120, 120, 255), width=2)
    base = rig["restY"]
    def box(name, jx, jy, k=1):
        bb = rig["parts"][name][0]; d.rectangle([*P(jx + bb[0] * k, jy + bb[3] * k), *P(jx + bb[1] * k, jy + bb[2] * k)], outline=BLUE, width=2)
        cx, cy = P(jx, jy); d.ellipse([cx - 6, cy - 6, cx + 6, cy + 6], outline=RED, width=3)
    box("leg_back", rig["legX"][0], base); box("leg_front", rig["legX"][1], base); box("torso", 0, base)
    box("arm_off", rig["shoulders"][1][0], base + rig["shoulders"][1][1], 0.88); box("arm_weapon", rig["shoulders"][0][0], base + rig["shoulders"][0][1]); box("head", rig["headPivot"][0], base + rig["headPivot"][1])
    d.text((ox - 380, oy + 8), "ASSEMBLED (reduced): part bounds on the rig. Red = joints.", fill=TXT, font=font(15))
    d.text((M, H - 50), "Draw each part INSIDE its cell, facing right, on a transparent layer. Keep the red pivot on the joint. Hide this layer before exporting.", fill=TXT, font=font(17))
    d.text((M, H - 80), rig["title"], fill=(60, 60, 60, 255), font=font(20))
    return im

for key, rig in RIGS.items():
    rig["key"] = key; cells = layout(rig)
    draw(rig, cells, (0, 0, 0, 0)).save(f"templates/{key}_guides.png")
    draw(rig, cells, (255, 255, 255, 255)).convert("RGB").save(f"templates/{key}_sheet.png")
    json.dump(dict(rig=key, scale_pt_per_px=0.128, padding=PAD, canvas=[W, H], in_game_scale=rig["scale"],
                   layout=dict(restY=rig["restY"], legX=rig["legX"], shoulders=rig["shoulders"], headPivot=rig["headPivot"], armLength=rig["armLength"]), cells=cells),
              open(f"templates/{key}_spec.json", "w"), indent=2)
    print(key, {n: (c["w"], c["h"]) for n, c in cells.items()})
