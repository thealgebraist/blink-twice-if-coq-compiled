#!/usr/bin/env python3
"""
run_wave26_agents.py - Wave 26 (Iteration 3 of 8): Blink Scroll-Driven Animations & View Timelines
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
        "id": "agent321",
        "file": "agent321_scroll_timeline_progress.md",
        "topic": "Chromium Blink Scroll Timeline Progress (core/animation/scroll_timeline.cc)",
        "spec": "Scroll-driven Animations 1 §2 (progress = (scroll - start) * 1000 / (end - start) clamped in [0, 1000])",
        "prompt": "You are Agent 321 auditing Blink scroll timeline progress. Detail progress computation and clamping in [0, 1000]."
    },
    {
        "id": "agent322",
        "file": "agent322_view_timeline_cover.md",
        "topic": "Chromium Blink View Timeline Cover Range (core/animation/view_timeline.cc)",
        "spec": "Scroll-driven Animations 1 §3.1 (cover range spans from element entry to element exit)",
        "prompt": "You are Agent 322 auditing Blink view timeline cover range. Detail cover progress formula and boundary endpoints."
    },
    {
        "id": "agent323",
        "file": "agent323_view_timeline_contain.md",
        "topic": "Chromium Blink View Timeline Contain Range (core/animation/view_timeline.cc)",
        "spec": "Scroll-driven Animations 1 §3.2 (contain range spans from element fully inside to starting exit)",
        "prompt": "You are Agent 323 auditing Blink view timeline contain range. Detail contain progress formula and bounds."
    },
    {
        "id": "agent324",
        "file": "agent324_view_timeline_entry.md",
        "topic": "Chromium Blink View Timeline Entry Range (core/animation/view_timeline.cc)",
        "spec": "Scroll-driven Animations 1 §3.3 (entry range from first entering to fully entered)",
        "prompt": "You are Agent 324 auditing Blink view timeline entry range. Detail entry progress formula and endpoints."
    },
    {
        "id": "agent325",
        "file": "agent325_view_timeline_exit.md",
        "topic": "Chromium Blink View Timeline Exit Range (core/animation/view_timeline.cc)",
        "spec": "Scroll-driven Animations 1 §3.4 (exit range from starting to leave to fully left)",
        "prompt": "You are Agent 325 auditing Blink view timeline exit range. Detail exit progress formula and endpoints."
    },
    {
        "id": "agent326",
        "file": "agent326_view_timeline_crossing.md",
        "topic": "Chromium Blink View Timeline Crossing Progress (core/animation/view_timeline.cc)",
        "spec": "Scroll-driven Animations 1 §3.5 (monotonicity between entry, contain, and exit ranges)",
        "prompt": "You are Agent 326 auditing Blink view timeline crossing progress. Detail monotonicity across timeline ranges."
    },
    {
        "id": "agent327",
        "file": "agent327_scroll_offset_clamping.md",
        "topic": "Chromium Blink Scroll Offset Clamping (core/paint/paint_layer_scrollable_area.cc)",
        "spec": "CSSOM View §4 (scroll offset clamped in [0, max(0, scroll_size - client_size)])",
        "prompt": "You are Agent 327 auditing Blink scroll offset clamping. Detail offset clamping bounds."
    },
    {
        "id": "agent328",
        "file": "agent328_scroll_timeline_inactive_zero_range.md",
        "topic": "Chromium Blink Inactive Timeline on Zero Range (core/animation/scroll_timeline.cc)",
        "spec": "Scroll-driven Animations 1 §2.3 (scroll timeline is inactive when scroll range <= 0)",
        "prompt": "You are Agent 328 auditing Blink inactive scroll timeline. Detail inactive state when range <= 0."
    },
    {
        "id": "agent329",
        "file": "agent329_scroll_snap_distance.md",
        "topic": "Chromium Blink Scroll Snap Distance (core/page/scroller.cc)",
        "spec": "CSS Scroll Snap 1 §6 (distance to snap point is absolute difference |s - snap_pos|)",
        "prompt": "You are Agent 329 auditing Blink scroll snap distance. Detail distance computation and non-negativity."
    },
    {
        "id": "agent330",
        "file": "agent330_scroll_snap_stop.md",
        "topic": "Chromium Blink Scroll Snap Stop (core/page/scroller.cc)",
        "spec": "CSS Scroll Snap 1 §6.2 (scroll-snap-stop: always forces stopping at intermediate snap point)",
        "prompt": "You are Agent 330 auditing Blink scroll snap stop. Detail stop always clamping."
    },
    {
        "id": "agent331",
        "file": "agent331_scroll_snap_proximity.md",
        "topic": "Chromium Blink Scroll Snap Proximity (core/page/scroller.cc)",
        "spec": "CSS Scroll Snap 1 §6.1 (snap points only attract within proximity threshold)",
        "prompt": "You are Agent 331 auditing Blink scroll snap proximity. Detail proximity threshold check."
    },
    {
        "id": "agent332",
        "file": "agent332_overscroll_behavior.md",
        "topic": "Chromium Blink Overscroll Behavior Containment (core/input/scroll_manager.cc)",
        "spec": "CSS Overscroll Behavior 1 §3 (overscroll-behavior: contain prevents scroll chaining)",
        "prompt": "You are Agent 332 auditing Blink overscroll behavior. Detail scroll propagation isolation."
    },
    {
        "id": "agent333",
        "file": "agent333_smooth_scroll_duration.md",
        "topic": "Chromium Blink Smooth Scroll Duration (core/scroll/scroll_animator.cc)",
        "spec": "CSSOM View §4 (smooth scroll animation duration non-negativity and upper bound)",
        "prompt": "You are Agent 333 auditing Blink smooth scroll duration. Detail animation duration calculation."
    },
    {
        "id": "agent334",
        "file": "agent334_scroll_margin_outset.md",
        "topic": "Chromium Blink Scroll Margin Outset (core/layout/layout_box.cc)",
        "spec": "CSS Scroll Snap 1 §4 (scroll-margin outsets element snap area: area' = area + margin)",
        "prompt": "You are Agent 334 auditing Blink scroll margin outset. Detail snap area expansion."
    },
    {
        "id": "agent335",
        "file": "agent335_scroll_padding_inset.md",
        "topic": "Chromium Blink Scroll Padding Inset (core/layout/layout_box.cc)",
        "spec": "CSS Scroll Snap 1 §5 (scroll-padding insets snapport: snapport' = snapport - padding)",
        "prompt": "You are Agent 335 auditing Blink scroll padding inset. Detail snapport shrinkage."
    },
    {
        "id": "agent336",
        "file": "agent336_scroll_directionality_mapping.md",
        "topic": "Chromium Blink Scroll Directionality Mapping (core/paint/paint_layer_scrollable_area.cc)",
        "spec": "CSS Writing Modes 4 §6 (scroll direction mapping in vertical-rl vs horizontal-tb)",
        "prompt": "You are Agent 336 auditing Blink scroll directionality. Detail coordinate mapping in orthogonal modes."
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
    print("Launching Wave 26 (Iteration 3 of 8): 16 concurrent Python3 agents using gemini-4-argon with benchmark-validated optimal Medium thinking budget (2048)...")
    with concurrent.futures.ThreadPoolExecutor(max_workers=16) as executor:
        results = list(executor.map(run_agent, tasks))

    total_p = sum(r.get("prompt_tokens", 0) for r in results)
    total_c = sum(r.get("candidates_tokens", 0) for r in results)
    total_t = sum(r.get("total_tokens", 0) for r in results)

    log_entry = {
        "timestamp": time.strftime("%Y-%m-%d %H:%M:%S"),
        "model": "gemini-4-argon",
        "wave": 26,
        "iteration": 3,
        "theme": "Blink Scroll-Driven Animations & View Timelines (Scroll Progress, Cover Range, Contain Range, Entry Range, Exit Range, Crossing Progress, Scroll Offset Clamping, Inactive Zero Range, Snap Distance, Snap Stop, Snap Proximity, Overscroll Containment, Smooth Scroll Duration, Scroll Margin Outset, Scroll Padding Inset, Directionality Mapping)",
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

    print("\n=== WAVE 26 (ITERATION 3 OF 8) TOKEN USAGE REPORT ===")
    print(f"Prompt Tokens:     {total_p}")
    print(f"Candidate Tokens:  {total_c}")
    print(f"Total Tokens Used: {total_t}")
    print("Appended log entry to token_usage.log.")
