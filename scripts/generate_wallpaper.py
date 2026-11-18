#!/usr/bin/env python3
"""
generate_wallpaper.py -- Generate gradient/pattern wallpaper PNGs at specified
resolutions. Useful for app preview backgrounds, social media thumbnails, and
store listing promotional images.

Usage:
  # Single wallpaper from named gradient
  python3 generate_wallpaper.py \
    --gradient "purple-night" \
    --sizes 1290x2796,1320x2868 \
    --output-dir assets/wallpapers/

  # Custom gradient
  python3 generate_wallpaper.py \
    --gradient-custom "#1a0033,#330066,#000033" \
    --sizes 1920x1080 \
    --output wallpaper.png

  # With text overlay (for thumbnail/social media)
  python3 generate_wallpaper.py \
    --gradient "sunset-fire" \
    --sizes 1280x720 \
    --title "MyApp" \
    --subtitle "Now available" \
    --output thumbnail.png

Requires: Pillow (pip3 install Pillow)
"""
import argparse
import os
import sys
from pathlib import Path

# Import shared gradient definitions from compose_screenshot
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, SCRIPT_DIR)

try:
    from compose_screenshot import GRADIENTS, make_gradient, add_radial_glow, draw_text_block, get_font
except ImportError:
    try:
        from PIL import Image, ImageDraw, ImageFont
        GRADIENTS = {
            "purple-night": [(30, 15, 60), (45, 20, 80), (20, 10, 40)],
            "teal-ocean": [(10, 40, 60), (15, 60, 80), (5, 25, 45)],
            "deep-space": [(5, 5, 20), (10, 10, 35), (3, 3, 12)],
        }

        def make_gradient(width, height, colors, direction="vertical"):
            if len(colors) < 2:
                colors = [colors[0], colors[0]]
            gradient = Image.new("RGB", (1, height))
            grad_px = gradient.load()
            for y in range(height):
                t = y / max(height - 1, 1)
                if len(colors) >= 3 and t > 0.5:
                    t2 = (t - 0.5) * 2
                    r = int(colors[1][0] * (1 - t2) + colors[2][0] * t2)
                    g = int(colors[1][1] * (1 - t2) + colors[2][1] * t2)
                    b = int(colors[1][2] * (1 - t2) + colors[2][2] * t2)
                else:
                    if len(colors) >= 3:
                        t = t * 2
                    r = int(colors[0][0] * (1 - t) + colors[1][0] * t)
                    g = int(colors[0][1] * (1 - t) + colors[1][1] * t)
                    b = int(colors[0][2] * (1 - t) + colors[1][2] * t)
                grad_px[0, y] = (r, g, b)
            return gradient.resize((width, height))

        def add_radial_glow(img, center, radius, color, intensity=0.15):
            return img

        def draw_text_block(img, title, subtitle, size_key, text_color=(255, 255, 255)):
            return img

        def get_font(size, bold=True):
            return ImageFont.load_default()
    except ImportError:
        print("ERROR: Pillow is required. Install: pip3 install Pillow", file=sys.stderr)
        sys.exit(1)

try:
    from PIL import Image, ImageDraw, ImageFont, ImageFilter
except ImportError:
    print("ERROR: Pillow is required. Install: pip3 install Pillow", file=sys.stderr)
    sys.exit(1)


# Common wallpaper / thumbnail resolutions
COMMON_SIZES = {
    # iOS device wallpapers (portrait)
    "iphone-17-pro":    "1290x2796",
    "iphone-16-plus":   "1320x2868",
    "iphone-15-pro":    "1179x2556",
    "iphone-13":        "1170x2532",
    "ipad-pro-13":      "1024x1024",

    # Social media / thumbnails (landscape)
    "youtube-thumb":    "1280x720",
    "twitter-card":     "1200x675",
    "og-image":         "1200x630",
    "app-icon-bg":      "1024x1024",

    # App Store preview / promotional
    "asc-preview-69":   "1290x2796",
    "asc-preview-67":   "1290x2796",
    "asc-preview-55":   "1242x2208",
}


def parse_size(size_str: str) -> tuple:
    """Parse 'WxH' or 'WxH' string into (width, height) tuple."""
    parts = size_str.lower().replace("x", "x").split("x")
    if len(parts) == 2:
        return (int(parts[0]), int(parts[1]))
    raise ValueError(f"Invalid size format: {size_str}. Expected WxH (e.g., 1290x2796)")


def parse_sizes(sizes_str: str) -> list:
    """Parse comma-separated sizes string into list of (w, h) tuples."""
    sizes = []
    for s in sizes_str.split(","):
        s = s.strip()
        if not s:
            continue
        if s in COMMON_SIZES:
            sizes.append(parse_size(COMMON_SIZES[s]))
        else:
            sizes.append(parse_size(s))
    return sizes


def generate_wallpaper(
    gradient_name: str = "purple-night",
    gradient_custom: str = None,
    width: int = 1290,
    height: int = 2796,
    title: str = "",
    subtitle: str = "",
    glow: bool = True,
    pattern: str = None,
) -> Image.Image:
    """Generate a wallpaper/thumbnail image."""

    # Parse gradient
    if gradient_custom:
        hex_colors = gradient_custom.split(",")
        colors = []
        for h in hex_colors:
            h = h.strip().lstrip("#")
            r = int(h[0:2], 16)
            g = int(h[2:4], 16)
            b = int(h[4:6], 16)
            colors.append((r, g, b))
    else:
        colors = GRADIENTS.get(gradient_name, GRADIENTS["purple-night"])

    # Create gradient background
    img = make_gradient(width, height, colors, direction="diagonal")

    # Add radial glow
    if glow:
        glow_color = (
            min(255, colors[0][0] + 40),
            min(255, colors[0][1] + 40),
            min(255, colors[0][2] + 40),
        )
        img = add_radial_glow(img, (width // 2, int(height * 0.5)), int(width * 0.5),
                              glow_color, intensity=0.08)

    # Add subtle noise texture for depth (anti-flat)
    if pattern == "noise":
        import random
        noise = Image.new("L", (width, height), 128)
        noise_px = noise.load()
        for y in range(0, height, 2):
            for x in range(0, width, 2):
                noise_px[x, y] = random.randint(120, 135)
        noise = noise.filter(ImageFilter.GaussianBlur(radius=1))
        noise = noise.resize((width, height))
        img = Image.composite(
            Image.new("RGB", img.size, (255, 255, 255)),
            img,
            noise
        )

    # Add text overlay
    if title:
        avg_brightness = sum(colors[0]) / 3
        text_color = (30, 30, 35) if avg_brightness > 128 else (255, 255, 255)

        # Use a reasonable size key for text sizing
        size_key = "6.9" if height > 2000 else "6.5" if height > 1500 else "5.5"
        img = img.convert("RGB")
        img = draw_text_block(img, title, subtitle, size_key, text_color)

    # Ensure RGB output
    img = img.convert("RGB")
    return img


def main():
    parser = argparse.ArgumentParser(
        description="Generate gradient wallpaper/thumbnail PNGs at specified resolutions."
    )
    parser.add_argument("--gradient", "-g", default="purple-night", help="Named gradient preset")
    parser.add_argument("--gradient-custom", help="Custom gradient: '#top,#mid,#bottom' hex colors")
    parser.add_argument("--sizes", "-s", default="1290x2796",
                        help="Comma-separated sizes (WxH) or named presets")
    parser.add_argument("--output-dir", "-d", default=".", help="Output directory")
    parser.add_argument("--output", "-o", help="Single output path (overrides --output-dir)")
    parser.add_argument("--title", "-t", default="", help="Title text overlay")
    parser.add_argument("--subtitle", "-u", default="", help="Subtitle text overlay")
    parser.add_argument("--no-glow", action="store_true", help="Disable radial glow")
    parser.add_argument("--pattern", choices=["noise"], help="Add texture pattern")

    args = parser.parse_args()

    sizes = parse_sizes(args.sizes)
    results = []

    for i, (w, h) in enumerate(sizes):
        img = generate_wallpaper(
            gradient_name=args.gradient,
            gradient_custom=args.gradient_custom,
            width=w, height=h,
            title=args.title,
            subtitle=args.subtitle,
            glow=not args.no_glow,
            pattern=args.pattern,
        )

        if args.output and len(sizes) == 1:
            out_path = args.output
        else:
            os.makedirs(args.output_dir, exist_ok=True)
            out_path = os.path.join(args.output_dir, f"wallpaper-{w}x{h}.png")

        img.save(out_path, "PNG")
        print(f"Generated: {out_path} ({w}x{h})")
        results.append(out_path)

    print(f"\nDone: {len(results)} wallpaper(s) generated")


if __name__ == "__main__":
    main()
