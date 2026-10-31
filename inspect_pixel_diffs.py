#!/usr/bin/env python3
import numpy as np
from PIL import Image

def analyze_crop(name, img_formal, img_chrom, y0, y1, x0, x1):
    f_crop = img_formal[y0:y1, x0:x1]
    c_crop = img_chrom[y0:y1, x0:x1]
    diff = np.abs(f_crop.astype(np.int32) - c_crop.astype(np.int32))
    max_d = np.max(diff, axis=2)
    far = np.sum(max_d > 15)
    near = np.sum((max_d > 0) & (max_d <= 15))
    exact = np.sum(max_d == 0)
    total = f_crop.shape[0] * f_crop.shape[1]
    print(f"--- Region '{name}' [y: {y0}..{y1}, x: {x0}..{x1}] ---")
    print(f"    Total: {total:5d} | Exact: {exact:5d} ({exact/total*100:5.1f}%) | Near: {near:5d} ({near/total*100:5.1f}%) | Far: {far:5d} ({far/total*100:5.1f}%)")
    # Find row-wise far diffs
    row_far = np.sum(max_d > 15, axis=1)
    bad_rows = [(y0 + r, row_far[r]) for r in range(len(row_far)) if row_far[r] > 10]
    if bad_rows:
        print(f"    Top diff Y-rows: {bad_rows[:6]}")

def main():
    p1_f = np.array(Image.open("blink_formal_wikipedia_flowers_p1.png").convert("RGB"))
    p1_c = np.array(Image.open("chromium_wikipedia_flowers.png").convert("RGB"))

    p2_f = np.array(Image.open("blink_formal_wikipedia_flowers_p2.png").convert("RGB"))
    p2_c = np.array(Image.open("chromium_wikipedia_flowers_p2.png").convert("RGB"))

    p3_f = np.array(Image.open("blink_formal_wikipedia_flowers_p3.png").convert("RGB"))
    p3_c = np.array(Image.open("chromium_wikipedia_flowers_p3.png").convert("RGB"))

    print("=== PAGE 1 ANALYSIS ===")
    analyze_crop("P1 Hatnote", p1_f, p1_c, 120, 150, 25, 600)
    analyze_crop("P1 Lead Paragraph", p1_f, p1_c, 150, 230, 25, 485)
    analyze_crop("P1 Infobox Title & Header", p1_f, p1_c, 150, 185, 505, 775)
    analyze_crop("P1 Table Rows", p1_f, p1_c, 376, 474, 25, 485)

    print("\n=== PAGE 2 ANALYSIS ===")
    analyze_crop("P2 Heading 1.1", p2_f, p2_c, 70, 95, 25, 485)
    analyze_crop("P2 Paragraph 1 (Perianth)", p2_f, p2_c, 90, 175, 25, 485)
    analyze_crop("P2 Diagram Caption", p2_f, p2_c, 260, 280, 512, 768)
    analyze_crop("P2 Heading 1.2 & Paragraph 2", p2_f, p2_c, 280, 375, 25, 485)
    analyze_crop("P2 Infobox Metadata Rows", p2_f, p2_c, 290, 375, 512, 768)
    analyze_crop("P2 Footer Navigation", p2_f, p2_c, 470, 510, 25, 775)

    print("\n=== PAGE 3 ANALYSIS ===")
    analyze_crop("P3 Heading 2 & Paragraph 1", p3_f, p3_c, 70, 155, 25, 775)
    analyze_crop("P3 Clades Table", p3_f, p3_c, 155, 255, 25, 775)
    analyze_crop("P3 Heading 3 & Paragraph 2", p3_f, p3_c, 275, 338, 25, 775)
    analyze_crop("P3 Syndromes Table", p3_f, p3_c, 338, 436, 25, 775)
    analyze_crop("P3 Category Box", p3_f, p3_c, 444, 475, 25, 775)
    analyze_crop("P3 Footer", p3_f, p3_c, 480, 515, 25, 775)

if __name__ == "__main__":
    main()

