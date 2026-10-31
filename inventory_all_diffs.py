#!/usr/bin/env python3
"""
inventory_all_diffs.py: MECE partition and mathematical characterization of
every single one of the 137,647 differing pixels across the full 800x1800 canvas.
"""

import numpy as np
from PIL import Image

def main():
    f_img = Image.open("blink_formal_wikipedia_flowers_full.png").convert("RGB")
    c_img = Image.open("chromium_wikipedia_flowers_full.png").convert("RGB")
    
    arr_f = np.array(f_img, dtype=np.int32)
    arr_c = np.array(c_img, dtype=np.int32)
    
    diff = np.abs(arr_f - arr_c)
    max_d = np.max(diff, axis=-1)
    
    diff_mask = max_d > 0
    total_diff_px = np.sum(diff_mask)
    total_canvas_px = arr_f.shape[0] * arr_f.shape[1]
    
    print(f"Total canvas pixels: {total_canvas_px:,}")
    print(f"Total differing pixels: {total_diff_px:,} ({total_diff_px/total_canvas_px*100:.2f}% of canvas)")
    print(f"Total exact match pixels: {total_canvas_px - total_diff_px:,} ({(total_canvas_px - total_diff_px)/total_canvas_px*100:.2f}%)")
    print("=" * 80)
    
    # Define spatial masks for different elements:
    # 1. Image areas:
    # Page 1 thumbnail: y in 180..360, x in 520..760
    # Page 2 diagram:   y in 690..860, x in 512..768
    img_mask = np.zeros_like(diff_mask, dtype=bool)
    img_mask[180:360, 520:760] = True
    img_mask[690:860, 512:768] = True
    
    diff_in_images = diff_mask & img_mask
    diff_outside_images = diff_mask & (~img_mask)
    
    # 2. Text vs Non-text in non-image regions:
    # In non-image regions, white background in Chromium is typically > 240 in all channels,
    # or background gray #F8F9FA is (248, 249, 250).
    # If BOTH formal and chrom are background (> 240 in all channels), it's background.
    # If one of them has dark pixels (< 220), it's text, icons, or borders.
    is_dark_f = np.any(arr_f < 235, axis=-1)
    is_dark_c = np.any(arr_c < 235, axis=-1)
    is_text_or_line = (is_dark_f | is_dark_c) & (~img_mask)
    
    diff_in_text_lines = diff_mask & is_text_or_line
    diff_in_pure_background = diff_mask & (~img_mask) & (~is_text_or_line)
    
    # Subdivide diff_in_text_lines:
    # A. Low-delta text antialiasing (gamma curve falloff): max_d <= 50
    text_gamma_aa = diff_in_text_lines & (max_d <= 50)
    # B. High-delta text phase shift (horizontal / kerning / advance shift): max_d > 50
    text_phase_shift = diff_in_text_lines & (max_d > 50)
    
    # Subdivide image differences:
    # A. Subtle filter resampler diffs: max_d <= 30
    img_subtle = diff_in_images & (max_d <= 30)
    # B. High filter / edge diffs: max_d > 30
    img_edge = diff_in_images & (max_d > 30)
    
    print("MECE CLASSIFICATION OF ALL 137,647 DIFFERING PIXELS:")
    print("-" * 80)
    print(f"1. Font Text Antialiasing & Gamma Curve (Δ <= 50): {np.sum(text_gamma_aa):8,d} px ({np.sum(text_gamma_aa)/total_diff_px*100:5.2f}% of diffs)")
    print(f"2. Subpixel Glyph Advance & Kerning Shift (Δ > 50) : {np.sum(text_phase_shift):8,d} px ({np.sum(text_phase_shift)/total_diff_px*100:5.2f}% of diffs)")
    print(f"3. Image Resampling Filter (Bilinear vs Mitchell) : {np.sum(diff_in_images):8,d} px ({np.sum(diff_in_images)/total_diff_px*100:5.2f}% of diffs)")
    print(f"     - Subtle resampler color variance (Δ <= 30)  : {np.sum(img_subtle):8,d} px ({np.sum(img_subtle)/total_diff_px*100:5.2f}% of diffs)")
    print(f"     - High-frequency edge resampler (Δ > 30)     : {np.sum(img_edge):8,d} px ({np.sum(img_edge)/total_diff_px*100:5.2f}% of diffs)")
    print(f"4. Background & Container Antialiased Seams        : {np.sum(diff_in_pure_background):8,d} px ({np.sum(diff_in_pure_background)/total_diff_px*100:5.2f}% of diffs)")
    print("-" * 80)
    print(f"TOTAL CLASSIFIED                                  : {np.sum(text_gamma_aa) + np.sum(text_phase_shift) + np.sum(diff_in_images) + np.sum(diff_in_pure_background):8,d} px (100.00%)")
    print("=" * 80)
    
    # Detailed inspection of pure background differences
    print("\nDetailed breakdown of Category 4 (Background & Container Seams):")
    bg_max_d = max_d[diff_in_pure_background]
    print(f"  Max delta in background seams: {np.max(bg_max_d) if len(bg_max_d) > 0 else 0}")
    print(f"  Mean delta in background seams: {np.mean(bg_max_d) if len(bg_max_d) > 0 else 0:.2f}")
    print(f"  Count with Δ <= 5: {np.sum(bg_max_d <= 5):,d} ({np.sum(bg_max_d <= 5)/len(bg_max_d)*100:.1f}%)")
    print(f"  Count with 6 <= Δ <= 15: {np.sum((bg_max_d >= 6) & (bg_max_d <= 15)):,d} ({np.sum((bg_max_d >= 6) & (bg_max_d <= 15))/len(bg_max_d)*100:.1f}%)")

if __name__ == "__main__":
    main()

