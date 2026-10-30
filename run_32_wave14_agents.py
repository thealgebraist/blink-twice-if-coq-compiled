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
        "id": "agent113",
        "file": "agent113_table_dynamic_grid.md",
        "topic": "Chromium Blink Table Dynamic M x N Grid & Cell Indexing (core/layout/table/table_layout_algorithm.cc)",
        "spec": "CSS 2.1 §17.5 & CSS Table 3 §3 (Dynamic M x N Table Grid Indexing)",
        "prompt": """You are Agent 113 auditing Chromium Blink Dynamic Table Grid Geometry vs CSS 2.1 §17.5 and CSS Table 3 §3.
Detail:
1. Core data structures in Blink LayoutNG table layout for M x N grids: TableGridData, TableRowGroup, TableRow, TableCell.
2. Grid coordinate mapping: cell at row r, col c receives coordinates from row offsets and column positions.
3. Invariants: index bounds validity 0 <= r < R, 0 <= c < C, row offset monotonicity, column coordinate preservation.
4. Concrete Rocq/Coq definitions and theorems for BlinkTableDynamicGridSemantics.v."""
    },
    {
        "id": "agent114",
        "file": "agent114_table_colspan_rowspan.md",
        "topic": "Chromium Blink Table Colspan & Rowspan Expansion (core/layout/table/table_grid_cell.cc)",
        "spec": "HTML Living Standard §4.9.11 & CSS 2.1 §17.5.1 (Colspan and Rowspan Geometry)",
        "prompt": """You are Agent 114 auditing Chromium Blink Colspan/Rowspan expansion vs HTML §4.9.11 and CSS 2.1 §17.5.1.
Detail:
1. Representation of spanned cells across multiple columns/rows, clamping bounds (1 <= span <= 65534).
2. Spanned width and height accumulation: width is sum of spanned column widths plus (span - 1) * border_spacing.
3. Invariants: span width >= individual column width, disjointness of non-overlapping multi-span cells.
4. Concrete Rocq/Coq definitions and theorems for BlinkTableColspanRowspanSemantics.v."""
    },
    {
        "id": "agent115",
        "file": "agent115_html_paragraph_layout.md",
        "topic": "Chromium Blink Paragraph Layout & Inter-Paragraph Margin Collapsing (core/layout/block/block_layout_algorithm.cc)",
        "spec": "HTML Living Standard §4.4.1 & CSS 2.1 §9.4.1 (Paragraph Formatting)",
        "prompt": """You are Agent 115 auditing Chromium Blink Paragraph Layout vs HTML §4.4.1 and CSS 2.1 §9.4.1.
Detail:
1. Paragraph block formatting, default UA vertical margins (1em = 16px top and bottom).
2. Inter-paragraph margin collapsing: collapse_margins 16 16 = 16px spacing between consecutive paragraphs.
3. Invariants: vertical cursor monotonicity, paragraph height non-negativity, paragraph advance.
4. Concrete Rocq/Coq definitions and theorems for BlinkHTMLParagraphLayoutSemantics.v."""
    },
    {
        "id": "agent116",
        "file": "agent116_html_list_layout.md",
        "topic": "Chromium Blink HTML Lists & Counter Progression (core/layout/list/layout_list_item.cc)",
        "spec": "HTML Living Standard §4.4.4-4.4.8 & CSS Lists 3 §3 (Lists ul, ol, li)",
        "prompt": """You are Agent 116 auditing Chromium Blink List Item Layout vs HTML §4.4.4-4.4.8 and CSS Lists 3 §3.
Detail:
1. Ordered list (ol) counter sequence: item k receives ordinal k (1, 2, ..., N), unordered list (ul) bullet marker.
2. Marker indentation and list padding (default UA 40px left padding).
3. Invariants: counter strictly increasing, marker fits in padding box, list item vertical stacking.
4. Concrete Rocq/Coq definitions and theorems for BlinkHTMLListLayoutSemantics.v."""
    },
    {
        "id": "agent117",
        "file": "agent117_css_box_sizing.md",
        "topic": "Chromium Blink CSS box-sizing content-box vs border-box (core/layout/geometry/box_strut.cc)",
        "spec": "W3C CSS Box Sizing 3 §3 (box-sizing property)",
        "prompt": """You are Agent 117 auditing Chromium Blink CSS box-sizing vs CSS Box Sizing 3 §3.
Detail:
1. Definition of content-box: specified width is content width; border-box width is W + border + padding.
2. Definition of border-box: specified width includes border and padding; content width is max(0, W - border - padding).
3. Invariants: non-negativity of content width, idempotence, invertibility when W >= border + padding.
4. Concrete Rocq/Coq definitions and theorems for BlinkCSSBoxSizingSemantics.v."""
    },
    {
        "id": "agent118",
        "file": "agent118_css_border_box.md",
        "topic": "Chromium Blink CSS Border Box Geometry & Border Styles (core/paint/box_border_painter.cc)",
        "spec": "W3C CSS Backgrounds and Borders 3 §4 (Borders: width, style, color)",
        "prompt": """You are Agent 118 auditing Chromium Blink Border Box Geometry vs CSS Backgrounds & Borders 3 §4.
Detail:
1. Outer border box encompasses inner padding box; border widths for top, right, bottom, left.
2. Border style enumeration (none, solid, dashed, dotted, double).
3. Invariants: outer box dimensions = inner dimensions + 2 * border_width, border box area monotonic in border width.
4. Concrete Rocq/Coq definitions and theorems for BlinkCSSBorderBoxSemantics.v."""
    },
    {
        "id": "agent119",
        "file": "agent119_css_padding_geometry.md",
        "topic": "Chromium Blink CSS Padding Geometry & Content Area Clamping (core/layout/ng_box_fragment.cc)",
        "spec": "W3C CSS Box Model 3 §6 (Padding Box Geometry)",
        "prompt": """You are Agent 119 auditing Chromium Blink Padding Geometry vs CSS Box Model 3 §6.
Detail:
1. Padding constraints: padding values must be non-negative (P >= 0).
2. Content box derivation: content_x = pad_x + pad_left, content_y = pad_y + pad_top.
3. Invariants: content box strictly contained within padding box, padding box area monotonic in padding.
4. Concrete Rocq/Coq definitions and theorems for BlinkCSSPaddingGeometrySemantics.v."""
    },
    {
        "id": "agent120",
        "file": "agent120_css_background_clip.md",
        "topic": "Chromium Blink CSS Background Painting Area & Clipping (core/paint/background_image_geometry.cc)",
        "spec": "W3C CSS Backgrounds and Borders 3 §3 (background-clip property)",
        "prompt": """You are Agent 120 auditing Chromium Blink Background Clip vs CSS Backgrounds & Borders 3 §3.
Detail:
1. Clipping rect derivation for border-box, padding-box, content-box.
2. Geometric containment hierarchy: ContentBox <= PaddingBox <= BorderBox.
3. Invariants: clip area monotonicity, point containment transitivity.
4. Concrete Rocq/Coq definitions and theorems for BlinkCSSBackgroundClipSemantics.v."""
    },
    {
        "id": "agent121",
        "file": "agent121_text_decoration.md",
        "topic": "Chromium Blink CSS Text Decoration Geometry (core/paint/text_decoration_painter.cc)",
        "spec": "W3C CSS Text Decoration 3 §2 (underline, overline, line-through)",
        "prompt": """You are Agent 121 auditing Chromium Blink Text Decoration vs CSS Text Decoration 3 §2.
Detail:
1. Text decoration line geometry: thickness T >= 1, vertical offset relative to font alphabetic baseline.
2. Underline below baseline, overline above ascent, line-through across mid-cap.
3. Invariants: line thickness non-negativity, decoration bounds contained within line box vertical extent.
4. Concrete Rocq/Coq definitions and theorems for BlinkTextDecorationSemantics.v."""
    },
    {
        "id": "agent122",
        "file": "agent122_css_font_weight_style.md",
        "topic": "Chromium Blink CSS Font Weight & Style Resolution (core/css/resolver/font_builder.cc)",
        "spec": "W3C CSS Fonts 4 §2 & §5 (font-weight and font-style resolution)",
        "prompt": """You are Agent 122 auditing Chromium Blink Font Weight/Style Resolution vs CSS Fonts 4 §2/§5.
Detail:
1. Font weight quantization: 100, 200, ..., 900, normal=400, bold=700.
2. Bolder / lighter stepped transitions; font-style matching (normal, italic, oblique).
3. Invariants: font weight clamping [100, 900], bolder monotonicity, determinism.
4. Concrete Rocq/Coq definitions and theorems for BlinkCSSFontWeightStyleSemantics.v."""
    },
    {
        "id": "agent123",
        "file": "agent123_css_spacing.md",
        "topic": "Chromium Blink CSS Letter Spacing & Word Spacing (core/layout/inline/inline_layout_algorithm.cc)",
        "spec": "W3C CSS Text 3 §8 (letter-spacing and word-spacing)",
        "prompt": """You are Agent 123 auditing Chromium Blink Letter/Word Spacing vs CSS Text 3 §8.
Detail:
1. Tracking expansion formula: total_width = N * glyph_w + (N - 1) * letter_spacing + word_count * word_spacing.
2. Handling of negative spacing, clamping to zero or negative offsets.
3. Invariants: total advance monotonic in letter_spacing and word_spacing for fixed character count.
4. Concrete Rocq/Coq definitions and theorems for BlinkCSSSpacingSemantics.v."""
    },
    {
        "id": "agent124",
        "file": "agent124_line_box_stacking.md",
        "topic": "Chromium Blink Multiline Line Box Stacking (core/layout/inline/line_box_fragment_builder.cc)",
        "spec": "W3C CSS Inline 3 §3 & CSS 2.1 §10.8 (Multiline Line Box Stacking)",
        "prompt": """You are Agent 124 auditing Chromium Blink Line Box Stacking vs CSS Inline 3 §3 and CSS 2.1 §10.8.
Detail:
1. Accumulation of multiple line boxes within a block container: total_height = sum line_heights.
2. Line box offset progression: y_{k+1} = y_k + h_k.
3. Invariants: line box index monotonicity, non-overlapping vertical line boxes, total height non-negativity.
4. Concrete Rocq/Coq definitions and theorems for BlinkLineBoxStackingSemantics.v."""
    },
    {
        "id": "agent125",
        "file": "agent125_overflow_clipping.md",
        "topic": "Chromium Blink CSS Overflow Clipping (core/layout/overflow_model.cc)",
        "spec": "W3C CSS Overflow 3 §3 (overflow: visible vs hidden vs clip)",
        "prompt": """You are Agent 125 auditing Chromium Blink Overflow Clipping vs CSS Overflow 3 §3.
Detail:
1. Clip rect computation for overflow: hidden based on padding box.
2. Ink overflow vs scrollable overflow containment.
3. Invariants: scrollable overflow encompasses padding box, clipped paint region contained within clip rect.
4. Concrete Rocq/Coq definitions and theorems for BlinkOverflowClippingSemantics.v."""
    },
    {
        "id": "agent126",
        "file": "agent126_replaced_element.md",
        "topic": "Chromium Blink CSS Replaced Elements img & Aspect Ratio (core/layout/ng_replaced_layout_algorithm.cc)",
        "spec": "W3C CSS 2.1 §10.3.2 & CSS Sizing 3 §5 (Replaced Elements and Aspect Ratio)",
        "prompt": """You are Agent 126 auditing Chromium Blink Replaced Element Layout vs CSS 2.1 §10.3.2 and CSS Sizing 3 §5.
Detail:
1. Intrinsic dimensions and aspect ratio preservation: W * H_0 = H * W_0.
2. Resolution when only width or only height is specified.
3. Invariants: dimension non-negativity, aspect ratio scaling consistency, containment in container width.
4. Concrete Rocq/Coq definitions and theorems for BlinkReplacedElementSemantics.v."""
    },
    {
        "id": "agent127",
        "file": "agent127_nested_table_layout.md",
        "topic": "Chromium Blink Nested Table Layout (core/layout/table/table_layout_algorithm.cc)",
        "spec": "W3C CSS 2.1 §17.5 (Nested Tables in Table Cells)",
        "prompt": """You are Agent 127 auditing Chromium Blink Nested Table Layout vs CSS 2.1 §17.5.
Detail:
1. Embedding a table inside a table cell: cell available inline size acts as containing block width for inner table.
2. Inner table height contribution to outer cell min/max and row height.
3. Invariants: inner table coordinates contained within outer cell, outer cell height >= inner table height.
4. Concrete Rocq/Coq definitions and theorems for BlinkNestedTableLayoutSemantics.v."""
    },
    {
        "id": "agent128",
        "file": "agent128_table_caption_layout.md",
        "topic": "Chromium Blink Table Caption Placement (core/layout/table/table_layout_algorithm.cc)",
        "spec": "W3C CSS 2.1 §17.4 (Table Captions: caption-side top and bottom)",
        "prompt": """You are Agent 128 auditing Chromium Blink Table Caption Placement vs CSS 2.1 §17.4.
Detail:
1. Caption positioning: caption-side: top places caption above table grid; bottom places caption below grid.
2. Caption width matches table grid width.
3. Invariants: top caption Y + H <= table grid Y, table total height = caption_height + grid_height.
4. Concrete Rocq/Coq definitions and theorems for BlinkTableCaptionLayoutSemantics.v."""
    },
    {
        "id": "agent129",
        "file": "agent129_table_section_stacking.md",
        "topic": "Chromium Blink Table Section Stacking thead, tbody, tfoot (core/layout/table/table_section_layout_algorithm.cc)",
        "spec": "HTML Living Standard §4.9.5-4.9.7 & CSS 2.1 §17.5 (Table Section Stacking)",
        "prompt": """You are Agent 129 auditing Chromium Blink Table Section Stacking vs HTML §4.9.5-4.9.7 and CSS 2.1 §17.5.
Detail:
1. Section visual ordering: thead rendered first, then all tbody sections, then tfoot rendered last.
2. Section vertical stacking offset calculation: Y_k+1 = Y_k + H_k + border_spacing.
3. Invariants: section order preservation, section vertical disjointness, total table height decomposition.
4. Concrete Rocq/Coq definitions and theorems for BlinkTableSectionStackingSemantics.v."""
    },
    {
        "id": "agent130",
        "file": "agent130_css_color_alpha_blending.md",
        "topic": "Chromium Blink CSS Color & Alpha Blending (core/css/resolver/style_cascade.cc)",
        "spec": "W3C CSS Color 4 §12 & Compositing 1 §3 (Alpha Blending and Compositing)",
        "prompt": """You are Agent 130 auditing Chromium Blink CSS Color & Alpha Blending vs CSS Color 4 §12.
Detail:
1. RGBA color channel clamping to [0, 255].
2. Source-over alpha compositing: C = (alpha * C_src + (255 - alpha) * C_dst) / 255.
3. Invariants: blended channel remains in [0, 255], opacity monotonicity, boundary identity (alpha=255 -> src, alpha=0 -> dst).
4. Concrete Rocq/Coq definitions and theorems for BlinkCSSColorAlphaBlendingSemantics.v."""
    },
    {
        "id": "agent131",
        "file": "agent131_bfc_isolation.md",
        "topic": "Chromium Blink Block Formatting Context (BFC) Isolation (core/layout/block/block_layout_algorithm.cc)",
        "spec": "W3C CSS 2.1 §9.4.1 (Block Formatting Contexts)",
        "prompt": """You are Agent 131 auditing Chromium Blink BFC Isolation vs CSS 2.1 §9.4.1.
Detail:
1. Conditions establishing a BFC (overflow != visible, float != none, display: inline-block, etc.).
2. Margin collapsing isolation: margins do not collapse across BFC root boundaries.
3. Invariants: internal margins confined to BFC, BFC root encompasses internal floats.
4. Concrete Rocq/Coq definitions and theorems for BlinkBFCIsolationSemantics.v."""
    },
    {
        "id": "agent132",
        "file": "agent132_float_exclusion.md",
        "topic": "Chromium Blink Float Positioning & Text Exclusion (core/layout/floats_utils.cc)",
        "spec": "W3C CSS 2.1 §9.5.1 (Floats and Exclusion Geometry)",
        "prompt": """You are Agent 132 auditing Chromium Blink Float Positioning vs CSS 2.1 §9.5.1.
Detail:
1. Left/right float placement at container boundary, available inline space reduction for subsequent inline boxes.
2. Invariants: line box inline size = container_width - float_width, float Y >= current cursor, line box non-negativity.
3. Concrete Rocq/Coq definitions and theorems for BlinkFloatExclusionSemantics.v."""
    },
    {
        "id": "agent133",
        "file": "agent133_clearance_computation.md",
        "topic": "Chromium Blink CSS Clearance Computation (core/layout/block/block_layout_algorithm.cc)",
        "spec": "W3C CSS 2.1 §9.5.2 (Clearance property clear: left, right, both)",
        "prompt": """You are Agent 133 auditing Chromium Blink Clearance Computation vs CSS 2.1 §9.5.2.
Detail:
1. Clearance calculation: clearance = max(0, float_bottom - (block_y + margin_top)).
2. Effective margin and cursor advancement past preceding floats.
3. Invariants: clearance >= 0, cleared block Y >= float_bottom, clearance monotonicity.
4. Concrete Rocq/Coq definitions and theorems for BlinkClearanceComputationSemantics.v."""
    },
    {
        "id": "agent134",
        "file": "agent134_inline_block_layout.md",
        "topic": "Chromium Blink Inline-Block Layout Semantics (core/layout/inline/inline_node.cc)",
        "spec": "W3C CSS 2.1 §9.2.4 & CSS Inline 3 §3 (display: inline-block)",
        "prompt": """You are Agent 134 auditing Chromium Blink Inline-Block Layout vs CSS 2.1 §9.2.4 and CSS Inline 3 §3.
Detail:
1. Atomic inline box: treated as inline from the outside, block container from the inside.
2. Baseline determination: baseline of inline-block is baseline of its last line box (or bottom margin edge if no lines).
3. Invariants: inline-block width preserved as atomic advance, baseline offset non-negativity.
4. Concrete Rocq/Coq definitions and theorems for BlinkInlineBlockLayoutSemantics.v."""
    },
    {
        "id": "agent135",
        "file": "agent135_relative_position_offset.md",
        "topic": "Chromium Blink Relative Positioning Offsets (core/layout/geometry/box_strut.cc)",
        "spec": "W3C CSS 2.1 §9.4.3 & CSS Position 3 §2 (position: relative)",
        "prompt": """You are Agent 135 auditing Chromium Blink Relative Positioning vs CSS 2.1 §9.4.3.
Detail:
1. In-flow footprint preservation: flow layout occupies original static bounds without shift.
2. Visual paint coordinate offset: visual_x = static_x + left, visual_y = static_y + top.
3. Invariants: flow geometry invariant under relative shift, visual shift linearity.
4. Concrete Rocq/Coq definitions and theorems for BlinkRelativePositionOffsetSemantics.v."""
    },
    {
        "id": "agent136",
        "file": "agent136_sticky_constraint.md",
        "topic": "Chromium Blink Sticky Positioning Constraint Calculation (core/layout/sticky_position_data.cc)",
        "spec": "W3C CSS Positioned Layout 3 §6 (position: sticky)",
        "prompt": """You are Agent 136 auditing Chromium Blink Sticky Positioning Constraints vs CSS Position 3 §6.
Detail:
1. Sticky constraint rectangle: min_offset and max_offset derived from scroll container and containing block bounds.
2. Effective sticky offset clamping: clamped_y = max(min_y, min(max_y, scroll_y + top_inset)).
3. Invariants: clamped sticky offset within containing block bounds, non-negative sticky translation bounds.
4. Concrete Rocq/Coq definitions and theorems for BlinkStickyConstraintSemantics.v."""
    },
    {
        "id": "agent137",
        "file": "agent137_stacking_tree.md",
        "topic": "Chromium Blink Stacking Context Tree & Paint Order (core/paint/paint_layer_stacking_node.cc)",
        "spec": "W3C CSS 2.1 Appendix E & CSS Position 3 §8 (Stacking Contexts and Paint Order)",
        "prompt": """You are Agent 137 auditing Chromium Blink Stacking Context Tree vs CSS 2.1 Appendix E.
Detail:
1. Stacking context formation (root, position + z-index != auto, opacity < 1, transform != none).
2. Integer z-index sorting: negative z-index -> in-flow block -> positive z-index.
3. Invariants: total preorder by z-index, child stacking context isolation, paint tree traversal determinism.
4. Concrete Rocq/Coq definitions and theorems for BlinkStackingTreeSemantics.v."""
    },
    {
        "id": "agent138",
        "file": "agent138_css_visibility.md",
        "topic": "Chromium Blink CSS Visibility visible vs hidden vs collapse (core/paint/box_painter.cc)",
        "spec": "W3C CSS 2.1 §11.2 & §17.5.5 (visibility property)",
        "prompt": """You are Agent 138 auditing Chromium Blink CSS Visibility vs CSS 2.1 §11.2 and §17.5.5.
Detail:
1. visibility: hidden preserves exact layout footprint (dimensions and margin collapsing unchanged) but suppresses paint.
2. visibility: collapse in table rows removes row height while preserving column widths.
3. Invariants: layout dimensions identical between visible and hidden, collapse row height = 0.
4. Concrete Rocq/Coq definitions and theorems for BlinkCSSVisibilitySemantics.v."""
    },
    {
        "id": "agent139",
        "file": "agent139_white_space_collapsing.md",
        "topic": "Chromium Blink CSS White-Space Collapsing (core/layout/inline/inline_text_auto_space.cc)",
        "spec": "W3C CSS Text 3 §4 (white-space collapsing and preservation)",
        "prompt": """You are Agent 139 auditing Chromium Blink White-Space Collapsing vs CSS Text 3 §4.
Detail:
1. White-space handling: normal collapses sequences of whitespace into single space; pre preserves all spaces and newlines.
2. Collapsed text advance calculation.
3. Invariants: collapsed length <= original length, collapsing operator idempotence, length non-negativity.
4. Concrete Rocq/Coq definitions and theorems for BlinkWhiteSpaceCollapsingSemantics.v."""
    },
    {
        "id": "agent140",
        "file": "agent140_block_height_clamping.md",
        "topic": "Chromium Blink Block Height Clamping min-height and max-height (core/layout/block/block_layout_algorithm.cc)",
        "spec": "W3C CSS 2.1 §10.6.4 & CSS Sizing 3 §5 (min-height and max-height)",
        "prompt": """You are Agent 140 auditing Chromium Blink Block Height Clamping vs CSS 2.1 §10.6.4.
Detail:
1. Clamping rule: resolved_h = max(min_h, min(max_h, h)).
2. Special case when min_h > max_h (spec mandates min_h wins).
3. Invariants: resolved_h >= min_h, resolved_h <= max(min_h, max_h), monotonicity in input height h.
4. Concrete Rocq/Coq definitions and theorems for BlinkBlockHeightClampingSemantics.v."""
    },
    {
        "id": "agent141",
        "file": "agent141_block_width_clamping.md",
        "topic": "Chromium Blink Block Width Clamping min-width and max-width (core/layout/block/block_layout_algorithm.cc)",
        "spec": "W3C CSS 2.1 §10.4 & CSS Sizing 3 §5 (min-width and max-width)",
        "prompt": """You are Agent 141 auditing Chromium Blink Block Width Clamping vs CSS 2.1 §10.4.
Detail:
1. Clamping rule: resolved_w = max(min_w, min(max_w, w)).
2. Special case when min_w > max_w (min_w wins).
3. Invariants: resolved_w >= min_w, resolved_w <= max(min_w, max_w), monotonicity in input width w.
4. Concrete Rocq/Coq definitions and theorems for BlinkBlockWidthClampingSemantics.v."""
    },
    {
        "id": "agent142",
        "file": "agent142_html_form_control_layout.md",
        "topic": "Chromium Blink HTML Form Controls Layout (core/layout/forms/layout_text_control.cc)",
        "spec": "HTML Living Standard §4.10 & CSS Form Controls 1 (input, button layout)",
        "prompt": """You are Agent 142 auditing Chromium Blink Form Controls Layout vs HTML §4.10.
Detail:
1. Form control intrinsic minimum dimensions (default text input width ~20ch, button min height).
2. Native border/padding absorption and baseline alignment in line boxes.
3. Invariants: control dimensions non-negativity, button baseline aligns with text baseline.
4. Concrete Rocq/Coq definitions and theorems for BlinkHTMLFormControlLayoutSemantics.v."""
    },
    {
        "id": "agent143",
        "file": "agent143_document_fragment_hierarchy.md",
        "topic": "Chromium Blink Document Physical Fragment Hierarchy Serialization (core/layout/box_fragment_builder.cc)",
        "spec": "W3C CSS Box Model 3 & Display 3 (Document Fragment Tree Hierarchy)",
        "prompt": """You are Agent 143 auditing Chromium Blink Physical Fragment Tree vs CSS Box Model 3.
Detail:
1. Fragment tree traversal: root document -> body fragment -> block fragments -> row/line fragments.
2. Bounding box enclosing union: parent bounding box encompasses all child physical fragments.
3. Invariants: tree acyclicity, pre-order child count conservation, fragment coordinates non-negativity.
4. Concrete Rocq/Coq definitions and theorems for BlinkDocumentFragmentHierarchySemantics.v."""
    },
    {
        "id": "agent144",
        "file": "agent144_composite_web_page_model.md",
        "topic": "Chromium Blink End-to-End Composite Web Page Layout Model (core/frame/local_frame_view.cc)",
        "spec": "HTML Living Standard + W3C CSS 2.1 Composite Web Page Model",
        "prompt": """You are Agent 144 auditing the End-to-End Composite Web Page Layout Pipeline in Blink.
Detail:
1. Full composite page layout pipeline integrating:
   - Headers (h1, h2) with margin collapsing
   - Paragraphs (p) with text runs and spacing
   - Lists (ol, ul, li) with counter progression
   - Tables with dynamic grid, rows, cells, and separated borders
   - CSS box-sizing (border-box vs content-box)
   - Borders and padding geometry
2. Concrete evaluation of a composite web page with exact integer coordinates in Rocq/Coq.
3. Complete mathematical proofs of determinism, root dimension matching, vertical ordering, and pairwise disjointness.
4. Concrete Rocq/Coq definitions and theorems for BlinkCompositeWebPageModel.v."""
    }
]

def run_agent(task):
    t0 = time.time()
    try:
        response = client.models.generate_content(
            model='gemini-4-argon',
            contents=task['prompt'],
            config=types.GenerateContentConfig(
                thinking_config=types.ThinkingConfig(thinking_budget=512),
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
    print("Launching Wave 14: 32 concurrent Python3 agents using gemini-4-argon (low thinking budget 512) for Next Bottom-Up Formalization Areas...")
    with concurrent.futures.ThreadPoolExecutor(max_workers=32) as executor:
        results = list(executor.map(run_agent, tasks))

    total_p = sum(r.get("prompt_tokens", 0) for r in results)
    total_c = sum(r.get("candidates_tokens", 0) for r in results)
    total_t = sum(r.get("total_tokens", 0) for r in results)

    log_entry = {
        "timestamp": time.strftime("%Y-%m-%d %H:%M:%S"),
        "model": "gemini-4-argon",
        "wave": 14,
        "theme": "Bottom-Up Formalization of Composite Web Page (Dynamic M x N Tables, Colspan/Rowspan, Paragraphs, Lists, Box-Sizing, Borders, Padding, Background Clip, Text Decoration, Font Weight/Style, Letter/Word Spacing, Line Box Stacking, Overflow Clipping, Replaced Images, Nested Tables, Captions, Sections thead/tbody/tfoot, Color Alpha Blending, BFC Isolation, Float Exclusion, Clearance, Inline-Block, Relative Position, Sticky Constraints, Stacking Context Tree, Visibility, White-Space Collapsing, Block Height Clamping, Block Width Clamping, Form Controls, Document Fragment Hierarchy, Composite Web Page Model)",
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

    print("\n=== WAVE 14 (32 AGENTS: COMPOSITE WEB PAGE FORMALIZATION) TOKEN USAGE REPORT ===")
    print(f"Prompt Tokens:     {total_p}")
    print(f"Candidate Tokens:  {total_c}")
    print(f"Total Tokens Used: {total_t}")
    print("Appended log entry to token_usage.log.")

