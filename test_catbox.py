#!/usr/bin/env python3
import numpy as np
from PIL import Image

def test_catbox():
    p3_c = np.array(Image.open("chromium_wikipedia_flowers_p3.png").convert("RGB"))
    p3_f = np.array(Image.open("blink_formal_wikipedia_flowers_p3.png").convert("RGB"))

    crop_c = p3_c[446:472, 25:775]
    crop_f = p3_f[446:472, 25:775]
    diff = np.abs(crop_c.astype(int) - crop_f.astype(int))
    far0 = np.sum(np.max(diff, axis=2) > 15)
    print(f"Current Far diffs in Category Box: {far0}")

if __name__ == "__main__":
    test_catbox()
