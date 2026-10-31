#!/usr/bin/env python3
import numpy as np
from PIL import Image

def find_text_bbox(img, y0, y1, x0, x1, bg_thresh=250):
    crop = img[y0:y1, x0:x1]
    # Non-background pixels: min channel < bg_thresh
    is_text = np.min(crop, axis=2) < bg_thresh
    rows = np.where(np.any(is_text, axis=1))[0]
    cols = np.where(np.any(is_text, axis=0))[0]
    if len(rows) == 0:
        return None
    min_y, max_y = y0 + rows[0], y0 + rows[-1]
    min_x, max_x = x0 + cols[0], x0 + cols[-1]
    # Center of mass in Y
    y_weights = np.sum(is_text, axis=1)
    y_com = y0 + np.average(np.arange(len(y_weights)), weights=y_weights)
    return min_y, max_y, min_x, max_x, y_com

def compare_features():
    p1_f = np.array(Image.open("blink_formal_wikipedia_flowers_p1.png").convert("RGB"))
    p1_c = np.array(Image.open("chromium_wikipedia_flowers.png").convert("RGB"))

    p2_f = np.array(Image.open("blink_formal_wikipedia_flowers_p2.png").convert("RGB"))
    p2_c = np.array(Image.open("chromium_wikipedia_flowers_p2.png").convert("RGB"))

    p3_f = np.array(Image.open("blink_formal_wikipedia_flowers_p3.png").convert("RGB"))
    p3_c = np.array(Image.open("chromium_wikipedia_flowers_p3.png").convert("RGB"))

    features = [
        ("P1 Hatnote", p1_f, p1_c, 120, 145, 25, 550),
        ("P1 H1 Flower", p1_f, p1_c, 60, 95, 25, 200),
        ("P1 TOC Heading", p1_f, p1_c, 240, 265, 80, 180),
        ("P2 Diagram Caption", p2_f, p2_c, 260, 280, 515, 765),
        ("P2 H1.1 Heading", p2_f, p2_c, 65, 85, 25, 300),
        ("P2 H1.2 Heading", p2_f, p2_c, 265, 288, 25, 450),
        ("P2 Footer Page2", p2_f, p2_c, 475, 505, 330, 420),
        ("P3 H2 Heading", p3_f, p3_c, 65, 85, 25, 450),
        ("P3 H3 Heading", p3_f, p3_c, 265, 285, 25, 450),
        ("P3 Category Label", p3_f, p3_c, 448, 470, 35, 100),
        ("P3 Footer Page3", p3_f, p3_c, 485, 510, 300, 500),
    ]

    print(f"{'Feature':<22} | {'Formal (minY, maxY, yCOM)':<26} | {'Chromium (minY, maxY, yCOM)':<26} | {'Delta YCOM':<10}")
    print("-" * 90)
    for name, f_img, c_img, y0, y1, x0, x1 in features:
        bb_f = find_text_bbox(f_img, y0, y1, x0, x1)
        bb_c = find_text_bbox(c_img, y0, y1, x0, x1)
        if bb_f and bb_c:
            dy = bb_f[4] - bb_c[4]
            print(f"{name:<22} | [{bb_f[0]:3d}, {bb_f[1]:3d}, {bb_f[4]:5.2f}]         | [{bb_c[0]:3d}, {bb_c[1]:3d}, {bb_c[4]:5.2f}]           | {dy:+5.2f}px")

if __name__ == "__main__":
    compare_features()

