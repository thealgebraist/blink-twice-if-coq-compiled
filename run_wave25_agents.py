#!/usr/bin/env python3
"""
run_wave25_agents.py - Wave 25 (Iteration 2 of 8): Blink Web Animations & Transitions Semantics
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
        "id": "agent305",
        "file": "agent305_animation_cubic_bezier.md",
        "topic": "Chromium Blink Cubic Bézier Timing Function (core/animation/cubic_bezier_timing_function.cc)",
        "spec": "CSS Easing 1 §3.1 (cubic-bezier(x1, y1, x2, y2) bounds B(t) in [0, 1000] and endpoints B(0)=0, B(1000)=1000)",
        "prompt": "You are Agent 305 auditing Blink cubic-bezier timing function. Detail endpoint identities and bounds in [0, 1000]."
    },
    {
        "id": "agent306",
        "file": "agent306_animation_steps_timing.md",
        "topic": "Chromium Blink Steps Timing Function (core/animation/steps_timing_function.cc)",
        "spec": "CSS Easing 1 §3.2 (steps(n, jump-term) discrete step index calculation and bounds [0, n])",
        "prompt": "You are Agent 306 auditing Blink steps timing function. Detail discrete step index bounds and monotonicity."
    },
    {
        "id": "agent307",
        "file": "agent307_animation_linear_easing.md",
        "topic": "Chromium Blink Linear Easing Function (core/animation/linear_timing_function.cc)",
        "spec": "CSS Easing 2 §2 (linear piecewise linear interpolation between control points)",
        "prompt": "You are Agent 307 auditing Blink linear easing function. Detail piecewise linear interpolation monotonicity."
    },
    {
        "id": "agent308",
        "file": "agent308_animation_keyframe_delay.md",
        "topic": "Chromium Blink Keyframe Timing Delay (core/animation/animation_effect.cc)",
        "spec": "Web Animations §5.3.4 (start_delay, active_interval = max(0, total_duration - delay))",
        "prompt": "You are Agent 308 auditing Blink keyframe timing delay. Detail delay calculation and non-negativity."
    },
    {
        "id": "agent309",
        "file": "agent309_animation_iteration_time.md",
        "topic": "Chromium Blink Current Iteration Time (core/animation/keyframe_effect_model.cc)",
        "spec": "Web Animations §5.3.6 (iteration_time = active_time mod iteration_duration in [0, duration])",
        "prompt": "You are Agent 309 auditing Blink iteration time. Detail modulo bounding within [0, iteration_duration]."
    },
    {
        "id": "agent310",
        "file": "agent310_animation_active_duration.md",
        "topic": "Chromium Blink Active Duration Monotonicity (core/animation/timing.cc)",
        "spec": "Web Animations §5.3.7 (active_duration = iteration_duration * iteration_count monotonicity)",
        "prompt": "You are Agent 310 auditing Blink active duration. Detail monotonicity with respect to iteration count."
    },
    {
        "id": "agent311",
        "file": "agent311_animation_transition_trigger.md",
        "topic": "Chromium Blink CSS Transition Triggering (core/animation/css/css_transition.cc)",
        "spec": "CSS Transitions 1 §3 (transition triggered iff style_old != style_new; identity when equal)",
        "prompt": "You are Agent 311 auditing Blink transition triggering. Detail condition for transition initiation."
    },
    {
        "id": "agent312",
        "file": "agent312_animation_reversing_factor.md",
        "topic": "Chromium Blink Reversing Transition Factor (core/animation/css/css_transition_data.cc)",
        "spec": "CSS Transitions 1 §3.2 (reversing-shortening-factor bounded in [0, 1000])",
        "prompt": "You are Agent 312 auditing Blink reversing transition factor. Detail factor clamping into [0, 1000]."
    },
    {
        "id": "agent313",
        "file": "agent313_animation_composite_operation.md",
        "topic": "Chromium Blink Composite Operation (core/animation/keyframe.cc)",
        "spec": "Web Animations §5.4 (replace, add, accumulate algebraic identities)",
        "prompt": "You are Agent 313 auditing Blink composite operation. Detail replace vs add vs accumulate semantics."
    },
    {
        "id": "agent314",
        "file": "agent314_animation_transform_interpolation.md",
        "topic": "Chromium Blink Transform Interpolation (core/animation/transform_interpolation_functions.cc)",
        "spec": "CSS Transforms 2 §4 (linear interpolation of 2D translation vector: lerp(p1, p2, t))",
        "prompt": "You are Agent 314 auditing Blink transform interpolation. Detail lerp endpoints at t=0 and t=1000."
    },
    {
        "id": "agent315",
        "file": "agent315_animation_filter_list_padding.md",
        "topic": "Chromium Blink Filter List Padding (core/animation/filter_interpolation_functions.cc)",
        "spec": "Filter Effects 1 §7 (zero-element padding for unequal filter list lengths)",
        "prompt": "You are Agent 315 auditing Blink filter list padding. Detail length equalization via neutral element padding."
    },
    {
        "id": "agent316",
        "file": "agent316_animation_opacity_clamping.md",
        "topic": "Chromium Blink Opacity Animation Clamping (core/animation/css_color_interpolation_type.cc)",
        "spec": "CSS Color 4 §4 (opacity animation clamped in [0, 1000] milli-units)",
        "prompt": "You are Agent 316 auditing Blink opacity clamping. Detail clamping bounds and idempotency."
    },
    {
        "id": "agent317",
        "file": "agent317_animation_path_offset_progress.md",
        "topic": "Chromium Blink Motion Path Offset Progress (core/animation/offset_path_animation_type.cc)",
        "spec": "Motion Path 1 §3 (distance progress along path length clamped in [0, 1000])",
        "prompt": "You are Agent 317 auditing Blink motion path offset progress. Detail progress computation along path length."
    },
    {
        "id": "agent318",
        "file": "agent318_animation_timeline_monotonicity.md",
        "topic": "Chromium Blink Animation Timeline Monotonicity (core/animation/document_timeline.cc)",
        "spec": "Web Animations §4.3 (timeline clock monotonically non-decreasing: t1 <= t2 -> clock(t1) <= clock(t2))",
        "prompt": "You are Agent 318 auditing Blink document timeline. Detail monotonic clock advancement."
    },
    {
        "id": "agent319",
        "file": "agent319_animation_play_state.md",
        "topic": "Chromium Blink Animation Play State Machine (core/animation/animation.cc)",
        "spec": "Web Animations §4.5 (play states: idle, running, paused, finished transition invariants)",
        "prompt": "You are Agent 319 auditing Blink animation play states. Detail state machine transition invariants."
    },
    {
        "id": "agent320",
        "file": "agent320_animation_effect_end_time.md",
        "topic": "Chromium Blink Effect End Time Calculation (core/animation/animation_effect.cc)",
        "spec": "Web Animations §5.3.8 (end_time = max(0, start_delay + active_duration))",
        "prompt": "You are Agent 320 auditing Blink effect end time. Detail non-negativity and delay addition."
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
    print("Launching Wave 25 (Iteration 2 of 8): 16 concurrent Python3 agents using gemini-4-argon with benchmark-validated optimal Medium thinking budget (2048)...")
    with concurrent.futures.ThreadPoolExecutor(max_workers=16) as executor:
        results = list(executor.map(run_agent, tasks))

    total_p = sum(r.get("prompt_tokens", 0) for r in results)
    total_c = sum(r.get("candidates_tokens", 0) for r in results)
    total_t = sum(r.get("total_tokens", 0) for r in results)

    log_entry = {
        "timestamp": time.strftime("%Y-%m-%d %H:%M:%S"),
        "model": "gemini-4-argon",
        "wave": 25,
        "iteration": 2,
        "theme": "Blink Web Animations & Transitions Semantics (Cubic Bezier, Steps Timing, Linear Easing, Keyframe Delay, Iteration Time, Active Duration, Transition Trigger, Reversing Factor, Composite Op, Transform Interpolation, Filter List Padding, Opacity Clamping, Path Offset Progress, Timeline Monotonicity, Play State, Effect End Time)",
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

    print("\n=== WAVE 25 (ITERATION 2 OF 8) TOKEN USAGE REPORT ===")
    print(f"Prompt Tokens:     {total_p}")
    print(f"Candidate Tokens:  {total_c}")
    print(f"Total Tokens Used: {total_t}")
    print("Appended log entry to token_usage.log.")
