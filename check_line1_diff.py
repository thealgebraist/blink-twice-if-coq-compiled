#!/usr/bin/env python3
import numpy as np
from PIL import Image

def main():
    p1_f = np.array(Image.open("blink_formal_wikipedia_flowers_p1.png").convert("RGB"))
    p1_c = np.array(Image.open("chromium_wikipedia_flowers.png").convert("RGB"))

    # Line 1: y 155..165, x 25..485
    f_l1 = p1_f[155:165, 25:485]
    c_l1 = p1_c[155:165, 25:485]
    diff = np.abs(f_l1.astype(int) - c_l1.astype(int))
    max_d = np.max(diff, axis=2)

    # Let's find columns with diff > 15
    col_diffs = np.sum(max_d > 15, axis=0)
    print(f"Total columns in Line 1: {len(col_diffs)}")
    print(f"Columns with diff > 15: {np.sum(col_diffs > 0)}")

    # Group into intervals
    intervals = []
    in_int = False
    start = 0
    for i in range(len(col_diffs)):
        if col_diffs[i] > 0 and not in_int:
            in_int = True
            start = i
        elif col_diffs[i] == 0 and in_int:
            in_int = False
            intervals.append((start + 25, i + 25 - 1))
    if in_int:
        intervals.append((start + 25, len(col_diffs) + 25 - 1))

    print(f"Diff intervals in Line 1 (x-coords): {intervals[:10]}")

if __name__ == "__main__":
    main()

