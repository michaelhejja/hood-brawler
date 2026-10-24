"""Cuts a full-canvas export (transparent PNG, drawn on a template) into one file per cell.
Characters: python3 slice_sheet.py my_character.png cloak            ->  ../Brawler/Sprites/cloak_head.png, cloak_torso.png, ...
Others:     python3 slice_sheet.py demon.png demon templates/demon_spec.json
Weapons:    python3 slice_sheet.py weapons.png weapon templates/weapon_spec.json  (or just run import_weapons.sh)
A spec with "meta": true (weapons) also records each drawing's grip and extents in <prefix>_meta.json, which the game places its overlays from."""
import json, os, sys
from PIL import Image
PPP = 0.128                                                 # game points per template pixel
sheet_path, prefix = sys.argv[1], sys.argv[2]
here = os.path.dirname(os.path.abspath(__file__))
spec = json.load(open(sys.argv[3] if len(sys.argv) > 3 else os.path.join(here, "template_spec.json")))      # optional 3rd arg: another spec (e.g. templates/demon_spec.json)
im = Image.open(sheet_path).convert("RGBA")
canvas = tuple(spec.get("canvas", [2048, 1536]))            # weapon sheets are bigger than character sheets
assert im.size == canvas, f"expected {canvas[0]}x{canvas[1]}, got {im.size}"
out = os.path.join(here, "..", "Brawler", "Sprites"); os.makedirs(out, exist_ok=True)
metafile = os.path.join(out, f"{prefix}_meta.json")
meta = json.load(open(metafile)) if spec.get("meta") and os.path.exists(metafile) else {}      # keeps weapons from earlier imports
for name, c in spec["cells"].items():
    part = im.crop((c["x"], c["y"], c["x"] + c["w"], c["y"] + c["h"]))
    box = part.getchannel("A").point(lambda a: 255 if a > 16 else 0).getbbox()
    if box is None: print("skipped (empty):", name); continue
    part.save(os.path.join(out, f"{prefix}_{name}.png")); print("wrote", f"{prefix}_{name}.png")
    l, t, r, b = box
    if l == 0 or t == 0 or r == c["w"] or b == c["h"]: print(f"  warning: {name} touches the edge of its cell, so it may be cut off")
    if spec.get("meta"):
        px, py = c["pivot"]                                 # [grip x, grip y, top, bottom, left, right]: extents in points from the grip, y up
        meta[name] = [px, py, round((py - t) * PPP, 1), round((py - b) * PPP, 1), round((l - px) * PPP, 1), round((r - px) * PPP, 1)]
if spec.get("meta"): json.dump(meta, open(metafile, "w"), indent=1)
