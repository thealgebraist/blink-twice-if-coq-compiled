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
        "id": "agent81",
        "file": "agent81_clip_path_clipper.md",
        "topic": "Chromium Blink CSS Masking & Clip Paths (third_party/blink/renderer/core/paint/clip_path_clipper.cc)",
        "spec": "W3C CSS Masking Module Level 1 (§3 Clipping Paths: clip-path property and SVG clippath references)",
        "prompt": """You are Agent 81 auditing Chromium Blink ClipPathClipper vs CSS Masking Level 1 §3.
Detail:
1. Core data structures in Blink clip path clipping (ClipPathClipper, ClipPathOperation, FloatRoundedRect, Path, DisplayItemClient).
2. Clip evaluation and coordinate mapping: intersection between target bounding box and clip geometry (basic shapes vs SVG path).
3. Monotonic intersection and bounding box containment: Area(A ∩ B) <= Area(A), clipped bounding rect non-negativity.
4. Idempotence of repeated clipping operations with identical clip paths.
5. Provide concrete Rocq/Coq inductive definitions and theorems for formalizing this into BlinkClipPathGeometrySemantics.v."""
    },
    {
        "id": "agent82",
        "file": "agent82_text_indent_hanging.md",
        "topic": "Chromium Blink Text Indent & Hanging Punctuation (third_party/blink/renderer/core/layout/inline/inline_layout_algorithm.cc)",
        "spec": "W3C CSS Text Module Level 3 (§9 Spacing & Indentation: text-indent and hanging-punctuation)",
        "prompt": """You are Agent 82 auditing Chromium Blink Text Indent and Hanging Punctuation vs CSS Text Level 3 §9.
Detail:
1. Core data structures in Blink inline indentation (TextIndent, HangingPunctuation, LineInfo, InlineItem).
2. First formatted line detection and text-indent offset application (handling positive, negative, and percentage indents).
3. Hanging punctuation offset calculation: allowing initial/final punctuation glyphs to hang outside line box margins.
4. Mathematical invariants: available inline width adjustments, non-negative remaining line space or controlled overflow, line width conservation.
5. Provide concrete Rocq/Coq inductive definitions and theorems for formalizing this into BlinkTextIndentHangingSemantics.v."""
    },
    {
        "id": "agent83",
        "file": "agent83_flex_baseline_synthesis.md",
        "topic": "Chromium Blink Flexbox Baseline Alignment & Baseline Synthesis (third_party/blink/renderer/core/layout/flex/flex_layout_algorithm.cc)",
        "spec": "W3C CSS Flexible Box Layout Module Level 1 (§8.5 Aligning by Baselines) & CSS Box Alignment Module Level 3 (§9 Baseline Alignment)",
        "prompt": """You are Agent 83 auditing Chromium Blink Flexbox Baseline Alignment & Synthesis vs CSS Flexbox 1 §8.5 & Box Alignment 3 §9.
Detail:
1. Core data structures in Blink flex baseline calculations (FlexItem, BaselineGroup, FontBaseline, LogicalBoxStrut).
2. First vs last baseline synthesis: extracting font baseline from first/last child or falling back to box border/padding bottom/top edge.
3. Multi-item baseline grouping: computing max ascent and max descent across items sharing a baseline alignment context.
4. Mathematical invariants: synthesized baseline bounded within item border box, flex line cross size lower bounded by max ascent + max descent.
5. Provide concrete Rocq/Coq inductive definitions and theorems for formalizing this into BlinkFlexBaselineSynthesisSemantics.v."""
    },
    {
        "id": "agent84",
        "file": "agent84_grid_track_growth.md",
        "topic": "Chromium Blink CSS Grid Track Growth Algorithm Phase 2 (third_party/blink/renderer/core/layout/grid/grid_track_collection.cc)",
        "spec": "W3C CSS Grid Layout Module Level 1 (§11.5 Track Sizing Algorithm: Step 2 Max Breadth & Beyond Limits)",
        "prompt": """You are Agent 84 auditing Chromium Blink Grid Track Growth vs CSS Grid 1 §11.5.
Detail:
1. Core data structures in Blink grid track sizing (GridTrackCollection, GridSet, TrackSize, GridItemData).
2. Growth algorithm: distributing available space beyond base sizes up to max breadth across growable track sets.
3. Free space distribution weights, infinite max track handling, and freeze condition when space is exhausted.
4. Mathematical invariants: track base size monotonic growth (base' >= base), bounded by max track size if definite, space conservation sum(delta) <= FreeSpace.
5. Provide concrete Rocq/Coq inductive definitions and theorems for formalizing this into BlinkGridTrackGrowthSemantics.v."""
    },
    {
        "id": "agent85",
        "file": "agent85_table_border_conflict.md",
        "topic": "Chromium Blink Table Collapsed Border Conflict Resolution (third_party/blink/renderer/core/layout/table/table_borders.cc)",
        "spec": "W3C CSS 2.1 (§17.6.2.1 Border Conflict Resolution in Collapsed Borders Model)",
        "prompt": """You are Agent 85 auditing Chromium Blink Collapsed Table Borders vs CSS 2.1 §17.6.2.1.
Detail:
1. Core data structures in Blink table border resolution (TableBorders, TableBorderEdge, EBorderStyle, BorderPrecedence).
2. Conflict resolution rules: 'hidden' wins unconditionally > width comparison (thicker wins) > style priority (double > solid > dashed > dotted > ridge > outset > groove > inset) > tree order (cell > row > rowgroup > col > colgroup > table).
3. Transitivity, antisymmetry, and determinism of the border resolution total preorder.
4. Half-width distribution across adjoining cells in 26.6 LayoutUnit arithmetic.
5. Provide concrete Rocq/Coq inductive definitions and theorems for formalizing this into BlinkTableBorderConflictSemantics.v."""
    },
    {
        "id": "agent86",
        "file": "agent86_multicol_rule_geometry.md",
        "topic": "Chromium Blink Multi-Column Column Rules & Gutter Geometry (third_party/blink/renderer/core/paint/ng_multicol_painter.cc)",
        "spec": "W3C CSS Multi-column Layout Module Level 1 (§4 Column Rules: column-rule-width, column-rule-style, column-rule-color)",
        "prompt": """You are Agent 86 auditing Chromium Blink Multi-Column Column Rules vs CSS Multicol 1 §4.
Detail:
1. Core data structures in Blink multi-column painting (NGMulticolPainter, MultiColumnFlowThread, PhysicalRect, ColumnRule).
2. Column rule placement: centered in the gutter between adjacent column boxes without taking up space or affecting column width.
3. Gutter width and rule thickness bounds: rule centering formula offset = col_x + col_w + (gutter - rule_w)/2.
4. Mathematical invariants: rule position strictly bounded inside the multi-column container, non-overlapping with column content if rule <= gutter.
5. Provide concrete Rocq/Coq inductive definitions and theorems for formalizing this into BlinkMulticolRuleGeometrySemantics.v."""
    },
    {
        "id": "agent87",
        "file": "agent87_svg_filter_subregion.md",
        "topic": "Chromium Blink SVG Filter Primitive Subregion Clipping (third_party/blink/renderer/core/svg/graphics/filters/svg_filter_builder.cc)",
        "spec": "W3C Filter Effects Module Level 1 (§7 Filter Primitive Subregion: x, y, width, height on primitives)",
        "prompt": """You are Agent 87 auditing Chromium Blink SVG Filter Subregions vs W3C Filter Effects 1 §7.
Detail:
1. Core data structures in Blink SVG filter primitive processing (SVGFilterBuilder, FilterEffect, SVGFilterPrimitiveStandardAttributes, FloatRect).
2. Subregion calculation: default values inheriting from overall filter region, user-specified coordinates in filterUnits vs primitiveUnits.
3. Clipping filter primitive output: intersection of primitive natural effect rect with resolved primitive subregion rect.
4. Mathematical invariants: resulting rect is contained within both parent filter region and specified subregion, monotonic intersection area reduction.
5. Provide concrete Rocq/Coq inductive definitions and theorems for formalizing this into BlinkSVGFilterSubregionSemantics.v."""
    },
    {
        "id": "agent88",
        "file": "agent88_color_interpolation.md",
        "topic": "Chromium Blink CSS Color Gamut Clamping & Interpolation (third_party/blink/renderer/platform/graphics/color.cc)",
        "spec": "W3C CSS Color Module Level 4 (§12 Color Interpolation & §13 Resolving & Gamut Mapping)",
        "prompt": """You are Agent 88 auditing Chromium Blink Color Interpolation vs CSS Color 4 §12/§13.
Detail:
1. Core data structures in Blink color representation (Color, ColorSpace, RGBA32, ColorInterpolationSpace).
2. Linear interpolation in specified color spaces (sRGB, Display P3, OKLab), premultiplied alpha handling during lerp.
3. Channel clamping to valid gamut ranges: clamp(0, v, 255) or [0.0, 1.0].
4. Mathematical invariants: alpha conservation, convex combination boundary preservation (at t=0 matches C0, at t=1 matches C1), monotonicity of interpolation in t.
5. Provide concrete Rocq/Coq inductive definitions and theorems for formalizing this into BlinkColorInterpolationSemantics.v."""
    },
    {
        "id": "agent89",
        "file": "agent89_scroll_timeline_progress.md",
        "topic": "Chromium Blink CSS Scroll-Driven Animations & Timeline Progress (third_party/blink/renderer/core/animation/scroll_timeline.cc)",
        "spec": "W3C CSS Scroll-driven Animations Module Level 1 (§3 Scroll-driven Timelines: scroll() and view())",
        "prompt": """You are Agent 89 auditing Chromium Blink Scroll Timeline Progress vs CSS Scroll-driven Animations 1 §3.
Detail:
1. Core data structures in Blink scroll timeline evaluation (ScrollTimeline, ScrollTimelineOffset, TimelineRange, ScrollOffsets).
2. Progress computation: mapping current scroll offset S within scroll range [S_start, S_end] to normalized progress tau in [0, 1].
3. Edge case handling: zero scroll range (S_start == S_end), out-of-bounds scroll offsets (clamping vs phase inactive).
4. Mathematical invariants: monotonic mapping from scroll offset to progress, boundary values tau(S_start) = 0 and tau(S_end) = 1, progress containment in [0, 1].
5. Provide concrete Rocq/Coq inductive definitions and theorems for formalizing this into BlinkScrollTimelineProgressSemantics.v."""
    },
    {
        "id": "agent90",
        "file": "agent90_absolute_centering.md",
        "topic": "Chromium Blink Absolute Centering via Inset & Auto Margins (third_party/blink/renderer/core/layout/absolute_utils.cc)",
        "spec": "W3C CSS Positioned Layout Module Level 3 (§5 Centering Absolute Elements with auto Margins)",
        "prompt": """You are Agent 90 auditing Chromium Blink Absolute Centering vs CSS Positioned Layout 3 §5.
Detail:
1. Core data structures in Blink absolute positioning (LogicalOOFPositionedNode, AbsolutePosition, LogicalInsets, BoxStrut).
2. Inset-modified containing block calculation and auto-margin free space determination: FreeSpace = CB_size - (Inset_start + Inset_end + BorderBox_size).
3. Equal distribution of free space between start and end margins when both are 'auto': Margin_start = Margin_end = FreeSpace / 2.
4. Mathematical invariants: exact centering symmetry (Margin_start == Margin_end), total space conservation, non-negativity under positive free space.
5. Provide concrete Rocq/Coq inductive definitions and theorems for formalizing this into BlinkAbsoluteCenteringSemantics.v."""
    },
    {
        "id": "agent91",
        "file": "agent91_font_fallback_selection.md",
        "topic": "Chromium Blink Font Fallback Selection & Glyph Availability (third_party/blink/renderer/platform/fonts/font_fallback_iterator.cc)",
        "spec": "W3C CSS Fonts Module Level 4 (§5 Font Matching Algorithm: Font Family Fallback List)",
        "prompt": """You are Agent 91 auditing Chromium Blink Font Fallback Iterator vs CSS Fonts 4 §5.
Detail:
1. Core data structures in Blink font fallback (FontFallbackIterator, FontFallbackList, SimpleFontData, CharacterRun).
2. Fallback traversal: iterating through specified font family candidates in order, checking character coverage via HarfBuzz or cmap table.
3. System fallback termination: fallback to system UI / default font if no family in the font-family list covers code point U.
4. Mathematical invariants: finite iteration termination, monotonic search step, exact character set coverage partitioning.
5. Provide concrete Rocq/Coq inductive definitions and theorems for formalizing this into BlinkFontFallbackSemantics.v."""
    },
    {
        "id": "agent92",
        "file": "agent92_inline_fragmentation.md",
        "topic": "Chromium Blink Inline Line Box Fragmentation & Splitting (third_party/blink/renderer/core/layout/inline/inline_break_token.cc)",
        "spec": "W3C CSS Fragmentation Module Level 3 & CSS Inline Layout Module Level 3 (Breaking Inline Boxes Across Lines and Pages)",
        "prompt": """You are Agent 92 auditing Chromium Blink Inline Line Break Tokens vs CSS Fragmentation 3 & Inline 3.
Detail:
1. Core data structures in Blink inline break token propagation (InlineBreakToken, ItemIndex, TextOffset, LineBreakResult).
2. Splitting atomic runs, non-atomic inline boxes, and nested spans across multiple line boxes.
3. Resuming line layout: recording ItemIndex and TextOffset in InlineBreakToken to start subsequent line exactly where previous broke.
4. Mathematical invariants: strictly monotonic progress (item index / text offset strictly advances), total text length conservation upon completion, termination.
5. Provide concrete Rocq/Coq inductive definitions and theorems for formalizing this into BlinkInlineFragmentationSemantics.v."""
    },
    {
        "id": "agent93",
        "file": "agent93_svg_marker_angle.md",
        "topic": "Chromium Blink SVG Marker Auto-Angle & Transform (third_party/blink/renderer/core/layout/svg/layout_svg_resource_marker.cc)",
        "spec": "W3C SVG 2 (§13 Markers: orient attribute auto and auto-start-reverse)",
        "prompt": """You are Agent 93 auditing Chromium Blink SVG Marker Orientation vs SVG 2 §13.
Detail:
1. Core data structures in Blink SVG marker layout (LayoutSVGResourceMarker, MarkerPosition, FloatPoint, SVGMarkerData).
2. Auto angle calculation: computing tangent direction vector for start/end/mid markers, bisector angle between incoming and outgoing segments.
3. Auto-start-reverse angle reflection: reversing direction by 180 degrees (pi radians) on start marker.
4. Mathematical invariants: angle normalization to [0, 2*pi), bisector angle continuity, scale preservation of marker transform.
5. Provide concrete Rocq/Coq inductive definitions and theorems for formalizing this into BlinkSVGMarkerAngleSemantics.v."""
    },
    {
        "id": "agent94",
        "file": "agent94_layout_containment.md",
        "topic": "Chromium Blink CSS Size & Layout Containment (third_party/blink/renderer/core/layout/layout_box.cc)",
        "spec": "W3C CSS Containment Module Level 2 (§2 Size Containment & §3 Layout Containment)",
        "prompt": """You are Agent 94 auditing Chromium Blink Size & Layout Containment vs CSS Containment 2 §2/§3.
Detail:
1. Core data structures in Blink containment evaluation (ContainmentFlags, LayoutBox, MinMaxSizes, LayoutBlockFlow).
2. Size containment behavior: treating box as if it has no contents when calculating intrinsic sizes (min/max-content = 0 or specified ratio/fallback).
3. Layout containment behavior: box forms independent formatting context, internal floats/margins do not leak to parent.
4. Mathematical invariants: intrinsic min/max size monotonicity under containment, containment isolation (child changes do not affect parent intrinsic dimensions).
5. Provide concrete Rocq/Coq inductive definitions and theorems for formalizing this into BlinkLayoutContainmentSemantics.v."""
    },
    {
        "id": "agent95",
        "file": "agent95_motion_path_offset.md",
        "topic": "Chromium Blink CSS Motion Path Offset & Direction (third_party/blink/renderer/core/layout/layout_box_model_object.cc)",
        "spec": "W3C Motion Path Module Level 1 (§2 Motion Path Properties: offset-path, offset-distance, offset-rotate)",
        "prompt": """You are Agent 95 auditing Chromium Blink Motion Path vs W3C Motion Path 1 §2.
Detail:
1. Core data structures in Blink motion path evaluation (OffsetPath, LengthPercentage, MotionTransform, PathPosition).
2. Distance along path: converting offset-distance percentage/length to arc-length parameter s in [0, L] with clamping or modulo.
3. Transformation matrix derivation: translating element center to path point (x(s), y(s)) and applying rotation based on tangent angle.
4. Mathematical invariants: arc-length parameter containment in [0, L], angle continuity, distance monotonicity in progress.
5. Provide concrete Rocq/Coq inductive definitions and theorems for formalizing this into BlinkMotionPathOffsetSemantics.v."""
    },
    {
        "id": "agent96",
        "file": "agent96_oof_bubble_propagation.md",
        "topic": "Chromium Blink Out-of-Flow Bubble Propagation in Fragment Tree (third_party/blink/renderer/core/layout/box_fragment_builder.cc)",
        "spec": "W3C CSS Positioned Layout Module Level 3 & CSS Fragmentation Module Level 3 (Bubbling OOF Candidates Across Fragment Boundaries)",
        "prompt": """You are Agent 96 auditing Chromium Blink OOF Candidate Bubbling vs CSS Positioned Layout 3 & Fragmentation 3.
Detail:
1. Core data structures in Blink OOF bubbling (BoxFragmentBuilder, LogicalOOFPositionedNode, PhysicalFragment, ContainingBlockScope).
2. Propagation mechanism: child fragments propagate unhandled OOF positioned nodes up the fragment tree to ancestor builders.
3. Containing block matching: when an ancestor builder is identified as the containing block for node N, N is consumed and laid out.
4. Mathematical invariants: candidate node set union monotonically grows until containing block is reached, candidate set is partitioned into consumed vs forwarded sets, no loss of OOF nodes.
5. Provide concrete Rocq/Coq inductive definitions and theorems for formalizing this into BlinkOOFBubblePropagationSemantics.v."""
    }
]

def run_agent(task):
    print(f"[{task['id']}] Starting audit for {task['topic']}...")
    t0 = time.time()
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
    print("Launching Wave 12: 16 concurrent Python3 agents using gemini-4-argon (thinking budget 1024) across Central Blink Areas...")
    with concurrent.futures.ThreadPoolExecutor(max_workers=16) as executor:
        results = list(executor.map(run_agent, tasks))

    total_p = sum(r.get("prompt_tokens", 0) for r in results)
    total_c = sum(r.get("candidates_tokens", 0) for r in results)
    total_t = sum(r.get("total_tokens", 0) for r in results)

    log_entry = {
        "timestamp": time.strftime("%Y-%m-%d %H:%M:%S"),
        "model": "gemini-4-argon",
        "wave": 12,
        "theme": "16 Central Engine Areas (Clip Path Clipper, Text Indent & Hanging, Flex Baseline Synthesis, Grid Track Growth, Table Border Conflict, Multicol Rule Geometry, SVG Filter Subregions, Color Interpolation & Gamut, Scroll Timeline Progress, Absolute Centering, Font Fallback Selection, Inline Fragmentation Break Tokens, SVG Marker Auto-Angle, Layout & Size Containment, Motion Path Offset, OOF Bubble Propagation)",
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

    print("\n=== WAVE 12 (16 AGENTS: CENTRAL BLINK AREAS) TOKEN USAGE REPORT ===")
    print(f"Prompt Tokens:     {total_p}")
    print(f"Candidate Tokens:  {total_c}")
    print(f"Total Tokens Used: {total_t}")
    print("Appended log entry to token_usage.log.")

