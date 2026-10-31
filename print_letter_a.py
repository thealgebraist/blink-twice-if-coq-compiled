#!/usr/bin/env python3
import numpy as np
from PIL import Image

def main():
    p1_f = np.array(Image.open("blink_formal_wikipedia_flowers_p1.png").convert("RGB"))
    p1_c = np.array(Image.open("chromium_wikipedia_flowers.png").convert("RGB"))

    # Print the "A" glyph
    print("Formal 'A' (min channel):")
    for y in range(155, 165):
        row_str = "".join(f"{np.min(p1_f[y, x]):3d} " for x in range(25, 35))
        print(f"y={y}: {row_str}")

    print("\nChromium 'A' (min channel):")
    for y in range(155, 165):
        row_str = "".join(f"{np.min(p1_c[y, x]):3d} " for x in range(25, 35))
        print(f"y={y}: {row_str}")

if __name__ == "__main__":
    main()
