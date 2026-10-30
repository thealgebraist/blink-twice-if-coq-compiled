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
        "id": "agent145",
        "file": "agent145_flex_multiline_wrap.md",
        "topic": "Chromium Blink Multi-Line Flexbox Wrapping & Cross-Size Distribution (core/layout/flex/flex_layout_algorithm.cc)",
        "spec": "CSS Flexible Box Layout 1 §8.4 & §9.4 (flex-wrap: wrap, line breaking, align-content)",
        "prompt": """You are Agent 145 auditing Chromium Blink Multi-Line Flexbox Wrapping vs CSS Flexbox 1 §8.4 & §9.4.
Detail:
1. Core data structures in Blink LayoutNG flex layout: FlexLine, FlexItem, NGSizedFlexItem, align-content resolution.
2. Line breaking: item advances along main axis; if item main size exceeds remaining line space (and line is not empty), a new FlexLine is created.
3. Cross-size distribution: cross offset monotonic accumulation across lines, align-content (flex-start, space-between, center, stretch).
4. Concrete Rocq/Coq definitions and theorems for BlinkFlexMultiLineWrapSemantics.v."""
    },
    {
        "id": "agent146",
        "file": "agent146_grid_subgrid_axis.md",
        "topic": "Chromium Blink CSS Grid 2 Subgrid Axis Inheritance & Margin Alignment (core/layout/grid/grid_subtree.cc)",
        "spec": "CSS Grid Layout 2 §2 (Subgrid axis adoption, line index mapping, margin alignment)",
        "prompt": """You are Agent 146 auditing Chromium Blink Grid 2 Subgrid Axis Inheritance vs CSS Grid 2 §2.
Detail:
1. Representation of subgrid items adopting parent grid tracks (GridSubtree, GridLineResolver).
2. Line index translation: subgrid lines map directly to parent track range [start_line, end_line].
3. Invariants: subgrid track count equals spanned parent tracks, subgrid child placement clamped within parent span.
4. Concrete Rocq/Coq definitions and theorems for BlinkGridSubgridAxisSemantics.v."""
    },
    {
        "id": "agent147",
        "file": "agent147_subpixel_layout_snapping.md",
        "topic": "Chromium Blink Subpixel Layout Snapping & Pixel Snapping Geometry (core/layout/geometry/layout_unit.h)",
        "spec": "CSS Values and Units 3 §5.1 & Device Adaptation (LayoutUnit::Round, pixel snapping)",
        "prompt": """You are Agent 147 auditing Chromium Blink LayoutUnit Subpixel Snapping vs CSS Values 3 §5.1.
Detail:
1. LayoutUnit fixed-point representation (26.6, denominator 64) and snapping function LayoutUnit::Round() / Floor() / Ceil().
2. Pixel snapping of borders and coordinates: snap(x) = round(x / 64). Snapping error bound: |x - 64 * round(x / 64)| <= 32.
3. Invariants: snap non-negativity for non-negative inputs, idempotence of pixel snapping on integer pixel boundaries, triangle inequality.
4. Concrete Rocq/Coq definitions and theorems for BlinkSubpixelLayoutSnappingSemantics.v."""
    },
    {
        "id": "agent148",
        "file": "agent148_affine_transform_2d.md",
        "topic": "Chromium Blink CSS Transform 2D Affine Matrix Composition (platform/transforms/affine_transform.cc)",
        "spec": "CSS Transforms 1 §5 & §6 (2D homogeneous transformation matrix [a, b, c, d, e, f])",
        "prompt": """You are Agent 148 auditing Chromium Blink 2D Affine Transform Composition vs CSS Transforms 1 §5 & §6.
Detail:
1. Representation of 2D AffineTransform matrix: [a, b, c, d, e, f] corresponding to 3x3 matrix [[a, c, e], [b, d, f], [0, 0, 1]].
2. Matrix composition: multiplication of two affine transforms (t1 * t2).
3. Invariants: identity transformation neutrality, associativity of transform composition, scaling linearity, translation offset addition.
4. Concrete Rocq/Coq definitions and theorems for BlinkAffineTransform2DSemantics.v."""
    },
    {
        "id": "agent149",
        "file": "agent149_bidi_neutral_resolution.md",
        "topic": "Chromium Blink Inline BiDi Neutral Character Resolution & Embedding Levels (core/layout/inline/bidi_paragraph.cc)",
        "spec": "Unicode Bidirectional Algorithm UAX #9 §3.3.4 & §3.3.5, CSS Writing Modes 3 §2",
        "prompt": """You are Agent 149 auditing Chromium Blink BiDi Neutral Character Resolution vs UAX #9 & CSS Writing Modes 3 §2.
Detail:
1. Directional types in Blink (BidiParagraph, BidiResolver): L (Left-to-Right), R (Right-to-Left), N (Neutral: spaces, punctuation).
2. Neutral character resolution: neutral sequences between identical strong types adopt that type (L N L -> L L L; R N R -> R R R).
3. Invariants: embedding levels bounded in [0, 125], even level corresponds to LTR visual order, odd level corresponds to RTL visual order.
4. Concrete Rocq/Coq definitions and theorems for BlinkBidiNeutralResolutionSemantics.v."""
    },
    {
        "id": "agent150",
        "file": "agent150_text_hyphenation_break.md",
        "topic": "Chromium Blink CSS Text Hyphenation Opportunity Detection & Soft Hyphens (core/layout/inline/hyphenator.cc)",
        "spec": "CSS Text 3 §5.4 (hyphens: auto | manual | none, soft hyphen &shy;, prefix/suffix bounds)",
        "prompt": """You are Agent 150 auditing Chromium Blink Text Hyphenation vs CSS Text 3 §5.4.
Detail:
1. Hyphenation break opportunity detection in Hyphenator (core/layout/inline/hyphenator.cc).
2. Soft hyphen (&shy; / U+00AD) manual breaks vs dictionary auto hyphenation.
3. Invariants: break opportunity index i satisfies min_prefix <= i <= len - min_suffix, inserted hyphen width fits in remaining inline space.
4. Concrete Rocq/Coq definitions and theorems for BlinkTextHyphenationBreakSemantics.v."""
    },
    {
        "id": "agent151",
        "file": "agent151_table_percent_column_sizing.md",
        "topic": "Chromium Blink Table Percentage Column Sizing under Variable Free Space (core/layout/table/table_layout_algorithm.cc)",
        "spec": "CSS Table 3 §3.3 & CSS 2.1 §17.5.2.2 (Percentage column resolution against available table width)",
        "prompt": """You are Agent 151 auditing Chromium Blink Table Percentage Column Sizing vs CSS Table 3 §3.3.
Detail:
1. Representation of percentage columns in TableLayoutAlgorithm::ComputeColumnWidths.
2. Resolution: column width W_col = floor(W_avail * P / 100), residual free space allocation among non-percent columns.
3. Invariants: sum of percentage column widths <= W_avail when sum(P) <= 100, column width monotonic in W_avail, non-negativity.
4. Concrete Rocq/Coq definitions and theorems for BlinkTablePercentColumnSizingSemantics.v."""
    },
    {
        "id": "agent152",
        "file": "agent152_css_containment_layout_size.md",
        "topic": "Chromium Blink CSS Containment Layout and Size Boundaries (core/layout/layout_box.cc)",
        "spec": "CSS Containment 2 §2 & §3 (contain: layout size, independent formatting boundaries)",
        "prompt": """You are Agent 152 auditing Chromium Blink CSS Containment (contain: layout size) vs CSS Containment 2 §2 & §3.
Detail:
1. Representation of containment flags in ComputedStyle and LayoutBox (HasLayoutContainment(), HasSizeContainment()).
2. Layout isolation: containment boundary prevents margin collapsing with external siblings (creates independent formatting context).
3. Invariants: external margin collapse suppression, size containment treats subtree as empty box for intrinsic size computation.
4. Concrete Rocq/Coq definitions and theorems for BlinkCSSContainmentLayoutSizeSemantics.v."""
    },
    {
        "id": "agent153",
        "file": "agent153_clip_path_polygon.md",
        "topic": "Chromium Blink CSS Clip Path Polygon Point Containment (core/paint/clip_path_clipper.cc)",
        "spec": "CSS Masking 1 §5 & §6 (clip-path: polygon(...), bounding box calculation, point containment)",
        "prompt": """You are Agent 153 auditing Chromium Blink Clip Path Polygon Geometry vs CSS Masking 1 §5 & §6.
Detail:
1. Representation of polygonal clip paths in ClipPathClipper and Path (core/paint/clip_path_clipper.cc).
2. Bounding box computation: min_x, max_x, min_y, max_y encompassing all polygon vertices.
3. Invariants: polygon bounding rect contains all vertices, any point outside bounding rect is clipped out (containment necessary condition).
4. Concrete Rocq/Coq definitions and theorems for BlinkClipPathPolygonSemantics.v."""
    },
    {
        "id": "agent154",
        "file": "agent154_scroll_snap_alignment.md",
        "topic": "Chromium Blink Scroll Snap Container & Snap Points Alignment (core/page/scroller.cc)",
        "spec": "CSS Scroll Snap 1 §4 & §6 (scroll-snap-type: x mandatory, scroll-snap-align: start | center | end)",
        "prompt": """You are Agent 154 auditing Chromium Blink Scroll Snap Alignment vs CSS Scroll Snap 1 §4 & §6.
Detail:
1. Scroll snap data structures: SnapCoordinator, SnapArea, snap-align (start, center, end).
2. Target scroll offset calculation: aligning snap area edge/center with snap port edge/center, clamping within [0, max_scroll].
3. Invariants: target scroll position bounded within [0, content_width - viewport_width], proximity threshold determinism.
4. Concrete Rocq/Coq definitions and theorems for BlinkScrollSnapAlignmentSemantics.v."""
    },
    {
        "id": "agent155",
        "file": "agent155_css_filter_color_matrix.md",
        "topic": "Chromium Blink CSS Filter Matrix Operators & Brightness/Contrast (core/paint/filter_effect_builder.cc)",
        "spec": "Filter Effects 1 §5 & §13 (filter: brightness(b) contrast(c) grayscale(g), clamping in [0, 255])",
        "prompt": """You are Agent 155 auditing Chromium Blink CSS Filter Color Matrix vs Filter Effects 1 §5 & §13.
Detail:
1. Filter matrix builder in FilterEffectBuilder and fe_color_matrix.cc.
2. Channel scaling: brightness(b) scales RGB by b; contrast(c) scales around midpoint 128; channel output clamped to [0, 255].
3. Invariants: brightness(1) is identity, output channel bounded in [0, 255], brightness monotonic in b for non-negative inputs.
4. Concrete Rocq/Coq definitions and theorems for BlinkCSSFilterColorMatrixSemantics.v."""
    },
    {
        "id": "agent156",
        "file": "agent156_multicol_column_spanner.md",
        "topic": "Chromium Blink CSS Multi-Column Spanner Layout (core/layout/fragmentation/column_layout_algorithm.cc)",
        "spec": "CSS Multi-column Layout 1 §6 (column-span: all, flow thread interruption, spanner inline width)",
        "prompt": """You are Agent 156 auditing Chromium Blink Multi-Column Spanner Layout vs CSS Multi-column 1 §6.
Detail:
1. Column spanner detection in ColumnLayoutAlgorithm (column-span: all).
2. Geometry: spanner breaks multi-column flow; spanner inline size spans full multicol width W_multicol (ignoring column count/gutters).
3. Invariants: spanner inline size W_span = W_multicol, spanner vertical placement advances beyond preceding columns, subsequent columns resume below spanner.
4. Concrete Rocq/Coq definitions and theorems for BlinkMulticolColumnSpannerSemantics.v."""
    },
    {
        "id": "agent157",
        "file": "agent157_form_button_sizing.md",
        "topic": "Chromium Blink Form Button Intrinsic Sizing & Padding (core/layout/forms/layout_button.cc)",
        "spec": "HTML Living Standard §4.10.8 & CSS 2.1 §10.3 (Button default UA padding, native borders, min-content width)",
        "prompt": """You are Agent 157 auditing Chromium Blink Button Intrinsic Sizing vs HTML §4.10.8 & CSS 2.1 §10.3.
Detail:
1. Form button layout in LayoutButton / LayoutTextControl.
2. Inline size calculation: W_button = max(text_width + 2 * padding + 2 * border, author_width).
3. Invariants: button inline size >= text run width, button height >= text line height + 2 * padding + 2 * border, non-negativity.
4. Concrete Rocq/Coq definitions and theorems for BlinkFormButtonSizingSemantics.v."""
    },
    {
        "id": "agent158",
        "file": "agent158_css_mask_alpha_composition.md",
        "topic": "Chromium Blink CSS Masking & Alpha Mask Composition (core/paint/mask_painter.cc)",
        "spec": "CSS Masking 1 §3 & §4 (mask-image, luminance-to-alpha conversion, alpha multiplication)",
        "prompt": """You are Agent 158 auditing Chromium Blink CSS Mask Alpha Composition vs CSS Masking 1 §3 & §4.
Detail:
1. Alpha mask application in MaskPainter (core/paint/mask_painter.cc).
2. Alpha multiplication: A_out = (A_src * A_mask) / 255.
3. Invariants: A_out bounded in [0, 255], A_mask = 0 gives A_out = 0 (full clip), A_mask = 255 gives A_out = A_src (full pass), monotonicity in both alphas.
4. Concrete Rocq/Coq definitions and theorems for BlinkCSSMaskAlphaCompositionSemantics.v."""
    },
    {
        "id": "agent159",
        "file": "agent159_outside_list_marker_alignment.md",
        "topic": "Chromium Blink Outside List Marker Positioning & Gutter Offset (core/layout/list/layout_outside_list_marker.cc)",
        "spec": "CSS Lists and Counters 3 §3 (list-style-position: outside, marker offset, non-overlap with text)",
        "prompt": """You are Agent 159 auditing Chromium Blink Outside List Marker Alignment vs CSS Lists 3 §3.
Detail:
1. Representation of outside list markers in LayoutOutsideListMarker.
2. Outside placement: marker is placed to the left (in LTR) of the list item's content edge by marker_width + spacing.
3. Invariants: marker right edge <= list item text left edge (disjointness / no overlap), marker advance non-negative, offset strictly negative relative to content box.
4. Concrete Rocq/Coq definitions and theorems for BlinkOutsideListMarkerAlignmentSemantics.v."""
    },
    {
        "id": "agent160",
        "file": "agent160_interactive_page_pipeline.md",
        "topic": "Chromium Blink Capstone Interactive Web Page Layout Pipeline (core/frame/local_frame_view.cc)",
        "spec": "HTML Living Standard & W3C CSS 2.1 / CSS 3 (Comprehensive page with headers, flex container, tables, list markers, and form buttons)",
        "prompt": """You are Agent 160 auditing Chromium Blink Capstone Interactive Page Layout Pipeline in LocalFrameView.
Detail:
1. Unified page assembly: Header 1 -> Paragraph -> Multi-line Flex Box -> 2-Column Table with Percent Columns -> Outside Marked List -> Styled Form Button.
2. Strict monotonic vertical accumulation of block cursors with inter-element margin collapsing.
3. Invariants: deterministic page fragment dimensions, viewport bounding, vertical monotonic stacking order of all elements, pairwise disjointness of table cells and button bounds.
4. Concrete Rocq/Coq definitions and theorems for BlinkInteractivePagePipelineModel.v."""
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
                thinking_config=types.ThinkingConfig(thinking_budget=512)
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
    print("Launching Wave 15: 16 concurrent Python3 agents using gemini-4-argon (low thinking budget 512) for Next Bottom-Up Formalization Areas...")
    with concurrent.futures.ThreadPoolExecutor(max_workers=16) as executor:
        results = list(executor.map(run_agent, tasks))

    total_p = sum(r.get("prompt_tokens", 0) for r in results)
    total_c = sum(r.get("candidates_tokens", 0) for r in results)
    total_t = sum(r.get("total_tokens", 0) for r in results)

    log_entry = {
        "timestamp": time.strftime("%Y-%m-%d %H:%M:%S"),
        "model": "gemini-4-argon",
        "wave": 15,
        "theme": "Bottom-Up Formalization of Interactive Web Page Subsystems (Flex Multi-Line Wrap, Grid 2 Subgrid Axis, Subpixel Layout Snapping, Affine Transform 2D, BiDi Neutral Resolution, Text Hyphenation Breaks, Table Percent Columns, CSS Containment Layout/Size, Clip Path Polygon, Scroll Snap Alignment, CSS Filter Color Matrix, Multicol Column Spanners, Form Button Sizing, CSS Mask Alpha Composition, Outside List Marker Alignment, Capstone Interactive Page Pipeline)",
        "thinking_budget": 512,
        "agents": results,
        "aggregate": {
            "prompt_tokens": total_p,
            "candidates_tokens": total_c,
            "total_tokens": total_t
        }
    }

    with open("token_usage.log", "a") as f:
        f.write(json.dumps(log_entry, indent=2) + "\n---\n")

    print("\n=== WAVE 15 (16 AGENTS: INTERACTIVE PAGE SUBSYSTEMS) TOKEN USAGE REPORT ===")
    print(f"Prompt Tokens:     {total_p}")
    print(f"Candidate Tokens:  {total_c}")
    print(f"Total Tokens Used: {total_t}")
    print("Appended log entry to token_usage.log.")

