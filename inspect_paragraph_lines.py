#!/usr/bin/env python3
import numpy as np
from PIL import Image

def inspect_lines(name, img_f, img_c, y0, y1, x0, x1):
    f_crop = img_f[y0:y1, x0:x1]
    c_crop = img_c[y0:y1, x0:x1]
    # Check dark pixels across X to find lines
    # Sum dark pixels per Y
    f_dark = np.sum(np.min(f_crop, axis=2) < 200, axis=1)
    c_dark = np.sum(np.min(c_crop, axis=2) < 200, axis=1)

    print(f"=== {name} [y: {y0}..{y1}] ===")
    # Find peaks in Y
    print(f"Formal line count / peaks:")
    for dy in range(len(f_dark)):
        if f_dark[dy] > 30 and (dy == 0 or f_dark[dy] >= f_dark[dy-1]) and (dy == len(f_dark)-1 or f_dark[dy] >= f_dark[dy+1]):
            print(f"  Formal peak at y = {y0 + dy:3d} (weight {f_dark[dy]})")
    print(f"Chromium line count / peaks:")
    for dy in range(len(c_dark)):
        if c_dark[dy] > 30 and (dy == 0 or c_dark[dy] >= c_dark[dy-1]) and (dy == len(c_dark)-1 or c_dark[dy] >= c_dark[dy+1]):
            print(f"  Chromium peak at y = {y0 + dy:3d} (weight {c_dark[dy]})")

def main():
    p1_f = np.array(Image.open("blink_formal_wikipedia_flowers_p1.png").convert("RGB"))
    p1_c = np.array(Image.open("chromium_wikipedia_flowers.png").convert("RGB"))
    p2_f = np.array(Image.open("blink_formal_wikipedia_flowers_p2.png").convert("RGB"))
    p2_c = np.array(Image.open("chromium_wikipedia_flowers_p2.png").convert("RGB"))
    p3_f = np.array(Image.open("blink_formal_wikipedia_flowers_p3.png").convert("RGB"))
    p3_c = np.array(Image.open("chromium_wikipedia_flowers_p3.png").convert("RGB"))

    inspect_lines("P1 Lead Paragraph", p1_f, p1_c, 150, 230, 25, 485)
    inspect_lines("P2 Paragraph 1 (Perianth)", p2_f, p2_c, 90, 175, 25, 485)
    inspect_lines("P2 Paragraph 2 (Reproductive)", p2_f, p2_c, 290, 375, 25, 485)
    inspect_lines("P3 Paragraph 1 (Evolution)", p3_f, p3_c, 90, 160, 25, 775)
    inspect_lines("P3 Paragraph 2 (Syndromes)", p3_f, p3_c, 290, 340, 25, 775)

if __name__ == "__main__":
    main()

