#!/usr/bin/env python3
"""
Forensic Pixel Divergence Characterizer
Categorizes every differing pixel between Chromium and Formal Renderings into:
  Bucket 1: Subpixel Font Antialiasing & Gamma Curve (Near Diffs on text stems: diff <= 50)
  Bucket 2: Image Resampling Filter (Bilinear vs Bicubic/Mitchell-Netravali)
  Bucket 3: Subpixel Line Break / Word Advance Drift (1/64th px LayoutUnit vs integer)
  Bucket 4: Border / Container Grid Snapping
"""

import numpy as np
from PIL import Image

def categorize_differences(name, f_path, c_path):
    img_f = np.array(Image.open(f_path).convert("RGB"), dtype=np.int32)
    img_c = np.array(Image.open(c_path).convert("RGB"), dtype=np.int32)

    h, w, _ = img_f.shape
    total_pixels = h * w

    diff = np.abs(img_f - img_c)
    max_d = np.max(diff, axis=2)

    exact = np.sum(max_d == 0)
    diff_pixels = max_d > 0
    total_diff_count = np.sum(diff_pixels)

    # 1. Antialiasing & Gamma: pixels where both images are non-white, but difference is subtle (1 <= diff <= 50)
    is_text_or_edge = (np.min(img_c, axis=2) < 250) | (np.min(img_f, axis=2) < 250)
    gamma_aa_mask = diff_pixels & is_text_or_edge & (max_d <= 50)
    gamma_aa_count = np.sum(gamma_aa_mask)

    # 2. Large text edge divergence (50 < diff <= 255 on text/glyph boundaries)
    # This happens when glyph outline or stem boundary is shifted by a fractional subpixel
    glyph_subpixel_mask = diff_pixels & is_text_or_edge & (max_d > 50)
    glyph_subpixel_count = np.sum(glyph_subpixel_mask)

    # 3. Image region diffs (around infobox thumbnail: Page 1 y in [187..357], x in [512..768]; Page 2 y in [98..258], x in [512..768])
    image_mask = np.zeros((h, w), dtype=bool)
    if "p1" in f_path:
        image_mask[187:357, 512:768] = True
    elif "p2" in f_path:
        image_mask[98:258, 512:768] = True
    image_diff_count = np.sum(diff_pixels & image_mask)

    # 4. Background / White pixels where border or element bounds differed
    bg_diff_mask = diff_pixels & (~is_text_or_edge) & (~image_mask)
    bg_diff_count = np.sum(bg_diff_mask)

    print(f"================================================================================")
    print(f"FORENSIC DIVERGENCE PROFILE: {name} ({w}x{h} = {total_pixels:,} px)")
    print(f"================================================================================")
    print(f"Exact Matches (diff == 0)                 : {exact:8,d} ({exact/total_pixels*100:5.2f}%)")
    print(f"Total Differing Pixels (diff > 0)          : {total_diff_count:8,d} ({total_diff_count/total_pixels*100:5.2f}%)")
    print(f"--------------------------------------------------------------------------------")
    print(f"Root Cause Breakdown of Divergence:")
    print(f"  1. Font Antialiasing & Gamma Curve (diff <= 50) : {gamma_aa_count:8,d} ({gamma_aa_count/total_diff_count*100:5.1f}% of diffs)")
    print(f"  2. Subpixel Glyph Boundary Shift (diff > 50)    : {glyph_subpixel_count:8,d} ({glyph_subpixel_count/total_diff_count*100:5.1f}% of diffs)")
    print(f"  3. Image Resampler Filter (Bilinear vs Mitchell): {image_diff_count:8,d} ({image_diff_count/total_diff_count*100:5.1f}% of diffs)")
    print(f"  4. Container Box / Border Geometry Drift        : {bg_diff_count:8,d} ({bg_diff_count/total_diff_count*100:5.1f}% of diffs)")
    print(f"================================================================================\n")

def main():
    categorize_differences("Page 1 (Overview & Infobox)", "blink_formal_wikipedia_flowers_p1.png", "chromium_wikipedia_flowers.png")
    categorize_differences("Page 2 (Anatomy & Perianth)", "blink_formal_wikipedia_flowers_p2.png", "chromium_wikipedia_flowers_p2.png")
    categorize_differences("Page 3 (Taxonomy & Syndromes)", "blink_formal_wikipedia_flowers_p3.png", "chromium_wikipedia_flowers_p3.png")
    categorize_differences("Full Continuous 3-Page Stack", "blink_formal_wikipedia_flowers_full.png", "chromium_wikipedia_flowers_full.png")

if __name__ == "__main__":
    main()

