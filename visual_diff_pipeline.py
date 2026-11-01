#!/usr/bin/env python3
import sys, os, subprocess
from PIL import Image, ImageChops

CHROMIUM = "/Applications/Chromium.app/Contents/MacOS/Chromium"
URL2PNG = "./blink_url2png"

def render_chromium(html_path, out_png, width=800, height=800):
    cmd = [
        CHROMIUM,
        "--headless",
        "--disable-gpu",
        f"--window-size={width},{height}",
        "--force-device-scale-factor=1",
        f"--screenshot={out_png}",
        f"file://{os.path.abspath(html_path)}"
    ]
    subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)

def render_blink(html_path, out_prefix, width=800, height=800):
    cmd = [
        URL2PNG,
        f"file://{os.path.abspath(html_path)}",
        f"--out={out_prefix}",
        f"--width={width}",
        f"--page-height={height}"
    ]
    subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)

def diff_images(img1_path, img2_path, out_diff_png, threshold=15):
    im1 = Image.open(img1_path).convert("RGB")
    im2 = Image.open(img2_path).convert("RGB")
    w = min(im1.width, im2.width)
    h = min(im1.height, im2.height)
    c1 = im1.crop((0, 0, w, h))
    c2 = im2.crop((0, 0, w, h))
    
    diff = ImageChops.difference(c1, c2)
    diff.save(out_diff_png)
    
    diff_l = diff.convert("L")
    diff_pixels = sum(1 for p in diff_l.getdata() if p > threshold)
    total_pixels = w * h
    ratio = (diff_pixels / total_pixels) * 100.0
    return diff_pixels, total_pixels, ratio

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python3 visual_diff_pipeline.py <file.html> [width] [height]")
        sys.exit(1)
    html_f = sys.argv[1]
    w = int(sys.argv[2]) if len(sys.argv) > 2 else 800
    h = int(sys.argv[3]) if len(sys.argv) > 3 else 800
    base = os.path.splitext(os.path.basename(html_f))[0]
    
    c_png = f"/tmp/{base}_chrome.png"
    b_prefix = f"/tmp/{base}_coq"
    d_png = f"/tmp/{base}_diff.png"
    
    render_chromium(html_f, c_png, w, h)
    render_blink(html_f, b_prefix, w, h)
    b_png = f"{b_prefix}_full.png"
    
    diff_cnt, total, pct = diff_images(c_png, b_png, d_png)
    print(f"[{base}] Differing pixels (>15): {diff_cnt}/{total} ({pct:.2f}%) -> Diff image: {d_png}")
