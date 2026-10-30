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
        "id": "agent9",
        "file": "agent9_svg_text.md",
        "topic": "Chromium Blink SVG Text Layout (third_party/blink/renderer/core/layout/svg/layout_svg_text.cc and svg_text_layout_algorithm.cc)",
        "spec": "W3C SVG 2 (§11.4 Text Layout Algorithm, SVG Text Chunks, Glyph Positioning)",
        "prompt": """You are Agent 9 auditing Chromium Blink SVG Text Chunk Layout vs W3C SVG 2 §11.4.
Detail:
1. Core data structures in Blink SVG text (LayoutSVGText, SVGTextLayoutAlgorithm, SVGInlineNode, SVGTextFragment, SVGTextChunk).
2. SVG text chunk building and glyph positioning algorithm (handling x, y, dx, dy attribute lists, text-anchor: start/middle/end adjustments).
3. Text chunk bi-directional reordering and anchor offset shifts.
4. Mathematical invariants (chunk length conservation, glyph coordinate monotonicity along advance axis, non-negative glyph advances), edge cases, and gaps between Blink and SVG 2 §11.4.
5. Provide concrete Rocq/Coq inductive definitions and theorems for formalizing this into BlinkSVGTextSemantics.v."""
    },
    {
        "id": "agent10",
        "file": "agent10_form_control.md",
        "topic": "Chromium Blink Form Control Baseline Overrides (third_party/blink/renderer/core/layout/forms/layout_text_control.cc and layout_text_control_single_line.cc)",
        "spec": "HTML Standard (§4.10 Form Controls, §15 Rendering: Form controls layout and baseline synthesis)",
        "prompt": """You are Agent 10 auditing Chromium Blink Form Control Baselines vs HTML Standard §4.10 & CSS Box Alignment 3.
Detail:
1. Core data structures in Blink form control layout (LayoutTextControl, LayoutTextControlSingleLine, TextControlInnerEditor).
2. Intrinsic baseline calculation algorithm: single-line text inputs, textarea baseline synthesis (first line baseline vs bottom margin edge fallback).
3. Padding, border, and scrollable inner-editor offset interactions on baseline position.
4. Mathematical invariants (baseline boundedness within border-box, deterministic baseline calculation, monotonicity with respect to inner font ascent), edge cases, and gaps.
5. Provide concrete Rocq/Coq inductive definitions and theorems for formalizing this into BlinkFormControlSemantics.v."""
    },
    {
        "id": "agent11",
        "file": "agent11_calc_size.md",
        "topic": "Chromium Blink CSS Calc-Size & Progress Functions (third_party/blink/renderer/core/css/css_math_expression_node.cc and css_calc_symbol_token.cc)",
        "spec": "W3C CSS Values and Units Module Level 4 (§10.1 The calc-size() Function, §10.6 progress(), mix())",
        "prompt": """You are Agent 11 auditing Chromium Blink CSS calc-size() and progress() vs W3C CSS Values and Units Level 4.
Detail:
1. Core data structures in Blink CSS math extensions (CSSMathExpressionCalcSizeNode, CSSMathExpressionProgressNode, CSSCalcSymbolToken).
2. Calculation and evaluation semantics: calc-size(basis, calculation) where basis can be 'any', 'auto', 'min-content', 'max-content', 'fit-content'; progress(val from A to B) = (val - A) / (B - A).
3. Division by zero and NaN/Infinity clamping in progress expressions.
4. Mathematical invariants (progress monotonicity, calc-size basis substitution soundness, boundedness under defined ranges), edge cases, and gaps.
5. Provide concrete Rocq/Coq inductive definitions and theorems for formalizing this into BlinkCalcSizeProgressSemantics.v."""
    },
    {
        "id": "agent12",
        "file": "agent12_grid_placement.md",
        "topic": "Chromium Blink Grid Item Placement (third_party/blink/renderer/core/layout/grid/grid_placement.cc and grid_line_resolver.cc)",
        "spec": "W3C CSS Grid Layout Module Level 1 (§8 Placing Grid Items, §8.3 Line-based Placement, §8.5 Automatic Placement)",
        "prompt": """You are Agent 12 auditing Chromium Blink CSS Grid Placement vs W3C CSS Grid Layout Level 1 §8.
Detail:
1. Core data structures in Blink grid item placement (GridPlacement, GridPlacementData, GridLineResolver, GridSpan).
2. Grid item placement algorithm: explicit placement (named lines, integer indices, span) followed by auto-placement cursor progression (sparse vs dense packing).
3. Line resolution and negative index normalization (-1 is the trailing explicit grid line).
4. Mathematical invariants (span strictly positive, normalized line indices within clamped bounds, placement determinism), edge cases, and gaps.
5. Provide concrete Rocq/Coq inductive definitions and theorems for formalizing this into BlinkGridPlacementSemantics.v."""
    },
    {
        "id": "agent13",
        "file": "agent13_view_transition.md",
        "topic": "Chromium Blink View Transition Layout (third_party/blink/renderer/core/layout/view_transition_layout_algorithm.cc)",
        "spec": "W3C CSS View Transitions Module Level 1 (§3 Layout of View Transition Pseudo-elements, Snapshot Sizing)",
        "prompt": """You are Agent 13 auditing Chromium Blink View Transition Layout vs W3C CSS View Transitions Level 1.
Detail:
1. Core data structures in Blink view transition layout (ViewTransitionLayoutAlgorithm, ViewTransitionStyleTracker, ::view-transition-group, ::view-transition-image-pair).
2. Layout sizing and positioning algorithm: snapshot intrinsic size preservation, transform matrix computation, aspect-ratio preserving fit.
3. Containing block override and root pseudo-element viewport projection.
4. Mathematical invariants (snapshot aspect ratio preservation, non-negative fragment dimensions, transform continuity), edge cases, and gaps.
5. Provide concrete Rocq/Coq inductive definitions and theorems for formalizing this into BlinkViewTransitionSemantics.v."""
    },
    {
        "id": "agent14",
        "file": "agent14_flex_order.md",
        "topic": "Chromium Blink Flex Child Order Iteration (third_party/blink/renderer/core/layout/flex/flex_child_iterator.cc)",
        "spec": "W3C CSS Flexible Box Layout Module Level 1 (§5.4 Display Order: the order property)",
        "prompt": """You are Agent 14 auditing Chromium Blink Flex Order Iteration vs W3C CSS Flexible Box Layout Level 1 §5.4.
Detail:
1. Core data structures in Blink flex child ordering (FlexChildIterator, FlexItem, LayoutInputNode, 'order' property integer).
2. Sorting algorithm: stable sort based on (order, original_index) tuple.
3. Iterator traversal semantics during flex line generation.
4. Mathematical invariants (strict monotonicity of iterated items, stability: items with equal order retain document order, permutation preservation: all input items are visited exactly once), edge cases, and gaps.
5. Provide concrete Rocq/Coq inductive definitions and theorems for formalizing this into BlinkFlexOrderSemantics.v."""
    },
    {
        "id": "agent15",
        "file": "agent15_table_borders.md",
        "topic": "Chromium Blink Collapsed Table Borders (third_party/blink/renderer/core/layout/table/table_borders.cc)",
        "spec": "W3C CSS 2.1 (§17.6.2 The border-conflict resolution algorithm in collapsing borders model)",
        "prompt": """You are Agent 15 auditing Chromium Blink Table Border Collapsing vs W3C CSS 2.1 §17.6.2.
Detail:
1. Core data structures in Blink collapsed table borders (TableBorders, TableBorderEdge, BorderConflictResolution).
2. Conflict resolution priority rules: border-style: hidden wins over all; thicker border wins; style priority: double > solid > dashed > dotted > ridge > outset > groove > inset; origin precedence: cell > row > row_group > col > col_group > table.
3. Border width half-distribution between adjacent cells.
4. Mathematical invariants (conflict resolution total ordering, symmetry across cell boundaries, non-negative resolved border width), edge cases, and gaps.
5. Provide concrete Rocq/Coq inductive definitions and theorems for formalizing this into BlinkTableBorderCollapseSemantics.v."""
    },
    {
        "id": "agent16",
        "file": "agent16_min_max_sizes.md",
        "topic": "Chromium Blink Intrinsic Min/Max Sizes (third_party/blink/renderer/core/layout/min_max_sizes.cc)",
        "spec": "W3C CSS Box Sizing Module Level 3 (§5 Intrinsic Size Contributions: min-content, max-content, min/max clamping)",
        "prompt": """You are Agent 16 auditing Chromium Blink MinMaxSizes vs W3C CSS Box Sizing Level 3 §5.
Detail:
1. Core data structures in Blink intrinsic sizing (MinMaxSizes, MinMaxSizesResult, MinMaxSizesType: kContent, kIntrinsic).
2. Operations on MinMaxSizes: Add(), Encompass(), ShrinkTo(), ClampSizeToMinAndMax().
3. Invariant enforcement: min_size <= max_size, and behavior when CSS min-width > max-width.
4. Mathematical invariants (lattice ordering: Encompass is commutative and associative join, min <= max monotonicity preservation, non-negativity), edge cases, and gaps.
5. Provide concrete Rocq/Coq inductive definitions and theorems for formalizing this into BlinkMinMaxSizesSemantics.v."""
    }
]

def run_agent(task):
    t0 = time.time()
    print(f"[{task['id']}] Starting query for {task['topic']}...")
    try:
        response = client.models.generate_content(
            model='gemini-4-argon',
            contents=task['prompt'],
            config=types.GenerateContentConfig(
                thinking_config=types.ThinkingConfig(thinking_budget=1024),
                max_output_tokens=3500
            )
        )
        t1 = time.time()
        content = response.text
        with open(task['file'], 'w') as f:
            f.write(content)
        
        usage = response.usage_metadata
        prompt_tokens = usage.prompt_token_count if usage else 0
        candidates_tokens = usage.candidates_token_count if usage else 0
        total_tokens = usage.total_token_count if usage else 0
        
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
    print("Launching Wave 6: 8 concurrent Python3 agents using gemini-4-argon (thinking budget 1024)...")
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as executor:
        results = list(executor.map(run_agent, tasks))

    total_p = sum(r.get("prompt_tokens", 0) for r in results)
    total_c = sum(r.get("candidates_tokens", 0) for r in results)
    total_t = sum(r.get("total_tokens", 0) for r in results)

    log_entry = {
        "timestamp": time.strftime("%Y-%m-%d %H:%M:%S"),
        "model": "gemini-4-argon",
        "wave": 6,
        "thinking_budget": 1024,
        "agents": results,
        "aggregate": {
            "prompt_tokens": total_p,
            "candidates_tokens": total_c,
            "total_tokens": total_t
        }
    }

    with open("token_usage.log", "a") as f:
        f.write(json.dumps(log_entry, indent=2) + "\n---\n")

    print("\n=== WAVE 6 (8 AGENTS) TOKEN USAGE REPORT ===")
    print(f"Prompt Tokens:     {total_p}")
    print(f"Candidate Tokens:  {total_c}")
    print(f"Total Tokens Used: {total_t}")
    print("Appended log entry to token_usage.log.")

