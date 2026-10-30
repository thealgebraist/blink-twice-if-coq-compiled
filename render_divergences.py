import os
import subprocess
import shutil

html_files = [
    "01_subpixel_rounding.html",
    "02_quirks_margin_dropping.html",
    "03_grid_remainder_bias.html",
    "04_grid_track_clamping.html",
    "05_table_min_width_incompressible.html",
    "06_table_border_conflict.html",
    "07_float_max_content_defect.html",
    "08_font_ex_unit_fallback.html",
    "09_shape_outside_ellipse.html",
    "10_writing_mode_isomorphism.html"
]

artifacts_dir = "/Users/anders/.gemini/antigravity/brain/272518ec-10f8-4697-9cc0-5de480e9211a"
os.makedirs(artifacts_dir, exist_ok=True)

chrome_bin = "/Applications/Chromium.app/Contents/MacOS/Chromium"

for name in html_files:
    base = os.path.splitext(name)[0]
    html_path = os.path.abspath(os.path.join("visual_divergences", name))
    png_name = f"{base}.png"
    png_path = os.path.abspath(os.path.join("visual_divergences", png_name))
    
    cmd = [
        chrome_bin,
        "--headless=new",
        "--disable-gpu",
        f"--screenshot={png_path}",
        "--window-size=1200,750",
        f"file://{html_path}"
    ]
    
    res = subprocess.run(cmd, capture_output=True, text=True)
    if os.path.exists(png_path):
        size = os.path.getsize(png_path)
        print(f"Rendered {png_name} ({size} bytes)")
        dest = os.path.join(artifacts_dir, png_name)
        shutil.copy2(png_path, dest)
        print(f"Copied to artifact dir: {dest}")
    else:
        print(f"Failed to render {png_name}: {res.stderr}")

print("All screenshots generated successfully!")

