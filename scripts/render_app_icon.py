#!/usr/bin/env python3
"""Render docs/brand/app-icon.svg into the 1024 icons (RGB, no alpha): AppIcon (Prod) and the
badged AppIcon-Dev / AppIcon-Staging variants. Needs rsvg-convert + Pillow."""
import subprocess, tempfile
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "docs/brand/app-icon.svg"
ASSETS = ROOT / "App/Resources/Assets.xcassets"
# icon set -> (ribbon text, ribbon colour); Prod has no ribbon.
VARIANTS = {"AppIcon": None, "AppIcon-Staging": ("STG", (124, 58, 237)), "AppIcon-Dev": ("DEV", (234, 88, 12))}

with tempfile.TemporaryDirectory() as tmp:
    png = Path(tmp) / "icon.png"
    subprocess.run(["rsvg-convert", "-w", "1024", "-h", "1024", "-o", str(png), str(SRC)], check=True)
    rgba = Image.open(png).convert("RGBA")

# ASC rejects icons with an alpha channel: flatten onto white.
base = Image.new("RGB", rgba.size, (255, 255, 255))
base.paste(rgba, mask=rgba.getchannel("A"))

for name, ribbon in VARIANTS.items():
    icon = base.copy()
    if ribbon:
        text, colour = ribbon
        draw = ImageDraw.Draw(icon)
        # Bottom band stays inside the iOS corner mask and reads at home-screen size.
        draw.rectangle([0, 780, 1024, 1024], fill=colour)
        draw.text((512, 902), text, fill="white", anchor="mm", font=ImageFont.load_default(size=170))
    out = ASSETS / f"{name}.appiconset/AppIcon-1024.png"
    icon.save(out)
    check = Image.open(out)
    assert check.size == (1024, 1024) and check.mode == "RGB", (name, check.size, check.mode)
    print(f"Rendered {out.relative_to(ROOT)}")
