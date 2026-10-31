#!/usr/bin/env python3
import numpy as np
from PIL import Image

def analyze_horizontal_slice(name, p_f, p_c, y0, y1, x0, x1):
    f_crop = p_f[y0:y1, x0:x1]
    c_crop = p_c[y0:y1, x0:x1]
    # Check width of text in each line
    f_dark = np.min(f_crop, axis=2) < 220
    c_dark = np.min(c_crop, axis=2) < 220

    f_cols = np.where(np.any(f_dark, axis=0))[0]
    c_cols = np.where(np.any(c_dark, axis=0))[0]
    print(f"Slice {name} [y: {y0}..{y1}]:")
    if len(f_cols) > 0 and len(c_cols) > 0:
        print(f"  Formal   X range: {x0 + f_cols[0]} .. {x0 + f_cols[-1]} (span: {f_cols[-1] - f_cols[0] + 1})")
        print(f"  Chromium X range: {x0 + c_cols[0]} .. {x0 + c_cols[-1]} (span: {c_cols[-1] - c_cols[0] + 1})")

def main():
    p1_f = np.array(Image.open("blink_formal_wikipedia_flowers_p1.png").convert("RGB"))
    p1_c = np.array(Image.open("chromium_wikipedia_flowers.png").convert("RGB"))

    for line_idx, (y0, y1) in enumerate([(152, 168), (170, 186), (188, 204), (206, 222)], 1):
        analyze_horizontal_slice(f"P1 Lead Line {line_idx}", p1_f, p1_c, y0, y1, 25, 485)

if __name__ == "__main__":
    main()

