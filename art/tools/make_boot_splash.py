"""Compose the boot splash from the menu key art and the real wordmark.

    D:/Programas/comfy-venv/Scripts/python.exe art/tools/make_boot_splash.py [--check]

No generation: the splash is the main menu's backdrop
(do-not-drop/assets/ui/backgrounds/tx_ui_menu_background_1920.png, ComfyUI
seed 11) with the S-306 wordmark
(do-not-drop/assets/ui/logo/tx_ui_logo_wordmark_2048.png) pasted exactly where
the menu draws it, so going from splash to menu does not make the logo jump.

The menu (scripts/ui/main_menu.gd `_build_brand`, and loading_screen.gd
`_build_logo`) works on a 1280x720 base (stretch `canvas_items`, aspect
`expand`) and puts the whole 2048x1024 texture in a 420x210 TextureRect at
(64, 48), STRETCH_KEEP_ASPECT_CENTERED. At 1920x1080 that is x1.5: the whole
texture scaled to 630x315 (LANCZOS) and alpha-composited at (96, 72). The menu
has no dark tint over the art, so neither does the splash; no baked subtitle
either (the menu shows translated tags under the logo).

Output (same path and name project.godot's boot_splash/image points to):
    do-not-drop/assets/ui/backgrounds/tx_ui_boot_splash_1920.png  (1920x1080 RGB)

--check rebuilds in memory and exits 1 if the file on disk differs.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from PIL import Image, ImageChops

ROOT = Path(__file__).resolve().parents[2]
UI = ROOT / "do-not-drop" / "assets" / "ui"
BACKGROUND = UI / "backgrounds" / "tx_ui_menu_background_1920.png"
WORDMARK = UI / "logo" / "tx_ui_logo_wordmark_2048.png"
OUTPUT = UI / "backgrounds" / "tx_ui_boot_splash_1920.png"

SIZE = (1920, 1080)
MENU_BASE = (1280, 720)
LOGO_POS = (64, 48)  # main_menu.gd brand.position, menu base units
LOGO_BOX = (420, 210)  # TextureRect custom_minimum_size, menu base units


def compose() -> Image.Image:
    scale = SIZE[1] / MENU_BASE[1]  # 1.5; same as SIZE[0] / MENU_BASE[0]
    bg = Image.open(BACKGROUND).convert("RGB")
    if bg.size != SIZE:
        # Cover, like the menu's STRETCH_KEEP_ASPECT_COVERED.
        k = max(SIZE[0] / bg.width, SIZE[1] / bg.height)
        bg = bg.resize((round(bg.width * k), round(bg.height * k)), Image.LANCZOS)
        left, top = (bg.width - SIZE[0]) // 2, (bg.height - SIZE[1]) // 2
        bg = bg.crop((left, top, left + SIZE[0], top + SIZE[1]))
    logo = Image.open(WORDMARK).convert("RGBA")
    box_w, box_h = LOGO_BOX[0] * scale, LOGO_BOX[1] * scale
    # KEEP_ASPECT_CENTERED: fit the whole texture inside the box, centred.
    k = min(box_w / logo.width, box_h / logo.height)
    w, h = round(logo.width * k), round(logo.height * k)
    logo = logo.resize((w, h), Image.LANCZOS)
    x = round(LOGO_POS[0] * scale + (box_w - w) / 2)
    y = round(LOGO_POS[1] * scale + (box_h - h) / 2)
    canvas = bg.convert("RGBA")
    canvas.alpha_composite(logo, (x, y))
    return canvas.convert("RGB")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--check", action="store_true",
                        help="exit 1 if the splash on disk is out of date")
    args = parser.parse_args()
    splash = compose()
    if args.check:
        if not OUTPUT.exists():
            print(f"missing: {OUTPUT.relative_to(ROOT)}")
            return 1
        current = Image.open(OUTPUT).convert("RGB")
        if current.size != splash.size or ImageChops.difference(current, splash).getbbox():
            print(f"out of date: {OUTPUT.relative_to(ROOT)} (run without --check)")
            return 1
        print(f"ok: {OUTPUT.relative_to(ROOT)}")
        return 0
    splash.save(OUTPUT, optimize=True)
    print(f"wrote {OUTPUT.relative_to(ROOT)} {splash.size[0]}x{splash.size[1]}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
