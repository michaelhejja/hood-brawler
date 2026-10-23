"""Builds the Demon drawing template: the shared humanoid cells plus two wing cells.
Writes templates/demon_sheet.png (white bg), templates/demon_guides.png (transparent), templates/demon_spec.json.
Slice a finished sheet with: python3 slice_sheet.py demon.png demon templates/demon_spec.json"""
import json
from PIL import Image, ImageDraw, ImageFont
W, H, PAD = 2048, 1536, 30
spec = json.load(open("template_spec.json"))
cells = spec["cells"]
# wings: 640x760 cells in the free middle/lower area. Pivot = where the wing joins the back (inner top).
cells["wing_back"]  = dict(x=620,  y=700, w=640, h=760, pivot=[560, 150], art=[580, 700])
cells["wing_front"] = dict(x=1300, y=700, w=640, h=760, pivot=[560, 150], art=[580, 700])
notes = {"head": "HEAD - horns welcome, they extend past the circle", "torso": "TORSO", "arm_weapon": "ARM (fire hand)", "arm_off": "OFF ARM",
         "leg_back": "BACK LEG", "leg_front": "FRONT LEG", "wing_back": "WING BACK - darker, drawn spread, tip pointing up-left. Red = where it joins the back",
         "wing_front": "WING FRONT - same wing, a little brighter"}
def draw(bg):
    im = Image.new("RGBA", (W, H), bg); d = ImageDraw.Draw(im)
    f = ImageFont.truetype("/System/Library/Fonts/Menlo.ttc", 16)
    for n, c in cells.items():
        x, y, w, h = c["x"], c["y"], c["w"], c["h"]
        d.rectangle([x, y, x + w, y + h], outline=(150, 150, 150, 255), width=3)
        px, py = x + c["pivot"][0], y + c["pivot"][1]
        d.line([px - 26, py, px + 26, py], fill=(255, 0, 0, 255), width=4); d.line([px, py - 26, px, py + 26], fill=(255, 0, 0, 255), width=4)
        d.text((x + 4, y + h + 6), notes[n], fill=(90, 90, 90, 255), font=f)
    d.text((40, H - 50), "Draw each part INSIDE its cell, facing right, on a transparent layer. Hide this layer before exporting.", fill=(90, 90, 90, 255), font=f)
    return im
draw((255, 255, 255, 255)).convert("RGB").save("templates/demon_sheet.png"); draw((0, 0, 0, 0)).save("templates/demon_guides.png")
json.dump(dict(spec, rig="demon", cells=cells), open("templates/demon_spec.json", "w"), indent=2)
print("ok", list(cells))
