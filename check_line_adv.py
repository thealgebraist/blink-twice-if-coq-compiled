#!/usr/bin/env python3
import numpy as np
from PIL import Image

def main():
    p1_f = np.array(Image.open("blink_formal_wikipedia_flowers_p1.png").convert("RGB"))
    p1_c = np.array(Image.open("chromium_wikipedia_flowers.png").convert("RGB"))

    f_crop = p1_f[295:308, 45:180]
    c_crop = p1_c[295:308, 45:180]
    diff = np.abs(f_crop.astype(int) - c_crop.astype(int))
    max_d = np.max(diff, axis=2)
    far = np.sum(max_d > 15)
    print(f"Far diffs in '1.2 Reproductive organs': {far}")

    # Check horizontal advance difference along X
    col_d = np.sum(max_d > 15, axis=0)
    for x in range(len(col_d)):
        if col_d[x] > 0:
            print(f"x={45+x}: col far diff={col_d[x]}")

if __name__ == "__main__":
    main()

