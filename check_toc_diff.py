#!/usr/bin/env python3
import numpy as np
from PIL import Image

def main():
    p1_f = np.array(Image.open("blink_formal_wikipedia_flowers_p1.png").convert("RGB"))
    p1_c = np.array(Image.open("chromium_wikipedia_flowers.png").convert("RGB"))

    for line_y0, line_y1, label in [
        (265, 278, "1 Floral anatomy"),
        (280, 293, "1.1 Perianth"),
        (295, 309, "1.2 Reproductive organs"),
        (310, 325, "2 Major flower groups")
    ]:
        f_sub = p1_f[line_y0:line_y1, 30:230]
        c_sub = p1_c[line_y0:line_y1, 30:230]
        # Text is blue or gray
        f_is_text = np.min(f_sub, axis=2) < 220
        c_is_text = np.min(c_sub, axis=2) < 220

        f_rows = np.where(np.any(f_is_text, axis=1))[0]
        c_rows = np.where(np.any(c_is_text, axis=1))[0]
        f_cols = np.where(np.any(f_is_text, axis=0))[0]
        c_cols = np.where(np.any(c_is_text, axis=0))[0]
        
        f_y = line_y0 + f_rows[0] if len(f_rows) > 0 else 0
        c_y = line_y0 + c_rows[0] if len(c_rows) > 0 else 0
        f_x = 30 + f_cols[0] if len(f_cols) > 0 else 0
        c_x = 30 + c_cols[0] if len(c_cols) > 0 else 0

        print(f"  {label:<25} | Formal Y={f_y}, X={f_x} | Chrom Y={c_y}, X={c_x} | Delta Y={f_y - c_y:+d}, X={f_x - c_x:+d}")

if __name__ == "__main__":
    main()
