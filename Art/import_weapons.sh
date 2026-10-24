#!/bin/sh
# Imports a finished weapon sheet: slices it into Brawler/Sprites and regenerates the Xcode project.
# Usage: Art/import_weapons.sh path/to/weapons.png      (a 2560x1640 transparent PNG drawn on Art/templates/weapon_guides.png)
set -e
[ -n "$1" ] || { echo "usage: Art/import_weapons.sh weapons.png"; exit 1; }
cd "$(dirname "$0")/.."
python3 Art/slice_sheet.py "$1" weapon Art/templates/weapon_spec.json
xcodegen generate
echo "Done. Weapons you left empty keep their code-drawn art."
