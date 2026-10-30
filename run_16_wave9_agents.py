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
        "id": "agent33",
        "file": "agent33_css_custom_properties.md",
        "topic": "Chromium Blink CSS Custom Properties & var() Substitution (third_party/blink/renderer/core/css/resolver/style_cascade.cc and css_variable_data.cc)",
        "spec": "W3C CSS Custom Properties for Cascading Variables Module Level 1 (§2 Custom Properties, §3 The var() Function, §4 Cyclic Dependencies)",
        "prompt": """You are Agent 33 auditing Chromium Blink CSS Custom Properties and var() Substitution vs CSS Custom Properties Level 1.
Detail:
1. Core data structures in Blink CSS custom properties (CSSVariableData, StyleCascade, TokenSequence, Resolver).
2. The var() substitution and cycle detection algorithm: tracking the active resolution stack, detecting cycles (guaranteed invalid at computed-value time), and fallback value substitution.
3. Universal syntax and token serialization.
4. Mathematical invariants: cycle detection terminates, cycle resolution deterministically yields unset/invalid, acyclic chains terminate in finite steps, fallback validity.
5. Provide concrete Rocq/Coq inductive definitions and theorems for formalizing this into BlinkCSSCustomPropertiesSemantics.v."""
    },
    {
        "id": "agent34",
        "file": "agent34_flex_cross_alignment.md",
        "topic": "Chromium Blink Flexbox Cross Sizing & Align-Self (third_party/blink/renderer/core/layout/flex/flex_layout_algorithm.cc)",
        "spec": "W3C CSS Flexible Box Layout Module Level 1 (§9.4 Cross Size Determination, §9.6 Cross Axis Alignment: stretch, flex-start, flex-end, center, baseline)",
        "prompt": """You are Agent 34 auditing Chromium Blink Flex Cross Alignment vs W3C CSS Flexible Box Layout Level 1 §9.4 & §9.6.
Detail:
1. Core data structures in Blink flex cross sizing (FlexItem, FlexLine, ItemPosition: Stretch, FlexStart, FlexEnd, Center, Baseline).
2. Cross size determination and stretch alignment: resolving item cross size to line cross size when align-self is stretch and cross size is auto, clamped by min/max cross size.
3. Cross offset calculation: top/left for flex-start, bottom/right for flex-end, centered offset (line_cross_size - item_cross_size) / 2.
4. Mathematical invariants: item cross size bounded by line cross size, offset non-negativity, offset + item_cross_size <= line_cross_size, determinism.
5. Provide concrete Rocq/Coq inductive definitions and theorems for formalizing this into BlinkFlexCrossAlignmentSemantics.v."""
    },
    {
        "id": "agent35",
        "file": "agent35_grid_auto_repeat.md",
        "topic": "Chromium Blink CSS Grid Auto-Repeat Tracks (third_party/blink/renderer/core/layout/grid/grid_line_resolver.cc and grid_track_collection.cc)",
        "spec": "W3C CSS Grid Layout Module Level 1 (§7.2.3.1 Auto-repeating Tracks: repeat(auto-fill), repeat(auto-fit))",
        "prompt": """You are Agent 35 auditing Chromium Blink Grid Auto-Repeat vs CSS Grid Layout Level 1 §7.2.3.1.
Detail:
1. Core data structures in Blink grid auto-repeat (NGGridTrackList, GridTrackRepeater, AutoRepeatType: AutoFill, AutoFit).
2. Track repetition count calculation: N = max(1, floor((available_space - non_auto_tracks_size) / (repeated_tracks_size + gap))).
3. Auto-fit track collapsing: collapsing empty auto-repeated tracks to 0px while preserving line names.
4. Mathematical invariants: repetition count N >= 1 whenever available space is finite, total auto-repeated size <= available space (when available space >= min_size), determinism.
5. Provide concrete Rocq/Coq inductive definitions and theorems for formalizing this into BlinkGridAutoRepeatSemantics.v."""
    },
    {
        "id": "agent36",
        "file": "agent36_replaced_elements.md",
        "topic": "Chromium Blink Replaced Element Sizing (third_party/blink/renderer/core/layout/layout_replaced.cc and length_utils.cc ComputeReplacedSize)",
        "spec": "W3C CSS Box Sizing Module Level 3 (§6 Sizing Replaced Elements with Natural Dimensions and Aspect Ratio)",
        "prompt": """You are Agent 36 auditing Chromium Blink Replaced Element Sizing vs CSS Box Sizing Level 3 §6.
Detail:
1. Core data structures in Blink replaced sizing (LayoutReplaced, IntrinsicSizingInfo: has_width, has_height, aspect_ratio, natural_size).
2. The 3-way resolution algorithm: when specified width/height are set or auto, computing resolved dimensions from natural width, natural height, and aspect ratio.
3. Min/Max size constraint enforcement: overriding aspect ratio scaling when one dimension hits a min/max boundary.
4. Mathematical invariants: resolved dimensions >= 0, aspect ratio preserved when unconstrained by min/max, determinism.
5. Provide concrete Rocq/Coq inductive definitions and theorems for formalizing this into BlinkReplacedElementSemantics.v."""
    },
    {
        "id": "agent37",
        "file": "agent37_scroll_snap.md",
        "topic": "Chromium Blink CSS Scroll Snap Points (third_party/blink/renderer/core/page/scrolling/snap_coordinator.cc and scroll_snap_data.cc)",
        "spec": "W3C CSS Scroll Snap Module Level 1 (§4 Snap Model: scroll-snap-type, §5 Snap Alignment: scroll-snap-align start, end, center)",
        "prompt": """You are Agent 37 auditing Chromium Blink Scroll Snap vs CSS Scroll Snap Level 1.
Detail:
1. Core data structures in Blink scroll snap (SnapCoordinator, SnapContainerData, SnapAreaData, ScrollSnapAlign: Start, End, Center).
2. Snap target calculation: determining snap offset for a snap area within a scroll container viewport for start, end, and center alignments.
3. Strict vs proximity snapping: clamping snap position within scrollable bounds.
4. Mathematical invariants: snap offset bounded within [min_scroll_offset, max_scroll_offset], determinism, distance minimization.
5. Provide concrete Rocq/Coq inductive definitions and theorems for formalizing this into BlinkScrollSnapSemantics.v."""
    },
    {
        "id": "agent38",
        "file": "agent38_multicol_spanner.md",
        "topic": "Chromium Blink Multi-Column Column Spanning (third_party/blink/renderer/core/layout/fragmentation/column_layout_algorithm.cc)",
        "spec": "W3C CSS Multi-column Layout Module Level 1 (§6 Spanning Columns: column-span all)",
        "prompt": """You are Agent 38 auditing Chromium Blink Multi-column Spanner Layout vs CSS Multicol 1 §6.
Detail:
1. Core data structures in Blink column spanners (MulticolLayoutAlgorithm, SpannerPart, ColumnSpannerPath).
2. Spanner layout algorithm: interrupting multi-column fragmentation, balancing preceding columns, spanning across the full multicol container width (column_count * width + gaps), and resuming columns below.
3. Available inline size override for column-span: all vs regular column children.
4. Mathematical invariants: spanner inline size equals multicol content width, spanner block offset >= preceding column balanced height, determinism.
5. Provide concrete Rocq/Coq inductive definitions and theorems for formalizing this into BlinkMulticolSpannerSemantics.v."""
    },
    {
        "id": "agent39",
        "file": "agent39_stepped_math.md",
        "topic": "Chromium Blink CSS Stepped Value Math Functions (third_party/blink/renderer/core/css/css_math_expression_node.cc round, mod, rem)",
        "spec": "W3C CSS Values and Units Module Level 4 (§10.4 Stepped Value Functions: round(), mod(), rem())",
        "prompt": """You are Agent 39 auditing Chromium Blink CSS round(), mod(), and rem() vs CSS Values and Units Level 4 §10.4.
Detail:
1. Core data structures in Blink math functions (CSSMathExpressionOperation, CSSMathOperator: kRoundNearest, kRoundUp, kRoundDown, kRoundToZero, kMod, kRem).
2. Evaluation semantics: round(val, step, strategy), mod(A, B) = A - B * floor(A / B), rem(A, B) = A - B * trunc(A / B).
3. Handling step = 0 (NaN/Infinity or fallback) and sign preservation.
4. Mathematical invariants: round result is an integer multiple of step, mod has sign of divisor B, rem has sign of dividend A, determinism.
5. Provide concrete Rocq/Coq inductive definitions and theorems for formalizing this into BlinkCSSSteppedMathSemantics.v."""
    },
    {
        "id": "agent40",
        "file": "agent40_orthogonal_modes.md",
        "topic": "Chromium Blink Orthogonal Writing Modes Layout (third_party/blink/renderer/core/layout/ng_block_layout_algorithm.cc and writing_mode_converter.cc)",
        "spec": "W3C CSS Writing Modes Level 3 (§7 Flow-Relative Sizing & Orthogonal Flows)",
        "prompt": """You are Agent 40 auditing Chromium Blink Orthogonal Writing Modes vs CSS Writing Modes Level 3 §7.
Detail:
1. Core data structures in Blink orthogonal flows (OrthogonalWritingModeRoot, ConstraintSpace, LogicalToPhysical).
2. Sizing transformation: child inline size maps to parent block size, child block size maps to parent inline size.
3. Multi-pass resolution: measuring child's min/max content size along child's inline axis to provide a definite block constraint to the parent.
4. Mathematical invariants: coordinate involution under double transposition, non-negativity preservation, determinism.
5. Provide concrete Rocq/Coq inductive definitions and theorems for formalizing this into BlinkOrthogonalWritingModeSemantics.v."""
    },
    {
        "id": "agent41",
        "file": "agent41_font_metrics.md",
        "topic": "Chromium Blink Font Metrics & Baseline Synthesis (third_party/blink/renderer/platform/fonts/font_metrics.cc and simple_font_data.cc)",
        "spec": "W3C CSS Fonts Module Level 4 (§5 Font Metrics) & CSS Inline Layout 3 (§2 Baseline Systems)",
        "prompt": """You are Agent 41 auditing Chromium Blink Font Metrics vs W3C CSS Fonts Level 4 & CSS Inline 3.
Detail:
1. Core data structures in Blink font metrics (FontMetrics, SimpleFontData, FontHeight: ascent, descent).
2. Synthesized metrics: calculating line-gap, x-height, cap-height, and baseline offsets when missing from font tables.
3. Half-leading distribution: leading = line_height - (ascent + descent), half_leading = leading / 2.
4. Mathematical invariants: ascent + descent + leading = line_height, ascent >= 0, descent >= 0, line_height non-negative, determinism.
5. Provide concrete Rocq/Coq inductive definitions and theorems for formalizing this into BlinkFontMetricsSemantics.v."""
    },
    {
        "id": "agent42",
        "file": "agent42_inline_spacing.md",
        "topic": "Chromium Blink Inline Spacing & Justification (third_party/blink/renderer/core/layout/inline/inline_layout_algorithm.cc)",
        "spec": "W3C CSS Text Module Level 3 (§6 Alignment and Justification, §8 Spacing: letter-spacing, word-spacing)",
        "prompt": """You are Agent 42 auditing Chromium Blink Inline Spacing vs CSS Text Level 3 §6 & §8.
Detail:
1. Core data structures in Blink inline text spacing (ShapeResult, TextJustifier, SpacingParameters).
2. Justification algorithm: distributing expansion delta across expansion opportunities (spaces, ideographic boundaries) on a justified line.
3. Letter-spacing and word-spacing addition to shaped glyph clusters.
4. Mathematical invariants: sum of expansion opportunities absorbs total expansion delta, line width equals target available inline width, determinism.
5. Provide concrete Rocq/Coq inductive definitions and theorems for formalizing this into BlinkInlineSpacingSemantics.v."""
    },
    {
        "id": "agent43",
        "file": "agent43_filter_outset.md",
        "topic": "Chromium Blink CSS Filter Outsets (third_party/blink/renderer/core/paint/filter_effect_builder.cc and style/filter_operations.cc)",
        "spec": "W3C Filter Effects Module Level 1 (§3 Filter Functions: blur, drop-shadow, §8 Filter Region)",
        "prompt": """You are Agent 43 auditing Chromium Blink CSS Filter Outsets vs W3C Filter Effects Level 1.
Detail:
1. Core data structures in Blink filter operations (FilterOperations, BlurFilterOperation, DropShadowFilterOperation, Outsets).
2. Ink overflow expansion: blur radius sigma contributes outset = ceil(3 * sigma * sqrt(2 * pi) / 4) ~= ceil(3 * sigma); drop-shadow adds (dx, dy) shift + blur spread.
3. Filter outset union across a list of filter operations.
4. Mathematical invariants: filter outsets are non-negative, monotonicity with respect to blur radius, union associativity, determinism.
5. Provide concrete Rocq/Coq inductive definitions and theorems for formalizing this into BlinkFilterOutsetSemantics.v."""
    },
    {
        "id": "agent44",
        "file": "agent44_first_line_letter.md",
        "topic": "Chromium Blink First-Line & First-Letter Pseudo-Elements (third_party/blink/renderer/core/css/resolver/style_resolver.cc and layout_text_fragment.cc)",
        "spec": "W3C CSS Pseudo-Elements Module Level 4 (§2 First-Line and First-Letter Pseudo-elements)",
        "prompt": """You are Agent 44 auditing Chromium Blink ::first-line and ::first-letter vs CSS Pseudo-Elements Level 4 §2.
Detail:
1. Core data structures in Blink pseudo-element styling (PseudoElement, FirstLetterPseudoElement, LayoutTextFragment, StyleRequest).
2. First-letter text splitting: isolating the first typographic letter unit (including leading punctuation and quote characters) into a dedicated layout object.
3. First-line style cascade: applying restricted properties (fonts, colors, backgrounds) to line 0 fragments.
4. Mathematical invariants: original text length = first_letter_length + remaining_length, non-empty first letter, determinism.
5. Provide concrete Rocq/Coq inductive definitions and theorems for formalizing this into BlinkFirstLineLetterSemantics.v."""
    },
    {
        "id": "agent45",
        "file": "agent45_pixel_snapping.md",
        "topic": "Chromium Blink Subpixel Layout & Pixel Snapping (third_party/blink/renderer/core/layout/geometry/pixel_snapping.cc and layout_unit.h)",
        "spec": "CSS Device Adaptation & Blink Fixed-Point Pixel Snapping Algebra",
        "prompt": """You are Agent 45 auditing Chromium Blink Pixel Snapping vs CSS Subpixel Rendering.
Detail:
1. Core data structures in Blink pixel snapping (LayoutUnit, SnapSizeToPixel, SnapRectToPixel, RoundToPixel).
2. Snapping functions: RoundToPixel(val) = floor(val + 0.5), SnapSizeToPixel(location, size) = RoundToPixel(location + size) - RoundToPixel(location).
3. Snapping rectangular bounds: preserving visual adjacency between abutting boxes (no 1px gaps or overlaps).
4. Mathematical invariants: adjacent rects with right_A = left_B have snapped_right_A = snapped_left_B (adjacency preservation), idempotence, determinism.
5. Provide concrete Rocq/Coq inductive definitions and theorems for formalizing this into BlinkPixelSnappingSemantics.v."""
    },
    {
        "id": "agent46",
        "file": "agent46_oof_static_position.md",
        "topic": "Chromium Blink Out-of-Flow Static Position Resolution (third_party/blink/renderer/core/layout/out_of_flow_layout_part.cc and static_position.h)",
        "spec": "W3C CSS 2.1 (§10.3.7 & §10.6.4) and CSS Position 3 §5 (Static Position of Absolutely Positioned Boxes)",
        "prompt": """You are Agent 46 auditing Chromium Blink OOF Static Position vs CSS Position Level 3 §5.
Detail:
1. Core data structures in Blink static position (StaticPosition, LogicalStaticPosition: inline_edge, block_edge).
2. Static position computation: determining where an absolute/fixed box would have been placed in normal flow if position: static were specified.
3. Inset resolution when top/left/bottom/right are auto: substituting static position into the 1D positioned constraint equation.
4. Mathematical invariants: static position is deterministic, static position falls within containing block bounds, non-negativity.
5. Provide concrete Rocq/Coq inductive definitions and theorems for formalizing this into BlinkOutOfFlowStaticPositionSemantics.v."""
    },
    {
        "id": "agent47",
        "file": "agent47_auto_margins.md",
        "topic": "Chromium Blink Auto Margins Space Distribution (third_party/blink/renderer/core/layout/length_utils.cc ResolveAutoMargins)",
        "spec": "W3C CSS 2.1 (§10.3.3 & §10.6.4 Auto Margins Distribution for Inflow and Positioned Boxes)",
        "prompt": """You are Agent 47 auditing Chromium Blink Auto Margins vs CSS 2.1 §10.3.3 & §10.6.4.
Detail:
1. Core data structures in Blink auto margins (NGBoxStrut, ResolveAutoMargins, EBoxSizing).
2. Available free space distribution: delta = available_width - (border_padding + width + fixed_margins).
   - If both left and right are auto: margin_left = delta / 2, margin_right = delta - margin_left.
   - If one is auto: it absorbs all delta.
   - If delta < 0: left margin becomes 0, right margin absorbs delta (in LTR).
3. Mathematical invariants: margin_left + margin_right + width + border_padding = available_width (space conservation), symmetry when delta >= 0, determinism.
4. Provide concrete Rocq/Coq inductive definitions and theorems for formalizing this into BlinkAutoMarginSemantics.v."""
    },
    {
        "id": "agent48",
        "file": "agent48_fragment_tree.md",
        "topic": "Chromium Blink Fragment Tree Builder & Geometry Propagation (third_party/blink/renderer/core/layout/physical_box_fragment.cc and box_fragment_builder.cc)",
        "spec": "W3C CSS Display Module Level 3 (§3 Generating Fragment Trees & Overflow Propagation)",
        "prompt": """You are Agent 48 auditing Chromium Blink Fragment Tree Building vs CSS Display Level 3 §3.
Detail:
1. Core data structures in Blink fragment trees (PhysicalBoxFragment, BoxFragmentBuilder, FragmentLink).
2. Tree assembly and overflow propagation: aggregating scrollable overflow and ink overflow from child fragments into parent fragment bounds.
3. Propagating self-collapsing margin struts and break tokens.
4. Mathematical invariants: parent scrollable overflow contains child border boxes, fragment tree is a directed acyclic graph (tree), determinism.
5. Provide concrete Rocq/Coq inductive definitions and theorems for formalizing this into BlinkFragmentTreePropagationSemantics.v."""
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
    print("Launching Wave 9: 16 concurrent Python3 agents using gemini-4-argon (thinking budget 1024) across Central Blink Areas...")
    with concurrent.futures.ThreadPoolExecutor(max_workers=16) as executor:
        results = list(executor.map(run_agent, tasks))

    total_p = sum(r.get("prompt_tokens", 0) for r in results)
    total_c = sum(r.get("candidates_tokens", 0) for r in results)
    total_t = sum(r.get("total_tokens", 0) for r in results)

    log_entry = {
        "timestamp": time.strftime("%Y-%m-%d %H:%M:%S"),
        "model": "gemini-4-argon",
        "wave": 9,
        "theme": "16 Central Engine Areas (Custom Properties, Flex Cross, Grid Auto-Repeat, Replaced, Scroll Snap, Multicol Spanner, Stepped Math, Orthogonal, Fonts, Spacing, Filter Outsets, Pseudo Elements, Pixel Snapping, Static Position, Auto Margins, Fragment Tree)",
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

    print("\n=== WAVE 9 (16 AGENTS: CENTRAL BLINK AREAS) TOKEN USAGE REPORT ===")
    print(f"Prompt Tokens:     {total_p}")
    print(f"Candidate Tokens:  {total_c}")
    print(f"Total Tokens Used: {total_t}")
    print("Appended log entry to token_usage.log.")

