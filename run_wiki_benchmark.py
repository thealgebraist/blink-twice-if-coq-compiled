import os
import sys
import subprocess
import time
import json
import glob
from PIL import Image
import numpy as np

WIKI_ARTICLES = [
    ("denmark", "https://en.wikipedia.org/wiki/Denmark", "Denmark"),
    ("united_states", "https://en.wikipedia.org/wiki/United_States", "United States"),
    ("wikipedia", "https://en.wikipedia.org/wiki/Wikipedia", "Wikipedia"),
    ("world_wide_web", "https://en.wikipedia.org/wiki/World_Wide_Web", "World Wide Web"),
    ("donald_trump", "https://en.wikipedia.org/wiki/Donald_Trump", "Donald Trump"),
    ("barack_obama", "https://en.wikipedia.org/wiki/Barack_Obama", "Barack Obama"),
    ("albert_einstein", "https://en.wikipedia.org/wiki/Albert_Einstein", "Albert Einstein"),
    ("isaac_newton", "https://en.wikipedia.org/wiki/Isaac_Newton", "Isaac Newton"),
    ("alan_turing", "https://en.wikipedia.org/wiki/Alan_Turing", "Alan Turing"),
    ("computer_science", "https://en.wikipedia.org/wiki/Computer_science", "Computer Science"),
    ("artificial_intelligence", "https://en.wikipedia.org/wiki/Artificial_intelligence", "Artificial Intelligence"),
    ("chatgpt", "https://en.wikipedia.org/wiki/ChatGPT", "ChatGPT"),
    ("linux", "https://en.wikipedia.org/wiki/Linux", "Linux"),
    ("python", "https://en.wikipedia.org/wiki/Python_(programming_language)", "Python"),
    ("c_lang", "https://en.wikipedia.org/wiki/C_(programming_language)", "C (Programming Language)"),
    ("rocq_prover", "https://en.wikipedia.org/wiki/Rocq_prover", "The Rocq Prover"),
    ("earth", "https://en.wikipedia.org/wiki/Earth", "Earth"),
    ("solar_system", "https://en.wikipedia.org/wiki/Solar_System", "Solar System"),
    ("moon", "https://en.wikipedia.org/wiki/Moon", "Moon"),
    ("sun", "https://en.wikipedia.org/wiki/Sun", "Sun"),
    ("greenland", "https://en.wikipedia.org/wiki/Greenland", "Greenland"),
    ("united_kingdom", "https://en.wikipedia.org/wiki/United_Kingdom", "United Kingdom"),
    ("germany", "https://en.wikipedia.org/wiki/Germany", "Germany"),
    ("france", "https://en.wikipedia.org/wiki/France", "France"),
    ("japan", "https://en.wikipedia.org/wiki/Japan", "Japan"),
    ("china", "https://en.wikipedia.org/wiki/China", "China"),
    ("india", "https://en.wikipedia.org/wiki/India", "India"),
    ("bruce_lee", "https://en.wikipedia.org/wiki/Bruce_Lee", "Bruce Lee"),
    ("leonardo_da_vinci", "https://en.wikipedia.org/wiki/Leonardo_da_Vinci", "Leonardo da Vinci"),
    ("mathematics", "https://en.wikipedia.org/wiki/Mathematics", "Mathematics"),
    ("physics", "https://en.wikipedia.org/wiki/Physics", "Physics"),
    ("biology", "https://en.wikipedia.org/wiki/Biology", "Biology")
]

OUT_DIR = "/Users/anders/projects/testapi/gallery_wiki"
CHROMIUM_BIN = "/Applications/Chromium.app/Contents/MacOS/Chromium"
COQ_BIN = "/Users/anders/projects/testapi/blink_url2png"
VIEWPORT_W = 1280
PAGE_H = 1024
MAX_PAGES_PER_ARTICLE = 4  # Full height sample up to 4 consecutive 1024px pages (4096px height)

os.makedirs(OUT_DIR, exist_ok=True)

def compute_diff(chrome_path, coq_path, diff_out_path):
    try:
        c_img = Image.open(chrome_path).convert('RGB')
        q_img = Image.open(coq_path).convert('RGB')
        if c_img.size != q_img.size:
            q_img = q_img.resize(c_img.size, Image.Resampling.LANCZOS)
        
        ca = np.array(c_img, dtype=np.int16)
        qa = np.array(q_img, dtype=np.int16)
        diff = np.abs(ca - qa)
        
        # Pixels with perceptible delta > 20 in any channel
        max_diff = np.max(diff, axis=-1)
        diff_mask = max_diff > 20
        diff_count = int(np.sum(diff_mask))
        total_pixels = c_img.size[0] * c_img.size[1]
        diff_pct = (diff_count / total_pixels) * 100.0
        
        # Build visually amplified heatmap
        heat = np.zeros((c_img.size[1], c_img.size[0], 3), dtype=np.uint8)
        gray = np.array(c_img.convert('L'), dtype=np.uint8) // 3
        heat[:, :, 0] = gray
        heat[:, :, 1] = gray
        heat[:, :, 2] = gray
        
        # Bright red for differences
        heat[diff_mask, 0] = 255
        heat[diff_mask, 1] = 30
        heat[diff_mask, 2] = 30
        
        Image.fromarray(heat).save(diff_out_path)
        return True, diff_pct, diff_count
    except Exception as e:
        print(f"    Diff calculation error: {e}")
        return False, 100.0, 0

def run_pipeline():
    results = []
    print(f"Starting 32 Top Wikipedia Pages Full-Height Multi-Page Benchmark...")
    print(f"Viewport: {VIEWPORT_W}x{PAGE_H}, Pages per article: up to {MAX_PAGES_PER_ARTICLE}\n")

    for idx, (slug, url, title) in enumerate(WIKI_ARTICLES, 1):
        print(f"[{idx}/32] Processing: {title} ({url})")
        article_record = {
            "slug": slug,
            "title": title,
            "url": url,
            "pages": [],
            "mean_diff_pct": 0.0,
            "total_coq_time": 0.0,
            "total_chrome_time": 0.0
        }

        # 1. Chromium Headless Full Capture (up to 4096px)
        chrome_full_png = f"{OUT_DIR}/{slug}_chrome_full.png"
        t0_c = time.time()
        c_ok = False
        try:
            cmd_c = [
                CHROMIUM_BIN,
                "--headless=new",
                "--disable-gpu",
                "--no-first-run",
                "--no-default-browser-check",
                f"--window-size={VIEWPORT_W},{PAGE_H * MAX_PAGES_PER_ARTICLE}",
                "--blink-settings=preferredColorScheme=0",
                "--default-background-color=ffffffff",
                f"--screenshot={chrome_full_png}",
                url
            ]
            res_c = subprocess.run(cmd_c, timeout=30, capture_output=True)
            t_chrome = time.time() - t0_c
            article_record["total_chrome_time"] = t_chrome
            if os.path.exists(chrome_full_png) and os.path.getsize(chrome_full_png) > 1000:
                c_ok = True
                # Slice into individual 1024px pages
                full_c_img = Image.open(chrome_full_png)
                for p in range(MAX_PAGES_PER_ARTICLE):
                    top = p * PAGE_H
                    bottom = min((p + 1) * PAGE_H, full_c_img.size[1])
                    if top >= full_c_img.size[1]:
                        break
                    slice_c = full_c_img.crop((0, top, VIEWPORT_W, bottom))
                    # Pad to exact 1024 if needed
                    if slice_c.size[1] < PAGE_H:
                        padded = Image.new('RGB', (VIEWPORT_W, PAGE_H), (255, 255, 255))
                        padded.paste(slice_c, (0, 0))
                        slice_c = padded
                    slice_c.save(f"{OUT_DIR}/{slug}_chrome_p{p+1}.png")
        except Exception as e:
            print(f"  Chromium capture error: {e}")

        # 2. Coq Formal Engine Render (Multi-Page slices)
        coq_prefix = f"{OUT_DIR}/{slug}_coq"
        t0_q = time.time()
        q_ok = False
        try:
            cmd_q = [
                COQ_BIN,
                url,
                f"--width={VIEWPORT_W}",
                f"--page-height={PAGE_H}",
                f"--out={coq_prefix}"
            ]
            res_q = subprocess.run(cmd_q, timeout=60, capture_output=True)
            t_coq = time.time() - t0_q
            article_record["total_coq_time"] = t_coq
            q_ok = (res_q.returncode == 0) and os.path.exists(f"{coq_prefix}_p1.png")
            if not q_ok:
                print(f"  Coq engine error: {res_q.stderr.decode('utf-8', errors='ignore')[:200]}")
        except Exception as e:
            print(f"  Coq execution error: {e}")

        # 3. Compare Slices across all pages
        page_diffs = []
        for p in range(1, MAX_PAGES_PER_ARTICLE + 1):
            chrome_p = f"{OUT_DIR}/{slug}_chrome_p{p}.png"
            coq_p = f"{OUT_DIR}/{slug}_coq_p{p}.png"
            diff_p = f"{OUT_DIR}/{slug}_diff_p{p}.png"
            if os.path.exists(chrome_p) and os.path.exists(coq_p):
                diff_ok, diff_pct, diff_cnt = compute_diff(chrome_p, coq_p, diff_p)
                page_info = {
                    "page": p,
                    "diff_pct": diff_pct,
                    "diff_count": diff_cnt,
                    "chrome_png": f"{slug}_chrome_p{p}.png",
                    "coq_png": f"{slug}_coq_p{p}.png",
                    "diff_png": f"{slug}_diff_p{p}.png"
                }
                article_record["pages"].append(page_info)
                page_diffs.append(diff_pct)
                print(f"    Page {p}: diff = {diff_pct:.2f}% ({diff_cnt:,} px)")
            else:
                break
        
        if page_diffs:
            article_record["mean_diff_pct"] = float(np.mean(page_diffs))
            print(f"  -> Article Average Diff: {article_record['mean_diff_pct']:.2f}% (over {len(page_diffs)} pages)\n")
        else:
            print(f"  -> No comparable pages generated.\n")

        results.append(article_record)
        # Progressively update results.json
        with open(f"{OUT_DIR}/results.json", "w") as f:
            json.dump(results, f, indent=2)

    print("All 32 articles complete! Building gallery HTML...")
    generate_gallery_html(results)

def generate_gallery_html(results):
    html = """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>Wikipedia Full-Height Multi-Page Benchmark: Coq vs Headless Chromium</title>
<style>
  :root {
    --bg: #0f1117;
    --surface: #1e222d;
    --border: #2e3440;
    --accent: #4c8bf5;
    --text: #e6edf3;
    --muted: #8b949e;
    --diff-high: #f85149;
    --diff-med: #d29922;
    --diff-low: #3fb950;
  }
  body {
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
    background: var(--bg);
    color: var(--text);
    margin: 0;
    padding: 24px;
  }
  header {
    margin-bottom: 24px;
    padding-bottom: 16px;
    border-bottom: 1px solid var(--border);
  }
  h1 { margin: 0 0 8px 0; font-size: 26px; }
  .stats-bar {
    display: flex;
    gap: 20px;
    font-size: 15px;
    color: var(--muted);
    margin-top: 10px;
  }
  .stat-val { color: var(--text); font-weight: bold; }
  .grid {
    display: flex;
    flex-direction: column;
    gap: 32px;
  }
  .article-card {
    background: var(--surface);
    border: 1px solid var(--border);
    border-radius: 8px;
    overflow: hidden;
    padding: 20px;
  }
  .article-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 16px;
    border-bottom: 1px solid var(--border);
    padding-bottom: 10px;
  }
  .article-title {
    font-size: 20px;
    font-weight: 600;
  }
  .article-title a { color: var(--accent); text-decoration: none; }
  .article-title a:hover { text-decoration: underline; }
  .badge {
    padding: 4px 10px;
    border-radius: 20px;
    font-weight: bold;
    font-size: 13px;
  }
  .badge-low { background: rgba(63, 185, 80, 0.2); color: var(--diff-low); }
  .badge-med { background: rgba(210, 153, 34, 0.2); color: var(--diff-med); }
  .badge-high { background: rgba(248, 81, 73, 0.2); color: var(--diff-high); }
  .pages-container {
    display: flex;
    flex-direction: column;
    gap: 20px;
  }
  .page-row {
    background: #151821;
    border: 1px solid #252b38;
    border-radius: 6px;
    padding: 12px;
  }
  .page-title {
    font-size: 14px;
    font-weight: bold;
    margin-bottom: 10px;
    color: var(--muted);
    display: flex;
    justify-content: space-between;
  }
  .comparison-columns {
    display: grid;
    grid-template-columns: 1fr 1fr 1fr;
    gap: 12px;
  }
  .col {
    display: flex;
    flex-direction: column;
    align-items: center;
  }
  .col-label {
    font-size: 12px;
    color: var(--muted);
    margin-bottom: 6px;
    font-weight: 500;
  }
  .img-wrap {
    width: 100%;
    aspect-ratio: 1280 / 1024;
    background: #000;
    border-radius: 4px;
    overflow: hidden;
    border: 1px solid var(--border);
  }
  .img-wrap img {
    width: 100%;
    height: 100%;
    object-fit: cover;
    display: block;
    cursor: zoom-in;
    transition: transform 0.2s;
  }
  .img-wrap img:hover {
    transform: scale(1.02);
  }
</style>
</head>
<body>
<header>
  <h1>Wikipedia Full-Height Multi-Page Benchmark</h1>
  <div>Formal Coq Blink C99 Engine (with Skia LCD RGB Subpixel Rasterization) vs Headless Chromium</div>
  <div class="stats-bar">
    <div>Total Articles: <span class="stat-val">32</span></div>
    <div>Resolution: <span class="stat-val">1280 × 1024 per page slice</span></div>
    <div>Max Depth: <span class="stat-val">Up to 4096px (4 Pages)</span></div>
  </div>
</header>
<div class="grid">
"""

    for a in results:
        m_diff = a.get("mean_diff_pct", 100.0)
        badge_cls = "badge-low" if m_diff < 20 else ("badge-med" if m_diff < 40 else "badge-high")
        html += f"""
  <div class="article-card">
    <div class="article-header">
      <div class="article-title"><a href="{a['url']}" target="_blank">{a['title']}</a></div>
      <div class="badge {badge_cls}">Avg Diff: {m_diff:.2f}%</div>
    </div>
    <div class="pages-container">
"""
        for p in a.get("pages", []):
            html += f"""
      <div class="page-row">
        <div class="page-title">
          <span>Page Slice #{p['page']} (y: {(p['page']-1)*1024}px – {p['page']*1024}px)</span>
          <span>Pixel Diff: <b>{p['diff_pct']:.2f}%</b> ({p['diff_count']:,} px)</span>
        </div>
        <div class="comparison-columns">
          <div class="col">
            <span class="col-label">Headless Chromium (Light Mode)</span>
            <div class="img-wrap"><img src="{p['chrome_png']}" loading="lazy"></div>
          </div>
          <div class="col">
            <span class="col-label">Coq Model (Skia LCD RGB)</span>
            <div class="img-wrap"><img src="{p['coq_png']}" loading="lazy"></div>
          </div>
          <div class="col">
            <span class="col-label">Differential Heatmap (Δ > 20)</span>
            <div class="img-wrap"><img src="{p['diff_png']}" loading="lazy"></div>
          </div>
        </div>
      </div>
"""
        html += """
    </div>
  </div>
"""

    html += """
</div>
</body>
</html>
"""
    with open(f"{OUT_DIR}/index.html", "w") as f:
        f.write(html)
    print(f"Generated gallery HTML at: {OUT_DIR}/index.html")

if __name__ == "__main__":
    run_pipeline()

