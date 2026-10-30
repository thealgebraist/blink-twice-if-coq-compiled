#!/usr/bin/env python3
"""
run_wave21_agents.py - Wave 21 (Iteration 6 of 8): Paint Layer, Stacking & Compositing Pipeline
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
        "id": "agent241",
        "file": "agent241_stacking_tree_traversal.md",
        "topic": "Chromium Blink Stacking Context 7-Phase Traversal (core/paint/paint_layer_stacking_node.cc)",
        "spec": "CSS 2.1 Appendix E (7-phase painting order: background -> neg z -> blocks -> floats -> inlines -> z=0 -> pos z)",
        "prompt": """You are Agent 241 auditing Chromium Blink Stacking Context 7-Phase Traversal vs CSS 2.1 App E.
Detail:
1. 7 phases: PhaseBackground (0), PhaseNegZ (1), PhaseBlockChildren (2), PhaseFloats (3), PhaseInlines (4), PhaseAutoZ (5), PhasePosZ (6).
2. Invariants: painting order is strictly monotonic in phase indices; earlier phases painted under later phases.
3. Concrete Rocq/Coq definitions and theorems for BlinkStackingPhaseOrderSemantics.v with 0 admits."""
    },
    {
        "id": "agent242",
        "file": "agent242_negative_z_index_sorting.md",
        "topic": "Chromium Blink Negative Z-Index Child Sorting (core/paint/paint_layer_stacking_node.cc)",
        "spec": "CSS 2.1 App E §E.2 (Negative z-index layers sorted strictly ascending by z-index value)",
        "prompt": """You are Agent 242 auditing Chromium Blink Negative Z-Index Child Sorting vs CSS 2.1 App E.
Detail:
1. Sorting: z-index < 0 list ordered such that for i < j, z_i <= z_j.
2. Invariants: layers with lower negative z-index painted before layers with higher negative z-index.
3. Concrete Rocq/Coq definitions and theorems for BlinkNegativeZIndexSortingSemantics.v with 0 admits."""
    },
    {
        "id": "agent243",
        "file": "agent243_positive_z_index_sorting.md",
        "topic": "Chromium Blink Positive Z-Index Child Sorting (core/paint/paint_layer_stacking_node.cc)",
        "spec": "CSS 2.1 App E §E.2 (Positive z-index layers sorted strictly ascending by z-index value)",
        "prompt": """You are Agent 243 auditing Chromium Blink Positive Z-Index Child Sorting vs CSS 2.1 App E.
Detail:
1. Sorting: z-index > 0 list ordered such that for i < j, z_i <= z_j.
2. Invariants: layers with lower positive z-index painted under layers with higher positive z-index.
3. Concrete Rocq/Coq definitions and theorems for BlinkPositiveZIndexSortingSemantics.v with 0 admits."""
    },
    {
        "id": "agent244",
        "file": "agent244_paint_invalidation_clamping.md",
        "topic": "Chromium Blink Paint Invalidation Rect Clamping (core/paint/paint_invalidator.cc)",
        "spec": "W3C CSS Painting & Blink Paint Invalidation (Invalidation rect clamped to layer bounds)",
        "prompt": """You are Agent 244 auditing Chromium Blink Paint Invalidation Rect Clamping.
Detail:
1. Clamping: invalidation_rect = intersect(dirty_rect, layer_bounds).
2. Invariants: invalidation_rect is subset of layer_bounds, invalidation_rect width/height >= 0.
3. Concrete Rocq/Coq definitions and theorems for BlinkPaintInvalidationClampingSemantics.v with 0 admits."""
    },
    {
        "id": "agent245",
        "file": "agent245_compositing_promotion.md",
        "topic": "Chromium Blink Composited Layer Promotion Reasons (core/paint/compositing/compositing_reason_finder.cc)",
        "spec": "W3C CSS Transforms 2 & Blink Compositing (3D transform, will-change, or opacity animation promotes layer)",
        "prompt": """You are Agent 245 auditing Chromium Blink Compositing Promotion Decisions.
Detail:
1. Promotion predicate: has_3d_transform || will_change_transform || active_opacity_animation.
2. Invariants: layer promoted if and only if at least one compositing trigger holds.
3. Concrete Rocq/Coq definitions and theorems for BlinkCompositingPromotionSemantics.v with 0 admits."""
    },
    {
        "id": "agent246",
        "file": "agent246_cull_rect_culling.md",
        "topic": "Chromium Blink Cull Rect Geometry & Paint Skipping (core/paint/cull_rect.cc)",
        "spec": "Blink Paint Pipeline (Display item painted if and only if bounds intersect cull_rect)",
        "prompt": """You are Agent 246 auditing Chromium Blink Cull Rect Paint Skipping.
Detail:
1. Cull check: intersects(item_bounds, cull_rect).
2. Invariants: completely disjoint items (r_item < l_cull || l_item > r_cull) are culled (painted = false).
3. Concrete Rocq/Coq definitions and theorems for BlinkCullRectCullingSemantics.v with 0 admits."""
    },
    {
        "id": "agent247",
        "file": "agent247_backdrop_filter_outset.md",
        "topic": "Chromium Blink Backdrop Filter Blur Outset (core/paint/paint_layer_painter.cc)",
        "spec": "CSS Filters 2 (Backdrop filter blur radius expands affected backdrop sampling bounds)",
        "prompt": """You are Agent 247 auditing Chromium Blink Backdrop Filter Blur Outset vs CSS Filters 2.
Detail:
1. Outset: sampling_rect = expand(layer_rect, 3 * blur_radius).
2. Invariants: sampling_rect contains layer_rect, sampling area expands monotonically with blur_radius.
3. Concrete Rocq/Coq definitions and theorems for BlinkBackdropFilterOutsetSemantics.v with 0 admits."""
    },
    {
        "id": "agent248",
        "file": "agent248_opacity_multiplier_chain.md",
        "topic": "Chromium Blink Opacity Alpha Multiplier Compounding (core/paint/paint_property_tree_builder.cc)",
        "spec": "CSS Color 3 §3.2 (Cascaded opacity values multiply: alpha = (parent_alpha * child_alpha) / 255)",
        "prompt": """You are Agent 248 auditing Chromium Blink Opacity Multiplier Compounding vs CSS Color 3 §3.2.
Detail:
1. Compounding: effective_alpha = (a1 * a2) / 255 with 0 <= a <= 255.
2. Invariants: 0 <= effective_alpha <= min(a1, a2), effective_alpha monotonic in each operand.
3. Concrete Rocq/Coq definitions and theorems for BlinkOpacityMultiplierChainSemantics.v with 0 admits."""
    },
    {
        "id": "agent249",
        "file": "agent249_transform_property_tree_concat.md",
        "topic": "Chromium Blink Transform Property Tree Matrix Composition (platform/graphics/paint/transform_paint_property_node.cc)",
        "spec": "CSS Transforms 1 §5 (Transform nodes accumulate by 2D matrix multiplication)",
        "prompt": """You are Agent 249 auditing Chromium Blink Transform Matrix Composition vs CSS Transforms 1 §5.
Detail:
1. 2D Translation accumulation: (tx_total, ty_total) = (tx_parent + tx_child, ty_parent + ty_child).
2. Invariants: translation composition is commutative, associative, and has identity (0, 0).
3. Concrete Rocq/Coq definitions and theorems for BlinkTransformPropertyTreeConcatSemantics.v with 0 admits."""
    },
    {
        "id": "agent250",
        "file": "agent250_clip_path_non_zero_winding.md",
        "topic": "Chromium Blink Clip Path Non-Zero Winding Rule (core/paint/clip_path_clipper.cc)",
        "spec": "SVG 2 §13.4.2 & CSS Masking 1 §6 (Non-zero fill rule: point inside if winding number != 0)",
        "prompt": """You are Agent 250 auditing Chromium Blink Clip Path Non-Zero Winding vs SVG 2 §13.4.2.
Detail:
1. Non-zero rule: is_inside(p) = (winding_number(p) !=? 0).
2. Invariants: winding number 0 means exterior; non-zero integer means interior.
3. Concrete Rocq/Coq definitions and theorems for BlinkClipPathNonZeroWindingSemantics.v with 0 admits."""
    },
    {
        "id": "agent251",
        "file": "agent251_box_reflection_geometry.md",
        "topic": "Chromium Blink Box Reflection Geometry (core/paint/box_reflection_utils.cc)",
        "spec": "CSS WebKit Extensions (-webkit-box-reflect: below/above offset mirrors coordinates)",
        "prompt": """You are Agent 251 auditing Chromium Blink Box Reflection Geometry.
Detail:
1. Reflection below: y_reflect = 2 * (y_box + h_box) + offset - (y_orig + h_box).
2. Invariants: reflection preserves height of reflected content, reflection is isometric.
3. Concrete Rocq/Coq definitions and theorems for BlinkBoxReflectionGeometrySemantics.v with 0 admits."""
    },
    {
        "id": "agent252",
        "file": "agent252_outline_offset_geometry.md",
        "topic": "Chromium Blink Outline Geometry & Non-Layout Invariance (core/paint/outline_painter.cc)",
        "spec": "CSS 2.1 §18.4 (Outlines do not take up layout space; bounds expand border-box by width + offset)",
        "prompt": """You are Agent 252 auditing Chromium Blink Outline Geometry vs CSS 2.1 §18.4.
Detail:
1. Outline rect: expand border-box by (outline_width + outline_offset).
2. Invariants: layout box dimensions unchanged, visual outline bounds contain border box.
3. Concrete Rocq/Coq definitions and theorems for BlinkOutlineOffsetGeometrySemantics.v with 0 admits."""
    },
    {
        "id": "agent253",
        "file": "agent253_scroll_hit_test_mapping.md",
        "topic": "Chromium Blink Scroll Hit-Test Layer Mapping (core/paint/scroll_hit_test_display_item.cc)",
        "spec": "W3C CSSOM View §12 (Hit testing translates point through scroll offset vector: p_scrolled = p + scroll_offset)",
        "prompt": """You are Agent 253 auditing Chromium Blink Scroll Hit-Test Layer Mapping vs CSSOM View §12.
Detail:
1. Hit-test point transform: (x_content, y_content) = (x_viewport + scroll_x, y_viewport + scroll_y).
2. Invariants: inverse transform recovers viewport coordinates, translation is bijective.
3. Concrete Rocq/Coq definitions and theorems for BlinkScrollHitTestMappingSemantics.v with 0 admits."""
    },
    {
        "id": "agent254",
        "file": "agent254_filter_drop_shadow_bounds.md",
        "topic": "Chromium Blink Filter Drop-Shadow Bounds Expansion (core/paint/filter_painter.cc)",
        "spec": "CSS Filters 1 §5.4 (drop-shadow expands visual bounds by blur_radius and offset dx, dy)",
        "prompt": """You are Agent 254 auditing Chromium Blink Filter Drop-Shadow Bounds vs CSS Filters 1 §5.4.
Detail:
1. Expansion: x_min = min(x, x + dx - blur), x_max = max(x + w, x + dx + w + blur).
2. Invariants: visual bounds contain original box and shadow box, bounds monotonic in blur radius.
3. Concrete Rocq/Coq definitions and theorems for BlinkFilterDropShadowBoundsSemantics.v with 0 admits."""
    },
    {
        "id": "agent255",
        "file": "agent255_blend_mode_isolation.md",
        "topic": "Chromium Blink Mix-Blend-Mode Stacking Context Isolation (core/paint/paint_layer.cc)",
        "spec": "CSS Compositing and Blending 1 §3.1 (mix-blend-mode creates an isolated group / stacking context)",
        "prompt": """You are Agent 255 auditing Chromium Blink Mix-Blend-Mode Isolation vs CSS Compositing 1 §3.1.
Detail:
1. Isolation rule: if blend_mode != Normal then is_isolated_stacking_context = true.
2. Invariants: blend operations contained within stacking subtree; does not bleed into parent backings.
3. Concrete Rocq/Coq definitions and theorems for BlinkBlendModeIsolationSemantics.v with 0 admits."""
    },
    {
        "id": "agent256",
        "file": "agent256_paint_chunk_state_dedup.md",
        "topic": "Chromium Blink Paint Chunk State Deduplication (platform/graphics/paint/paint_chunk.cc)",
        "spec": "Blink Paint Pipeline (Paint chunks sharing identical property tree state can be merged / reused)",
        "prompt": """You are Agent 256 auditing Chromium Blink Paint Chunk State Deduplication.
Detail:
1. Chunk state equality: state1 == state2 if transform_id, clip_id, effect_id match.
2. Invariants: chunk state equality is an equivalence relation (reflexive, symmetric, transitive).
3. Concrete Rocq/Coq definitions and theorems for BlinkPaintChunkStateDedupSemantics.v with 0 admits."""
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
    print("Launching Wave 21 (Iteration 6 of 8): 16 concurrent Python3 agents using gemini-4-argon with benchmark-validated optimal Medium thinking budget (2048)...")
    with concurrent.futures.ThreadPoolExecutor(max_workers=16) as executor:
        results = list(executor.map(run_agent, tasks))

    total_p = sum(r.get("prompt_tokens", 0) for r in results)
    total_c = sum(r.get("candidates_tokens", 0) for r in results)
    total_t = sum(r.get("total_tokens", 0) for r in results)

    log_entry = {
        "timestamp": time.strftime("%Y-%m-%d %H:%M:%S"),
        "model": "gemini-4-argon",
        "wave": 21,
        "iteration": 6,
        "theme": "Paint Layer, Stacking & Compositing Pipeline (Stacking Context 7 Phases, Negative Z-Index Sorting, Positive Z-Index Sorting, Paint Invalidation Clamping, Compositing Promotion Triggers, Cull Rect Paint Skipping, Backdrop Filter Outsets, Opacity Multiplier Compounding, Transform Property Tree Concat, Clip Path Winding, Box Reflection Geometry, Outline Offset Geometry, Scroll Hit-Test Mapping, Filter Drop-Shadow Bounds, Blend Mode Isolation, Paint Chunk State Deduplication)",
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

    print("\n=== WAVE 21 (ITERATION 6 OF 8) TOKEN USAGE REPORT ===")
    print(f"Prompt Tokens:     {total_p}")
    print(f"Candidate Tokens:  {total_c}")
    print(f"Total Tokens Used: {total_t}")
    print("Appended log entry to token_usage.log.")

