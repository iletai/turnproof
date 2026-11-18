#!/usr/bin/env python3
"""
compose_screenshot.py -- Compose raw iOS screenshots into App Store-ready
marketing images with device frames, gradient backgrounds, and text overlays.

Usage:
  # Single screenshot
  python3 compose_screenshot.py \
    --screenshot raw-home.png \
    --title "Transform Your Sleep" \
    --subtitle "AI-powered sleep experiments" \
    --gradient "purple-night" \
    --device "iphone-17-pro" \
    --output 01-home.png

  # Batch from manifest
  python3 compose_screenshot.py \
    --manifest screenshots.json \
    --output-dir fastlane/screenshots/en-US/

  # Custom gradient (hex colors)
  python3 compose_screenshot.py \
    --screenshot raw.png \
    --gradient-custom "#1a1a2e,#16213e,#0f3460" \
    --title "Hello" \
    --output out.png

Requires: Pillow (pip3 install Pillow)
"""
import argparse
import json
import math
import os
import sys
from pathlib import Path

try:
    from PIL import Image, ImageDraw, ImageFont, ImageFilter
except ImportError:
    print("ERROR: Pillow is required. Install: pip3 install Pillow", file=sys.stderr)
    sys.exit(1)

# ---------------------------------------------------------------------------
# ASC screenshot sizes (width x height)
# ---------------------------------------------------------------------------
ASC_SIZES = {
    "6.9":  (1290, 2796),
    "6.9-alt": (1320, 2868),
    "6.7":  (1290, 2796),
    "6.5":  (1284, 2778),
    "5.5":  (1242, 2208),
}

# Default to 6.9" (iPhone 17 Pro / 16 Pro Max)
DEFAULT_SIZE_KEY = "6.9"

# ---------------------------------------------------------------------------
# Named gradient presets
# Format: (top_color, mid_color, bottom_color) as RGB tuples
# ---------------------------------------------------------------------------
GRADIENTS = {
    # Dark, premium feel
    "purple-night":    [(30, 15, 60), (45, 20, 80), (20, 10, 40)],
    "teal-ocean":      [(10, 40, 60), (15, 60, 80), (5, 25, 45)],
    "midight-blue":    [(10, 20, 50), (15, 30, 70), (5, 10, 30)],
    "rose-gold":       [(60, 20, 40), (80, 30, 50), (40, 15, 30)],
    "emerald-forest":  [(10, 40, 30), (15, 55, 40), (5, 25, 20)],
    "sunset-fire":     [(50, 20, 10), (70, 35, 15), (40, 15, 5)],
    "deep-space":      [(5, 5, 20), (10, 10, 35), (3, 3, 12)],
    "aurora":          [(15, 25, 60), (30, 15, 70), (10, 20, 40)],

    # Light, clean feel
    "morning-sky":     [(135, 180, 220), (180, 200, 230), (200, 215, 235)],
    "soft-lavender":   [(180, 160, 200), (200, 180, 220), (220, 200, 230)],
    "warm-sand":       [(180, 160, 130), (200, 180, 150), (210, 195, 170)],
    "mint-fresh":      [(140, 200, 180), (170, 220, 200), (190, 230, 215)],

    # Vibrant, energetic
    "electric-purple": [(65, 20, 110), (105, 40, 160), (45, 12, 80)],
    "coral-burst":     [(185, 80, 65), (205, 105, 80), (150, 55, 50)],
    "cyan-wave":       [(10, 105, 145), (20, 135, 175), (8, 75, 105)],
    "lime-pulse":      [(75, 135, 45), (95, 160, 60), (60, 105, 35)],

    # Neutral, elegant
    "graphite":        [(40, 40, 45), (55, 55, 60), (25, 25, 30)],
    "silver-mist":     [(180, 180, 190), (200, 200, 210), (160, 160, 175)],
    "champagne":       [(180, 160, 120), (195, 175, 140), (165, 145, 110)],

    # Apple-inspired
    "apple-dark":      [(28, 28, 30), (44, 44, 46), (18, 18, 20)],
    "apple-light":     [(242, 242, 247), (229, 229, 234), (255, 255, 255)],
}

# ---------------------------------------------------------------------------
# Device frame dimensions (screen area, not the frame itself)
# These match the screenshot capture sizes for each device
# ---------------------------------------------------------------------------
DEVICE_SCREENS = {
    "iphone-17-pro": {
        "screen_size": (1206, 2622),  # logical screen capture size
        "bezel": 12,
        "corner_radius": 55,
        "dynamic_island": ( 0, 0, 0, 0 ),  # not drawn, implied by screenshot
        "frame_color": (10, 10, 12),
    },
    "iphone-16-plus": {
        "screen_size": (1284, 2778),
        "bezel": 10,
        "corner_radius": 50,
        "dynamic_island": (0, 0, 0, 0),
        "frame_color": (10, 10, 12),
    },
    "iphone-13": {
        "screen_size": (1170, 2532),
        "bezel": 8,
        "corner_radius": 45,
        "dynamic_island": (0, 0, 0, 0),
        "frame_color": (15, 15, 15),
    },
    "none": None,  # no device frame, just text + gradient
}

# ---------------------------------------------------------------------------
# Typography
# ---------------------------------------------------------------------------
TITLE_FONT_SIZES = {
    "6.9":      88,
    "6.9-alt":  88,
    "6.7":      88,
    "6.5":      84,
    "5.5":      72,
}

SUBTITLE_FONT_SIZES = {
    "6.9":      52,
    "6.9-alt":  52,
    "6.7":      52,
    "6.5":      50,
    "5.5":      42,
}


def get_font(size: int, bold: bool = True) -> ImageFont.FreeTypeFont:
    """Try to load SF Pro Display, fall back to Helvetica Neue, then default."""
    font_paths = [
        "/System/Library/Fonts/SFPro-Display-Bold.otf" if bold else "/System/Library/Fonts/SFPro-Display-Regular.otf",
        "/System/Library/Fonts/Helvetica.ttc",
        "/System/Library/Fonts/HelveticaNeue.ttc",
        "/Library/Fonts/Arial.ttf",
    ]
    for path in font_paths:
        if os.path.exists(path):
            try:
                return ImageFont.truetype(path, size)
            except Exception:
                continue
    return ImageFont.load_default()


def make_gradient(width: int, height: int, colors: list, direction: str = "vertical") -> Image.Image:
    """
    Create a gradient image with the given colors.
    Supports 2-3 color stops. Direction: 'vertical', 'horizontal', 'diagonal'.
    """
    if len(colors) < 2:
        colors = [colors[0], colors[0]]

    base = Image.new("RGB", (width, height), colors[0])
    top = Image.new("RGB", (width, height), colors[-1])

    mask = Image.new("L", (width, height))
    mask_px = mask.load()

    for y in range(height):
        for x in range(width):
            if direction == "vertical":
                t = y / max(height - 1, 1)
            elif direction == "horizontal":
                t = x / max(width - 1, 1)
            elif direction == "diagonal":
                t = (x / max(width - 1, 1) + y / max(height - 1, 1)) / 2
            else:
                t = y / max(height - 1, 1)

            # 3-color gradient: interpolate between first-second, then second-third
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

            mask_px[x, y] = int(r * 0 + 255)  # not used this way

    # Use a simpler approach: create gradient via PIL's built-in
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

    gradient = gradient.resize((width, height))
    return gradient


def add_radial_glow(img: Image.Image, center: tuple, radius: int,
                    color: tuple, intensity: float = 0.15) -> Image.Image:
    """Add a subtle radial glow at the given center point."""
    overlay = Image.new("RGBA", img.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)

    steps = 20
    for i in range(steps, 0, -1):
        r = int(radius * i / steps)
        alpha = int(255 * intensity * (1 - i / steps))
        draw.ellipse(
            [center[0] - r, center[1] - r, center[0] + r, center[1] + r],
            fill=(color[0], color[1], color[2], alpha)
        )

    overlay = overlay.filter(ImageFilter.GaussianBlur(radius=radius // 4))
    result = Image.new("RGB", img.size)
    result.paste(img, (0, 0))
    result.paste(overlay, (0, 0), overlay)
    return result


def round_corners(img: Image.Image, radius: int) -> Image.Image:
    """Round the corners of an image."""
    mask = Image.new("L", img.size, 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle([0, 0, img.size[0], img.size[1]], radius=radius, fill=255)
    result = Image.new("RGBA", img.size)
    result.paste(img, (0, 0), mask)
    return result


def draw_device_frame(img: Image.Image, device_config: dict, screenshot: Image.Image,
                      shadow: bool = True) -> Image.Image:
    """
    Place the screenshot inside a device frame on the background image.
    The device frame is drawn programmatically (metallic bezel + rounded corners).
    """
    if device_config is None:
        # No frame, just paste the screenshot centered
        sw, sh = screenshot.size
        bg_w, bg_h = img.size
        x = (bg_w - sw) // 2
        y = (bg_h - sh) // 2
        img.paste(screenshot, (x, y))
        return img

    screen_w, screen_h = device_config["screen_size"]
    bezel = device_config["bezel"]
    corner = device_config["corner_radius"]
    frame_color = device_config["frame_color"]

    # Scale screenshot to fit the device screen area
    screenshot = screenshot.resize((screen_w, screen_h), Image.LANCZOS)

    # Round the screenshot corners
    screenshot = round_corners(screenshot, corner - bezel)

    # Build the device body: metallic bezel (light edge -> dark body)
    frame_w = screen_w + bezel * 2
    frame_h = screen_h + bezel * 2

    # Metallic edge highlight: a thin bright ring around the body
    edge = max(2, bezel // 3)
    edge_light = tuple(min(255, c + 70) for c in frame_color)

    body = Image.new("RGBA", (frame_w, frame_h), frame_color + (255,))
    edge_layer = Image.new("RGBA", (frame_w, frame_h), edge_light + (255,))
    body.paste(edge_layer, (0, 0), edge_layer)
    # Re-paint the inner body over the edge ring to leave only a border
    inner = Image.new("RGBA", (frame_w - edge * 2, frame_h - edge * 2),
                      frame_color + (255,))
    body.paste(inner, (edge, edge))
    body = round_corners(body, corner)

    # Paste screenshot into the frame
    body.paste(screenshot, (bezel, bezel),
               screenshot if screenshot.mode == "RGBA" else None)

    # Scale to fit within the background (leave padding for text)
    bg_w, bg_h = img.size
    max_device_h = int(bg_h * 0.72)  # device takes up 72% of height
    max_device_w = int(bg_w * 0.88)

    scale = min(max_device_h / frame_h, max_device_w / frame_w, 1.0)
    new_w = int(frame_w * scale)
    new_h = int(frame_h * scale)
    body = body.resize((new_w, new_h), Image.LANCZOS)

    # Center horizontally, position in lower portion
    x = (bg_w - new_w) // 2
    y = bg_h - new_h - int(bg_h * 0.04)  # 4% bottom padding
    y = max(y, int(bg_h * 0.28))  # don't overlap title area

    # Soft drop shadow behind the device for depth separation
    if shadow:
        shadow_layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
        shadow_draw = ImageDraw.Draw(shadow_layer)
        offset = int(new_h * 0.02)
        shadow_draw.rounded_rectangle(
            [x, y + offset, x + new_w, y + new_h + offset],
            radius=int(corner * scale),
            fill=(0, 0, 0, 130),
        )
        shadow_layer = shadow_layer.filter(ImageFilter.GaussianBlur(radius=int(new_w * 0.05)))
        img.paste(shadow_layer, (0, 0), shadow_layer)

    img.paste(body, (x, y), body if body.mode == "RGBA" else None)
    return img



def draw_text_block(img: Image.Image, title: str, subtitle: str,
                    size_key: str, text_color: tuple = (255, 255, 255)) -> Image.Image:
    """
    Draw the marketing text block above the device frame.
    Title is bold and large; subtitle is regular and smaller.
    """
    draw = ImageDraw.Draw(img)
    bg_w, bg_h = img.size

    title_size = TITLE_FONT_SIZES.get(size_key, 84)
    subtitle_size = SUBTITLE_FONT_SIZES.get(size_key, 50)

    title_font = get_font(title_size, bold=True)
    subtitle_font = get_font(subtitle_size, bold=False)

    # Calculate text widths for centering
    title_bbox = draw.textbbox((0, 0), title, font=title_font)
    title_w = title_bbox[2] - title_bbox[0]
    title_h = title_bbox[3] - title_bbox[1]

    title_x = (bg_w - title_w) // 2
    title_y = int(bg_h * 0.07)  # 7% from top

    # Draw title with subtle shadow for readability on any gradient
    shadow_offset = 3
    draw.text((title_x + shadow_offset, title_y + shadow_offset), title,
              fill=(0, 0, 0, 128), font=title_font)
    draw.text((title_x, title_y), title, fill=text_color, font=title_font)

    if subtitle:
        sub_bbox = draw.textbbox((0, 0), subtitle, font=subtitle_font)
        sub_w = sub_bbox[2] - sub_bbox[0]
        sub_x = (bg_w - sub_w) // 2
        sub_y = title_y + title_h + int(title_size * 0.25)

        draw.text((sub_x + shadow_offset, sub_y + shadow_offset), subtitle,
                  fill=(0, 0, 0, 128), font=subtitle_font)
        draw.text((sub_x, sub_y), subtitle, fill=text_color, font=subtitle_font)

    return img


def compose_single(
    screenshot_path: str,
    title: str = "",
    subtitle: str = "",
    gradient_name: str = "purple-night",
    gradient_custom: str = None,
    device: str = "iphone-17-pro",
    output_path: str = "output.png",
    size_key: str = DEFAULT_SIZE_KEY,
    text_color: tuple = (255, 255, 255),
    glow: bool = True,
) -> str:
    """Compose a single screenshot into an ASC-ready marketing image."""

    # Determine output size
    out_w, out_h = ASC_SIZES.get(size_key, ASC_SIZES[DEFAULT_SIZE_KEY])

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
    bg = make_gradient(out_w, out_h, colors, direction="diagonal")

    # Add subtle radial glow behind the device area
    if glow:
        glow_color = colors[0]
        # Lighten the glow color
        glow_color = (
            min(255, glow_color[0] + 40),
            min(255, glow_color[1] + 40),
            min(255, glow_color[2] + 40),
        )
        bg = add_radial_glow(bg, (out_w // 2, int(out_h * 0.55)), int(out_w * 0.4),
                             glow_color, intensity=0.08)

    # Load and paste screenshot into device frame
    if screenshot_path and os.path.exists(screenshot_path):
        screenshot = Image.open(screenshot_path).convert("RGBA")
        device_config = DEVICE_SCREENS.get(device, DEVICE_SCREENS["iphone-17-pro"])
        bg = draw_device_frame(bg, device_config, screenshot)
    else:
        # No screenshot provided, just gradient + text (useful for wallpaper)
        pass

    # Draw text overlay
    if title:
        bg = bg.convert("RGB")
        # Determine text color based on gradient brightness
        avg_brightness = sum(colors[0]) / 3
        if avg_brightness > 128:
            text_color = (30, 30, 35)  # dark text on light gradient
        bg = draw_text_block(bg, title, subtitle, size_key, text_color)

    # Ensure RGB output (ASC rejects alpha)
    bg = bg.convert("RGB")
    bg.save(output_path, "PNG")
    print(f"Composed: {output_path} ({out_w}x{out_h})")
    return output_path


def compose_batch(manifest_path: str, output_dir: str, size_key: str = DEFAULT_SIZE_KEY) -> list:
    """Compose multiple screenshots from a JSON manifest."""
    with open(manifest_path, "r", encoding="utf-8") as f:
        items = json.load(f)

    os.makedirs(output_dir, exist_ok=True)
    results = []

    for item in items:
        out_path = os.path.join(output_dir, item.get("filename", "screenshot.png"))
        compose_single(
            screenshot_path=item.get("screenshot", ""),
            title=item.get("title", ""),
            subtitle=item.get("subtitle", ""),
            gradient_name=item.get("gradient", "purple-night"),
            gradient_custom=item.get("gradient_custom"),
            device=item.get("device", "iphone-17-pro"),
            output_path=out_path,
            size_key=item.get("size_key", size_key),
        )
        results.append(out_path)

    return results


def main():
    parser = argparse.ArgumentParser(
        description="Compose App Store screenshots with device frames, gradients, and text overlays."
    )
    parser.add_argument("--screenshot", "-s", help="Path to raw screenshot PNG")
    parser.add_argument("--manifest", "-m", help="Path to JSON manifest for batch mode")
    parser.add_argument("--output", "-o", default="output.png", help="Output file path")
    parser.add_argument("--output-dir", "-d", default=".", help="Output directory (batch mode)")
    parser.add_argument("--title", "-t", default="", help="Marketing title text")
    parser.add_argument("--subtitle", "-u", default="", help="Marketing subtitle text")
    parser.add_argument("--gradient", "-g", default="purple-night", help="Named gradient preset")
    parser.add_argument("--gradient-custom", help="Custom gradient: '#top,#mid,#bottom' hex colors")
    parser.add_argument("--device", default="iphone-17-pro",
                        help="Device frame: iphone-17-pro, iphone-16-plus, iphone-13, none")
    parser.add_argument("--size", default=DEFAULT_SIZE_KEY,
                        help=f"ASC size key: {', '.join(ASC_SIZES.keys())}")
    parser.add_argument("--no-glow", action="store_true", help="Disable radial glow effect")

    args = parser.parse_args()

    if args.manifest:
        results = compose_batch(args.manifest, args.output_dir, args.size)
        print(f"\nBatch complete: {len(results)} screenshots composed")
        for r in results:
            print(f"  -> {r}")
    elif args.screenshot:
        compose_single(
            screenshot_path=args.screenshot,
            title=args.title,
            subtitle=args.subtitle,
            gradient_name=args.gradient,
            gradient_custom=args.gradient_custom,
            device=args.device,
            output_path=args.output,
            size_key=args.size,
            glow=not args.no_glow,
        )
    else:
        parser.print_help()
        print("\nERROR: Either --screenshot or --manifest is required.", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
