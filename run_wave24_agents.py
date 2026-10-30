#!/usr/bin/env python3
"""
run_wave24_agents.py - Wave 24 (Iteration 1 of 8): Blink SVG Filter & Vector Layout Semantics
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
        "id": "agent289",
        "file": "agent289_svg_gaussian_blur.md",
        "topic": "Chromium Blink SVG Gaussian Blur Kernel Spread (platform/graphics/filters/fe_gaussian_blur.cc)",
        "spec": "Filter Effects 1 §8 (feGaussianBlur stdDeviation radius d = floor(stdDev * 3 * sqrt(2 * pi) / 4 + 0.5) kernel bounds)",
        "prompt": """You are Agent 289 auditing Chromium Blink feGaussianBlur kernel bounds vs W3C Filter Effects 1 §8.
Detail:
1. Kernel spread radius: std_dev >= 0 -> kernel_radius >= 0.
2. Invariants: blurred bounds outset(w, h, r) = (w + 2*r, h + 2*r); preserves non-negativity.
3. Concrete Rocq/Coq definitions and theorems for BlinkSVGGaussianBlurSpreadSemantics.v with 0 admits."""
    },
    {
        "id": "agent290",
        "file": "agent290_svg_color_matrix.md",
        "topic": "Chromium Blink SVG Color Matrix 5x4 Affine Transform (platform/graphics/filters/fe_color_matrix.cc)",
        "spec": "Filter Effects 1 §9 (feColorMatrix 5x4 matrix multiplication and clamping to [0, 255])",
        "prompt": """You are Agent 290 auditing Chromium Blink feColorMatrix vs W3C Filter Effects 1 §9.
Detail:
1. Color matrix transform: identity matrix preserves RGBA components exactly.
2. Invariants: color channel clamping bounds output in [0, 255].
3. Concrete Rocq/Coq definitions and theorems for BlinkSVGColorMatrixTransformSemantics.v with 0 admits."""
    },
    {
        "id": "agent291",
        "file": "agent291_svg_offset.md",
        "topic": "Chromium Blink SVG feOffset Translation (platform/graphics/filters/fe_offset.cc)",
        "spec": "Filter Effects 1 §10 (feOffset translates image by dx, dy; preserves image dimensions)",
        "prompt": """You are Agent 291 auditing Chromium Blink feOffset vs W3C Filter Effects 1 §10.
Detail:
1. Offset translation: pos' = (x + dx, y + dy); width and height invariant under translation.
2. Invariants: double offset composition is additive: offset(d1) . offset(d2) = offset(d1 + d2).
3. Concrete Rocq/Coq definitions and theorems for BlinkSVGOffsetTranslationSemantics.v with 0 admits."""
    },
    {
        "id": "agent292",
        "file": "agent292_svg_blend_modes.md",
        "topic": "Chromium Blink SVG feBlend Porter-Duff and Separable Modes (platform/graphics/filters/fe_blend.cc)",
        "spec": "Filter Effects 1 §11 (feBlend modes: normal, multiply, screen, darken, lighten)",
        "prompt": """You are Agent 292 auditing Chromium Blink feBlend vs W3C Filter Effects 1 §11.
Detail:
1. Multiply mode: (c1 * c2) / 255 bounded in [0, 255] when c1, c2 in [0, 255].
2. Screen mode: 255 - ((255 - c1) * (255 - c2)) / 255 bounded in [0, 255].
3. Concrete Rocq/Coq definitions and theorems for BlinkSVGBlendModeSemantics.v with 0 admits."""
    },
    {
        "id": "agent293",
        "file": "agent293_svg_composite_arithmetic.md",
        "topic": "Chromium Blink SVG feComposite Arithmetic Mode (platform/graphics/filters/fe_composite.cc)",
        "spec": "Filter Effects 1 §12 (feComposite arithmetic: result = clamp(k1*i1*i2 + k2*i1 + k3*i2 + k4, 0, 255))",
        "prompt": """You are Agent 293 auditing Chromium Blink feComposite Arithmetic mode.
Detail:
1. Arithmetic composite: k1, k2, k3, k4 integer coefficients in fixed-point.
2. Invariants: clamp bounds result strictly in [0, 255]; idempotent clamping.
3. Concrete Rocq/Coq definitions and theorems for BlinkSVGCompositeArithmeticSemantics.v with 0 admits."""
    },
    {
        "id": "agent294",
        "file": "agent294_svg_turbulence_bounds.md",
        "topic": "Chromium Blink SVG feTurbulence Noise Bounds (platform/graphics/filters/fe_turbulence.cc)",
        "spec": "Filter Effects 1 §13 (Perlin turbulence pseudo-random noise output strictly bounded in [-1, 1] or [0, 255])",
        "prompt": """You are Agent 294 auditing Chromium Blink feTurbulence Noise Generation.
Detail:
1. Pseudo-random noise output bounds.
2. Invariants: baseFrequency >= 0, octave count >= 1; noise clamping into [0, 255].
3. Concrete Rocq/Coq definitions and theorems for BlinkSVGTurbulenceNoiseSemantics.v with 0 admits."""
    },
    {
        "id": "agent295",
        "file": "agent295_svg_displacement_map.md",
        "topic": "Chromium Blink SVG feDisplacementMap Coordinate Mapping (platform/graphics/filters/fe_displacement_map.cc)",
        "spec": "Filter Effects 1 §14 (P'(x, y) = P(x + scale * (XC(x,y) - 0.5), y + scale * (YC(x,y) - 0.5)))",
        "prompt": """You are Agent 295 auditing Chromium Blink feDisplacementMap Coordinate Mapping.
Detail:
1. Coordinate displacement formula: scale = 0 implies P'(x, y) = P(x, y) (identity).
2. Invariants: displacement preserves domain boundedness when clamped to rect bounds.
3. Concrete Rocq/Coq definitions and theorems for BlinkSVGDisplacementMapSemantics.v with 0 admits."""
    },
    {
        "id": "agent296",
        "file": "agent296_svg_morphology_radius.md",
        "topic": "Chromium Blink SVG feMorphology Dilate and Erode (platform/graphics/filters/fe_morphology.cc)",
        "spec": "Filter Effects 1 §15 (feMorphology dilate takes maximum, erode takes minimum over radius rx, ry)",
        "prompt": """You are Agent 296 auditing Chromium Blink feMorphology Dilate and Erode.
Detail:
1. Dilate monotonicity: dilate(val, 0) = val; dilate(val, r) >= val.
2. Erode monotonicity: erode(val, 0) = val; erode(val, r) <= val.
3. Concrete Rocq/Coq definitions and theorems for BlinkSVGMorphologyRadiusSemantics.v with 0 admits."""
    },
    {
        "id": "agent297",
        "file": "agent297_svg_drop_shadow_bounds.md",
        "topic": "Chromium Blink SVG feDropShadow Bounds Expansion (platform/graphics/filters/fe_drop_shadow.cc)",
        "spec": "Filter Effects 1 §16 (feDropShadow bounds = union of source rect and offset blur rect)",
        "prompt": """You are Agent 297 auditing Chromium Blink feDropShadow Bounds Expansion.
Detail:
1. Drop shadow rect union: union(source, offset_blur) contains both source and offset_blur.
2. Invariants: union is monotonic; area(union) >= area(source).
3. Concrete Rocq/Coq definitions and theorems for BlinkSVGDropShadowBoundsSemantics.v with 0 admits."""
    },
    {
        "id": "agent298",
        "file": "agent298_svg_convolve_matrix.md",
        "topic": "Chromium Blink SVG feConvolveMatrix Normalization (platform/graphics/filters/fe_convolve_matrix.cc)",
        "spec": "Filter Effects 1 §17 (feConvolveMatrix divisor = sum(kernel) or explicit divisor; result clamped to [0, 255])",
        "prompt": """You are Agent 298 auditing Chromium Blink feConvolveMatrix Normalization.
Detail:
1. Kernel divisor normalization: sum of kernel entries or user-specified divisor.
2. Invariants: clamping guarantees channel value in [0, 255].
3. Concrete Rocq/Coq definitions and theorems for BlinkSVGConvolveMatrixSemantics.v with 0 admits."""
    },
    {
        "id": "agent299",
        "file": "agent299_svg_specular_lighting.md",
        "topic": "Chromium Blink SVG feSpecularLighting Phong Model (platform/graphics/filters/fe_specular_lighting.cc)",
        "spec": "Filter Effects 1 §18 (Phong specular reflection intensity Ks * (N . H)^specularExponent clamped to [0, 255])",
        "prompt": """You are Agent 299 auditing Chromium Blink feSpecularLighting Phong Model.
Detail:
1. Specular lighting intensity calculation: non-negative dot product and exponentiation.
2. Invariants: output intensity clamped into [0, 255].
3. Concrete Rocq/Coq definitions and theorems for BlinkSVGSpecularLightingSemantics.v with 0 admits."""
    },
    {
        "id": "agent300",
        "file": "agent300_svg_diffuse_lighting.md",
        "topic": "Chromium Blink SVG feDiffuseLighting Lambertian Model (platform/graphics/filters/fe_diffuse_lighting.cc)",
        "spec": "Filter Effects 1 §19 (Lambertian diffuse reflection intensity Kd * max(0, N . L) clamped to [0, 255])",
        "prompt": """You are Agent 300 auditing Chromium Blink feDiffuseLighting Lambertian Model.
Detail:
1. Diffuse lighting intensity: Kd * max(0, N . L).
2. Invariants: dot product clamped below at 0; result clamped in [0, 255].
3. Concrete Rocq/Coq definitions and theorems for BlinkSVGDiffuseLightingSemantics.v with 0 admits."""
    },
    {
        "id": "agent301",
        "file": "agent301_svg_tile_repetition.md",
        "topic": "Chromium Blink SVG feTile Pattern Repetition (platform/graphics/filters/fe_tile.cc)",
        "spec": "Filter Effects 1 §20 (feTile repeats input texture seamlessly using modulo arithmetic)",
        "prompt": """You are Agent 301 auditing Chromium Blink feTile Pattern Repetition.
Detail:
1. Seamless tiling modulo: tile_coord(p, w) = p mod w for w > 0.
2. Invariants: tile_coord bounded in [0, w - 1]; periodic: tile_coord(p + w, w) = tile_coord(p, w).
3. Concrete Rocq/Coq definitions and theorems for BlinkSVGTileRepetitionSemantics.v with 0 admits."""
    },
    {
        "id": "agent302",
        "file": "agent302_svg_path_monotonicity.md",
        "topic": "Chromium Blink SVG Path Traversal and Bounding Box (core/svg/svg_path_parser.cc)",
        "spec": "SVG 2 §9 (SVG Path parsing and bounding box union over MoveTo, LineTo, CurveTo segments)",
        "prompt": """You are Agent 302 auditing Chromium Blink SVG Path Parser and BBox computation.
Detail:
1. Path segments: MoveTo(x, y), LineTo(x, y), ClosePath.
2. Invariants: path bounding box contains all endpoints (x, y) visited by LineTo.
3. Concrete Rocq/Coq definitions and theorems for BlinkSVGPathMonotonicitySemantics.v with 0 admits."""
    },
    {
        "id": "agent303",
        "file": "agent303_svg_marker_orientation.md",
        "topic": "Chromium Blink SVG Marker Auto-Start-Reverse Angle (core/layout/svg/layout_svg_resource_marker.cc)",
        "spec": "SVG 2 §11.6.2 (orient='auto-start-reverse' computes tangent angle and reverses start marker by 180 degrees)",
        "prompt": """You are Agent 303 auditing Chromium Blink SVG Marker auto-start-reverse orientation.
Detail:
1. Start marker angle: reversed by 180 degrees (angle + 180 mod 360).
2. Invariants: reversing twice returns to original angle: (angle + 180 + 180) mod 360 = angle mod 360.
3. Concrete Rocq/Coq definitions and theorems for BlinkSVGMarkerOrientationSemantics.v with 0 admits."""
    },
    {
        "id": "agent304",
        "file": "agent304_svg_clippath_mask_intersection.md",
        "topic": "Chromium Blink SVG ClipPath and Mask Intersection (core/layout/svg/layout_svg_resource_clipper.cc)",
        "spec": "SVG 2 §14.3 (Intersection of clip paths yields bounding box no larger than either constituent)",
        "prompt": """You are Agent 304 auditing Chromium Blink SVG ClipPath and Mask Intersection.
Detail:
1. Clip rect intersection: rect_intersect(r1, r2).
2. Invariants: intersected width <= width(r1) and intersected height <= height(r1).
3. Concrete Rocq/Coq definitions and theorems for BlinkSVGClippathMaskIntersectionSemantics.v with 0 admits."""
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
    print("Launching Wave 24 (Iteration 1 of 8): 16 concurrent Python3 agents using gemini-4-argon with benchmark-validated optimal Medium thinking budget (2048)...")
    with concurrent.futures.ThreadPoolExecutor(max_workers=16) as executor:
        results = list(executor.map(run_agent, tasks))

    total_p = sum(r.get("prompt_tokens", 0) for r in results)
    total_c = sum(r.get("candidates_tokens", 0) for r in results)
    total_t = sum(r.get("total_tokens", 0) for r in results)

    log_entry = {
        "timestamp": time.strftime("%Y-%m-%d %H:%M:%S"),
        "model": "gemini-4-argon",
        "wave": 24,
        "iteration": 1,
        "theme": "Blink SVG Filter & Vector Layout Semantics (Gaussian Blur, Color Matrix, feOffset, feBlend, Composite Arithmetic, Turbulence Noise, Displacement Map, Morphology Radius, Drop Shadow Bounds, Convolve Matrix, Specular Lighting, Diffuse Lighting, Tile Repetition, Path Monotonicity, Marker Orientation, ClipPath Intersection)",
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

    print("\n=== WAVE 24 (ITERATION 1 OF 8) TOKEN USAGE REPORT ===")
    print(f"Prompt Tokens:     {total_p}")
    print(f"Candidate Tokens:  {total_c}")
    print(f"Total Tokens Used: {total_t}")
    print("Appended log entry to token_usage.log.")
