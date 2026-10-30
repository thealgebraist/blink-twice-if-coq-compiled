#!/usr/bin/env python3
"""
run_wave33_agents.py - Wave 33 (Iteration 2 of 8): Web Audio, HTML5 Canvas & 2D Rasterization Primitives
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
        "id": "agent433",
        "file": "agent433_webaudio_graph_transitivity.md",
        "topic": "Chromium Blink Web Audio DSP Graph Connection (modules/webaudio/audio_node.cc)",
        "spec": "Web Audio API 1 §1 (AudioNode connection reachability transitivity)",
        "prompt": "You are Agent 433 auditing Blink Web Audio DSP graph connection. Detail AudioNode connection transitivity."
    },
    {
        "id": "agent434",
        "file": "agent434_gain_node_attenuation.md",
        "topic": "Chromium Blink GainNode Attenuation (modules/webaudio/gain_node.cc)",
        "spec": "Web Audio API 1 §4 (GainNode output amplitude scaling non-negativity)",
        "prompt": "You are Agent 434 auditing Blink GainNode attenuation. Detail output amplitude bounds."
    },
    {
        "id": "agent435",
        "file": "agent435_biquad_filter_bounds.md",
        "topic": "Chromium Blink BiquadFilter Frequency Clamping (modules/webaudio/biquad_dsp_kernel.cc)",
        "spec": "Web Audio API 1 §4 (BiquadFilter cutoff frequency clamped to [0, Nyquist])",
        "prompt": "You are Agent 435 auditing Blink BiquadFilter frequency clamping. Detail cutoff bounds."
    },
    {
        "id": "agent436",
        "file": "agent436_audioparam_ramp_monotonicity.md",
        "topic": "Chromium Blink AudioParam Timeline Ramping (modules/webaudio/audio_param_timeline.cc)",
        "spec": "Web Audio API 1 §2 (linearRampToValueAtTime monotonic interpolation between values)",
        "prompt": "You are Agent 436 auditing Blink AudioParam timeline ramping. Detail ramp monotonicity."
    },
    {
        "id": "agent437",
        "file": "agent437_canvas_state_stack.md",
        "topic": "Chromium Blink Canvas 2D State Stack (modules/canvas/canvas2d/canvas_rendering_context_2d.cc)",
        "spec": "HTML Canvas 2D §2 (save/restore pushdown automaton preserves stack depth invariant)",
        "prompt": "You are Agent 437 auditing Blink Canvas 2D state stack. Detail save/restore pushdown semantics."
    },
    {
        "id": "agent438",
        "file": "agent438_canvas_path_closure.md",
        "topic": "Chromium Blink Path2D Subpath Closure (modules/canvas/canvas2d/canvas_path.cc)",
        "spec": "HTML Canvas 2D §4 (closePath connects current point back to subpath initial point)",
        "prompt": "You are Agent 438 auditing Blink Path2D subpath closure. Detail endpoint connection identity."
    },
    {
        "id": "agent439",
        "file": "agent439_canvas_global_alpha.md",
        "topic": "Chromium Blink Canvas globalAlpha Clamping (modules/canvas/canvas2d/canvas_rendering_context_2d_state.cc)",
        "spec": "HTML Canvas 2D §3 (globalAlpha clamped within [0, 1000] milli-units)",
        "prompt": "You are Agent 439 auditing Blink Canvas globalAlpha clamping. Detail bounds clamping."
    },
    {
        "id": "agent440",
        "file": "agent440_canvas_imagedata_length.md",
        "topic": "Chromium Blink ImageData Buffer Length (modules/canvas/canvas2d/canvas_rendering_context_2d.cc)",
        "spec": "HTML Canvas 2D §11 (ImageData byte length = 4 * width * height identity)",
        "prompt": "You are Agent 440 auditing Blink ImageData buffer length. Detail 4-channel byte allocation identity."
    },
    {
        "id": "agent441",
        "file": "agent441_canvas_transform_invertibility.md",
        "topic": "Chromium Blink Canvas Transform Invertibility (modules/canvas/canvas2d/canvas_rendering_context_2d.cc)",
        "spec": "HTML Canvas 2D §2 (2D affine transform matrix invertible when det != 0)",
        "prompt": "You are Agent 441 auditing Blink Canvas transform invertibility. Detail determinant non-zero invertibility."
    },
    {
        "id": "agent442",
        "file": "agent442_canvas_stroke_offset.md",
        "topic": "Chromium Blink Stroke Half-Width Offset (platform/graphics/graphics_context.cc)",
        "spec": "HTML Canvas 2D §4 (stroke half-width = line_width / 2 >= 0)",
        "prompt": "You are Agent 442 auditing Blink Canvas stroke offset. Detail stroke half-width derivation."
    },
    {
        "id": "agent443",
        "file": "agent443_canvas_dash_array_period.md",
        "topic": "Chromium Blink Dash Array Cycle Period (platform/graphics/graphics_context.cc)",
        "spec": "HTML Canvas 2D §4 (dash pattern period = sum of dash segments strictly positive)",
        "prompt": "You are Agent 443 auditing Blink Dash array cycle period. Detail cycle period accumulation."
    },
    {
        "id": "agent444",
        "file": "agent444_gradient_color_stops.md",
        "topic": "Chromium Blink Linear Gradient Stop Monotonicity (platform/graphics/gradient.cc)",
        "spec": "HTML Canvas 2D §3 (color stop offsets monotonically increase within [0, 1000])",
        "prompt": "You are Agent 444 auditing Blink Gradient color stops. Detail offset monotonic ordering."
    },
    {
        "id": "agent445",
        "file": "agent445_radial_gradient_radii.md",
        "topic": "Chromium Blink Radial Gradient Radii Clamping (platform/graphics/gradient.cc)",
        "spec": "HTML Canvas 2D §3 (radial gradient inner and outer radii non-negative)",
        "prompt": "You are Agent 445 auditing Blink Radial gradient radii clamping. Detail radii non-negativity."
    },
    {
        "id": "agent446",
        "file": "agent446_pattern_wrap_coordinates.md",
        "topic": "Chromium Blink Canvas Pattern Repeat Wrapping (platform/graphics/pattern.cc)",
        "spec": "HTML Canvas 2D §3 (pattern repeat coordinate wrap x mod w, y mod h)",
        "prompt": "You are Agent 446 auditing Blink Canvas pattern repeat wrapping. Detail modulo coordinate wrapping."
    },
    {
        "id": "agent447",
        "file": "agent447_bezier_bounding_box.md",
        "topic": "Chromium Blink Bézier Envelope Containment (platform/graphics/path.cc)",
        "spec": "HTML Canvas 2D §4 (quadratic Bézier curve bounded within control point convex hull)",
        "prompt": "You are Agent 447 auditing Blink Bézier curve bounding envelope. Detail convex hull containment."
    },
    {
        "id": "agent448",
        "file": "agent448_color_space_clamping.md",
        "topic": "Chromium Blink Canvas Color Space Clamping (platform/graphics/color.cc)",
        "spec": "HTML Canvas 2D §11 (sRGB / Display-P3 color components clamped to [0, 255])",
        "prompt": "You are Agent 448 auditing Blink Canvas color component clamping. Detail channel byte clamping."
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
    print("Launching Wave 33 (Iteration 2 of 8): 16 concurrent Python3 agents using gemini-4-argon with benchmark-validated optimal Medium thinking budget (2048)...")
    with concurrent.futures.ThreadPoolExecutor(max_workers=16) as executor:
        results = list(executor.map(run_agent, tasks))

    total_p = sum(r.get("prompt_tokens", 0) for r in results)
    total_c = sum(r.get("candidates_tokens", 0) for r in results)
    total_t = sum(r.get("total_tokens", 0) for r in results)

    log_entry = {
        "timestamp": time.strftime("%Y-%m-%d %H:%M:%S"),
        "model": "gemini-4-argon",
        "wave": 33,
        "iteration": 2,
        "theme": "Web Audio, HTML5 Canvas & 2D Rasterization Primitives",
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

    print("\n=== WAVE 33 (ITERATION 2 OF 8) TOKEN USAGE REPORT ===")
    print(f"Prompt Tokens:     {total_p}")
    print(f"Candidate Tokens:  {total_c}")
    print(f"Total Tokens Used: {total_t}")
    print("Appended log entry to token_usage.log.")

