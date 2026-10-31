#!/usr/bin/env python3
import numpy as np
from PIL import Image

def main():
    p2_c = np.array(Image.open("chromium_wikipedia_flowers_p2.png").convert("RGB"))
    p2_f = np.array(Image.open("blink_formal_wikipedia_flowers_p2.png").convert("RGB"))

    # Caption is between y 260 and 280, x 512 and 768
    crop_c = p2_c[260:280, 512:768]
    crop_f = p2_f[260:280, 512:768]
    diff = np.abs(crop_c.astype(int) - crop_f.astype(int))
    max_d = np.max(diff, axis=2)

    print(f"Caption Far diffs: {np.sum(max_d > 15)}")
    # Find Y rows with text
    for y in range(262, 278):
        c_dark = np.sum(np.min(crop_c[y-260, :], axis=1) < 200)
        f_dark = np.sum(np.min(crop_f[y-260, :], axis=1) < 200)
        print(f"y={y}: Chrom dark={c_dark:2d}, Formal dark={f_dark:2d}")

    # Find X range of text
    c_x = np.where(np.any(np.min(crop_c, axis=2) < 200, axis=0))[0] + 512
    f_x = np.where(np.any(np.min(crop_f, axis=2) < 200, axis=0))[0] + 512
    print(f"Chromium X range: {min(c_x)} .. {max(c_x)} (span: {max(c_x) - min(c_x) + 1})")
    print(f"Formal   X range: {min(f_x)} .. {max(f_x)} (span: {max(f_x) - min(f_x) + 1})")

if __name__ == "__main__":
    main()
