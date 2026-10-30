import os
import concurrent.futures
from google import genai
from google.genai import types

api_key = open('key.txt').read().strip()
client = genai.Client(api_key=api_key)

tasks = [
    {
        "id": "agent1",
        "file": "agent1_table_layout.md",
        "topic": "Chromium Blink Table Layout (third_party/blink/renderer/core/layout/table/table_layout_algorithm.cc and table_column_location.h)",
        "spec": "W3C CSS 2.1 Section 17.5 (Table Layout Algorithm: Fixed vs Auto Table Layout, Column Widths Distribution, Cell Colspan/Rowspan, Baseline Alignment)",
        "prompt": """You are Agent 1 auditing Chromium Blink Table Layout vs W3C CSS 2.1 Section 17.5.
Detail:
1. Core data structures in Blink table layout (TableGroupedChildren, TableSection, TableRow, TableCell, TableColumnLocation).
2. Algorithm for fixed table layout vs auto table layout (first row determining column widths vs multi-pass max/min-content distribution).
3. Colspan extra space distribution across spanned columns (similarities/differences to Grid track sizing).
4. Vertical alignment in table cells (baseline, top, middle, bottom) and baseline alignment across rows.
5. Mathematical formulas, invariants (monotonic column positions, non-negative widths), edge cases, and gaps between Blink and W3C CSS 2.1 Section 17.5.
6. Provide concrete Rocq/Coq inductive definitions and theorems for formalizing this into BlinkTableLayoutSemantics.v."""
    },
    {
        "id": "agent2",
        "file": "agent2_fragmentation.md",
        "topic": "Chromium Blink Multicol & Pagination Fragmentation (third_party/blink/renderer/core/layout/fragmentation/ng_fragmentation_utils.cc and block_break_token.h)",
        "spec": "W3C CSS Fragmentation Module Level 3 (Section 3: Breaking into Fragmentainers, Section 4: Break Points, Section 5: Between-Box Breaks & Margin Truncation)",
        "prompt": """You are Agent 2 auditing Chromium Blink Multicol & Pagination Fragmentation vs W3C CSS Fragmentation Module Level 3.
Detail:
1. Core data structures in Blink LayoutNG fragmentation (BlockBreakToken, BreakToken, Fragmentainer, PhysicalFragment with break tokens).
2. Fragmentainer sizing, consumed block size accumulation, and remaining block space calculation.
3. Forced breaks (break-before/after: page, column, avoid) vs unforced breaks (fitting content before fragmentainer edge).
4. Margin truncation at break boundaries: how Blink discards margins adjacent to fragmentainer breaks (MarginStrut::discard_margins).
5. Mathematical formulas, invariants (progress guarantee: each fragmentainer consumes > 0 content unless forced empty break, total block size conservation), edge cases, and gaps between Blink and W3C CSS Fragmentation Level 3.
6. Provide concrete Rocq/Coq inductive definitions and theorems for formalizing this into BlinkFragmentationSemantics.v."""
    },
    {
        "id": "agent3",
        "file": "agent3_svg_sizing.md",
        "topic": "Chromium Blink SVG Root & ViewBox Sizing (third_party/blink/renderer/core/layout/svg/layout_svg_root.cc and svg_length_context.cc)",
        "spec": "W3C SVG 2 Section 7.7 (The 'preserveAspectRatio' Attribute: meet, slice, none, align X/Y min/mid/max) and SVG 2 Section 7.12 (Sizing SVG Content in CSS Box Model)",
        "prompt": """You are Agent 3 auditing Chromium Blink SVG Layout vs W3C SVG 2 Section 7.7 and Section 7.12.
Detail:
1. Core data structures in Blink SVG layout (LayoutSVGRoot, SVGViewBox, SVGPreserveAspectRatio).
2. Sizing calculation: intrinsic dimensions (width, height, viewBox) vs CSS specified width/height under CSS Sizing 3.
3. preserveAspectRatio mathematical mapping: scale factors (scale_x = container_w / vb_w, scale_y = container_h / vb_h).
   - 'none': non-uniform scale (scale_x, scale_y).
   - 'meet': scale = min(scale_x, scale_y).
   - 'slice': scale = max(scale_x, scale_y).
   - alignment offsets for XMin, XMid, XMax and YMin, YMid, YMax.
4. Physical viewport clipping and transformed bounding rect calculation.
5. Invariants (non-negative scaling, bounding box containment, determinism), edge cases (zero or negative viewBox dimensions), and gaps between Blink and W3C SVG 2.
6. Provide concrete Rocq/Coq inductive definitions and theorems for formalizing this into BlinkSVGSizingSemantics.v."""
    },
    {
        "id": "agent4",
        "file": "agent4_css_math.md",
        "topic": "Chromium Blink CSS Math Expressions (third_party/blink/renderer/core/css/css_math_expression_node.cc and css_math_operator.h)",
        "spec": "W3C CSS Values and Units Module Level 4 (Section 10: Mathematical Expressions: calc(), min(), max(), clamp(), round(), mod(), rem())",
        "prompt": """You are Agent 4 auditing Chromium Blink CSS Math Expressions vs W3C CSS Values and Units Level 4 Section 10.
Detail:
1. Core AST data structures in Blink CSS math (CSSMathExpressionNode: NumericLiteral, Operation, Anchor, Negation).
2. Supported operators: Add, Subtract, Multiply, Divide, Min, Max, Clamp, Mod, Rem, RoundDown, RoundUp, RoundToZero.
3. Unit resolution, type category calculus (Length, Angle, Time, Frequency, Resolution, Number, Percent), and dimension checking rules.
4. Evaluation mechanics: double/fixed-point evaluation with CSSLengthResolver, division by zero handling, infinity/NaN saturation to LayoutUnit min/max.
5. Simplification rules (constant folding, algebraic rewrites like calc(10px + 20px) -> 30px, clamp(min, val, max) -> max(min, min(val, max))).
6. Invariants (type preservation, monotonicity, idempotence of clamp/min/max), edge cases, and gaps between Blink and W3C CSS Values 4.
7. Provide concrete Rocq/Coq inductive definitions and theorems for formalizing this into BlinkCSSMathSemantics.v."""
    }
]

def run_agent(task):
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
        content = response.text
        with open(task['file'], 'w') as f:
            f.write(content)
        print(f"[{task['id']}] Successfully completed! Wrote {task['file']} ({len(content)} chars)")
        return (task['id'], True, len(content))
    except Exception as e:
        print(f"[{task['id']}] Failed: {e}")
        return (task['id'], False, str(e))

print("Launching 4 concurrent Python3 agents using gemini-4-argon (thinking budget 1024)...")
with concurrent.futures.ThreadPoolExecutor(max_workers=4) as executor:
    results = list(executor.map(run_agent, tasks))

print("All 4 agents completed execution:")
for r in results:
    print(f" - {r[0]}: success={r[1]}, size/err={r[2]}")
