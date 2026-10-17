"""Cuts a full-canvas export (2048x1536, transparent PNG, drawn on the template) into the six part files.
Usage: python3 slice_sheet.py my_character.png cloak   ->  ../Brawler/Sprites/cloak_head.png, cloak_torso.png, ..."""
import json, os, sys
from PIL import Image
sheet_path, prefix = sys.argv[1], sys.argv[2]
spec = json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "template_spec.json")))
im = Image.open(sheet_path).convert("RGBA")
assert im.size == (2048, 1536), f"expected 2048x1536, got {im.size}"
out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Brawler", "Sprites"); os.makedirs(out, exist_ok=True)
for name, c in spec["cells"].items():
    part = im.crop((c["x"], c["y"], c["x"] + c["w"], c["y"] + c["h"]))
    if part.getchannel("A").getbbox() is None: print("skipped (empty):", name); continue
    part.save(os.path.join(out, f"{prefix}_{name}.png")); print("wrote", f"{prefix}_{name}.png")
