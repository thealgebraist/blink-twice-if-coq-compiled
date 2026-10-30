#!/usr/bin/env python3
"""
run_wave30_agents.py - Wave 30 (Iteration 7 of 8): Modern CSS Layout - Subgrid, Anchor Positioning & Masonry
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
        "id": "agent385",
        "file": "agent385_subgrid_track_span.md",
        "topic": "Chromium Blink Subgrid Track Span Matching (core/layout/grid/grid_layout_algorithm.cc)",
        "spec": "CSS Grid 2 §2 (subgrid track span matches parent grid span)",
        "prompt": "You are Agent 385 auditing Blink CSS Subgrid track span matching. Detail track span preservation and boundary clipping."
    },
    {
        "id": "agent386",
        "file": "agent386_subgrid_line_names.md",
        "topic": "Chromium Blink Subgrid Line Name Inheritance (core/layout/grid/grid_line_resolver.cc)",
        "spec": "CSS Grid 2 §2 (subgrid inherits line names from parent grid within spanned range)",
        "prompt": "You are Agent 386 auditing Blink CSS Subgrid line name inheritance. Detail line name lookup and indexing."
    },
    {
        "id": "agent387",
        "file": "agent387_anchor_resolution.md",
        "topic": "Chromium Blink Anchor Element Resolution (core/layout/anchor_evaluator_impl.cc)",
        "spec": "CSS Anchor Positioning §2 (anchor element lookup by identifier or default anchor)",
        "prompt": "You are Agent 387 auditing Blink CSS Anchor element resolution. Detail anchor matching and fallback."
    },
    {
        "id": "agent388",
        "file": "agent388_anchor_midpoint.md",
        "topic": "Chromium Blink Anchor Target Midpoint Calculation (core/layout/anchor_evaluator_impl.cc)",
        "spec": "CSS Anchor Positioning §3 (anchor target midpoint: (start + end) / 2)",
        "prompt": "You are Agent 388 auditing Blink CSS Anchor target midpoint calculation. Detail midpoint coordinate derivation."
    },
    {
        "id": "agent389",
        "file": "agent389_anchor_inset_clamping.md",
        "topic": "Chromium Blink Anchor Inset Clamping (core/layout/anchor_evaluator_impl.cc)",
        "spec": "CSS Anchor Positioning §3 (inset-area clamped within containing block bounds [0, max])",
        "prompt": "You are Agent 389 auditing Blink CSS Anchor inset clamping. Detail bounds clamping and containment."
    },
    {
        "id": "agent390",
        "file": "agent390_position_try_order.md",
        "topic": "Chromium Blink @position-try Fallback Evaluation Order (core/layout/out_of_flow_layout_part.cc)",
        "spec": "CSS Anchor Positioning §4 (position-try fallback options evaluated sequentially until overflow eliminated)",
        "prompt": "You are Agent 390 auditing Blink CSS position-try fallback evaluation order. Detail sequential evaluation semantics."
    },
    {
        "id": "agent391",
        "file": "agent391_position_try_flip.md",
        "topic": "Chromium Blink Position Try Coordinate Flip Reflection (core/layout/out_of_flow_layout_part.cc)",
        "spec": "CSS Anchor Positioning §4 (flip-block/flip-inline reflects coordinate: coord' = container_size - coord - target_size)",
        "prompt": "You are Agent 391 auditing Blink CSS position-try coordinate flip reflection. Detail reflection involution theorem."
    },
    {
        "id": "agent392",
        "file": "agent392_masonry_placement.md",
        "topic": "Chromium Blink Masonry Shortest Column Placement (core/layout/grid/grid_layout_algorithm.cc)",
        "spec": "CSS Grid 3 (Masonry) §2 (item placed into track with minimum accumulated block size)",
        "prompt": "You are Agent 392 auditing Blink Masonry shortest column placement. Detail minimal column index selection."
    },
    {
        "id": "agent393",
        "file": "agent393_masonry_accumulation.md",
        "topic": "Chromium Blink Masonry Column Height Accumulation (core/layout/grid/grid_layout_algorithm.cc)",
        "spec": "CSS Grid 3 (Masonry) §2 (inserting item monotonically increases column block height)",
        "prompt": "You are Agent 393 auditing Blink Masonry column height accumulation. Detail monotonic accumulation property."
    },
    {
        "id": "agent394",
        "file": "agent394_cqw_unit.md",
        "topic": "Chromium Blink Container Query Width Unit cqw (core/css/css_math_expression_node.cc)",
        "spec": "CSS Containment 3 §3 (1cqw = 1% of query container width)",
        "prompt": "You are Agent 394 auditing Blink CSS container query cqw unit resolution. Detail non-negativity and linearity."
    },
    {
        "id": "agent395",
        "file": "agent395_cqh_unit.md",
        "topic": "Chromium Blink Container Query Height Unit cqh (core/css/css_math_expression_node.cc)",
        "spec": "CSS Containment 3 §3 (1cqh = 1% of query container height)",
        "prompt": "You are Agent 395 auditing Blink CSS container query cqh unit resolution. Detail non-negativity and linearity."
    },
    {
        "id": "agent396",
        "file": "agent396_cqi_unit.md",
        "topic": "Chromium Blink Container Query Inline Unit cqi (core/css/css_math_expression_node.cc)",
        "spec": "CSS Containment 3 §3 (1cqi = 1% of query container inline size)",
        "prompt": "You are Agent 396 auditing Blink CSS container query cqi unit resolution. Detail inline size resolution."
    },
    {
        "id": "agent397",
        "file": "agent397_cqb_unit.md",
        "topic": "Chromium Blink Container Query Block Unit cqb (core/css/css_math_expression_node.cc)",
        "spec": "CSS Containment 3 §3 (1cqb = 1% of query container block size)",
        "prompt": "You are Agent 397 auditing Blink CSS container query cqb unit resolution. Detail block size resolution."
    },
    {
        "id": "agent398",
        "file": "agent398_cqmin_cqmax_unit.md",
        "topic": "Chromium Blink Container Query Min/Max Units cqmin and cqmax (core/css/css_math_expression_node.cc)",
        "spec": "CSS Containment 3 §3 (cqmin = min(cqi, cqb); cqmax = max(cqi, cqb))",
        "prompt": "You are Agent 398 auditing Blink CSS container query cqmin and cqmax units. Detail min <= max inequality."
    },
    {
        "id": "agent399",
        "file": "agent399_popover_top_layer.md",
        "topic": "Chromium Blink Popover Top Layer Stacking Order (core/html/html_dialog_element.cc)",
        "spec": "HTML / CSS Position 4 §6 (popover auto inserted at top of top layer stack with monotonic z-order)",
        "prompt": "You are Agent 399 auditing Blink Popover top layer stacking order. Detail strict top layer monotonicity."
    },
    {
        "id": "agent400",
        "file": "agent400_popover_backdrop.md",
        "topic": "Chromium Blink Popover Backdrop Coverage (core/paint/backdrop_filter_painter.cc)",
        "spec": "HTML / CSS Position 4 §6 (::backdrop covers entire viewport bounds [0, 0, vp_w, vp_h])",
        "prompt": "You are Agent 400 auditing Blink Popover ::backdrop coverage bounds. Detail full viewport coverage."
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
    print("Launching Wave 30 (Iteration 7 of 8): 16 concurrent Python3 agents using gemini-4-argon with benchmark-validated optimal Medium thinking budget (2048)...")
    with concurrent.futures.ThreadPoolExecutor(max_workers=16) as executor:
        results = list(executor.map(run_agent, tasks))

    total_p = sum(r.get("prompt_tokens", 0) for r in results)
    total_c = sum(r.get("candidates_tokens", 0) for r in results)
    total_t = sum(r.get("total_tokens", 0) for r in results)

    log_entry = {
        "timestamp": time.strftime("%Y-%m-%d %H:%M:%S"),
        "model": "gemini-4-argon",
        "wave": 30,
        "iteration": 7,
        "theme": "Modern CSS Layout - Subgrid, Anchor Positioning & Masonry Layout Semantics",
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

    print("\n=== WAVE 30 (ITERATION 7 OF 8) TOKEN USAGE REPORT ===")
    print(f"Prompt Tokens:     {total_p}")
    print(f"Candidate Tokens:  {total_c}")
    print(f"Total Tokens Used: {total_t}")
    print("Appended log entry to token_usage.log.")

