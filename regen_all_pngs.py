#!/usr/bin/env python3
"""
regen_all_pngs.py: Re-renders all multi-page formal engine PPMs, converts to PNGs,
generates differential heatmaps against Chromium, and syncs artifacts.
"""

import subprocess
import shutil
import os
from PIL import Image
import compare_pages

def main():
    print("=== Step 1: Compiling Multi-Page Drop-in C99 Engine ===")
    compile_cmd = [
        "clang", "-O3", "-std=c99",
        "render_wikipedia_flowers_multipage.c",
        "blink_image_codec.c",
        "blink_skia_font_engine.c",
        "blink_vertical_flow.c",
        "-framework", "CoreText",
        "-framework", "CoreGraphics",
        "-framework", "CoreFoundation"
    ]
    # Add FreeType flags
    cflags = subprocess.check_output(["pkg-config", "--cflags", "--libs", "freetype2"], text=True).split()
    compile_cmd.extend(cflags)
    compile_cmd.extend(["-o", "render_wikipedia_flowers_multipage"])
    
    subprocess.run(compile_cmd, check=True)
    print("✓ Successfully compiled render_wikipedia_flowers_multipage")

    print("\n=== Step 2: Executing Multi-Page Renderer in Chromium Mode ===")
    subprocess.run(["./render_wikipedia_flowers_multipage", "--mode=chromium"], check=True)
    print("✓ Rendered multi-page PPMs (p1, p2, p3, full)")

    print("\n=== Step 3: Converting PPMs to PNGs ===")
    pages = ["p1", "p2", "p3", "full", ""]
    for p in pages:
        suffix = f"_{p}" if p else ""
        ppm_name = f"blink_formal_wikipedia_flowers{suffix}.ppm"
        png_name = f"blink_formal_wikipedia_flowers{suffix}.png"
        if os.path.exists(ppm_name):
            img = Image.open(ppm_name)
            img.save(png_name)
            print(f"  Converted {ppm_name} -> {png_name} ({img.size[0]}x{img.size[1]})")

    # Also convert interactive runner ppm if present
    if os.path.exists("blink_formal_rendered_page.ppm"):
        img = Image.open("blink_formal_rendered_page.ppm")
        img.save("blink_formal_rendered_page.png")
        print("  Converted blink_formal_rendered_page.ppm -> blink_formal_rendered_page.png")

    print("\n=== Step 4: Regenerating Differential Heatmaps vs Chromium ===")
    pairs = [
        ("blink_formal_wikipedia_flowers_p1.ppm", "chromium_wikipedia_flowers.png", "diff_wikipedia_flowers_p1.png"),
        ("blink_formal_wikipedia_flowers_p2.ppm", "chromium_wikipedia_flowers_p2.png", "diff_wikipedia_flowers_p2.png"),
        ("blink_formal_wikipedia_flowers_p3.ppm", "chromium_wikipedia_flowers_p3.png", "diff_wikipedia_flowers_p3.png"),
        ("blink_formal_wikipedia_flowers_full.ppm", "chromium_wikipedia_flowers_full.png", "diff_wikipedia_flowers_full.png")
    ]
    for formal, chrom, diff in pairs:
        compare_pages.compare_images(formal, chrom, diff)

    # Also update diff_wikipedia_flowers.png (alias for p1)
    shutil.copyfile("diff_wikipedia_flowers_p1.png", "diff_wikipedia_flowers.png")
    print("✓ Copied diff_wikipedia_flowers_p1.png -> diff_wikipedia_flowers.png")

    print("\n=== Step 5: Updating Artifact Directory ===")
    artifact_dir = "/Users/anders/.gemini/antigravity/brain/272518ec-10f8-4697-9cc0-5de480e9211a"
    if os.path.isdir(artifact_dir):
        artifacts_to_copy = [
            "blink_formal_wikipedia_flowers_p1.png",
            "blink_formal_wikipedia_flowers_p2.png",
            "blink_formal_wikipedia_flowers_p3.png",
            "blink_formal_wikipedia_flowers_full.png",
            "blink_formal_wikipedia_flowers.png",
            "diff_wikipedia_flowers_p1.png",
            "diff_wikipedia_flowers_p2.png",
            "diff_wikipedia_flowers_p3.png",
            "diff_wikipedia_flowers_full.png",
            "diff_wikipedia_flowers.png",
            "blink_formal_rendered_page.png"
        ]
        for art in artifacts_to_copy:
            if os.path.exists(art):
                dst = os.path.join(artifact_dir, art)
                shutil.copyfile(art, dst)
                print(f"  Synced {art} -> artifact directory")
    print("\n✓ All PNGs and differential heatmaps regenerated and synchronized successfully!")

if __name__ == "__main__":
    main()

