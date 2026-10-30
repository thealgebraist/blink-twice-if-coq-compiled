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
        "id": "agent49",
        "file": "agent49_paint_layer_stacking.md",
        "topic": "Chromium Blink Paint Layer Stacking Order & Tree Walk (third_party/blink/renderer/core/paint/paint_layer.cc and paint_layer_stacking_node.cc)",
        "spec": "CSS 2.1 Appendix E (Elaborate description of Stacking Contexts) & CSS Color 4",
        "prompt": """You are Agent 49 auditing Chromium Blink Paint Layer Stacking Order vs CSS 2.1 Appendix E.
Detail:
1. Core data structures in Blink paint layering (PaintLayer, PaintLayerStackingNode, PaintLayerIterator, StackingContextPhase).
2. The 7-phase stacking context painting order:
   - Phase 1: Background and borders of the element forming the stacking context.
   - Phase 2: Stacking contexts formed by positioned/transformed descendants with negative z-index.
   - Phase 3: Non-positioned in-flow block-level descendants.
   - Phase 4: Non-positioned floating descendants.
   - Phase 5: Normal-flow inline-level descendants.
   - Phase 6: Positioned descendants with z-index: 0 or auto.
   - Phase 7: Positioned descendants with positive z-index sorted in ascending order.
3. Stable sorting of negative and positive z-indices (preserving tree order on ties).
4. Mathematical invariants: the stacking order is a strict weak order, tree order preservation on equal z-index, phase partition disjointness.
5. Provide concrete Rocq/Coq inductive definitions and theorems for formalizing this into BlinkPaintLayerStackingSemantics.v."""
    },
    {
        "id": "agent50",
        "file": "agent50_keyframe_interpolation.md",
        "topic": "Chromium Blink CSS Keyframe Interpolation & Cubic-Bezier Timing Functions (third_party/blink/renderer/core/animation/keyframe_effect_model.cc and platform/animation/timing_function.cc)",
        "spec": "W3C CSS Animations Level 1 (§3 Keyframes) & CSS Transitions Level 1 (§3 Timing Functions)",
        "prompt": """You are Agent 50 auditing Chromium Blink Keyframe Interpolation vs CSS Animations 1 & CSS Transitions 1.
Detail:
1. Core data structures in Blink keyframe animation (KeyframeEffectModel, Keyframe, CubicBezierTimingFunction, InterpolationTime).
2. Keyframe interval discovery: finding keyframes k_i and k_{i+1} enclosing normalized progress t in [0, 1].
3. Local progress parameter calculation: alpha = (t - offset_i) / (offset_{i+1} - offset_i).
4. Cubic-Bezier curve evaluation B(alpha) with control points P0=(0,0), P1=(x1,y1), P2=(x2,y2), P3=(1,1) and linear interpolation lerp(v_start, v_end, p).
5. Mathematical invariants: boundary values B(0)=0 and B(1)=1, lerp convexity (result in [min(a,b), max(a,b)] for alpha in [0,1]), determinism.
6. Provide concrete Rocq/Coq inductive definitions and theorems for formalizing this into BlinkKeyframeInterpolationSemantics.v."""
    },
    {
        "id": "agent51",
        "file": "agent51_column_balancing.md",
        "topic": "Chromium Blink Column Balancing & Target Height Bisection (third_party/blink/renderer/core/layout/fragmentation/column_layout_algorithm.cc)",
        "spec": "W3C CSS Multi-column Layout Module Level 1 (§4 Column Balancing Iterative Solver)",
        "prompt": """You are Agent 51 auditing Chromium Blink Multi-column Column Balancing vs CSS Multicol 1 §4.
Detail:
1. Core data structures in Blink column balancing (ColumnLayoutAlgorithm, ColumnBalancer, MulticolBreakToken).
2. Initial bracket computation: H_min = max(tallest_unbreakable_item, ceil(total_content_height / N_cols)), H_max = total_content_height.
3. Iterative binary search (bisection) simulation: checking if candidate column height H_cand accommodates content within N_cols.
4. Convergence condition: bracket width H_max - H_min <= tolerance (or max iterations reached).
5. Mathematical invariants: H_min <= H_balanced <= H_max, fragmentation count monotonically non-increasing with respect to column height, convergence in O(log(range)) steps.
6. Provide concrete Rocq/Coq inductive definitions and theorems for formalizing this into BlinkColumnBalancingSemantics.v."""
    },
    {
        "id": "agent52",
        "file": "agent52_text_wrap_balance.md",
        "topic": "Chromium Blink Text Wrap Balancing & Line Break Scoring (third_party/blink/renderer/core/layout/inline/text_wrap_evaluator.cc)",
        "spec": "W3C CSS Text Module Level 4 (§5.1 text-wrap: balance & Knuth-Plass Line Breaking Penalty Metric)",
        "prompt": """You are Agent 52 auditing Chromium Blink text-wrap: balance vs CSS Text Level 4 §5.1.
Detail:
1. Core data structures in Blink balanced text wrapping (TextWrapEvaluator, LineBreakCandidate, LineBalanceScore).
2. Balanced line breaking objective: minimizing variance of line lengths sum_{i=1}^M (line_width_i - mean_width)^2.
3. Line partitioning algorithm: distributing glyph clusters/words across M lines such that all line widths <= available_width.
4. Mathematical invariants: total items partitioned equals total input items (partition conservation), non-negativity of score/variance, determinism.
5. Provide concrete Rocq/Coq inductive definitions and theorems for formalizing this into BlinkTextWrapBalanceSemantics.v."""
    },
    {
        "id": "agent53",
        "file": "agent53_svg_viewbox_aspect.md",
        "topic": "Chromium Blink SVG Root Box & ViewBox Aspect Ratio Resolution (third_party/blink/renderer/core/layout/svg/layout_svg_root.cc and svg_preserve_aspect_ratio.cc)",
        "spec": "W3C SVG 2 (§7.7 preserveAspectRatio meet vs slice)",
        "prompt": """You are Agent 53 auditing Chromium Blink SVG viewBox and preserveAspectRatio vs SVG 2 §7.7.
Detail:
1. Core data structures in Blink SVG sizing (LayoutSVGRoot, SVGPreserveAspectRatio, ViewBoxRect, ViewportRect).
2. Uniform scale factor computation:
   - meet: scale = min(viewport_width / vb_width, viewport_height / vb_height).
   - slice: scale = max(viewport_width / vb_width, viewport_height / vb_height).
   - none: non-uniform scales scale_x = viewport_width / vb_width, scale_y = viewport_height / vb_height.
3. Alignment translation offset (xMidYMid, xMinYMin, xMaxYMax).
4. Mathematical invariants: meet scaling ensures fitted viewBox is strictly contained within viewport, slice scaling ensures scaled viewBox covers viewport, determinism.
5. Provide concrete Rocq/Coq inductive definitions and theorems for formalizing this into BlinkSVGViewBoxAspectSemantics.v."""
    },
    {
        "id": "agent54",
        "file": "agent54_transform_affine_matrix.md",
        "topic": "Chromium Blink CSS 2D Affine Transformation Matrix Algebra (third_party/blink/renderer/platform/transforms/affine_transform.cc)",
        "spec": "W3C CSS Transforms Module Level 1 (§5 The Transform Matrix & §6 2D Transformation Matrix Operations)",
        "prompt": """You are Agent 54 auditing Chromium Blink 2D Affine Transform Matrix vs CSS Transforms Level 1.
Detail:
1. Core data structures in Blink transforms (AffineTransform: [a, b, c, d, e, f] representing [[a, c, e], [b, d, f], [0, 0, 1]]).
2. Basic operations: Identity, Translation(tx, ty), Scale(sx, sy), Matrix Multiplication (composition), Point mapping (x' = ax + cy + e, y' = bx + dy + f).
3. Determinant computation: det = ad - bc. Invertibility criterion (det != 0).
4. Mathematical invariants: identity is neutral under multiplication, matrix multiplication is associative, determinant multiplicativity det(M1 * M2) = det(M1) * det(M2).
5. Provide concrete Rocq/Coq inductive definitions and theorems for formalizing this into BlinkTransformMatrixSemantics.v."""
    },
    {
        "id": "agent55",
        "file": "agent55_percentage_resolution.md",
        "topic": "Chromium Blink Percentage Logical Height & Indefinite Sizing Resolution (third_party/blink/renderer/core/layout/layout_box.cc ComputePercentageLogicalHeight)",
        "spec": "W3C CSS Box Sizing Module Level 3 (§5.2 Resolving Percentage Values in Indefinite Containing Blocks)",
        "prompt": """You are Agent 55 auditing Chromium Blink Percentage Height Resolution vs CSS Box Sizing Level 3 §5.2.
Detail:
1. Core data structures in Blink percentage sizing (LayoutBox, ConstraintSpace, PercentageResolutionType).
2. Definite vs Indefinite containing block rule:
   - If containing block height is indefinite (auto) and child is not out-of-flow / flex-item / grid-item, percentage height resolves to auto (treated as content-based).
   - If containing block height is definite (H_cb), percentage resolves to round(H_cb * percentage / 100).
3. Clamping with min-height and max-height constraints.
4. Mathematical invariants: indefinite basis yields indefinite result, definite basis yields monotonic scaling with respect to percentage, determinism.
5. Provide concrete Rocq/Coq inductive definitions and theorems for formalizing this into BlinkPercentageResolutionSemantics.v."""
    },
    {
        "id": "agent56",
        "file": "agent56_sticky_positioning.md",
        "topic": "Chromium Blink Sticky Positioning Constraints & Scroll Range Clamping (third_party/blink/renderer/core/layout/sticky_position_scroller_data.cc and layout_box_model_object.cc)",
        "spec": "W3C CSS Positioned Layout Module Level 3 (§6 Sticky Positioning)",
        "prompt": """You are Agent 56 auditing Chromium Blink Sticky Positioning vs CSS Position Level 3 §6.
Detail:
1. Core data structures in Blink sticky positioning (StickyPositionOffsetData, ScrollerOffsets, ContainingBlockConstraints).
2. Sticky 1D offset computation: offset = clamp(0, scroll_offset - static_position, cb_extent - box_extent).
3. Boundary constraints: item remains within its containing block rect and viewport scroll boundaries.
4. Mathematical invariants: sticky offset is non-negative, sticky offset is bounded by available containment space, determinism.
5. Provide concrete Rocq/Coq inductive definitions and theorems for formalizing this into BlinkStickyPositionSemantics.v."""
    },
    {
        "id": "agent57",
        "file": "agent57_canvas_backing_store.md",
        "topic": "Chromium Blink HTML Canvas Backing Store Layout & DPR Buffer Sizing (third_party/blink/renderer/core/html/canvas/canvas_rendering_context_host.cc)",
        "spec": "HTML Living Standard (§4.12.5 The canvas element & CSSOM View Device Pixel Ratio Scaling)",
        "prompt": """You are Agent 57 auditing Chromium Blink Canvas Backing Store Layout vs HTML Living Standard §4.12.5.
Detail:
1. Core data structures in Blink canvas sizing (HTMLCanvasElement, CanvasRenderingContextHost, IntSize: width, height).
2. Coordinate space (bitmap dimensions) vs CSS layout dimensions:
   - Layout size from CSS box model (specified width/height or default 300x150).
   - Buffer size = floor(css_size * device_pixel_ratio), clamped by max_texture_dimension (e.g. 16384).
3. Aspect ratio preservation when auto dimensions are derived from canvas intrinsic buffer size.
4. Mathematical invariants: buffer dimensions non-negative, buffer dimensions <= max_texture_dimension, DPR scaling monotonicity.
5. Provide concrete Rocq/Coq inductive definitions and theorems for formalizing this into BlinkCanvasBackingStoreSemantics.v."""
    },
    {
        "id": "agent58",
        "file": "agent58_css_math_calc.md",
        "topic": "Chromium Blink CSS Math Expression AST Simplification & Clamping (third_party/blink/renderer/core/css/css_math_expression_node.cc)",
        "spec": "W3C CSS Values and Units Module Level 4 (§10.2 & §10.3 Mathematical Expressions: calc(), min(), max(), clamp())",
        "prompt": """You are Agent 58 auditing Chromium Blink CSS Math calc/min/max/clamp vs CSS Values Level 4 §10.2 & §10.3.
Detail:
1. Core data structures in Blink math expressions (CSSMathExpressionNode, CSSMathExpressionNumericLiteral, CSSMathExpressionOperation: Add, Subtract, Multiply, Divide, Min, Max).
2. clamp(min_val, val, max_val) definition and normalization: max(min_val, min(val, max_val)).
3. Evaluation algebra: constant folding, associativity of addition/multiplication, distributive laws.
4. Mathematical invariants: clamp bounds satisfaction (min_val <= max_val implies min_val <= clamp <= max_val), clamp idempotence, determinism.
5. Provide concrete Rocq/Coq inductive definitions and theorems for formalizing this into BlinkCSSMathCalcSemantics.v."""
    },
    {
        "id": "agent59",
        "file": "agent59_scrollbar_gutter.md",
        "topic": "Chromium Blink CSS Scrollbar Gutter & Width Reservation (third_party/blink/renderer/core/layout/scrollbars.cc and layout_box.cc)",
        "spec": "W3C CSS Scrollbars Module Level 1 (§2 scrollbar-gutter & scrollbar-width)",
        "prompt": """You are Agent 59 auditing Chromium Blink Scrollbar Gutter Reservation vs CSS Scrollbars Level 1.
Detail:
1. Core data structures in Blink scrollbars (NGBoxStrut, ScrollbarGutter, ScrollbarWidth: Auto, Thin, None).
2. Reserved gutter width computation:
   - scrollbar-width: none -> 0px; thin -> thin_width (e.g., 8px); auto -> default_width (e.g., 16px).
   - scrollbar-gutter: auto (reserved only when scrolling active), stable (always reserved on end side), both-edges (reserved on both start and end sides).
3. Impact on available content inline size: W_content = max(0, W_box - (padding + border + reserved_gutters)).
4. Mathematical invariants: reserved gutter non-negative, W_content <= W_box, determinism.
5. Provide concrete Rocq/Coq inductive definitions and theorems for formalizing this into BlinkScrollbarGutterSemantics.v."""
    },
    {
        "id": "agent60",
        "file": "agent60_bidi_run_reversal.md",
        "topic": "Chromium Blink Inline Bidi Reordering & Contiguous Run Reversal (third_party/blink/renderer/platform/text/bidi_resolver.h and core/layout/inline/bidi_paragraph.cc)",
        "spec": "Unicode Standard Annex #9 (UAX #9 §3.4 L2 Rule: Run Reversal) & CSS Writing Modes Level 3",
        "prompt": """You are Agent 60 auditing Chromium Blink Bidi Paragraph Run Reversal vs Unicode UAX #9 L2.
Detail:
1. Core data structures in Blink bidi resolution (BidiParagraph, BidiRun, Direction: LTR, RTL, EmbeddingLevel: 0 to 125).
2. The L2 rule algorithm:
   - Determine max level in paragraph.
   - For level L from max down to lowest odd level: identify contiguous runs with level >= L and reverse their order in place.
3. Mathematical invariants: list length conservation (no items added/removed), run reversal is an involution on each contiguous segment (rev(rev(s)) = s), multiset element conservation (permutation), determinism.
4. Provide concrete Rocq/Coq inductive definitions and theorems for formalizing this into BlinkBidiRunReversalSemantics.v."""
    },
    {
        "id": "agent61",
        "file": "agent61_list_marker_placement.md",
        "topic": "Chromium Blink List Marker Positioning (Inside vs Outside) (third_party/blink/renderer/core/layout/list/layout_inline_list_item.cc and list_marker.cc)",
        "spec": "W3C CSS Lists and Counters Module Level 3 (§3 Markers: list-style-position inside/outside)",
        "prompt": """You are Agent 61 auditing Chromium Blink List Marker Layout vs CSS Lists Level 3 §3.
Detail:
1. Core data structures in Blink list markers (LayoutInlineListItem, ListMarker, EListStylePosition: Inside, Outside).
2. Layout positions:
   - Inside: marker is placed as an inline box at the beginning of the first line box; increases line box content width.
   - Outside: marker is placed in the line margin / gutter at negative inline offset - (marker_width + suffix_spacing); does not increase line box width.
3. Mathematical invariants: inside marker increases line advance by exact (w_marker + spacing), outside marker leaves line content width unchanged, determinism.
4. Provide concrete Rocq/Coq inductive definitions and theorems for formalizing this into BlinkListMarkerPlacementSemantics.v."""
    },
    {
        "id": "agent62",
        "file": "agent62_break_token_appeal.md",
        "topic": "Chromium Blink Multi-Column Fragmentation Break Tokens & Appeal (third_party/blink/renderer/core/layout/fragmentation/break_token.cc and break_appeal.cc)",
        "spec": "W3C CSS Fragmentation Module Level 3 (§4 Fragmenting Elements: Break Tokens & Break Appeal)",
        "prompt": """You are Agent 62 auditing Chromium Blink Fragmentation Break Tokens vs CSS Fragmentation Level 3 §4.
Detail:
1. Core data structures in Blink fragmentation tokens (BreakToken, BlockBreakToken, BreakAppeal: kBreakAppealLastResort < kBreakAppealViolatesOrphanWidow < kBreakAppealNone < kBreakAppealPerfect).
2. Consumed block size tracking and sequence chaining across fragments: fragment 1 consumes h1, fragment 2 resumes at offset h1 and consumes h2.
3. Break appeal total ordering: choosing optimal break points during column or page fragmentation.
4. Mathematical invariants: consumed block size monotonic accumulation sum_{i=1}^k h_i <= H_total, break appeal is a total order with transitivity and antisymmetry, determinism.
5. Provide concrete Rocq/Coq inductive definitions and theorems for formalizing this into BlinkBreakTokenAppealSemantics.v."""
    },
    {
        "id": "agent63",
        "file": "agent63_ellipsis_truncation.md",
        "topic": "Chromium Blink Inline Box Text Overflow & Ellipsis Truncation (third_party/blink/renderer/core/layout/inline/inline_layout_algorithm.cc TruncateLine)",
        "spec": "W3C CSS Overflow Module Level 3 (§3.1 text-overflow: ellipsis & Line Truncation Walk)",
        "prompt": """You are Agent 63 auditing Chromium Blink Text Truncation vs CSS Overflow Level 3 §3.1.
Detail:
1. Core data structures in Blink text truncation (InlineLayoutAlgorithm, LineTruncator, EllipsisItem, TruncationState).
2. Truncation algorithm: given line of items with total width > available_width, walk backwards from end to find truncation point where remaining_items_width + ellipsis_width <= available_width.
3. Edge case: if even 1 item + ellipsis does not fit, keep first character or clip cleanly.
4. Mathematical invariants: final line visual width <= available_width (when available_width >= ellipsis_width), truncated items count <= original items count, determinism.
5. Provide concrete Rocq/Coq inductive definitions and theorems for formalizing this into BlinkEllipsisTruncationSemantics.v."""
    },
    {
        "id": "agent64",
        "file": "agent64_shape_outside_polygon.md",
        "topic": "Chromium Blink CSS Shapes Polygon Ray-Scanbeam Intersection (third_party/blink/renderer/core/layout/shapes/polygon_shape.cc)",
        "spec": "W3C CSS Shapes Module Level 1 (§3 Basic Shapes: polygon(...) and Horizontal Scanbeam Slicing)",
        "prompt": """You are Agent 64 auditing Chromium Blink Polygon Shape Exclusion vs CSS Shapes Level 1 §3.
Detail:
1. Core data structures in Blink shape outside (PolygonShape, Segment2D, ShapeInterval, FloatPoint).
2. Scanbeam horizontal line intersection: at vertical coordinate y in [line_top, line_bottom], find all segment intersection x-coordinates, sort them, and pair them to obtain exclusion intervals.
3. Exclusion interval calculation for float placement around the polygon.
4. Mathematical invariants: interval [x_start, x_end] satisfies x_start <= x_end, empty intervals outside polygon bounding box [y_min, y_max], determinism.
5. Provide concrete Rocq/Coq inductive definitions and theorems for formalizing this into BlinkShapePolygonSemantics.v."""
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
    print("Launching Wave 10: 16 concurrent Python3 agents using gemini-4-argon (thinking budget 1024) across Central Blink Areas...")
    with concurrent.futures.ThreadPoolExecutor(max_workers=16) as executor:
        results = list(executor.map(run_agent, tasks))

    total_p = sum(r.get("prompt_tokens", 0) for r in results)
    total_c = sum(r.get("candidates_tokens", 0) for r in results)
    total_t = sum(r.get("total_tokens", 0) for r in results)

    log_entry = {
        "timestamp": time.strftime("%Y-%m-%d %H:%M:%S"),
        "model": "gemini-4-argon",
        "wave": 10,
        "theme": "16 Central Engine Areas (Paint Stacking, Keyframe Interpolation, Column Balancing, Text Wrap Balance, SVG ViewBox Aspect, Affine Transform Matrix, Percentage Resolution, Sticky Positioning, Canvas Backing Store, CSS Math Calc, Scrollbar Gutter, Bidi Run Reversal, List Marker Placement, Break Token Appeal, Ellipsis Truncation, Shape Outside Polygon)",
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

    print("\n=== WAVE 10 (16 AGENTS: CENTRAL BLINK AREAS) TOKEN USAGE REPORT ===")
    print(f"Prompt Tokens:     {total_p}")
    print(f"Candidate Tokens:  {total_c}")
    print(f"Total Tokens Used: {total_t}")
    print("Appended log entry to token_usage.log.")

