#!/usr/bin/env python3
"""
run_wave23_agents.py - Wave 23 (Iteration 8 of 8): Capstone LayoutNG Master Pipeline & Document Lifecycle
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
        "id": "agent273",
        "file": "agent273_document_lifecycle_state.md",
        "topic": "Chromium Blink Document Lifecycle State Machine (core/frame/local_frame_view.cc)",
        "spec": "HTML Standard §7.13 (Document lifecycle state monotonic progression: Unstyled -> StyleClean -> LayoutClean -> PaintClean)",
        "prompt": """You are Agent 273 auditing Chromium Blink Document Lifecycle vs HTML Standard §7.13.
Detail:
1. States: Unstyled (0), InStyleRecalc (1), StyleClean (2), InPerformLayout (3), LayoutClean (4), InCompositing (5), InPaint (6), PaintClean (7).
2. Invariants: lifecycle phase transitions strictly advance during render frame; cannot jump to PaintClean without passing LayoutClean.
3. Concrete Rocq/Coq definitions and theorems for BlinkDocumentLifecycleStateSemantics.v with 0 admits."""
    },
    {
        "id": "agent274",
        "file": "agent274_constraint_space_cache_key.md",
        "topic": "Chromium Blink Constraint Space Cache Key Equivalence (core/layout/constraint_space.cc)",
        "spec": "Blink LayoutNG Caching (Identical available sizes, percentage resolution size, and margin struts produce matching cache key)",
        "prompt": """You are Agent 274 auditing Chromium Blink Constraint Space Cache Key Equivalence.
Detail:
1. Cache key: (avail_inline, avail_block, pct_inline, pct_block).
2. Invariants: cache key equality is an equivalence relation (reflexive, symmetric, transitive).
3. Concrete Rocq/Coq definitions and theorems for BlinkConstraintSpaceCacheKeySemantics.v with 0 admits."""
    },
    {
        "id": "agent275",
        "file": "agent275_layout_result_cache_hit.md",
        "topic": "Chromium Blink Layout Result Cache Hit Invariance (core/layout/layout_result.cc)",
        "spec": "Blink LayoutNG Cache (Reusing cached layout result yields identical physical fragment geometry)",
        "prompt": """You are Agent 275 auditing Chromium Blink Layout Result Cache Invariance.
Detail:
1. Cache lookup: lookup(space, node) = Some cached_res -> geometry(cached_res) == geometry(fresh_res).
2. Invariants: cache hits preserve physical fragment dimensions and offsets identically.
3. Concrete Rocq/Coq definitions and theorems for BlinkLayoutResultCacheHitSemantics.v with 0 admits."""
    },
    {
        "id": "agent276",
        "file": "agent276_simplified_layout_fast_path.md",
        "topic": "Chromium Blink Simplified Layout Fast Path (core/layout/simplified_layout_algorithm.cc)",
        "spec": "Blink LayoutNG (When child dimensions are unchanged, parent re-computes offsets in O(N) without child re-layout)",
        "prompt": """You are Agent 276 auditing Chromium Blink Simplified Layout Fast Path.
Detail:
1. Simplified layout: skips recursive child layout passes when child intrinsic dimensions remain constant.
2. Invariants: output coordinates match full layout pass identically under un-invalidated children.
3. Concrete Rocq/Coq definitions and theorems for BlinkSimplifiedLayoutFastPathSemantics.v with 0 admits."""
    },
    {
        "id": "agent277",
        "file": "agent277_fragment_tree_dfs_traversal.md",
        "topic": "Chromium Blink Physical Fragment Tree Depth-First Traversal (core/layout/physical_box_fragment.cc)",
        "spec": "Blink LayoutNG Fragment Tree (Depth-first traversal visits all fragment nodes deterministically)",
        "prompt": """You are Agent 277 auditing Chromium Blink Fragment Tree Depth-First Traversal.
Detail:
1. Traversal: preorder and postorder fold over physical fragment tree.
2. Invariants: total node count preserved, parent visited before children in preorder traversal.
3. Concrete Rocq/Coq definitions and theorems for BlinkFragmentTreeDFSTraversalSemantics.v with 0 admits."""
    },
    {
        "id": "agent278",
        "file": "agent278_scrollable_overflow_union.md",
        "topic": "Chromium Blink Scrollable Overflow Accumulation (core/layout/overflow_model.cc)",
        "spec": "CSS Overflow 3 §3 (Scrollable overflow is union of border box and child overflow rects)",
        "prompt": """You are Agent 278 auditing Chromium Blink Scrollable Overflow Accumulation vs CSS Overflow 3 §3.
Detail:
1. Overflow union: union_overflow(border_box, children) = [min(bb_x1, min(ch_x1)), max(bb_x2, max(ch_x2))].
2. Invariants: scrollable overflow contains border box, union is monotone in child addition.
3. Concrete Rocq/Coq definitions and theorems for BlinkScrollableOverflowUnionSemantics.v with 0 admits."""
    },
    {
        "id": "agent279",
        "file": "agent279_paint_offset_propagation.md",
        "topic": "Chromium Blink Cumulative Paint Offset Propagation (core/paint/paint_property_tree_builder.cc)",
        "spec": "Blink Paint Properties (Cumulative paint offset = parent_paint_offset + child_relative_offset)",
        "prompt": """You are Agent 279 auditing Chromium Blink Paint Offset Propagation.
Detail:
1. Propagation: offset_accum(parent, child) = (px + cx, py + cy).
2. Invariants: root offset is (0,0); composition is commutative and associative.
3. Concrete Rocq/Coq definitions and theorems for BlinkPaintOffsetPropagationSemantics.v with 0 admits."""
    },
    {
        "id": "agent280",
        "file": "agent280_display_item_list_sequence.md",
        "topic": "Chromium Blink Display Item List Deterministic Order (platform/graphics/paint/display_item_list.cc)",
        "spec": "Blink Paint Pipeline (Display item list preserves exact sequential append drawing order)",
        "prompt": """You are Agent 280 auditing Chromium Blink Display Item List Sequence.
Detail:
1. Append: append_item(list, item) preserves head order and appends item at tail.
2. Invariants: length(list ++ [item]) = length(list) + 1, item index strictly increases.
3. Concrete Rocq/Coq definitions and theorems for BlinkDisplayItemListSequenceSemantics.v with 0 admits."""
    },
    {
        "id": "agent281",
        "file": "agent281_subpixel_layout_snapping_bound.md",
        "topic": "Chromium Blink Subpixel Layout Snapping Maximum Error (platform/geometry/layout_unit.cc)",
        "spec": "Blink Geometry (Snap LayoutUnit to nearest device pixel: |pixel_snapped - raw| <= 1/2 pixel)",
        "prompt": """You are Agent 281 auditing Chromium Blink Subpixel Snapping Maximum Error.
Detail:
1. Snapping formula: snap(raw) = (raw + 32) / 64 (in 26.6 fixed point).
2. Invariants: error is strictly bounded: |raw - 64 * snap(raw)| <= 32.
3. Concrete Rocq/Coq definitions and theorems for BlinkSubpixelSnappingBoundSemantics.v with 0 admits."""
    },
    {
        "id": "agent282",
        "file": "agent282_view_transition_pseudo_tree.md",
        "topic": "Chromium Blink View Transition Pseudo-Element Tree Generation (core/view_transition/view_transition.cc)",
        "spec": "CSS View Transitions 1 §3 (Generates root ::view-transition containing ::view-transition-group)",
        "prompt": """You are Agent 282 auditing Chromium Blink View Transition Pseudo Tree vs CSS View Transitions 1 §3.
Detail:
1. Pseudo tree: root -> group -> image-pair -> (old-image, new-image).
2. Invariants: tree hierarchy depth is fixed at 4 levels, root contains all transition groups.
3. Concrete Rocq/Coq definitions and theorems for BlinkViewTransitionPseudoTreeSemantics.v with 0 admits."""
    },
    {
        "id": "agent283",
        "file": "agent283_resize_observer_notification.md",
        "topic": "Chromium Blink ResizeObserver Notification Threshold (core/resize_observer/resize_observer_entry.cc)",
        "spec": "Resize Observer 1 §3 (Notification queued if used border/content box size changes: |size_new - size_old| > 0)",
        "prompt": """You are Agent 283 auditing Chromium Blink ResizeObserver Notification vs Resize Observer 1 §3.
Detail:
1. Change condition: has_changed(old_w, old_h, new_w, new_h) = (old_w !=? new_w) || (old_h !=? new_h).
2. Invariants: notification fired if and only if at least one dimension changes.
3. Concrete Rocq/Coq definitions and theorems for BlinkResizeObserverNotificationSemantics.v with 0 admits."""
    },
    {
        "id": "agent284",
        "file": "agent284_intersection_observer_threshold.md",
        "topic": "Chromium Blink IntersectionObserver Threshold Crossing (core/intersection_observer/intersection_observer_entry.cc)",
        "spec": "Intersection Observer 1 §3 (Trigger notification when intersection ratio crosses any defined threshold)",
        "prompt": """You are Agent 284 auditing Chromium Blink IntersectionObserver Threshold vs Intersection Observer 1 §3.
Detail:
1. Threshold crossing: crossed(old_ratio, new_ratio, th) = (old_ratio < th && th <= new_ratio) || (new_ratio < th && th <= old_ratio).
2. Invariants: strictly detects threshold traversal; ratio in [0, 1000] milli-units.
3. Concrete Rocq/Coq definitions and theorems for BlinkIntersectionObserverThresholdSemantics.v with 0 admits."""
    },
    {
        "id": "agent285",
        "file": "agent285_canvas_2d_state_stack.md",
        "topic": "Chromium Blink Canvas 2D State Stack Save/Restore (core/html/canvas/canvas_rendering_context_2d.cc)",
        "spec": "HTML Standard §4.12.5.1 (Canvas 2D context save/restore state stack: restore pops top saved state)",
        "prompt": """You are Agent 285 auditing Chromium Blink Canvas 2D State Stack vs HTML Standard §4.12.5.1.
Detail:
1. Stack: save(s, stack) = s :: stack; restore(stack) = match stack with s :: rest => (s, rest) | nil => default.
2. Invariants: restore(save(s, stack)) = (s, stack) (LIFO stack identity).
3. Concrete Rocq/Coq definitions and theorems for BlinkCanvas2DStateStackSemantics.v with 0 admits."""
    },
    {
        "id": "agent286",
        "file": "agent286_font_loading_lifecycle.md",
        "topic": "Chromium Blink Font Loading Lifecycle State Machine (core/css/font_face.cc)",
        "spec": "CSS Font Loading 3 §3 (Font face state machine: Unloaded -> Loading -> Loaded / Error)",
        "prompt": """You are Agent 286 auditing Chromium Blink Font Loading Lifecycle vs CSS Font Loading 3 §3.
Detail:
1. States: FontUnloaded (0), FontLoading (1), FontLoaded (2), FontError (3).
2. Invariants: terminal states Loaded and Error have no outbound transitions; lifecycle progresses monotonically.
3. Concrete Rocq/Coq definitions and theorems for BlinkFontLoadingLifecycleSemantics.v with 0 admits."""
    },
    {
        "id": "agent287",
        "file": "agent287_layout_view_root_pipeline.md",
        "topic": "Chromium Blink LayoutView Root Master Pipeline (core/layout/layout_view.cc)",
        "spec": "CSS 2.1 §10.1 & CSS Box Model 3 (LayoutView ICB viewport container bounding and child layout)",
        "prompt": """You are Agent 287 auditing Chromium Blink LayoutView Root Master Pipeline.
Detail:
1. Pipeline: ICB -> HTML box -> Body box -> Document children fragments.
2. Invariants: ICB contains entire viewport coordinate range [0, vw] x [0, vh].
3. Concrete Rocq/Coq definitions and theorems for BlinkLayoutViewRootPipelineSemantics.v with 0 admits."""
    },
    {
        "id": "agent288",
        "file": "agent288_capstone_master_soundness.md",
        "topic": "Chromium Blink Capstone Master Soundness & End-to-End Pipeline (LayoutMasterSoundness.v)",
        "spec": "Complete Chromium Blink HTML/CSS Semantic Model (AST -> Constraints -> LayoutNG -> Paint -> 2D Pixel Buffer)",
        "prompt": """You are Agent 288 auditing Chromium Blink Capstone Master Soundness across the entire formalization.
Detail:
1. Complete pipeline: parse AST -> resolve constraints -> compute fragments -> stacking order -> rasterize to FrameBuffer.
2. Invariants: deterministic execution, non-negative coordinates, 0 admits, pixel exactness.
3. Concrete Rocq/Coq definitions and theorems for BlinkCapstoneMasterSoundnessSemantics.v with 0 admits."""
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
    print("Launching Wave 23 (Iteration 8 of 8): 16 concurrent Python3 agents using gemini-4-argon with benchmark-validated optimal Medium thinking budget (2048)...")
    with concurrent.futures.ThreadPoolExecutor(max_workers=16) as executor:
        results = list(executor.map(run_agent, tasks))

    total_p = sum(r.get("prompt_tokens", 0) for r in results)
    total_c = sum(r.get("candidates_tokens", 0) for r in results)
    total_t = sum(r.get("total_tokens", 0) for r in results)

    log_entry = {
        "timestamp": time.strftime("%Y-%m-%d %H:%M:%S"),
        "model": "gemini-4-argon",
        "wave": 23,
        "iteration": 8,
        "theme": "Capstone LayoutNG Master Pipeline & Document Lifecycle (Document Lifecycle States, Constraint Space Cache Key, Layout Result Cache Hit, Simplified Layout Fast Path, Fragment Tree DFS Traversal, Scrollable Overflow Union, Paint Offset Propagation, Display Item List Sequence, Subpixel Snapping Maximum Error, View Transition Pseudo Tree, ResizeObserver Notification, IntersectionObserver Threshold, Canvas 2D State Stack, Font Loading Lifecycle, LayoutView Root Pipeline, Capstone Master Soundness)",
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

    print("\n=== WAVE 23 (ITERATION 8 OF 8) TOKEN USAGE REPORT ===")
    print(f"Prompt Tokens:     {total_p}")
    print(f"Candidate Tokens:  {total_c}")
    print(f"Total Tokens Used: {total_t}")
    print("Appended log entry to token_usage.log.")
