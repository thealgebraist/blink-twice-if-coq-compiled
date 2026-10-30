#!/usr/bin/env python3
"""
run_wave32_agents.py - Wave 32 (Iteration 1 of 8): CSS Custom Properties & CSS Houdini Layout Semantics
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
        "id": "agent417",
        "file": "agent417_custom_prop_inheritance.md",
        "topic": "Chromium Blink CSS Custom Property Inheritance (core/css/resolver/style_cascade.cc)",
        "spec": "CSS Custom Properties 1 §2 (custom property --* inherits down DOM tree unless overridden)",
        "prompt": "You are Agent 417 auditing Blink CSS custom property inheritance. Detail custom property resolution and cascade inheritance."
    },
    {
        "id": "agent418",
        "file": "agent418_var_cycle_detection.md",
        "topic": "Chromium Blink CSS Variable Cycle Detection (core/css/resolver/css_variable_resolver.cc)",
        "spec": "CSS Custom Properties 1 §3 (circular var() reference invalidates all variables in the cycle to guaranteed-invalid)",
        "prompt": "You are Agent 418 auditing Blink CSS variable cycle detection. Detail dependency DAG traversal and cycle invalidation."
    },
    {
        "id": "agent419",
        "file": "agent419_var_fallback.md",
        "topic": "Chromium Blink var() Fallback Evaluation (core/css/parser/css_variable_parser.cc)",
        "spec": "CSS Custom Properties 1 §3 (var(--x, fallback) evaluates to fallback if --x is unset/invalid)",
        "prompt": "You are Agent 419 auditing Blink CSS var() fallback evaluation. Detail conditional fallback substitution."
    },
    {
        "id": "agent420",
        "file": "agent420_property_registration.md",
        "topic": "Chromium Blink @property Registration (core/css/property_registration.cc)",
        "spec": "CSS Properties and Values 1 §2 (@property syntax descriptor registration and default initial value)",
        "prompt": "You are Agent 420 auditing Blink @property registration. Detail property dictionary insertion and initial value binding."
    },
    {
        "id": "agent421",
        "file": "agent421_typed_om_numeric.md",
        "topic": "Chromium Blink CSS Typed OM Numeric Value (core/css/cssom/css_numeric_value.cc)",
        "spec": "CSS Typed OM 1 §3 (CSSNumericValue addition maintains unit type consistency)",
        "prompt": "You are Agent 421 auditing Blink CSS Typed OM numeric value arithmetic. Detail unit dimension addition."
    },
    {
        "id": "agent422",
        "file": "agent422_paint_worklet.md",
        "topic": "Chromium Blink CSS Paint Worklet (core/paint/paint_worklet.cc)",
        "spec": "CSS Painting 1 §3 (CSS PaintWorklet registerPaint callback invoked with paint input arguments)",
        "prompt": "You are Agent 422 auditing Blink CSS Paint Worklet execution. Detail paint callback invocation and isolate safety."
    },
    {
        "id": "agent423",
        "file": "agent423_layout_worklet.md",
        "topic": "Chromium Blink CSS Layout Worklet (core/layout/custom/custom_layout_worklet.cc)",
        "spec": "CSS Layout API 1 §3 (LayoutWorklet custom layout returns layout fragments with positive dimensions)",
        "prompt": "You are Agent 423 auditing Blink CSS Layout Worklet. Detail custom fragment generation bounds."
    },
    {
        "id": "agent424",
        "file": "agent424_animation_worklet.md",
        "topic": "Chromium Blink CSS Animation Worklet (core/animation/animation_worklet.cc)",
        "spec": "CSS Animation Worklet 1 §2 (WorkletAnimation timeline progress mapped within [0, 1])",
        "prompt": "You are Agent 424 auditing Blink CSS Animation Worklet. Detail timeline fraction clamping."
    },
    {
        "id": "agent425",
        "file": "agent425_env_variables.md",
        "topic": "Chromium Blink CSS Environment Variables (core/css/css_environment_variables.cc)",
        "spec": "CSS Environment Variables 1 §2 (env(safe-area-inset-top) non-negative pixel dimension)",
        "prompt": "You are Agent 425 auditing Blink CSS env() variables. Detail safe-area inset resolution non-negativity."
    },
    {
        "id": "agent426",
        "file": "agent426_cascade_layers.md",
        "topic": "Chromium Blink Cascade Layers @layer (core/css/cascade_layer_map.cc)",
        "spec": "CSS Cascading 5 §6 (@layer declaration order determines layer priority monotonically)",
        "prompt": "You are Agent 426 auditing Blink @layer cascade ordering. Detail layer order monotonic resolution."
    },
    {
        "id": "agent427",
        "file": "agent427_revert_layer.md",
        "topic": "Chromium Blink revert-layer Keyword (core/css/resolver/style_cascade.cc)",
        "spec": "CSS Cascading 5 §7 (revert-layer rolls back value to previous cascade layer)",
        "prompt": "You are Agent 427 auditing Blink revert-layer keyword. Detail layer rollback stack traversal."
    },
    {
        "id": "agent428",
        "file": "agent428_scoped_styles_root.md",
        "topic": "Chromium Blink @scope Root Containment (core/css/style_scope.cc)",
        "spec": "CSS Cascading 6 §3 (@scope matches elements enclosed within scope root subtree)",
        "prompt": "You are Agent 428 auditing Blink @scope root matching. Detail subtree containment verification."
    },
    {
        "id": "agent429",
        "file": "agent429_scoped_styles_limit.md",
        "topic": "Chromium Blink @scope Donut Hole Scoping (core/css/style_scope.cc)",
        "spec": "CSS Cascading 6 §3 (scoped styles excluded inside lower boundary scope limit)",
        "prompt": "You are Agent 429 auditing Blink @scope lower boundary exclusion. Detail donut-hole boundary culling."
    },
    {
        "id": "agent430",
        "file": "agent430_css_nesting.md",
        "topic": "Chromium Blink CSS Nesting Selector & (core/css/parser/css_selector_parser.cc)",
        "spec": "CSS Nesting 1 §3 (& selector expands into parent selector list via :is())",
        "prompt": "You are Agent 430 auditing Blink CSS Nesting & expansion. Detail selector tree substitution."
    },
    {
        "id": "agent431",
        "file": "agent431_view_transitions.md",
        "topic": "Chromium Blink View Transitions Pseudo Elements (core/view_transition/view_transition_pseudo_element.cc)",
        "spec": "CSS View Transitions 1 §3 (::view-transition pseudo tree hierarchy depth monotonicity)",
        "prompt": "You are Agent 431 auditing Blink View Transitions pseudo elements. Detail transition pseudo tree nesting."
    },
    {
        "id": "agent432",
        "file": "agent432_color_mix_function.md",
        "topic": "Chromium Blink CSS color-mix() Function (core/css/css_color_mix_expression_node.cc)",
        "spec": "CSS Color 5 §3 (color-mix() percentage weights normalize: p1 + p2 = 100%)",
        "prompt": "You are Agent 432 auditing Blink CSS color-mix() normalization. Detail percentage normalization sum to 100%."
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
    print("Launching Wave 32 (Iteration 1 of 8): 16 concurrent Python3 agents using gemini-4-argon with benchmark-validated optimal Medium thinking budget (2048)...")
    with concurrent.futures.ThreadPoolExecutor(max_workers=16) as executor:
        results = list(executor.map(run_agent, tasks))

    total_p = sum(r.get("prompt_tokens", 0) for r in results)
    total_c = sum(r.get("candidates_tokens", 0) for r in results)
    total_t = sum(r.get("total_tokens", 0) for r in results)

    log_entry = {
        "timestamp": time.strftime("%Y-%m-%d %H:%M:%S"),
        "model": "gemini-4-argon",
        "wave": 32,
        "iteration": 1,
        "theme": "Modern Web Platform - CSS Custom Properties & CSS Houdini Layout Semantics",
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

    print("\n=== WAVE 32 (ITERATION 1 OF 8) TOKEN USAGE REPORT ===")
    print(f"Prompt Tokens:     {total_p}")
    print(f"Candidate Tokens:  {total_c}")
    print(f"Total Tokens Used: {total_t}")
    print("Appended log entry to token_usage.log.")

