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
        "id": "agent65",
        "file": "agent65_view_transitions.md",
        "topic": "Chromium Blink CSS View Transitions Geometry & Snapshot Quad Mapping (third_party/blink/renderer/core/view_transition/view_transition_style_tracker.cc)",
        "spec": "W3C CSS View Transitions Module Level 1 (§3 Capturing Snapshots & Geometry Transformations)",
        "prompt": """You are Agent 65 auditing Chromium Blink CSS View Transitions vs CSS View Transitions Level 1.
Detail:
1. Core data structures in Blink view transitions (ViewTransitionStyleTracker, ViewTransitionTransitionState, SnapshotQuad, ViewTransitionElement).
2. Snapshot geometry capture: recording old and new border-box rects in document space, computing delta affine transforms between old and new state.
3. Layer group transformation: interpolating position, size, and transform matrix across transition progress t in [0, 1].
4. Mathematical invariants: bounding rect non-negativity, interpolation boundary preservation (at t=0 matches old rect, at t=1 matches new rect), determinism.
5. Provide concrete Rocq/Coq inductive definitions and theorems for formalizing this into BlinkViewTransitionSnapshotSemantics.v."""
    },
    {
        "id": "agent66",
        "file": "agent66_sticky_multiaxis.md",
        "topic": "Chromium Blink 2D Multi-Axis Sticky Positioning (third_party/blink/renderer/core/layout/sticky_position_scroller_data.cc and logical_rect.h)",
        "spec": "W3C CSS Positioned Layout Module Level 3 (§6.3 Multi-axis Sticky Positioning: Simultaneous Inline & Block Insets)",
        "prompt": """You are Agent 66 auditing Chromium Blink Multi-Axis Sticky Positioning vs CSS Position Level 3 §6.3.
Detail:
1. Core data structures in Blink 2D sticky positioning (StickyPositionOffsetData, PhysicalOffset, LogicalRect, ScrollRange2D).
2. 2D offset computation: independent inline and block shift evaluations clamped by their respective containing block rectangular extents.
3. Handling conflicting constraints (both left & right, or both top & bottom specified): top/left win in default writing modes / LTR.
4. Mathematical invariants: 2D offset is contained within containing block bounds rect, idempotence, determinism.
5. Provide concrete Rocq/Coq inductive definitions and theorems for formalizing this into BlinkStickyMultiAxisSemantics.v."""
    },
    {
        "id": "agent67",
        "file": "agent67_inline_box_tree.md",
        "topic": "Chromium Blink Inline Box Tree Assembly & Atomic Inline Segmentation (third_party/blink/renderer/core/layout/inline/inline_box_state.cc and line_info.cc)",
        "spec": "W3C CSS Inline Layout Module Level 3 (§3 Inline Box Formatting Context Tree Generation)",
        "prompt": """You are Agent 67 auditing Chromium Blink Inline Box Tree Generation vs CSS Inline Level 3 §3.
Detail:
1. Core data structures in Blink inline formatting (InlineBoxState, InlineItem, LineInfo, LogicalLineItem).
2. Stack-based inline box hierarchy management: pushing/popping inline open/close tags, tracking cumulative margins, padding, and borders across line breaks.
3. Atomic inline box integration (inline-block, replaced elements) into the line box text run stream.
4. Mathematical invariants: stack balancedness (every push has matching pop), advance monotonicity, determinism.
5. Provide concrete Rocq/Coq inductive definitions and theorems for formalizing this into BlinkInlineBoxTreeSemantics.v."""
    },
    {
        "id": "agent68",
        "file": "agent68_aspect_ratio_transfer.md",
        "topic": "Chromium Blink CSS aspect-ratio Property & Automatic Dimension Transfer (third_party/blink/renderer/core/layout/aspect_ratio.cc and length_utils.cc)",
        "spec": "W3C CSS Box Sizing Module Level 4 (§2 & §3 The aspect-ratio Property and Intrinsic Size Transfer)",
        "prompt": """You are Agent 68 auditing Chromium Blink CSS aspect-ratio Property vs CSS Box Sizing Level 4.
Detail:
1. Core data structures in Blink aspect-ratio (LogicalAspectRatio: width, height, EAspectRatioType: Auto, Ratio, AutoAndRatio).
2. Dimension transfer algorithm: resolving inline size to block size via ratio = W/H (block = inline / ratio = inline * H / W), and vice versa.
3. Interaction with min/max sizing constraints: min overrides max, unconstrained dimension stretches to satisfy aspect ratio.
4. Mathematical invariants: ratio transfer involution (transferring back yields original size up to integer division), non-negativity, determinism.
5. Provide concrete Rocq/Coq inductive definitions and theorems for formalizing this into BlinkAspectRatioTransferSemantics.v."""
    },
    {
        "id": "agent69",
        "file": "agent69_grid_masonry_2d.md",
        "topic": "Chromium Blink Grid Masonry 2D Auto-Placement & Definite Tracks (third_party/blink/renderer/core/layout/grid/masonry_layout_algorithm.cc)",
        "spec": "W3C CSS Grid 3 / Masonry Layout Module (§2 Masonry Axis & Grid Axis Auto-Placement)",
        "prompt": """You are Agent 69 auditing Chromium Blink Grid Masonry 2D Placement vs CSS Masonry Layout Level 3.
Detail:
1. Core data structures in Blink masonry (MasonryLayoutAlgorithm, GridTrackCollection, MasonryItemPosition).
2. 2D item placement algorithm: spanning 1 or more tracks along the grid axis, selecting the track subset with minimal accumulated running height along the masonry axis.
3. Definite vs automatic track placement constraints.
4. Mathematical invariants: item track span remains strictly within grid track count [0, N-span], placed height monotonic expansion, determinism.
5. Provide concrete Rocq/Coq inductive definitions and theorems for formalizing this into BlinkGridMasonry2DSemantics.v."""
    },
    {
        "id": "agent70",
        "file": "agent70_counter_style_systems.md",
        "topic": "Chromium Blink CSS Counter Style Systems (Cyclic, Alphabetic, Additive) (third_party/blink/renderer/core/css/counter_style.cc and counter_style_map.cc)",
        "spec": "W3C CSS Counter Styles Level 3 (§2 & §3 Counter Style Descriptors and Systems)",
        "prompt": """You are Agent 70 auditing Chromium Blink CSS Counter Styles vs CSS Counter Styles Level 3 §2 & §3.
Detail:
1. Core data structures in Blink counter styles (CounterStyle, CounterStyleSystem: Cyclic, Numeric, Alphabetic, Symbolic, Additive).
2. Representation generation algorithms:
   - Cyclic: index = ((val - 1) mod N) + 1.
   - Alphabetic: bijective base-N conversion.
   - Additive: greedy descending subtraction of additive weight tuples.
3. Fallback style invocation when integer value is outside supported range.
4. Mathematical invariants: cyclic indexing boundedness in [0, N-1], bijective alphabetic representation uniqueness, determinism.
5. Provide concrete Rocq/Coq inductive definitions and theorems for formalizing this into BlinkCounterStyleSystemsSemantics.v."""
    },
    {
        "id": "agent71",
        "file": "agent71_line_break_penalty.md",
        "topic": "Chromium Blink Optimal Line Breaking & Hyphenation Penalty (third_party/blink/renderer/core/layout/inline/line_breaker.cc and hyphenator.cc)",
        "spec": "W3C CSS Text Module Level 3 (§5) & Knuth-Plass Dynamic Programming Breaking Penalty Formulation",
        "prompt": """You are Agent 71 auditing Chromium Blink Line Break Penalty Optimization vs CSS Text Level 3 §5.
Detail:
1. Core data structures in Blink line breaking (LineBreaker, BreakOpportunity, LineBreakPenaltyConfig).
2. Penalty formulation: total cost C = sum of line demerits + hyphenation penalty P_hyphen + orphan penalty.
3. Dynamic programming / greedy selection of break points.
4. Mathematical invariants: line width never exceeds available width for legal non-overflow breaks, cost non-negativity, determinism.
5. Provide concrete Rocq/Coq inductive definitions and theorems for formalizing this into BlinkLineBreakPenaltySemantics.v."""
    },
    {
        "id": "agent72",
        "file": "agent72_svg_arc_bezier.md",
        "topic": "Chromium Blink SVG Path Arc-to-Cubic-Bézier Conversion (third_party/blink/renderer/core/svg/svg_path_parser.cc and platform/graphics/path.cc)",
        "spec": "W3C SVG 2 (§9.5.1 Elliptical Arc Implementation Notes & Center Parameterization)",
        "prompt": """You are Agent 72 auditing Chromium Blink SVG Arc-to-Bézier vs SVG 2 §9.5.
Detail:
1. Core data structures in Blink SVG path parsing (SVGPathParser, PathAppender, ArcParameterization).
2. Elliptical arc conversion: endpoint to center parameterization, scaling radii when no solution exists, splitting arc into segments <= pi/2, and generating cubic Bézier control points.
3. Mathematical invariants: start and end points of reconstructed Bézier curve match arc endpoints, radii scaling ensures discriminant non-negativity, determinism.
4. Provide concrete Rocq/Coq inductive definitions and theorems for formalizing this into BlinkSVGArcToBezierSemantics.v."""
    },
    {
        "id": "agent73",
        "file": "agent73_box_strut_geometry.md",
        "topic": "Chromium Blink Flow-Relative Box Strut & Box Model Algebra (third_party/blink/renderer/core/layout/geometry/box_strut.h and box_sides.h)",
        "spec": "W3C CSS Box Model Module Level 3 (§3 Sizing Properties) & CSS Writing Modes Level 3 (§4 Flow-Relative Offsets)",
        "prompt": """You are Agent 73 auditing Chromium Blink BoxStrut Geometry vs CSS Box Model Level 3 & Writing Modes Level 3.
Detail:
1. Core data structures in Blink box geometry (BoxStrut: inline_start, inline_end, block_start, block_end; BoxSides; LogicalSize).
2. Box model composition: content_box + padding_strut + border_strut = border_box; border_box + margin_strut = margin_box.
3. Writing mode transposition: physical to logical strut conversion.
4. Mathematical invariants: strut addition commutativity and associativity, size non-negativity under non-negative struts, determinism.
5. Provide concrete Rocq/Coq inductive definitions and theorems for formalizing this into BlinkBoxStrutGeometrySemantics.v."""
    },
    {
        "id": "agent74",
        "file": "agent74_text_decoration_metrics.md",
        "topic": "Chromium Blink Text Decoration Sizing & Baseline Offsets (third_party/blink/renderer/core/paint/text_decoration_info.cc)",
        "spec": "W3C CSS Text Decoration Module Level 3 (§2 & §3 Line-through, Underline, and Overline Metrics)",
        "prompt": """You are Agent 74 auditing Chromium Blink Text Decoration Metrics vs CSS Text Decoration Level 3 §2 & §3.
Detail:
1. Core data structures in Blink text decoration (TextDecorationInfo, TextDecorationLine, ResolvedUnderlinePosition).
2. Underline thickness resolution: max(1, round(font_metrics.underline_thickness)), clamped by maximum bounds.
3. Underline vertical offset: baseline + font_metrics.underline_position (or auto / under).
4. Mathematical invariants: thickness >= 1px, overline offset <= baseline <= underline offset, determinism.
5. Provide concrete Rocq/Coq inductive definitions and theorems for formalizing this into BlinkTextDecorationMetricsSemantics.v."""
    },
    {
        "id": "agent75",
        "file": "agent75_table_row_baseline.md",
        "topic": "Chromium Blink Table Row Multi-Cell Baseline Alignment (third_party/blink/renderer/core/layout/table/table_row_layout_algorithm.cc)",
        "spec": "W3C CSS 2.1 (§17.5.3 Table Row Height and Multi-Cell Baseline Alignment)",
        "prompt": """You are Agent 75 auditing Chromium Blink Table Row Baseline Alignment vs CSS 2.1 §17.5.3.
Detail:
1. Core data structures in Blink table row layout (TableRowLayoutAlgorithm, TableRowMetrics, CellBaselineInfo).
2. Baseline aggregation algorithm: max_ascent = max_{c} ascent(c), max_descent = max_{c} descent(c).
3. Final row height: H_row = max(specified_height, max_ascent + max_descent, max_{c} content_height(c)).
4. Mathematical invariants: H_row >= max_ascent + max_descent, H_row >= specified_height, every cell's content is contained within H_row, determinism.
5. Provide concrete Rocq/Coq inductive definitions and theorems for formalizing this into BlinkTableRowBaselineSemantics.v."""
    },
    {
        "id": "agent76",
        "file": "agent76_flex_reverse_axis.md",
        "topic": "Chromium Blink Flexbox Reverse Directions & Line Packing (third_party/blink/renderer/core/layout/flex/flex_layout_algorithm.cc)",
        "spec": "W3C CSS Flexible Box Layout Module Level 1 (§5 Flex Directions: row-reverse, column-reverse & wrap-reverse)",
        "prompt": """You are Agent 76 auditing Chromium Blink Flex Reverse Directions vs CSS Flexible Box Level 1 §5.
Detail:
1. Core data structures in Blink flex direction (FlexLayoutAlgorithm, FlexDirection, FlexWrap, LogicalFlexItem).
2. Coordinate mirroring transformations:
   - row-reverse: main_offset = container_main_size - (item_main_offset + item_main_size).
   - wrap-reverse: cross_offset = container_cross_size - (line_cross_offset + line_cross_size).
3. Mathematical invariants: coordinate involution (mirroring twice yields identity), item remains strictly contained within container main size, determinism.
4. Provide concrete Rocq/Coq inductive definitions and theorems for formalizing this into BlinkFlexReverseAxisSemantics.v."""
    },
    {
        "id": "agent77",
        "file": "agent77_paint_invalidation_rect.md",
        "topic": "Chromium Blink Paint Invalidation & Visual Rect Mapping (third_party/blink/renderer/core/paint/paint_invalidator.cc and paint_property_tree_builder.cc)",
        "spec": "CSS 2.1 (§8 Box Dimensions) & CSS Containment Level 2 (Conservative Enclosing Invalidation Rects)",
        "prompt": """You are Agent 77 auditing Chromium Blink Paint Invalidation vs CSS Painting & Invalidation.
Detail:
1. Core data structures in Blink paint invalidation (PaintInvalidator, PaintInvalidatorContext, VisualRectMapping).
2. Invalidation rect accumulation: transforming local layout rect through paint property tree (transform, clip, scroll nodes) into backing container space.
3. Invalidation union: bounding box union between old visual rect and new visual rect.
4. Mathematical invariants: invalidation rect contains both old and new rects (containment), union is commutative and associative, non-negativity.
5. Provide concrete Rocq/Coq inductive definitions and theorems for formalizing this into BlinkPaintInvalidationRectSemantics.v."""
    },
    {
        "id": "agent78",
        "file": "agent78_scroll_anchoring.md",
        "topic": "Chromium Blink Scroll Anchoring Drift Calculation (third_party/blink/renderer/core/page/scrolling/scroll_anchor.cc)",
        "spec": "W3C Scroll Anchoring Module Level 1 (§3 Anchor Node Selection & Drift Adjustment)",
        "prompt": """You are Agent 78 auditing Chromium Blink Scroll Anchoring vs W3C Scroll Anchoring Level 1 §3.
Detail:
1. Core data structures in Blink scroll anchoring (ScrollAnchor, AnchorCandidate, ScrollAnchorData).
2. Drift calculation algorithm: delta = current_anchor_rect.top - saved_anchor_rect.top.
3. Scroll adjustment application: scroll_offset_new = scroll_offset_old + delta.
4. Mathematical invariants: scroll adjustment exactly compensates relative anchor movement (relative distance remains zero), drift is zero when anchor does not move, determinism.
5. Provide concrete Rocq/Coq inductive definitions and theorems for formalizing this into BlinkScrollAnchoringSemantics.v."""
    },
    {
        "id": "agent79",
        "file": "agent79_media_query_range.md",
        "topic": "Chromium Blink CSS Media Queries Range Context Evaluation (third_party/blink/renderer/core/css/media_query_evaluator.cc)",
        "spec": "W3C Media Queries Level 4 (§2 Media Query Range Syntax: min/max & range contexts <=, <, >=, >)",
        "prompt": """You are Agent 79 auditing Chromium Blink Media Query Range Syntax vs CSS Media Queries Level 4 §2.
Detail:
1. Core data structures in Blink media queries (MediaQueryEvaluator, MediaQueryExp, MediaQueryOperator: Le, Lt, Ge, Gt, Eq).
2. Evaluation semantics: evaluating expressions like (width <= 600px), (400px < width <= 800px) against viewport dimensions.
3. Interval containment and Boolean combination (and, or, not).
4. Mathematical invariants: monotonicity of one-sided inequalities, De Morgan's laws for media query conjunction/disjunction, determinism.
5. Provide concrete Rocq/Coq inductive definitions and theorems for formalizing this into BlinkMediaQueryRangeSemantics.v."""
    },
    {
        "id": "agent80",
        "file": "agent80_subgrid_alignment.md",
        "topic": "Chromium Blink CSS Subgrid Track Alignment & Span Sizing (third_party/blink/renderer/core/layout/grid/grid_data.h and grid_layout_algorithm.cc)",
        "spec": "W3C CSS Grid Layout Module Level 2 (§2 Subgrids: Inheriting Parent Grid Tracks)",
        "prompt": """You are Agent 80 auditing Chromium Blink CSS Subgrid Track Alignment vs CSS Grid Layout Level 2 §2.
Detail:
1. Core data structures in Blink subgrid (GridData, SubgridData, GridSpan, GridTrackCollection).
2. Subgrid track alignment: mapping subgrid's local tracks 1..K directly onto parent grid tracks [start, start + K - 1].
3. Subgrid margin/border/padding absorption into the first and last inherited tracks.
4. Mathematical invariants: subgrid track count equals parent spanned track count, track coordinate translation is an order-preserving isomorphism, determinism.
5. Provide concrete Rocq/Coq inductive definitions and theorems for formalizing this into BlinkSubgridAlignmentSemantics.v."""
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
    print("Launching Wave 11: 16 concurrent Python3 agents using gemini-4-argon (thinking budget 1024) across Central Blink Areas...")
    with concurrent.futures.ThreadPoolExecutor(max_workers=16) as executor:
        results = list(executor.map(run_agent, tasks))

    total_p = sum(r.get("prompt_tokens", 0) for r in results)
    total_c = sum(r.get("candidates_tokens", 0) for r in results)
    total_t = sum(r.get("total_tokens", 0) for r in results)

    log_entry = {
        "timestamp": time.strftime("%Y-%m-%d %H:%M:%S"),
        "model": "gemini-4-argon",
        "wave": 11,
        "theme": "16 Central Engine Areas (View Transitions, 2D Sticky, Inline Box Tree, Aspect Ratio Transfer, Grid Masonry 2D, Counter Style Systems, Line Break Penalty, SVG Arc-to-Bezier, BoxStrut Geometry, Text Decoration Metrics, Table Row Baseline, Flex Reverse Axis, Paint Invalidation Rect, Scroll Anchoring, Media Query Range, Subgrid Alignment)",
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

    print("\n=== WAVE 11 (16 AGENTS: CENTRAL BLINK AREAS) TOKEN USAGE REPORT ===")
    print(f"Prompt Tokens:     {total_p}")
    print(f"Candidate Tokens:  {total_c}")
    print(f"Total Tokens Used: {total_t}")
    print("Appended log entry to token_usage.log.")

