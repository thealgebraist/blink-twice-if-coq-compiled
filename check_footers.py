#!/usr/bin/env python3
import numpy as np
from PIL import Image

def inspect_footer(p2_c, p2_f, p3_c, p3_f):
    print("=== PAGE 2 FOOTER ===")
    for y in range(475, 505):
        c_dark = np.sum(np.min(p2_c[y, 25:775], axis=1) < 200)
        f_dark = np.sum(np.min(p2_f[y, 25:775], axis=1) < 200)
        if c_dark > 0 or f_dark > 0:
            print(f"P2 y={y:3d}: Chrom dark={c_dark:3d}, Formal dark={f_dark:3d}")

    # Check horizontal bounds of links on P2
    for name, x0, x1 in [("Left link", 25, 250), ("Center badge", 300, 450), ("Right link", 500, 775)]:
        c_x = np.where(np.any(np.min(p2_c[480:495, x0:x1], axis=2) < 200, axis=0))[0] + x0
        f_x = np.where(np.any(np.min(p2_f[480:495, x0:x1], axis=2) < 200, axis=0))[0] + x0
        if len(c_x) > 0 and len(f_x) > 0:
            print(f"P2 {name:<12}: Chrom X=[{min(c_x):3d}..{max(c_x):3d}], Formal X=[{min(f_x):3d}..{max(f_x):3d}]")

    print("\n=== PAGE 3 FOOTER ===")
    for y in range(485, 515):
        c_dark = np.sum(np.min(p3_c[y, 25:775], axis=1) < 200)
        f_dark = np.sum(np.min(p3_f[y, 25:775], axis=1) < 200)
        if c_dark > 0 or f_dark > 0:
            print(f"P3 y={y:3d}: Chrom dark={c_dark:3d}, Formal dark={f_dark:3d}")

    for name, x0, x1 in [("Left link", 25, 250), ("Center badge", 280, 480), ("Right link", 500, 775)]:
        c_x = np.where(np.any(np.min(p3_c[490:505, x0:x1], axis=2) < 200, axis=0))[0] + x0
        f_x = np.where(np.any(np.min(p3_f[490:505, x0:x1], axis=2) < 200, axis=0))[0] + x0
        if len(c_x) > 0 and len(f_x) > 0:
            print(f"P3 {name:<12}: Chrom X=[{min(c_x):3d}..{max(c_x):3d}], Formal X=[{min(f_x):3d}..{max(f_x):3d}]")

if __name__ == "__main__":
    p2_c = np.array(Image.open("chromium_wikipedia_flowers_p2.png").convert("RGB"))
    p2_f = np.array(Image.open("blink_formal_wikipedia_flowers_p2.png").convert("RGB"))
    p3_c = np.array(Image.open("chromium_wikipedia_flowers_p3.png").convert("RGB"))
    p3_f = np.array(Image.open("blink_formal_wikipedia_flowers_p3.png").convert("RGB"))
    inspect_footer(p2_c, p2_f, p3_c, p3_f)
