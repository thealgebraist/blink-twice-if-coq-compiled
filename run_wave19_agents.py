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
        "id": "agent209",
        "file": "agent209_table_fixed_layout.md",
        "topic": "Chromium Blink Fixed Table Layout Algorithm (core/layout/table/table_layout_algorithm.cc)",
        "spec": "CSS 2.1 §17.5.2.1 (Fixed table layout: column widths determined by first row or <col> elements)",
        "prompt": """You are Agent 209 auditing Chromium Blink Fixed Table Layout vs CSS 2.1 §17.5.2.1.
Detail:
1. Column sizing: width determined solely by <col> or cells in first row; subsequent rows do not affect column widths.
2. Free space distribution: remaining table width distributed equally among columns without declared width.
3. Invariants: sum of column widths equals table width (or minimum width), subsequent row cells do not alter column positions.
4. Concrete Rocq/Coq definitions and theorems for BlinkTableFixedLayoutSemantics.v with 0 admits."""
    },
    {
        "id": "agent210",
        "file": "agent210_table_column_location.md",
        "topic": "Chromium Blink Table Column Location & Offset Accumulation (core/layout/table/table_column_location.cc)",
        "spec": "CSS Table 3 §3 & CSS 2.1 §17.5 (Monotonic accumulation of column inline offsets)",
        "prompt": """You are Agent 210 auditing Chromium Blink Table Column Location vs CSS Table 3 §3.
Detail:
1. Offset accumulation: col_x(i+1) = col_x(i) + col_width(i) + border_spacing.
2. Invariants: column offsets strictly advance, column intervals [col_x(i), col_x(i) + col_width(i)) are mutually disjoint.
3. Concrete Rocq/Coq definitions and theorems for BlinkTableColumnLocationSemantics.v with 0 admits."""
    },
    {
        "id": "agent211",
        "file": "agent211_table_border_style_conflict.md",
        "topic": "Chromium Blink Collapsed Border Style Precedence (core/layout/table/table_borders.cc)",
        "spec": "CSS 2.1 §17.6.2.1 (Border style conflict resolution: hidden > double > solid > dashed > none)",
        "prompt": """You are Agent 211 auditing Chromium Blink Table Border Style Conflict vs CSS 2.1 §17.6.2.1.
Detail:
1. Style precedence ranking: hidden has highest priority (rank 5); none has lowest (rank 0); double, solid, dashed in between.
2. Invariants: winning style has maximum precedence rank; hidden unconditionally suppresses borders.
3. Concrete Rocq/Coq definitions and theorems for BlinkTableBorderStyleConflictSemantics.v with 0 admits."""
    },
    {
        "id": "agent212",
        "file": "agent212_table_border_width_conflict.md",
        "topic": "Chromium Blink Collapsed Border Width Precedence (core/layout/table/table_borders.cc)",
        "spec": "CSS 2.1 §17.6.2.1 (Border width conflict resolution: wider border wins over narrower border)",
        "prompt": """You are Agent 212 auditing Chromium Blink Table Border Width Conflict vs CSS 2.1 §17.6.2.1.
Detail:
1. When styles have equal precedence rank, border with larger used width wins: max(w1, w2).
2. Invariants: winning border width >= w1 and winning border width >= w2, resolution is commutative.
3. Concrete Rocq/Coq definitions and theorems for BlinkTableBorderWidthConflictSemantics.v with 0 admits."""
    },
    {
        "id": "agent213",
        "file": "agent213_table_row_baseline.md",
        "topic": "Chromium Blink Table Row Baseline Alignment (core/layout/table/table_row_layout_algorithm.cc)",
        "spec": "CSS 2.1 §17.5.3 (Row baseline is maximum of cell baselines; cells aligned to row baseline)",
        "prompt": """You are Agent 213 auditing Chromium Blink Table Row Baseline Alignment vs CSS 2.1 §17.5.3.
Detail:
1. Row baseline: row_baseline = max(cell_baseline(i)).
2. Cell vertical offset: y_cell = row_baseline - cell_baseline.
3. Invariants: y_cell >= 0, aligned cell baseline matches row_baseline exactly.
4. Concrete Rocq/Coq definitions and theorems for BlinkTableRowBaselineSemantics.v with 0 admits."""
    },
    {
        "id": "agent214",
        "file": "agent214_table_empty_row_suppression.md",
        "topic": "Chromium Blink Empty Table Row Suppression & Zero-Height Collapsing (core/layout/table/table_section_layout_algorithm.cc)",
        "spec": "CSS Table 3 §4 & CSS 2.1 §17.5.3 (Empty row height collapsing when no cells span it)",
        "prompt": """You are Agent 214 auditing Chromium Blink Empty Row Suppression vs CSS Table 3 §4.
Detail:
1. Empty row detection: row with no cells and no minimum height collapses to used block size 0.
2. Invariants: empty row block size = 0, row offsets remain monotonic.
3. Concrete Rocq/Coq definitions and theorems for BlinkTableEmptyRowSuppressionSemantics.v with 0 admits."""
    },
    {
        "id": "agent215",
        "file": "agent215_table_cell_colspan.md",
        "topic": "Chromium Blink Table Cell Colspan Width Distribution (core/layout/table/table_layout_utils.cc)",
        "spec": "CSS Table 3 §3.2 (Distributing spanning cell width across spanned columns)",
        "prompt": """You are Agent 215 auditing Chromium Blink Table Cell Colspan vs CSS Table 3 §3.2.
Detail:
1. Spanning check: if cell_min_width > sum(col_width(i)), distribute deficit across spanned columns.
2. Invariants: sum of spanned column widths >= cell_min_width post-distribution, column widths monotonic.
3. Concrete Rocq/Coq definitions and theorems for BlinkTableCellColspanSemantics.v with 0 admits."""
    },
    {
        "id": "agent216",
        "file": "agent216_table_cell_rowspan.md",
        "topic": "Chromium Blink Table Cell Rowspan Height Distribution (core/layout/table/table_layout_utils.cc)",
        "spec": "CSS Table 3 §4.2 (Distributing spanning cell height across spanned rows)",
        "prompt": """You are Agent 216 auditing Chromium Blink Table Cell Rowspan vs CSS Table 3 §4.2.
Detail:
1. Rowspan check: if cell_min_height > sum(row_height(j)), distribute excess height across spanned rows.
2. Invariants: sum of spanned row heights >= cell_min_height post-distribution, row boundaries monotonic.
3. Concrete Rocq/Coq definitions and theorems for BlinkTableCellRowspanSemantics.v with 0 admits."""
    },
    {
        "id": "agent217",
        "file": "agent217_table_caption_margin_collapse.md",
        "topic": "Chromium Blink Table Caption Block Margin Collapsing (core/layout/table/table_layout_algorithm.cc)",
        "spec": "CSS 2.1 §17.4 (Table caption margins do not collapse with table grid margins, but collapse internally)",
        "prompt": """You are Agent 217 auditing Chromium Blink Table Caption Margin Collapsing vs CSS 2.1 §17.4.
Detail:
1. Caption placement: caption sits outside table grid box; grid acts as formatting context boundary.
2. Invariants: caption margin does not collapse into grid border, total table wrapper height = caption_margin_box + grid_box.
3. Concrete Rocq/Coq definitions and theorems for BlinkTableCaptionMarginCollapseSemantics.v with 0 admits."""
    },
    {
        "id": "agent218",
        "file": "agent218_table_collapsed_border_half_width.md",
        "topic": "Chromium Blink Collapsed Border Half-Width Allocation (core/layout/table/table_borders.cc)",
        "spec": "CSS 2.1 §17.6.2 (Border half-width allocation to adjacent cells: w1 = floor(w/2), w2 = ceil(w/2))",
        "prompt": """You are Agent 218 auditing Chromium Blink Collapsed Border Half-Width Allocation vs CSS 2.1 §17.6.2.
Detail:
1. Integer allocation: w1 = w / 2, w2 = w - w / 2 (or ceil).
2. Invariants: w1 + w2 = w, |w1 - w2| <= 1 (exact pixel conservation without gaps).
3. Concrete Rocq/Coq definitions and theorems for BlinkTableCollapsedBorderHalfWidthSemantics.v with 0 admits."""
    },
    {
        "id": "agent219",
        "file": "agent219_table_min_max_sizing.md",
        "topic": "Chromium Blink Table Intrinsic Min/Max Content Sizing (core/layout/table/table_layout_algorithm_types.cc)",
        "spec": "CSS Table 3 §3.1 (Table min-content is sum of column min-content; max-content is sum of column max-content)",
        "prompt": """You are Agent 219 auditing Chromium Blink Table Min/Max Sizing vs CSS Table 3 §3.1.
Detail:
1. Table min-content = sum(col_min) + borders/spacing. Table max-content = sum(col_max) + borders/spacing.
2. Invariants: table min-content <= table max-content, each column min-content <= column max-content.
3. Concrete Rocq/Coq definitions and theorems for BlinkTableMinMaxSizingSemantics.v with 0 admits."""
    },
    {
        "id": "agent220",
        "file": "agent220_table_colgroup_expansion.md",
        "topic": "Chromium Blink Table <colgroup> Span Expansion (core/layout/table/table_column_location.cc)",
        "spec": "HTML 5 §4.9.3 & CSS Table 3 §2 (<colgroup span=N> expansion to N logical column structures)",
        "prompt": """You are Agent 220 auditing Chromium Blink <colgroup> Span Expansion vs HTML 5 §4.9.3.
Detail:
1. Expansion: a <col span=N> generates exactly N consecutive columns sharing the declared style.
2. Invariants: generated column count equals sum(span), each expanded column inherits width from parent colgroup.
3. Concrete Rocq/Coq definitions and theorems for BlinkTableColgroupExpansionSemantics.v with 0 admits."""
    },
    {
        "id": "agent221",
        "file": "agent221_table_row_percent_height.md",
        "topic": "Chromium Blink Table Row Percentage Height Resolution (core/layout/table/table_row_layout_algorithm.cc)",
        "spec": "CSS 2.1 §17.5.3 (Row percentage height resolution against table container height)",
        "prompt": """You are Agent 221 auditing Chromium Blink Table Row Percentage Height vs CSS 2.1 §17.5.3.
Detail:
1. Resolution: row_height = max(row_min_content, (table_height * pct) / 100).
2. Invariants: row_height >= row_min_content, row_height monotonic in table_height.
3. Concrete Rocq/Coq definitions and theorems for BlinkTableRowPercentHeightSemantics.v with 0 admits."""
    },
    {
        "id": "agent222",
        "file": "agent222_table_cell_vertical_align_middle.md",
        "topic": "Chromium Blink Table Cell Vertical-Align: Middle (core/layout/table/table_cell_layout_algorithm.cc)",
        "spec": "CSS 2.1 §17.5.3 (vertical-align: middle centering inside table cell: y = (row_height - cell_height) / 2)",
        "prompt": """You are Agent 222 auditing Chromium Blink Table Cell Vertical-Align Middle vs CSS 2.1 §17.5.3.
Detail:
1. Middle alignment: y_offset = (row_height - cell_height) / 2.
2. Invariants: y_offset >= 0 when row_height >= cell_height, top padding + y_offset + cell_height <= row_height.
3. Concrete Rocq/Coq definitions and theorems for BlinkTableCellVerticalAlignMiddleSemantics.v with 0 admits."""
    },
    {
        "id": "agent223",
        "file": "agent223_table_cell_vertical_align_bottom.md",
        "topic": "Chromium Blink Table Cell Vertical-Align: Bottom (core/layout/table/table_cell_layout_algorithm.cc)",
        "spec": "CSS 2.1 §17.5.3 (vertical-align: bottom alignment inside table cell: y = row_height - cell_height)",
        "prompt": """You are Agent 223 auditing Chromium Blink Table Cell Vertical-Align Bottom vs CSS 2.1 §17.5.3.
Detail:
1. Bottom alignment: y_offset = row_height - cell_height.
2. Invariants: y_offset + cell_height = row_height, y_offset >= 0 when row_height >= cell_height.
3. Concrete Rocq/Coq definitions and theorems for BlinkTableCellVerticalAlignBottomSemantics.v with 0 admits."""
    },
    {
        "id": "agent224",
        "file": "agent224_table_wrapper_fragment_assembly.md",
        "topic": "Chromium Blink Table Wrapper Box Fragment Tree Assembly (core/layout/table/table_layout_algorithm.cc)",
        "spec": "CSS Table 3 §2 & CSS Box Model 3 (Table wrapper fragment containing captions and table grid fragment)",
        "prompt": """You are Agent 224 auditing Chromium Blink Table Wrapper Box Fragment Tree Assembly.
Detail:
1. Fragment assembly: table wrapper fragment contains top captions, table grid fragment, bottom captions.
2. Invariants: vertical coordinates strictly advance: top_caption_bottom <= grid_top, grid_bottom <= bottom_caption_top.
3. Concrete Rocq/Coq definitions and theorems for BlinkTableWrapperFragmentAssemblySemantics.v with 0 admits."""
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
                thinking_config=types.ThinkingConfig(thinking_budget=2048)  # Benchmark-validated optimal budget!
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
    print("Launching Wave 19 (Iteration 4 of 8): 16 concurrent Python3 agents using gemini-4-argon with benchmark-validated optimal Medium thinking budget (2048)...")
    with concurrent.futures.ThreadPoolExecutor(max_workers=16) as executor:
        results = list(executor.map(run_agent, tasks))

    total_p = sum(r.get("prompt_tokens", 0) for r in results)
    total_c = sum(r.get("candidates_tokens", 0) for r in results)
    total_t = sum(r.get("total_tokens", 0) for r in results)

    log_entry = {
        "timestamp": time.strftime("%Y-%m-%d %H:%M:%S"),
        "model": "gemini-4-argon",
        "wave": 19,
        "iteration": 4,
        "theme": "Table Deep Semantics, Colgroups & Border Collapsing (Fixed Layout, Column Locations, Border Style Conflict, Border Width Conflict, Row Baseline Alignment, Empty Row Suppression, Cell Colspan Distribution, Cell Rowspan Distribution, Caption Margin Collapsing, Collapsed Border Half-Widths, Table Min/Max Sizing, Colgroup Span Expansion, Row Percent Heights, Cell Vertical Align Middle, Cell Vertical Align Bottom, Table Wrapper Fragment Tree Assembly)",
        "thinking_budget": 2048,
        "agents": results,
        "aggregate": {
            "prompt_tokens": total_p,
            "candidates_tokens": total_c,
            "total_tokens": total_t
        }
    }

    with open("token_usage.log", "a") as f:
        f.write(json.dumps(log_entry, indent=2) + "\n---\n")

    print("\n=== WAVE 19 (ITERATION 4 OF 8) TOKEN USAGE REPORT ===")
    print(f"Prompt Tokens:     {total_p}")
    print(f"Candidate Tokens:  {total_c}")
    print(f"Total Tokens Used: {total_t}")
    print("Appended log entry to token_usage.log.")
