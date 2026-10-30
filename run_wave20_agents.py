#!/usr/bin/env python3
"""
run_wave20_agents.py - Wave 20 (Iteration 5 of 8): CSS Box Model & Intrinsic Sizing Mechanics
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
        "id": "agent225",
        "file": "agent225_inline_margin_auto.md",
        "topic": "Chromium Blink Inline Margin Auto Distribution (core/layout/length_utils.cc)",
        "spec": "CSS 2.1 §10.3.3 (Equal division of remaining inline space when both margins are auto)",
        "prompt": """You are Agent 225 auditing Chromium Blink Inline Margin Auto Distribution vs CSS 2.1 §10.3.3.
Detail:
1. Auto margin splitting: margin_left = margin_right = max(0, (cb_width - used_width) / 2).
2. Invariants: margin_left + used_width + margin_right <= cb_width, symmetry of auto margins.
3. Concrete Rocq/Coq definitions and theorems for BlinkInlineMarginAutoSemantics.v with 0 admits."""
    },
    {
        "id": "agent226",
        "file": "agent226_self_collapsing_margin.md",
        "topic": "Chromium Blink Self-Collapsing Box Margin Strut (core/layout/margin_strut.cc)",
        "spec": "CSS 2.1 §8.3.1 (Box with 0 height and no borders/padding collapses top and bottom margins together)",
        "prompt": """You are Agent 226 auditing Chromium Blink Self-Collapsing Box Margin vs CSS 2.1 §8.3.1.
Detail:
1. Self-collapsing strut: joins top and bottom margin struts without advancing block cursor.
2. Invariants: cursor remains unchanged (delta_y = 0), combined strut contains max(pos_top, pos_bot) and min(neg_top, neg_bot).
3. Concrete Rocq/Coq definitions and theorems for BlinkSelfCollapsingMarginSemantics.v with 0 admits."""
    },
    {
        "id": "agent227",
        "file": "agent227_box_sizing_border_box.md",
        "topic": "Chromium Blink Box Sizing Border-Box Subtraction (core/layout/length_utils.cc)",
        "spec": "CSS Box Sizing 3 §3 (content_width = max(0, border_box_width - padding - border))",
        "prompt": """You are Agent 227 auditing Chromium Blink Box Sizing: border-box vs CSS Box Sizing 3 §3.
Detail:
1. Subtraction: content_size = max(0, border_box_size - (padding + border)).
2. Invariants: content_size >= 0, content_size + padding + border >= border_box_size (when border_box_size >= pb).
3. Concrete Rocq/Coq definitions and theorems for BlinkBoxSizingBorderBoxSemantics.v with 0 admits."""
    },
    {
        "id": "agent228",
        "file": "agent228_percent_padding_inline_basis.md",
        "topic": "Chromium Blink Percentage Padding Resolves Against Inline Size (core/layout/box_model.cc)",
        "spec": "CSS Box Model 3 §6 (padding-top/bottom percentages resolve against containing block inline width)",
        "prompt": """You are Agent 228 auditing Chromium Blink Percentage Padding vs CSS Box Model 3 §6.
Detail:
1. Basis: padding_block = (cb_inline_size * pct) / 100, regardless of containing block block size.
2. Invariants: padding_block monotonic in cb_inline_size, padding_block >= 0 when cb_inline_size >= 0.
3. Concrete Rocq/Coq definitions and theorems for BlinkPercentPaddingInlineBasisSemantics.v with 0 admits."""
    },
    {
        "id": "agent229",
        "file": "agent229_min_content_text_run.md",
        "topic": "Chromium Blink Min-Content Contribution of Text Run (core/layout/inline/inline_node.cc)",
        "spec": "CSS Sizing 3 §4 (min-content of unbroken text run is its shaped advance width)",
        "prompt": """You are Agent 229 auditing Chromium Blink Min-Content of Text Run vs CSS Sizing 3 §4.
Detail:
1. Min-content: min_content(run) = glyph_width_sum(run).
2. Invariants: min_content >= 0, concatenation of runs: min_content(r1 ++ r2) >= min_content(r1).
3. Concrete Rocq/Coq definitions and theorems for BlinkMinContentTextRunSemantics.v with 0 admits."""
    },
    {
        "id": "agent230",
        "file": "agent230_max_content_soft_hyphen.md",
        "topic": "Chromium Blink Max-Content of Soft-Hyphenated Word (core/layout/inline/inline_node.cc)",
        "spec": "CSS Sizing 3 §4 (max-content does not break at soft hyphens, using un-hyphenated length)",
        "prompt": """You are Agent 230 auditing Chromium Blink Max-Content of Soft-Hyphenated Word vs CSS Sizing 3 §4.
Detail:
1. Max-content: does not insert breaks at soft hyphens; measures word in continuous single line.
2. Invariants: max_content >= min_content (which can break at soft hyphens), soft hyphens have zero advance when un-broken.
3. Concrete Rocq/Coq definitions and theorems for BlinkMaxContentSoftHyphenSemantics.v with 0 admits."""
    },
    {
        "id": "agent231",
        "file": "agent231_replaced_aspect_ratio.md",
        "topic": "Chromium Blink Replaced Element Aspect Ratio Resolution (core/layout/length_utils.cc)",
        "spec": "CSS Sizing 3 §5.2 (height = (width * ratio_h) / ratio_w when width is specified)",
        "prompt": """You are Agent 231 auditing Chromium Blink Replaced Element Aspect Ratio vs CSS Sizing 3 §5.2.
Detail:
1. Cross-axis computation: h = (w * r_h) / r_w with integer arithmetic.
2. Invariants: h >= 0 when w >= 0, h monotonic in w.
3. Concrete Rocq/Coq definitions and theorems for BlinkReplacedAspectRatioSemantics.v with 0 admits."""
    },
    {
        "id": "agent232",
        "file": "agent232_inline_block_baseline_overflow.md",
        "topic": "Chromium Blink Inline-Block Baseline with Overflow != Visible (core/layout/layout_block.cc)",
        "spec": "CSS 2.1 §10.8.1 (baseline of inline-block with overflow != visible is bottom margin edge)",
        "prompt": """You are Agent 232 auditing Chromium Blink Inline-Block Baseline vs CSS 2.1 §10.8.1.
Detail:
1. Baseline rule: if overflow == visible and has line box, baseline = last line box baseline; else baseline = margin_box_bottom.
2. Invariants: overflow != visible baseline is exactly margin_box_bottom, ensuring deterministic vertical alignment.
3. Concrete Rocq/Coq definitions and theorems for BlinkInlineBlockBaselineOverflowSemantics.v with 0 admits."""
    },
    {
        "id": "agent233",
        "file": "agent233_percent_margin_inline_basis.md",
        "topic": "Chromium Blink Percentage Margin Resolves Against Inline Size (core/layout/box_model.cc)",
        "spec": "CSS Box Model 3 §7 (margin-top/bottom percentages resolve against containing block inline width)",
        "prompt": """You are Agent 233 auditing Chromium Blink Percentage Margin vs CSS Box Model 3 §7.
Detail:
1. Basis: margin_block = (cb_inline_size * pct) / 100.
2. Invariants: margin_block monotonic in cb_inline_size, independent of cb_block_size.
3. Concrete Rocq/Coq definitions and theorems for BlinkPercentMarginInlineBasisSemantics.v with 0 admits."""
    },
    {
        "id": "agent234",
        "file": "agent234_fit_content_clamp.md",
        "topic": "Chromium Blink Fit-Content Formula (core/layout/length_utils.cc)",
        "spec": "CSS Sizing 3 §4 (fit-content = max(min_content, min(max_content, available)))",
        "prompt": """You are Agent 234 auditing Chromium Blink Fit-Content Formula vs CSS Sizing 3 §4.
Detail:
1. Formula: fit_content(min_c, max_c, avail) = max(min_c, min(max_c, avail)).
2. Invariants: min_c <= max_c -> min_c <= fit_content <= max_c (when min_c <= avail <= max_c, fit_content = avail).
3. Concrete Rocq/Coq definitions and theorems for BlinkFitContentClampSemantics.v with 0 admits."""
    },
    {
        "id": "agent235",
        "file": "agent235_min_overrides_max_sizing.md",
        "topic": "Chromium Blink Min-Size Overrides Max-Size (core/layout/length_utils.cc)",
        "spec": "CSS 2.1 §10.4 (If min-width > max-width, min-width wins: used = max(min_w, min(max_w, target)))",
        "prompt": """You are Agent 235 auditing Chromium Blink Min-Size Overrides Max-Size vs CSS 2.1 §10.4.
Detail:
1. Formula: used = max(min_w, min(max_w, target)).
2. Invariants: used >= min_w always, even when min_w > max_w.
3. Concrete Rocq/Coq definitions and theorems for BlinkMinOverridesMaxSizingSemantics.v with 0 admits."""
    },
    {
        "id": "agent236",
        "file": "agent236_bfc_margin_isolation.md",
        "topic": "Chromium Blink BFC Root Margin Non-Collapsing (core/layout/block_layout_algorithm.cc)",
        "spec": "CSS 2.1 §8.3.1 (Margins of BFC root do not collapse with its in-flow children)",
        "prompt": """You are Agent 236 auditing Chromium Blink BFC Margin Isolation vs CSS 2.1 §8.3.1.
Detail:
1. Isolation: child top margin stays within BFC root interior, establishing internal cursor start.
2. Invariants: total BFC height contains child top margin without leaking outside.
3. Concrete Rocq/Coq definitions and theorems for BlinkBFCMarginIsolationSemantics.v with 0 admits."""
    },
    {
        "id": "agent237",
        "file": "agent237_negative_margin_algebra.md",
        "topic": "Chromium Blink Negative Margin Collapsing Algebra (core/layout/margin_strut.cc)",
        "spec": "CSS 2.1 §8.3.1 (Collapsed margin is max(pos) + min(neg) where neg <= 0)",
        "prompt": """You are Agent 237 auditing Chromium Blink Negative Margin Algebra vs CSS 2.1 §8.3.1.
Detail:
1. Collapsed sum: sum = pos + neg.
2. Invariants: pos >= 0, neg <= 0 -> neg <= sum <= pos.
3. Concrete Rocq/Coq definitions and theorems for BlinkNegativeMarginAlgebraSemantics.v with 0 admits."""
    },
    {
        "id": "agent238",
        "file": "agent238_overflow_clip_geometry.md",
        "topic": "Chromium Blink Overflow Clip Geometry (core/layout/overflow_model.cc)",
        "spec": "CSS Overflow 3 §3 (Clipped content rect is intersection of content with padding/border box)",
        "prompt": """You are Agent 238 auditing Chromium Blink Overflow Clip Geometry vs CSS Overflow 3 §3.
Detail:
1. Rect intersection: [max(x1, x2), min(r1, r2)].
2. Invariants: intersection rect is contained within clip rect, empty when disjoint.
3. Concrete Rocq/Coq definitions and theorems for BlinkOverflowClipGeometrySemantics.v with 0 admits."""
    },
    {
        "id": "agent239",
        "file": "agent239_box_strut_mapping.md",
        "topic": "Chromium Blink Box Strut Logical to Physical Mapping (core/layout/geometry/box_strut.cc)",
        "spec": "CSS Writing Modes 3 §4 (Logical box strut inline_start/end, block_start/end to physical sides)",
        "prompt": """You are Agent 239 auditing Chromium Blink Box Strut Mapping vs CSS Writing Modes 3 §4.
Detail:
1. Mapping: in horizontal-tb, block_start -> top, block_end -> bottom, inline_start -> left, inline_end -> right.
2. Invariants: sum of physical horizontal sides equals sum of logical inline sides.
3. Concrete Rocq/Coq definitions and theorems for BlinkBoxStrutMappingSemantics.v with 0 admits."""
    },
    {
        "id": "agent240",
        "file": "agent240_indefinite_percent_height.md",
        "topic": "Chromium Blink Indefinite Percentage Height Resolution (core/layout/length_utils.cc)",
        "spec": "CSS 2.1 §10.5 (Percentage height with indefinite containing block height resolves to auto / content height)",
        "prompt": """You are Agent 240 auditing Chromium Blink Indefinite Percentage Height vs CSS 2.1 §10.5.
Detail:
1. Rule: if cb_height == Indefinite, used_height = content_height; else used_height = (cb_height * pct) / 100.
2. Invariants: used_height >= 0 when content_height >= 0, indefinite fallback equals content_height.
3. Concrete Rocq/Coq definitions and theorems for BlinkIndefinitePercentHeightSemantics.v with 0 admits."""
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
    print("Launching Wave 20 (Iteration 5 of 8): 16 concurrent Python3 agents using gemini-4-argon with benchmark-validated optimal Medium thinking budget (2048)...")
    with concurrent.futures.ThreadPoolExecutor(max_workers=16) as executor:
        results = list(executor.map(run_agent, tasks))

    total_p = sum(r.get("prompt_tokens", 0) for r in results)
    total_c = sum(r.get("candidates_tokens", 0) for r in results)
    total_t = sum(r.get("total_tokens", 0) for r in results)

    log_entry = {
        "timestamp": time.strftime("%Y-%m-%d %H:%M:%S"),
        "model": "gemini-4-argon",
        "wave": 20,
        "iteration": 5,
        "theme": "CSS Box Model & Intrinsic Sizing Mechanics (Inline Margin Auto, Self-Collapsing Margin Struts, Border-Box Subtraction, Percent Padding Inline Basis, Min-Content Text Run, Max-Content Soft Hyphen, Replaced Aspect Ratio, Inline-Block Baseline Overflow, Percent Margin Inline Basis, Fit-Content Clamp, Min Overrides Max Sizing, BFC Margin Isolation, Negative Margin Algebra, Overflow Clip Geometry, Box Strut Mapping, Indefinite Percent Height)",
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

    print("\n=== WAVE 20 (ITERATION 5 OF 8) TOKEN USAGE REPORT ===")
    print(f"Prompt Tokens:     {total_p}")
    print(f"Candidate Tokens:  {total_c}")
    print(f"Total Tokens Used: {total_t}")
    print("Appended log entry to token_usage.log.")

