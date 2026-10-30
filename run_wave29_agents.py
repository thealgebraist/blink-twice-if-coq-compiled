#!/usr/bin/env python3
"""
run_wave29_agents.py - Wave 29 (Iteration 6 of 8): Blink MathML Core Layout Semantics
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
        "id": "agent369",
        "file": "agent369_mathml_display_mode.md",
        "topic": "Chromium Blink MathML Display Mode (core/layout/mathml/math_layout_utils.cc)",
        "spec": "MathML Core §2.1 (math display block vs inline display modes)",
        "prompt": "You are Agent 369 auditing Blink MathML display mode. Detail block math vs inline math layout constraints."
    },
    {
        "id": "agent370",
        "file": "agent370_mathml_token_sizing.md",
        "topic": "Chromium Blink MathML Token Element Font Style (core/layout/mathml/math_token_layout_algorithm.cc)",
        "spec": "MathML Core §3.2 (single-character mi elements default to italic; multi-character mi default to normal)",
        "prompt": "You are Agent 370 auditing Blink MathML mi element font style. Detail single vs multi-char italic determination."
    },
    {
        "id": "agent371",
        "file": "agent371_mathml_fraction_bar.md",
        "topic": "Chromium Blink MathML Fraction Bar Thickness (core/layout/mathml/math_fraction_layout_algorithm.cc)",
        "spec": "MathML Core §3.3.2 (fraction bar thickness derived from font MATH table FractionRuleThickness >= 1)",
        "prompt": "You are Agent 371 auditing Blink MathML fraction bar thickness. Detail thickness strictly positive lower bound."
    },
    {
        "id": "agent372",
        "file": "agent372_mathml_fraction_gap.md",
        "topic": "Chromium Blink MathML Fraction Gap Clearance (core/layout/mathml/math_fraction_layout_algorithm.cc)",
        "spec": "MathML Core §3.3.2 (gap between numerator, fraction bar, and denominator >= min_gap)",
        "prompt": "You are Agent 372 auditing Blink MathML fraction gap clearance. Detail vertical gap enforcement."
    },
    {
        "id": "agent373",
        "file": "agent373_mathml_superscript_shift.md",
        "topic": "Chromium Blink MathML Superscript Baseline Shift (core/layout/mathml/math_scripts_layout_algorithm.cc)",
        "spec": "MathML Core §3.4.1 (msup superscript baseline shift >= min_shift_up)",
        "prompt": "You are Agent 373 auditing Blink MathML superscript shift. Detail shift up non-negativity and bounds."
    },
    {
        "id": "agent374",
        "file": "agent374_mathml_subscript_drop.md",
        "topic": "Chromium Blink MathML Subscript Baseline Drop (core/layout/mathml/math_scripts_layout_algorithm.cc)",
        "spec": "MathML Core §3.4.1 (msub subscript baseline drop >= min_drop_down)",
        "prompt": "You are Agent 374 auditing Blink MathML subscript drop. Detail drop down non-negativity and bounds."
    },
    {
        "id": "agent375",
        "file": "agent375_mathml_subsup_gap.md",
        "topic": "Chromium Blink MathML SubSup Gap Disjointness (core/layout/mathml/math_scripts_layout_algorithm.cc)",
        "spec": "MathML Core §3.4.1 (msubsup gap between subscript top and superscript bottom >= SubSuperscriptGapMin)",
        "prompt": "You are Agent 375 auditing Blink MathML msubsup gap clearance. Detail non-overlap between scripts."
    },
    {
        "id": "agent376",
        "file": "agent376_mathml_under_over_centering.md",
        "topic": "Chromium Blink MathML UnderOver Horizontal Centering (core/layout/mathml/math_under_over_layout_algorithm.cc)",
        "spec": "MathML Core §3.5 (munder and mover center script horizontally over base: x = (base_w - script_w) / 2)",
        "prompt": "You are Agent 376 auditing Blink MathML under/over centering. Detail horizontal centering formula."
    },
    {
        "id": "agent377",
        "file": "agent377_mathml_under_over_gap.md",
        "topic": "Chromium Blink MathML UnderOver Vertical Gap (core/layout/mathml/math_under_over_layout_algorithm.cc)",
        "spec": "MathML Core §3.5 (vertical separation gap between base and under/overscript >= UnderbarVerticalGap)",
        "prompt": "You are Agent 377 auditing Blink MathML under/over vertical gap. Detail vertical clearance."
    },
    {
        "id": "agent378",
        "file": "agent378_mathml_under_over_limits.md",
        "topic": "Chromium Blink MathML Munderover Height Bounding (core/layout/mathml/math_under_over_layout_algorithm.cc)",
        "spec": "MathML Core §3.5 (munderover total height = under_h + base_h + over_h + 2*gap)",
        "prompt": "You are Agent 378 auditing Blink MathML munderover total height. Detail height accumulation monotonicity."
    },
    {
        "id": "agent379",
        "file": "agent379_mathml_radical_symbol.md",
        "topic": "Chromium Blink MathML Radical Symbol Sizing (core/layout/mathml/math_radical_layout_algorithm.cc)",
        "spec": "MathML Core §3.6.1 (msqrt radical symbol height >= radicand_height + vertical_gap)",
        "prompt": "You are Agent 379 auditing Blink MathML msqrt radical symbol sizing. Detail symbol height lower bound."
    },
    {
        "id": "agent380",
        "file": "agent380_mathml_root_index.md",
        "topic": "Chromium Blink MathML Root Index Positioning (core/layout/mathml/math_radical_layout_algorithm.cc)",
        "spec": "MathML Core §3.6.2 (mroot index position inside radical notch x, y within bounds)",
        "prompt": "You are Agent 380 auditing Blink MathML mroot index positioning. Detail notch coordinate bounds."
    },
    {
        "id": "agent381",
        "file": "agent381_mathml_op_vertical_stretch.md",
        "topic": "Chromium Blink MathML Operator Vertical Stretching (core/layout/mathml/math_operator_layout_algorithm.cc)",
        "spec": "MathML Core §3.2.4 (stretchy vertical operator height >= target_height)",
        "prompt": "You are Agent 381 auditing Blink MathML operator vertical stretching. Detail vertical stretching coverage."
    },
    {
        "id": "agent382",
        "file": "agent382_mathml_op_horizontal_stretch.md",
        "topic": "Chromium Blink MathML Operator Horizontal Stretching (core/layout/mathml/math_operator_layout_algorithm.cc)",
        "spec": "MathML Core §3.2.4 (stretchy horizontal operator width >= target_width)",
        "prompt": "You are Agent 382 auditing Blink MathML operator horizontal stretching. Detail horizontal stretching coverage."
    },
    {
        "id": "agent383",
        "file": "agent383_mathml_table_baseline.md",
        "topic": "Chromium Blink MathML Table Grid Baseline Alignment (core/layout/mathml/math_table_layout_algorithm.cc)",
        "spec": "MathML Core §3.7 (mtable row baseline alignment derived from cell baselines)",
        "prompt": "You are Agent 383 auditing Blink MathML mtable baseline alignment. Detail cell baseline alignment."
    },
    {
        "id": "agent384",
        "file": "agent384_mathml_scriptlevel_scaling.md",
        "topic": "Chromium Blink MathML Scriptlevel Font Scaling (core/layout/mathml/math_layout_utils.cc)",
        "spec": "MathML Core §2.4 (scriptlevel increment reduces font-size by factor of 0.71 bounded below)",
        "prompt": "You are Agent 384 auditing Blink MathML scriptlevel font scaling. Detail size attenuation and positive bounds."
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
    print("Launching Wave 29 (Iteration 6 of 8): 16 concurrent Python3 agents using gemini-4-argon with benchmark-validated optimal Medium thinking budget (2048)...")
    with concurrent.futures.ThreadPoolExecutor(max_workers=16) as executor:
        results = list(executor.map(run_agent, tasks))

    total_p = sum(r.get("prompt_tokens", 0) for r in results)
    total_c = sum(r.get("candidates_tokens", 0) for r in results)
    total_t = sum(r.get("total_tokens", 0) for r in results)

    log_entry = {
        "timestamp": time.strftime("%Y-%m-%d %H:%M:%S"),
        "model": "gemini-4-argon",
        "wave": 29,
        "iteration": 6,
        "theme": "Blink MathML Core Layout Semantics (Display Mode, Token Sizing, Fraction Bar, Fraction Gap, Superscript Shift, Subscript Drop, SubSup Gap, UnderOver Centering, UnderOver Gap, UnderOver Limits, Radical Symbol, Root Index, Op Vertical Stretch, Op Horizontal Stretch, Table Baseline, Scriptlevel Scaling)",
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

    print("\n=== WAVE 29 (ITERATION 6 OF 8) TOKEN USAGE REPORT ===")
    print(f"Prompt Tokens:     {total_p}")
    print(f"Candidate Tokens:  {total_c}")
    print(f"Total Tokens Used: {total_t}")
    print("Appended log entry to token_usage.log.")
