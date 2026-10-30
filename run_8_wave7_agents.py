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
        "id": "agent17",
        "file": "agent17_table_grid_map.md",
        "topic": "Chromium Blink Table Structural Grid & Cell Map Resolution (third_party/blink/renderer/core/layout/table/table_node.cc and table_layout_algorithm_types.cc)",
        "spec": "HTML Standard (§4.9.11 Forming a table: cell slot occupancy, colspan, rowspan) & CSS 2.1 §17.5",
        "prompt": """You are Agent 17 auditing Chromium Blink Table Grid Formation & Cell Slot Occupancy vs HTML Standard §4.9.11 and CSS 2.1 §17.5.
Detail:
1. Core data structures in Blink table cell mapping (TableNode, TableGroupedChildren, TableGridCell, CellSpan, Colspan, Rowspan).
2. The grid formation algorithm: walking rows and cells, skipping occupied slots from prior rowspans, advancing the current column pointer, clamping colspan/rowspan (e.g. max colspan 1000, max rowspan 65534 in Blink).
3. Handling missing cells (implicit empty grid slots) and overlapping cells.
4. Mathematical invariants: grid slots partition the table coordinate space [0, R) x [0, C), no two cell origins overlap, determinism, monotonic slot progression.
5. Provide concrete Rocq/Coq inductive definitions and theorems for formalizing this into BlinkTableGridMapSemantics.v."""
    },
    {
        "id": "agent18",
        "file": "agent18_table_columns.md",
        "topic": "Chromium Blink Table Column Width Distribution (third_party/blink/renderer/core/layout/table/table_layout_algorithm.cc and table_column_tracker.cc)",
        "spec": "W3C CSS 2.1 (§17.5.2 Fixed Table Layout, §17.5.3 Automatic Table Layout column width distribution)",
        "prompt": """You are Agent 18 auditing Chromium Blink Table Column Width Distribution vs CSS 2.1 §17.5.2 & §17.5.3.
Detail:
1. Core data structures in Blink column sizing (TableColumnTracker, TableColumnLocation, TableColumnGrouping).
2. Column width resolution algorithm: fixed layout (width from first row cells and <col> elements, remaining space divided equally among auto columns) vs auto layout (distributing excess inline space proportional to max-content minus min-content or percentages).
3. Handling percentage columns, fixed columns, and auto columns competing for available table inline size.
4. Mathematical invariants: sum of column widths equals total table content inline size (inline space conservation), column widths >= column min-content, monotonicity.
5. Provide concrete Rocq/Coq inductive definitions and theorems for formalizing this into BlinkTableColumnDistributionSemantics.v."""
    },
    {
        "id": "agent19",
        "file": "agent19_table_row.md",
        "topic": "Chromium Blink Table Row Layout & Baseline Alignment (third_party/blink/renderer/core/layout/table/table_row_layout_algorithm.cc)",
        "spec": "W3C CSS 2.1 (§17.5.3 Table row height computation, baseline alignment within a row)",
        "prompt": """You are Agent 19 auditing Chromium Blink Table Row Layout vs CSS 2.1 §17.5.3.
Detail:
1. Core data structures in Blink row layout (TableRowLayoutAlgorithm, RowBaselineTabulator, RowHeight).
2. Row height computation: maximum of specified row height, cell heights for non-spanning cells, and baseline-aligned cell heights (max cell ascent + max cell descent).
3. Interaction with empty rows (rows with 0 cells or only collapsed cells).
4. Mathematical invariants: row height >= max(cell heights), row height >= max_ascent + max_descent for baseline-aligned cells, non-negativity, determinism.
5. Provide concrete Rocq/Coq inductive definitions and theorems for formalizing this into BlinkTableRowLayoutSemantics.v."""
    },
    {
        "id": "agent20",
        "file": "agent20_table_cell.md",
        "topic": "Chromium Blink Table Cell Layout & Vertical Alignment (third_party/blink/renderer/core/layout/table/table_cell_layout_algorithm.cc)",
        "spec": "W3C CSS 2.1 (§17.5.3 Table cell vertical alignment: top, middle, bottom, baseline)",
        "prompt": """You are Agent 20 auditing Chromium Blink Table Cell Layout vs CSS 2.1 §17.5.3.
Detail:
1. Core data structures in Blink table cell layout (TableCellLayoutAlgorithm, EVerticalAlign: Top, Middle, Bottom, Baseline).
2. Vertical offset computation for cell content inside a cell of height H:
   - Top: offset = padding_top + border_top
   - Bottom: offset = H - (border_bottom + padding_bottom + content_height)
   - Middle: offset = border_top + padding_top + (H - border_top - border_bottom - padding_top - padding_bottom - content_height) / 2
   - Baseline: offset aligns cell baseline to row baseline.
3. Padding and border box clamping and minimum content height preservation.
4. Mathematical invariants: offset non-negativity, cell content fully contained within cell height (offset + content_height <= H when content fits), determinism.
5. Provide concrete Rocq/Coq inductive definitions and theorems for formalizing this into BlinkTableCellAlignSemantics.v."""
    },
    {
        "id": "agent21",
        "file": "agent21_table_section.md",
        "topic": "Chromium Blink Table Section Stacking & Ordering (third_party/blink/renderer/core/layout/table/table_section_layout_algorithm.cc)",
        "spec": "W3C CSS 2.1 (§17.5 Table section ordering: thead first, tfoot last, tbodies in between)",
        "prompt": """You are Agent 21 auditing Chromium Blink Table Section Ordering vs CSS 2.1 §17.5.
Detail:
1. Core data structures in Blink table sections (TableSectionLayoutAlgorithm, TableGroupedChildren, LayoutTableSection: kHeader, kBody, kFooter).
2. Section ordering and stacking algorithm: regardless of DOM source order (e.g. <tfoot> appearing before <tbody> in HTML4), the visual/layout block order is strictly: <thead>, then all <tbody> sections, then <tfoot>.
3. Cumulative block offset tracking for sections and rows within sections.
4. Mathematical invariants: visual section block offsets are strictly monotonic, total table block size is the sum of section block sizes (plus spacing/borders), permutation preservation of bodies.
5. Provide concrete Rocq/Coq inductive definitions and theorems for formalizing this into BlinkTableSectionLayoutSemantics.v."""
    },
    {
        "id": "agent22",
        "file": "agent22_table_rowspan.md",
        "topic": "Chromium Blink Rowspan Extra Height Distribution (third_party/blink/renderer/core/layout/table/table_row_height_tracker.cc)",
        "spec": "W3C CSS 2.1 (§17.5.3 Multi-row cell height distribution across spanned rows)",
        "prompt": """You are Agent 22 auditing Chromium Blink Rowspan Height Distribution vs CSS 2.1 §17.5.3.
Detail:
1. Core data structures in Blink rowspan distribution (TableRowHeightTracker, RowspanTracker, SpannedRowRange).
2. The distribution algorithm: for a cell spanning rows [r_start, r_end) with required height H_cell, if sum(row_heights) < H_cell, distribute extra = H_cell - sum(row_heights) among spanned rows.
3. Distribution strategies: proportional to row height, or divided equally among flexible/auto rows, without decreasing any row height.
4. Mathematical invariants: row heights are monotonically non-decreasing after distribution (new_height >= old_height), final sum(row_heights) >= H_cell (rowspan coverage guarantee), determinism.
5. Provide concrete Rocq/Coq inductive definitions and theorems for formalizing this into BlinkTableRowSpanDistributionSemantics.v."""
    },
    {
        "id": "agent23",
        "file": "agent23_table_separated_borders.md",
        "topic": "Chromium Blink Separated Borders & Spacing Model (third_party/blink/renderer/core/layout/table/table_layout_utils.cc and table_layout_algorithm.cc)",
        "spec": "W3C CSS 2.1 (§17.6.1 The separated borders model, border-spacing: h_spacing v_spacing)",
        "prompt": """You are Agent 23 auditing Chromium Blink Separated Borders vs CSS 2.1 §17.6.1.
Detail:
1. Core data structures in Blink separated table borders (TableBorders: kSeparated, border_spacing: LogicalSize(inline_spacing, block_spacing)).
2. Geometry resolution: cell positions incorporate border-spacing: cell_x(c) = padding_left + border_left + h_spacing + sum_{i=0}^{c-1} (col_width_i + h_spacing); total width includes (num_cols + 1) * h_spacing.
3. Border and background painting on individual cells rather than collapsed edges.
4. Mathematical invariants: cell bounding boxes are strictly separated by h_spacing and v_spacing (no cell overlap), total table inline/block size conservation with spacing, non-negativity.
5. Provide concrete Rocq/Coq inductive definitions and theorems for formalizing this into BlinkTableSeparatedBordersSemantics.v."""
    },
    {
        "id": "agent24",
        "file": "agent24_table_min_max.md",
        "topic": "Chromium Blink Table Intrinsic Min/Max Size Contributions (third_party/blink/renderer/core/layout/table/table_layout_algorithm.cc ComputeMinMaxSizes)",
        "spec": "W3C CSS 2.1 (§17.5.2.2 & CSS Box Sizing 3 Table min-content / max-content inline size)",
        "prompt": """You are Agent 24 auditing Chromium Blink Table Min/Max Content Sizing vs CSS 2.1 §17.5.2.2 & CSS Box Sizing 3.
Detail:
1. Core data structures in Blink table intrinsic sizing (TableLayoutAlgorithm::ComputeMinMaxSizes, ColumnMinMaxSizes).
2. Calculation algorithm: table min-content inline size is the sum of column min-content inline sizes (plus cell/table borders and border-spacing); table max-content is the sum of column max-content inline sizes (constrained by explicit table width if specified).
3. Handling cells with colspan > 1 during intrinsic sizing (distributing span min/max to spanned columns).
4. Mathematical invariants: min_content <= max_content for all columns and the table, monotonicity with respect to cell content, non-negativity, determinism.
5. Provide concrete Rocq/Coq inductive definitions and theorems for formalizing this into BlinkTableMinMaxSizesSemantics.v."""
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
    print("Launching Wave 7: 8 concurrent Python3 agents using gemini-4-argon (thinking budget 1024) for HTML Table Formalization...")
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as executor:
        results = list(executor.map(run_agent, tasks))

    total_p = sum(r.get("prompt_tokens", 0) for r in results)
    total_c = sum(r.get("candidates_tokens", 0) for r in results)
    total_t = sum(r.get("total_tokens", 0) for r in results)

    log_entry = {
        "timestamp": time.strftime("%Y-%m-%d %H:%M:%S"),
        "model": "gemini-4-argon",
        "wave": 7,
        "theme": "HTML Table Formalization Suite (table, tr, td, th)",
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

    print("\n=== WAVE 7 (8 AGENTS: HTML TABLE FORMALIZATION) TOKEN USAGE REPORT ===")
    print(f"Prompt Tokens:     {total_p}")
    print(f"Candidate Tokens:  {total_c}")
    print(f"Total Tokens Used: {total_t}")
    print("Appended log entry to token_usage.log.")

