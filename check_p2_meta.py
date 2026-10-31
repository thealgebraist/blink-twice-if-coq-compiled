#!/usr/bin/env python3
import numpy as np
from PIL import Image

def main():
    p2_c = np.array(Image.open("chromium_wikipedia_flowers_p2.png").convert("RGB"))
    p2_f = np.array(Image.open("blink_formal_wikipedia_flowers_p2.png").convert("RGB"))

    # In Chromium, let's inspect y 280..380, x 510..770
    print("=== CHROMIUM INFOBOX META ROWS ===")
    for y in range(285, 375):
        # row of dark pixels in th (515..560) and td (610..760)
        th_dark = np.sum(np.min(p2_c[y, 515:560], axis=1) < 200)
        td_dark = np.sum(np.min(p2_c[y, 610:760], axis=1) < 200)
        if th_dark > 0 or td_dark > 0:
            print(f"c y={y:3d}: th_dark={th_dark:2d}, td_dark={td_dark:2d}")

if __name__ == "__main__":
    main()
