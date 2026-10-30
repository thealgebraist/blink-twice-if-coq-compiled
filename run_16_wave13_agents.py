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
        "id": "agent97",
        "file": "agent97_html_tag_ast.md",
        "topic": "Chromium Blink HTML Element AST & Parser Tree Construction (third_party/blink/renderer/core/html/parser/html_element_stack.cc)",
        "spec": "HTML Living Standard (§13.2.6 Tree Construction for HTML, Body, Headers h1-h6, Table, TR, TH, TD)",
        "prompt": """You are Agent 97 auditing Chromium Blink HTML Parser Element Tree Construction vs HTML Living Standard §13.2.6.
Detail:
1. Core data structures in Blink HTML parser (HTMLStackItem, HTMLElementStack, HTMLConstructionSite, ContainerNode).
2. AST representation for basic HTML documents: Document -> HTML -> Body -> Headers (h1-h6), Table (Table -> TR -> TH/TD), Text nodes.
3. Node hierarchy validation: tables only contain rows/sections, rows only contain cells, headers contain inline text.
4. Mathematical invariants: structural inductive well-formedness, tree acyclicity, depth boundedness.
5. Concrete Rocq/Coq inductive definitions and theorems for formalizing this into BlinkHTMLTagASTSemantics.v."""
    },
    {
        "id": "agent98",
        "file": "agent98_html_ua_stylesheet.md",
        "topic": "Chromium Blink Default User Agent Stylesheet (third_party/blink/renderer/core/html/resources/html.css)",
        "spec": "HTML Living Standard (§15 Rendering: Default UA Stylesheet for Body, Headers, Table, TR, TD, TH)",
        "prompt": """You are Agent 98 auditing Chromium Blink UA Stylesheet vs HTML Living Standard §15.
Detail:
1. Core UA rules in Blink html.css for basic HTML elements:
   - body: display: block; margin: 8px;
   - h1: display: block; font-size: 2em; font-weight: bold; margin-block: 0.67em;
   - h2: display: block; font-size: 1.5em; font-weight: bold; margin-block: 0.83em;
   - table: display: table; border-collapse: separate; border-spacing: 2px;
   - tr: display: table-row; vertical-align: inherit;
   - td, th: display: table-cell; padding: 1px; vertical-align: inherit;
   - th: font-weight: bold; text-align: center;
2. Mapping from element tag name to initial UA Style struct.
3. Mathematical invariants: completeness of default style mapping, non-negative default margins and paddings, determinism.
4. Concrete Rocq/Coq inductive definitions and theorems for formalizing this into BlinkHTMLUASheetSemantics.v."""
    },
    {
        "id": "agent99",
        "file": "agent99_css_unit_resolution.md",
        "topic": "Chromium Blink CSS Value Units & Font Size Relative Resolution (third_party/blink/renderer/core/css/css_to_length_conversion_data.cc)",
        "spec": "W3C CSS Values and Units Module Level 4 (§5 Distance Units: px, em, rem, % to 26.6 LayoutUnit)",
        "prompt": """You are Agent 99 auditing Chromium Blink CSS Length Unit Conversion vs CSS Values 4 §5.
Detail:
1. Core data structures in Blink length resolution (CSSToLengthConversionData, FontDescription, LayoutUnit).
2. Resolution rules:
   - px: exact LayoutUnit (val * 64)
   - em: relative to current element font-size (val * font_size / 64)
   - rem: relative to root html element font-size (default 16px = 1024 LayoutUnits)
   - percentage: relative to reference size (container width/height)
3. Mathematical invariants: positive font size monotonicity, exact fixed-point scaling, non-negativity preservation.
4. Concrete Rocq/Coq inductive definitions and theorems for formalizing this into BlinkCSSUnitResolutionSemantics.v."""
    },
    {
        "id": "agent100",
        "file": "agent100_simple_css_cascade.md",
        "topic": "Chromium Blink Simple CSS Cascade & Property Inheritance (third_party/blink/renderer/core/css/style_cascade.cc)",
        "spec": "W3C CSS Cascading and Inheritance Module Level 4 (§3 & §4 Cascade Order & Inheritance)",
        "prompt": """You are Agent 100 auditing Chromium Blink Simple CSS Cascade vs CSS Cascading 4 §3/§4.
Detail:
1. Core data structures in Blink style cascade (StyleCascade, MatchResult, CascadePriority, ComputedStyle).
2. Cascade layers: UA default styles overridden by Author stylesheet rules overridden by inline style attributes.
3. Property inheritance: font-size, color, text-align inherit down the tree from parent to child; margins, paddings, borders, width, height, display do not inherit.
4. Mathematical invariants: override dominance of higher-priority layers, transitivity of property inheritance, determinism.
5. Concrete Rocq/Coq inductive definitions and theorems for formalizing this into BlinkSimpleCSSCascadeSemantics.v."""
    },
    {
        "id": "agent101",
        "file": "agent101_layout_box_generation.md",
        "topic": "Chromium Blink Layout Box Tree Generation from Styled HTML Elements (third_party/blink/renderer/core/layout/layout_object_factory.cc)",
        "spec": "W3C CSS Display Module Level 3 (§2 Generating Box Trees: Block, Table, TableRow, TableCell)",
        "prompt": """You are Agent 101 auditing Chromium Blink Box Generation vs CSS Display 3 §2.
Detail:
1. Core data structures in Blink box generation (LayoutObjectFactory, LayoutBlockFlow, LayoutTable, LayoutTableRow, LayoutTableCell).
2. Generation rules:
   - display: block (body, h1-h6) -> LayoutBlockFlow
   - display: table (table) -> LayoutTable
   - display: table-row (tr) -> LayoutTableRow
   - display: table-cell (th, td) -> LayoutTableCell
   - inline text -> LayoutText
3. Anonymous box generation: wrapping table cells missing a table-row in anonymous row; wrapping table rows missing a table in anonymous table.
4. Mathematical invariants: structural correspondence between DOM and box tree, display mode type preservation.
5. Concrete Rocq/Coq inductive definitions and theorems for formalizing this into BlinkLayoutBoxGenerationSemantics.v."""
    },
    {
        "id": "agent102",
        "file": "agent102_header_margin_collapsing.md",
        "topic": "Chromium Blink Header Margin Collapsing & Sibling Block Sequencing (third_party/blink/renderer/core/layout/block_layout_algorithm.cc)",
        "spec": "W3C CSS 2.1 (§8.3.1 Collapsing Margins between Headers and Siblings)",
        "prompt": """You are Agent 102 auditing Chromium Blink Margin Collapsing for Headers vs CSS 2.1 §8.3.1.
Detail:
1. Core data structures in Blink margin collapsing (MarginStrut, BlockLayoutAlgorithm, MarginInfo).
2. Collapsing rules between adjacent headers (e.g. h1 bottom margin collapsing with h2 top margin) and header bottom margin collapsing with table top margin:
   - max(positive margins) - max(|negative margins|)
3. Mathematical invariants: collapsed margin between [min(m1, m2), max(m1, m2)] for non-negative margins, commutativity, associativity.
4. Exact cursor position advancement: cursor_y' = cursor_y + collapsed_margin + block_size.
5. Concrete Rocq/Coq inductive definitions and theorems for formalizing this into BlinkHeaderMarginCollapsingSemantics.v."""
    },
    {
        "id": "agent103",
        "file": "agent103_table_auto_column_sizing.md",
        "topic": "Chromium Blink Automatic Table Column Width Distribution (third_party/blink/renderer/core/layout/table/table_layout_algorithm_types.cc)",
        "spec": "W3C CSS 2.1 (§17.5.2.2 Automatic Table Layout: Column Min/Max Sizes & Width Sizing)",
        "prompt": """You are Agent 103 auditing Chromium Blink Table Column Distribution vs CSS 2.1 §17.5.2.2.
Detail:
1. Core data structures in Blink column sizing (TableTypes::Column, TableLayoutAlgorithmTypes, MinMaxSizes).
2. Column min/max derivation: column min is max of cell min sizes in that column; column max is max of cell max sizes.
3. Distributing available table width across columns: proportional distribution of excess space beyond min sizes up to max sizes.
4. Mathematical invariants: column width >= column min size, sum of column widths equals available table width (or min sum if constrained), monotonicity.
5. Concrete Rocq/Coq inductive definitions and theorems for formalizing this into BlinkTableAutoColumnSizingSemantics.v."""
    },
    {
        "id": "agent104",
        "file": "agent104_table_cell_vertical_align.md",
        "topic": "Chromium Blink Table Cell Vertical Alignment & Content Box Placement (third_party/blink/renderer/core/layout/table/table_cell_layout_algorithm.cc)",
        "spec": "W3C CSS 2.1 (§17.5.3 Table Cell Vertical Alignment: top, middle, bottom, baseline)",
        "prompt": """You are Agent 104 auditing Chromium Blink Table Cell Vertical Align vs CSS 2.1 §17.5.3.
Detail:
1. Core data structures in Blink table cell layout (TableCellLayoutAlgorithm, EVerticalAlign, LogicalRect).
2. Alignment formula within row height R:
   - top: y = 0
   - middle: y = (R - cell_height) / 2
   - bottom: y = R - cell_height
   - baseline: y = max_row_ascent - cell_ascent
3. Mathematical invariants: cell vertical offset non-negative, cell + offset <= row height, determinism.
4. Concrete Rocq/Coq inductive definitions and theorems for formalizing this into BlinkTableCellVerticalAlignSemantics.v."""
    },
    {
        "id": "agent105",
        "file": "agent105_table_separated_grid.md",
        "topic": "Chromium Blink Separated Borders Table Grid Geometry (third_party/blink/renderer/core/layout/table/table_layout_algorithm.cc)",
        "spec": "W3C CSS 2.1 (§17.6.1 Separated Borders Model & Border Spacing)",
        "prompt": """You are Agent 105 auditing Chromium Blink Separated Borders Table Geometry vs CSS 2.1 §17.6.1.
Detail:
1. Core data structures in Blink separated table layout (TableLayoutAlgorithm, TableBorderData, TableBorders).
2. 2D Coordinate calculation:
   - col_x(j) = border_spacing_h + sum_{k < j} (col_width(k) + border_spacing_h)
   - row_y(i) = border_spacing_v + sum_{k < i} (row_height(k) + border_spacing_v)
3. Total table dimensions:
   - width = border_spacing_h + sum(col_widths) + N * border_spacing_h
   - height = border_spacing_v + sum(row_heights) + M * border_spacing_v
4. Mathematical invariants: cell bounding rects strictly inside table bounds, strictly non-overlapping with positive spacing.
5. Concrete Rocq/Coq inductive definitions and theorems for formalizing this into BlinkTableSeparatedGridSemantics.v."""
    },
    {
        "id": "agent106",
        "file": "agent106_inline_text_run_layout.md",
        "topic": "Chromium Blink Inline Text Run Layout in Headers and Table Cells (third_party/blink/renderer/core/layout/inline/inline_layout_algorithm.cc)",
        "spec": "W3C CSS Inline Layout Module Level 3 (§3 Text Run Advance & Baseline Positioning)",
        "prompt": """You are Agent 106 auditing Chromium Blink Inline Text Layout vs CSS Inline 3 §3.
Detail:
1. Core data structures in Blink inline text layout (InlineLayoutAlgorithm, InlineItem, LineInfo, LogicalLineItem).
2. Sizing text runs in headers (h1, h2) and table cells (th, td):
   - glyph advance = char_count * glyph_width_for_font(font_size)
   - line height = font_size * 1.2 (or specified line-height)
3. Centering text within line height box: half-leading = (line_height - font_size) / 2.
4. Mathematical invariants: line advance monotonic in character count and font size, non-negative line box height.
5. Concrete Rocq/Coq inductive definitions and theorems for formalizing this into BlinkInlineTextRunLayoutSemantics.v."""
    },
    {
        "id": "agent107",
        "file": "agent107_text_align_geometry.md",
        "topic": "Chromium Blink Text Alignment in Headers and Table Header Cells (third_party/blink/renderer/core/layout/inline/line_box_fragment_builder.cc)",
        "spec": "W3C CSS Text Module Level 3 (§7 Alignment & Justification: text-align left, center, right)",
        "prompt": """You are Agent 107 auditing Chromium Blink Text Align vs CSS Text 3 §7.
Detail:
1. Core data structures in Blink line box builder (LineBoxFragmentBuilder, ETextAlign, PhysicalOffset).
2. Offset computation for line items within available line width W_line and content width W_content:
   - text-align: left -> offset = 0
   - text-align: center -> offset = (W_line - W_content) / 2
   - text-align: right -> offset = W_line - W_content
3. Special UA default: 'th' table header cells default to text-align: center.
4. Mathematical invariants: offset non-negative when W_line >= W_content, offset + W_content <= W_line, centering symmetry.
5. Concrete Rocq/Coq inductive definitions and theorems for formalizing this into BlinkTextAlignGeometrySemantics.v."""
    },
    {
        "id": "agent108",
        "file": "agent108_table_cell_non_overlap.md",
        "topic": "Chromium Blink Table Cell Non-Overlap & Disjointness Invariant (third_party/blink/renderer/core/layout/table/table_layout_algorithm.cc)",
        "spec": "W3C CSS 2.1 (§17.5 Table Layout Geometry: Cell Disjointness Invariant)",
        "prompt": """You are Agent 108 auditing Chromium Blink Table Cell Non-Overlap vs CSS 2.1 §17.5.
Detail:
1. Table grid indexing: cells positioned at (row_idx, col_idx) with dimensions (width, height).
2. Invariant: For any two distinct table cells (r1, c1) != (r2, c2) in a valid table:
   - Either r1 < r2 (row separation: y1 + h1 <= y2) or r2 < r1 (y2 + h2 <= y1)
   - Or c1 < c2 (col separation: x1 + w1 <= x2) or c2 < c1 (x2 + w2 <= x1)
3. Mathematical proof of 2D disjointness of interior rectangles for all cells in the table grid.
4. Concrete Rocq/Coq inductive definitions and theorems for formalizing this into BlinkTableCellNonOverlapSemantics.v."""
    },
    {
        "id": "agent109",
        "file": "agent109_viewport_icb_layout.md",
        "topic": "Chromium Blink Viewport & Initial Containing Block Layout (third_party/blink/renderer/core/layout/view_layout_algorithm.cc)",
        "spec": "W3C CSS 2.1 (§10.1 Initial Containing Block & Viewport Layout)",
        "prompt": """You are Agent 109 auditing Chromium Blink Viewport Layout vs CSS 2.1 §10.1.
Detail:
1. Core data structures in Blink root layout (ViewLayoutAlgorithm, LayoutView, ConstraintSpace).
2. ICB dimensions initialized from viewport (viewport_width, viewport_height).
3. Root HTML and Body elements default width expansion: width = viewport_width - 2 * body_margin.
4. Mathematical invariants: body box strictly contained within viewport, non-negative available inline size.
5. Concrete Rocq/Coq inductive definitions and theorems for formalizing this into BlinkViewportICBLayoutSemantics.v."""
    },
    {
        "id": "agent110",
        "file": "agent110_table_row_height_accumulation.md",
        "topic": "Chromium Blink Table Row Stacking & Block Height Accumulation (third_party/blink/renderer/core/layout/table/table_section_layout_algorithm.cc)",
        "spec": "W3C CSS 2.1 (§17.5.3 Table Row Stacking and Section Sizing)",
        "prompt": """You are Agent 110 auditing Chromium Blink Table Row Stacking vs CSS 2.1 §17.5.3.
Detail:
1. Core data structures in Blink table section layout (TableSectionLayoutAlgorithm, RowLayoutResult).
2. Stacking algorithm: iterating through rows, accumulating row heights and vertical border spacings:
   - row_y(k+1) = row_y(k) + row_height(k) + border_spacing_v
3. Mathematical invariants: row offsets strictly monotonic (row_y(k+1) > row_y(k)), total table height equals sum of row heights + (M+1)*spacing.
4. Concrete Rocq/Coq inductive definitions and theorems for formalizing this into BlinkTableRowHeightAccumulationSemantics.v."""
    },
    {
        "id": "agent111",
        "file": "agent111_page_fragment_assembly.md",
        "topic": "Chromium Blink Hierarchical Page Fragment Tree Assembly (third_party/blink/renderer/core/layout/box_fragment_builder.cc)",
        "spec": "W3C CSS Box Model 3 & CSS Display 3 (Fragment Tree Assembly for Web Pages)",
        "prompt": """You are Agent 111 auditing Chromium Blink Fragment Tree Assembly vs CSS Box Model 3 / Display 3.
Detail:
1. Core data structures in Blink fragment builder (BoxFragmentBuilder, PhysicalBoxFragment, FragmentLink).
2. Hierarchy assembly: PageRootFragment -> BodyFragment -> [HeaderFragments, TableFragment -> [RowFragments -> [CellFragments -> [TextFragments]]]].
3. Preserving relative coordinates and bounding rects at each level.
4. Mathematical invariants: tree structure is a valid DAG / tree, child bounding boxes contained in parent fragment.
5. Concrete Rocq/Coq inductive definitions and theorems for formalizing this into BlinkPageFragmentAssemblySemantics.v."""
    },
    {
        "id": "agent112",
        "file": "agent112_simple_html_page_model.md",
        "topic": "Chromium Blink Complete End-to-End HTML Page Layout Model (third_party/blink/renderer/core/frame/local_frame_view.cc)",
        "spec": "HTML Living Standard + W3C CSS 2.1 Complete End-to-End Page Evaluation with Headers & Tables",
        "prompt": """You are Agent 112 synthesizing the complete HTML Page with Headers & Tables layout engine.
Detail:
1. End-to-end operational pipeline: HTML Page AST + simple CSS rules -> Style Resolution -> Layout Box Generation -> Block & Table Layout -> PhysicalFragment tree.
2. Concrete evaluation example: a sample HTML page with <h1>Header</h1>, <h2>Subheader</h2>, and a 2x2 <table><tr><th>H1</th><th>H2</th></tr><tr><td>D1</td><td>D2</td></tr></table>.
3. Soundness theorems:
   - Deterministic execution of entire page layout.
   - Non-overlapping table cells within the rendered page.
   - Headers and table vertically stacked with margin collapsing.
   - Complete page bounding rect non-negativity.
4. Concrete Rocq/Coq inductive definitions and theorems for formalizing this into BlinkSimpleHTMLPageModel.v."""
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
    print("Launching Wave 13: 16 concurrent Python3 agents using gemini-4-argon (low thinking budget 512) for Full HTML Page (Headers, Tables, Simple CSS) Layout...")
    with concurrent.futures.ThreadPoolExecutor(max_workers=16) as executor:
        results = list(executor.map(run_agent, tasks))

    total_p = sum(r.get("prompt_tokens", 0) for r in results)
    total_c = sum(r.get("candidates_tokens", 0) for r in results)
    total_t = sum(r.get("total_tokens", 0) for r in results)

    log_entry = {
        "timestamp": time.strftime("%Y-%m-%d %H:%M:%S"),
        "model": "gemini-4-argon",
        "wave": 13,
        "theme": "HTML Page with Headers, Tables, and Simple CSS (HTML Element AST, Default UA Stylesheet, CSS Length Units, Simple Cascade, Box Generation, Header Margin Collapsing, Table Column Distribution, Cell Vertical Align, Separated Borders Grid, Inline Text Runs, Text Align, Cell Non-Overlap, Viewport ICB Layout, Row Height Stacking, Fragment Tree Assembly, End-to-End Simple HTML Page Model)",
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

    print("\n=== WAVE 13 (16 AGENTS: HTML PAGE WITH HEADERS & TABLES) TOKEN USAGE REPORT ===")
    print(f"Prompt Tokens:     {total_p}")
    print(f"Candidate Tokens:  {total_c}")
    print(f"Total Tokens Used: {total_t}")
    print("Appended log entry to token_usage.log.")

