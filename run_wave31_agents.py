#!/usr/bin/env python3
"""
run_wave31_agents.py - Wave 31 (Iteration 8 of 8): Compositor, Paint Artifacts & Capstone Ultra-Soundness
Benchmark-proven optimal strategy: 16 concurrent agents, gemini-4-argon, thinking_budget=2048, max_output_tokens=3500.
"""

import os
import time
import json
import concurrent.futures
from google import genai
from google.genai import types

api_key = open('key.txt').read().strip()
client = genai.Client(api_key=api_key)

tasks = [
    {
        "id": "agent401",
        "file": "agent401_transform_composition.md",
        "topic": "Chromium Blink Property Tree Transform Composition (core/paint/paint_property_tree_builder.cc)",
        "spec": "CSS Transforms 2 §2 (parent * child affine transform translation additive composition)",
        "prompt": "You are Agent 401 auditing Blink Compositor transform composition. Detail affine translation addition."
    },
    {
        "id": "agent402",
        "file": "agent402_clip_intersection.md",
        "topic": "Chromium Blink Property Tree Clip Intersection (core/paint/clip_path_clipper.cc)",
        "spec": "CSS Masking 1 §3 (parent clip box intersect child clip box rectangle intersection)",
        "prompt": "You are Agent 402 auditing Blink Compositor clip intersection. Detail 2D bounding box intersection."
    },
    {
        "id": "agent403",
        "file": "agent403_effect_opacity.md",
        "topic": "Chromium Blink Property Tree Effect Opacity Product (core/paint/paint_property_tree_builder.cc)",
        "spec": "CSS Color 4 §4 (effective opacity = parent_opacity * child_opacity / 1000)",
        "prompt": "You are Agent 403 auditing Blink Compositor effect opacity product. Detail multiplicative opacity attenuation."
    },
    {
        "id": "agent404",
        "file": "agent404_paint_chunk_bounds.md",
        "topic": "Chromium Blink Paint Chunk Visual Rect Union (platform/graphics/paint/paint_chunk.cc)",
        "spec": "CSS Paint 1 §4 (paint chunk visual rect is the minimal bounding box enclosing all display items)",
        "prompt": "You are Agent 404 auditing Blink Paint chunk visual rect bounding. Detail union bounding box coverage."
    },
    {
        "id": "agent405",
        "file": "agent405_raster_invalidation.md",
        "topic": "Chromium Blink Raster Invalidation Damage Rect (platform/graphics/paint/raster_invalidation_tracking.cc)",
        "spec": "Blink Paint Invalidation §2 (invalidated damage rect bounded by layer bounds)",
        "prompt": "You are Agent 405 auditing Blink Raster invalidation tracking. Detail damage rect containment."
    },
    {
        "id": "agent406",
        "file": "agent406_cull_rect.md",
        "topic": "Chromium Blink Cull Rect Intersection (core/paint/cull_rect.cc)",
        "spec": "Blink Paint Culling §1 (cull rect intersects layer visual rect to discard out-of-view primitives)",
        "prompt": "You are Agent 406 auditing Blink Cull rect intersection. Detail out-of-view geometry culling."
    },
    {
        "id": "agent407",
        "file": "agent407_display_item_list.md",
        "topic": "Chromium Blink Display Item List Sequential Ordering (platform/graphics/paint/display_item_list.cc)",
        "spec": "CSS 2.1 Appendix E §E.2 (display item list preserves strict sequential paint order)",
        "prompt": "You are Agent 407 auditing Blink Display item list iteration. Detail index progression transitivity."
    },
    {
        "id": "agent408",
        "file": "agent408_rgba_packing.md",
        "topic": "Chromium Blink RGBA8888 Color Packing (platform/graphics/color.cc)",
        "spec": "W3C CSS Color 4 §3 (pack r, g, b, a into 32-bit integer: (a << 24) | (r << 16) | (g << 8) | b)",
        "prompt": "You are Agent 408 auditing Blink RGBA8888 color packing. Detail bit shift and mask formulation."
    },
    {
        "id": "agent409",
        "file": "agent409_rgba_unpacking.md",
        "topic": "Chromium Blink RGBA8888 Unpacking Identity (platform/graphics/color.cc)",
        "spec": "W3C CSS Color 4 §3 (unpack(pack(r,g,b,a)) is identity over [0, 255]^4)",
        "prompt": "You are Agent 409 auditing Blink RGBA8888 color unpacking. Detail round-trip channel extraction identity."
    },
    {
        "id": "agent410",
        "file": "agent410_alpha_premultiplication.md",
        "topic": "Chromium Blink Alpha Premultiplication (platform/graphics/color.cc)",
        "spec": "Compositing and Blending 1 §3 (premultiplied c' = (c * a) / 255 <= c for a <= 255)",
        "prompt": "You are Agent 410 auditing Blink Alpha premultiplication. Detail non-expansion and boundedness."
    },
    {
        "id": "agent411",
        "file": "agent411_blend_mode_normal.md",
        "topic": "Chromium Blink Porter-Duff Normal Blending (platform/graphics/graphics_context.cc)",
        "spec": "Compositing and Blending 1 §3 (source-over blending result in [0, 255])",
        "prompt": "You are Agent 411 auditing Blink Porter-Duff normal source-over blending. Detail output boundedness."
    },
    {
        "id": "agent412",
        "file": "agent412_tile_grid_coverage.md",
        "topic": "Chromium Blink Compositor Tile Grid Coverage (platform/graphics/compositing/tile_manager.cc)",
        "spec": "Blink Tile Manager §1 (tiling dimensions ceil(viewport / tile_size) cover full viewport)",
        "prompt": "You are Agent 412 auditing Blink Compositor tile grid coverage. Detail viewport tiling coverage."
    },
    {
        "id": "agent413",
        "file": "agent413_occlusion_culling.md",
        "topic": "Chromium Blink Occlusion Culling Invariance (core/paint/paint_layer_painter.cc)",
        "spec": "Blink Paint Layer §4 (occluded sub-rectangles contribute zero alpha to final raster output)",
        "prompt": "You are Agent 413 auditing Blink Occlusion culling soundness. Detail opacity preservation."
    },
    {
        "id": "agent414",
        "file": "agent414_scroll_clamping.md",
        "topic": "Chromium Blink Scroll Offset Clamping (core/paint/paint_layer_scrollable_area.cc)",
        "spec": "CSSOM View §4 (scroll offset clamped within [0, max_scroll_offset])",
        "prompt": "You are Agent 414 auditing Blink Scroll offset clamping. Detail bounds clamping and idempotency."
    },
    {
        "id": "agent415",
        "file": "agent415_compositor_commit.md",
        "topic": "Chromium Blink Compositor Commit Frame Token (core/frame/local_frame_view.cc)",
        "spec": "HTML / Rendering §7.5 (compositor frame token monotonically advances on each commit)",
        "prompt": "You are Agent 415 auditing Blink Compositor frame commit. Detail monotonic frame token progression."
    },
    {
        "id": "agent416",
        "file": "agent416_ultra_soundness.md",
        "topic": "Chromium Blink Formal Capstone Ultra-Soundness Metatheorem (LayoutMetaProofSystem.v)",
        "spec": "W3C CSS / MathML / SVG / HTML Unified Foundations (grand unification metatheorem)",
        "prompt": "You are Agent 416 auditing the Blink Formal Capstone Ultra-Soundness Metatheorem. Unify all engine modules into a grand inductive proof."
    }
]

def run_agent(task):
    t0 = time.time()
    try:
        response = client.models.generate_content(
            model="gemini-4-argon",
            contents=task["prompt"],
            config=types.GenerateContentConfig(
                max_output_tokens=3500,
                thinking_config=types.ThinkingConfig(thinking_budget=2048)
            )
        )
        content = response.text
        with open(task["file"], "w") as f:
            f.write(content)
        t1 = time.time()
        
        prompt_tokens = 0
        candidates_tokens = 0
        total_tokens = 0
        if hasattr(response, 'usage_metadata') and response.usage_metadata:
            prompt_tokens = getattr(response.usage_metadata, 'prompt_token_count', 0) or 0
            candidates_tokens = getattr(response.usage_metadata, 'candidates_token_count', 0) or 0
            total_tokens = getattr(response.usage_metadata, 'total_token_count', 0) or (prompt_tokens + candidates_tokens)

        info = {
            "id": task["id"],
            "file": task["file"],
            "elapsed_sec": round(t1 - t0, 2),
            "chars": len(content),
            "prompt_tokens": prompt_tokens,
            "candidates_tokens": candidates_tokens,
            "total_tokens": total_tokens
        }
        print(f"[{task['id']}] Done in {info['elapsed_sec']}s! Wrote {task['file']} ({len(content)} chars). Tokens: prompt={prompt_tokens}, candidate={candidates_tokens}, total={total_tokens}")
        return info
    except Exception as e:
        print(f"[{task['id']}] Failed: {e}")
        return {"id": task["id"], "file": task["file"], "error": str(e)}

if __name__ == '__main__':
    print("Launching Wave 31 (Iteration 8 of 8): 16 concurrent Python3 agents using gemini-4-argon with benchmark-validated optimal Medium thinking budget (2048)...")
    with concurrent.futures.ThreadPoolExecutor(max_workers=16) as executor:
        results = list(executor.map(run_agent, tasks))

    total_p = sum(r.get("prompt_tokens", 0) for r in results)
    total_c = sum(r.get("candidates_tokens", 0) for r in results)
    total_t = sum(r.get("total_tokens", 0) for r in results)

    log_entry = {
        "timestamp": time.strftime("%Y-%m-%d %H:%M:%S"),
        "model": "gemini-4-argon",
        "wave": 31,
        "iteration": 8,
        "theme": "Compositor, Paint Artifacts & Capstone Ultra-Soundness Semantics",
        "thinking_budget": 2048,
        "agents": results,
        "aggregate": {
            "prompt_tokens": total_p,
            "candidates_tokens": total_c,
            "total_tokens": total_t
        }
    }

    with open("token_usage.log", "a") as f:
        f.write(json.dumps(log_entry, indent=2) + "\n---\n")

    print("\n=== WAVE 31 (ITERATION 8 OF 8) TOKEN USAGE REPORT ===")
    print(f"Prompt Tokens:     {total_p}")
    print(f"Candidate Tokens:  {total_c}")
    print(f"Total Tokens Used: {total_t}")
    print("Appended log entry to token_usage.log.")
