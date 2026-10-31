import sys
import numpy as np
from PIL import Image

def compare_images(formal_path, chromium_path, diff_path):
    # Convert PPM to PNG if needed
    if formal_path.endswith('.ppm'):
        img = Image.open(formal_path)
        png_path = formal_path[:-4] + '.png'
        img.save(png_path)
        formal_path = png_path

    img1 = Image.open(formal_path).convert('RGB')
    img2 = Image.open(chromium_path).convert('RGB')

    arr1 = np.array(img1, dtype=np.int32)
    arr2 = np.array(img2, dtype=np.int32)

    assert arr1.shape == arr2.shape, f"Shapes differ: {arr1.shape} vs {arr2.shape}"

    h, w, c = arr1.shape
    total_pixels = h * w

    diff = np.abs(arr1 - arr2)
    max_diff_per_pixel = np.max(diff, axis=2)

    exact_matches = np.sum(max_diff_per_pixel == 0)
    near_matches = np.sum(max_diff_per_pixel <= 15)
    far_diffs = np.sum(max_diff_per_pixel > 15)

    mean_err = np.mean(diff)

    # Generate diff heatmap
    # Exact: dark/transparent or white background
    # Near: yellow/orange
    # Far: bright red/magenta
    heatmap = np.zeros((h, w, 3), dtype=np.uint8)
    # Background: white
    heatmap[:, :] = [255, 255, 255]
    
    # Near diffs (1 to 15): light orange
    near_mask = (max_diff_per_pixel > 0) & (max_diff_per_pixel <= 15)
    heatmap[near_mask] = [255, 200, 100]

    # Moderate diffs (16 to 50): red-orange
    mod_mask = (max_diff_per_pixel > 15) & (max_diff_per_pixel <= 50)
    heatmap[mod_mask] = [255, 100, 50]

    # Far diffs (> 50): bright crimson red
    far_mask = max_diff_per_pixel > 50
    heatmap[far_mask] = [255, 0, 0]

    Image.fromarray(heatmap).save(diff_path)

    print(f"=== Comparison: {formal_path} vs {chromium_path} ===")
    print(f"Resolution: {w}x{h} ({total_pixels} pixels)")
    print(f"Exact Matches (diff == 0): {exact_matches:8d} / {total_pixels} ({exact_matches/total_pixels*100:.2f}%)")
    print(f"Near Matches  (diff <= 15): {near_matches:8d} / {total_pixels} ({near_matches/total_pixels*100:.2f}%)")
    print(f"Far Diffs     (diff > 15): {far_diffs:8d} / {total_pixels} ({far_diffs/total_pixels*100:.2f}%)")
    print(f"Mean Abs Error per channel: {mean_err:.4f}")

    # Top diff regions (binned by 20x20 blocks)
    block_h = 20
    block_w = 20
    blocks_y = h // block_h
    blocks_x = w // block_w
    diff_regions = []
    for by in range(blocks_y):
        for bx in range(blocks_x):
            sub = max_diff_per_pixel[by*block_h:(by+1)*block_h, bx*block_w:(bx+1)*block_w]
            far_count = np.sum(sub > 15)
            if far_count > 0:
                diff_regions.append((far_count, by*block_h, bx*block_w))
    diff_regions.sort(key=lambda x: x[0], reverse=True)
    if diff_regions:
        print("Top 5 diff regions [far pixels, y, x]:", diff_regions[:5])
    print()

if __name__ == '__main__':
    pairs = [
        ("blink_formal_wikipedia_flowers_p1.ppm", "chromium_wikipedia_flowers.png", "diff_wikipedia_flowers_p1.png"),
        ("blink_formal_wikipedia_flowers_p2.ppm", "chromium_wikipedia_flowers_p2.png", "diff_wikipedia_flowers_p2.png"),
        ("blink_formal_wikipedia_flowers_p3.ppm", "chromium_wikipedia_flowers_p3.png", "diff_wikipedia_flowers_p3.png"),
        ("blink_formal_wikipedia_flowers_full.ppm", "chromium_wikipedia_flowers_full.png", "diff_wikipedia_flowers_full.png")
    ]
    for formal, chrom, diff in pairs:
        compare_images(formal, chrom, diff)
