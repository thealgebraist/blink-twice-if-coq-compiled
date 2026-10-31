#!/usr/bin/env python3
import numpy as np
from PIL import Image

def test_x_shift():
    p2_c = np.array(Image.open("chromium_wikipedia_flowers_p2.png").convert("RGB"))
    p2_f = np.array(Image.open("blink_formal_wikipedia_flowers_p2.png").convert("RGB"))

    crop_c = p2_c[263:274, 530:750]
    crop_f = p2_f[263:274, 530:750]

    for dx in range(-4, 5):
        if dx < 0:
            f_shifted = np.pad(crop_f[:, -dx:], ((0, 0), (0, -dx), (0, 0)), mode='edge')
        elif dx > 0:
            f_shifted = np.pad(crop_f[:, :-dx], ((0, 0), (dx, 0), (0, 0)), mode='edge')
        else:
            f_shifted = crop_f
        
        diff = np.abs(crop_c.astype(int) - f_shifted.astype(int))
        far = np.sum(np.max(diff, axis=2) > 15)
        print(f"Shift dx={dx:+2d}px: Far diffs in caption = {far}")

if __name__ == "__main__":
    test_x_shift()

