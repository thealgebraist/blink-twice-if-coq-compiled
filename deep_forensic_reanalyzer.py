#!/usr/bin/env python3
"""
deep_forensic_reanalyzer.py: Comprehensive forensic re-analysis of pixel differences
between Blink formal engine output and Chromium ground truth across all 3 pages and full stack.
"""

import numpy as np
from PIL import Image
import json

def analyze_page(name, formal_path, chrom_path, width, height):
    f_img = Image.open(formal_path).convert("RGB")
    c_img = Image.open(chrom_path).convert("RGB")
    
    arr_f = np.array(f_img, dtype=np.int32)
    arr_c = np.array(c_img, dtype=np.int32)
    
    assert arr_f.shape == arr_c.shape, f"Mismatch shape for {name}: {arr_f.shape} vs {arr_c.shape}"
    
    total_px = width * height
    diff = np.abs(arr_f - arr_c)
    max_d = np.max(diff, axis=2)
    
    exact = np.sum(max_d == 0)
    diff_px = np.sum(max_d > 0)
    
    # Error magnitude buckets
    bucket_1_5   = np.sum((max_d >= 1) & (max_d <= 5))
    bucket_6_15  = np.sum((max_d >= 6) & (max_d <= 15))
    bucket_16_50 = np.sum((max_d >= 16) & (max_d <= 50))
    bucket_51_100= np.sum((max_d >= 51) & (max_d <= 100))
    bucket_gt100 = np.sum(max_d > 100)
    
    near = np.sum(max_d <= 15)
    perceptible = np.sum(max_d <= 50)
    far = np.sum(max_d > 50)
    
    mae = np.mean(diff)
    rmse = np.sqrt(np.mean(diff ** 2))
    
    # Top 20x20 blocks
    bh, bw = 20, 20
    blocks = []
    for by in range(height // bh):
        for bx in range(width // bw):
            sub = max_d[by*bh:(by+1)*bh, bx*bw:(bx+1)*bw]
            far_c = np.sum(sub > 50)
            total_d = np.sum(sub > 0)
            if total_d > 0:
                blocks.append({
                    "y": by * bh,
                    "x": bx * bw,
                    "far": int(far_c),
                    "total_diff": int(total_d),
                    "max_val": int(np.max(sub)),
                    "mean_d": float(np.mean(sub))
                })
    blocks.sort(key=lambda b: (b["far"], b["total_diff"]), reverse=True)
    
    return {
        "name": name,
        "total_px": total_px,
        "exact": int(exact),
        "diff_px": int(diff_px),
        "exact_pct": float(exact / total_px * 100),
        "near_pct": float(near / total_px * 100),
        "perceptible_pct": float(perceptible / total_px * 100),
        "bucket_1_5": int(bucket_1_5),
        "bucket_6_15": int(bucket_6_15),
        "bucket_16_50": int(bucket_16_50),
        "bucket_51_100": int(bucket_51_100),
        "bucket_gt100": int(bucket_gt100),
        "far": int(far),
        "mae": float(mae),
        "rmse": float(rmse),
        "top_blocks": blocks[:8]
    }

def main():
    pages = [
        ("Page 1 (Overview & Infobox)", "blink_formal_wikipedia_flowers_p1.png", "chromium_wikipedia_flowers.png", 800, 600),
        ("Page 2 (Anatomy & Perianth)", "blink_formal_wikipedia_flowers_p2.png", "chromium_wikipedia_flowers_p2.png", 800, 600),
        ("Page 3 (Taxonomy & Syndromes)", "blink_formal_wikipedia_flowers_p3.png", "chromium_wikipedia_flowers_p3.png", 800, 600),
        ("Full Continuous 3-Page Stack", "blink_formal_wikipedia_flowers_full.png", "chromium_wikipedia_flowers_full.png", 800, 1800)
    ]
    
    results = []
    print("=" * 80)
    print("COMPREHENSIVE FORENSIC RE-ANALYSIS OF PIXEL DIFFERENTIALS")
    print("=" * 80)
    
    for name, f_path, c_path, w, h in pages:
        res = analyze_page(name, f_path, c_path, w, h)
        results.append(res)
        
        print(f"\n--- {res['name']} ({w}x{h} = {res['total_px']:,} px) ---")
        print(f"  Exact Matches (diff == 0) : {res['exact']:8,d} ({res['exact_pct']:.2f}%)")
        print(f"  Near Matches  (diff <= 15): {int(res['exact'] + res['bucket_1_5'] + res['bucket_6_15']):8,d} ({res['near_pct']:.2f}%)")
        print(f"  Sub-50 Delta  (diff <= 50): {int(res['total_px'] - res['far']):8,d} ({res['perceptible_pct']:.2f}%)")
        print(f"  Far Diffs     (diff > 50) : {res['far']:8,d} ({res['far']/res['total_px']*100:.2f}%)")
        print(f"  Mean Absolute Error (MAE) : {res['mae']:.4f}")
        print(f"  Root Mean Square Error    : {res['rmse']:.4f}")
        
        print("\n  Error Magnitude Histogram Distribution:")
        print(f"    Δ = 0      (Exact)       : {res['exact']:8,d} ({res['exact']/res['total_px']*100:5.2f}%)")
        print(f"    1 <= Δ <= 5(Imperceptible): {res['bucket_1_5']:8,d} ({res['bucket_1_5']/res['total_px']*100:5.2f}%)")
        print(f"    6 <= Δ <=15(Gamma Drift)  : {res['bucket_6_15']:8,d} ({res['bucket_6_15']/res['total_px']*100:5.2f}%)")
        print(f"   16 <= Δ <=50(Antialiasing) : {res['bucket_16_50']:8,d} ({res['bucket_16_50']/res['total_px']*100:5.2f}%)")
        print(f"   51 <= Δ<=100(Phase Shift)  : {res['bucket_51_100']:8,d} ({res['bucket_51_100']/res['total_px']*100:5.2f}%)")
        print(f"    Δ > 100    (Edge Contrast): {res['bucket_gt100']:8,d} ({res['bucket_gt100']/res['total_px']*100:5.2f}%)")
        
        print("\n  Top Divergent 20x20 Spatial Clusters:")
        for idx, b in enumerate(res['top_blocks'], 1):
            print(f"    [{idx}] y={b['y']:4d}..{b['y']+20:4d}, x={b['x']:4d}..{b['x']+20:4d} | Far(>50): {b['far']:3d} px | Total diff: {b['total_diff']:3d}/400 | Max Δ: {b['max_val']:3d}")

    # Output JSON summary for artifact embedding
    with open("forensic_reanalysis_summary.json", "w") as fp:
        json.dump(results, fp, indent=2)

if __name__ == "__main__":
    main()

