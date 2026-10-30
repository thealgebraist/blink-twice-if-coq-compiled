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
        "id": "agent1",
        "file": "agent1_multicol_column_balancing.md",
        "topic": "Chromium Blink Multi-column Balancing (third_party/blink/renderer/core/layout/fragmentation/column_layout_algorithm.cc and column_balancing_info.h)",
        "spec": "W3C CSS Multi-column Layout Module Level 1 (Section 3: Column Width and Count, Section 4: Column Breaking and Balancing)",
        "prompt": """You are Agent 1 auditing Chromium Blink Multi-column Layout and Column Balancing vs W3C CSS Multi-column Layout Module Level 1.
Detail:
1. Core data structures in Blink column balancing (ColumnLayoutAlgorithm, ColumnBalancingInfo, ColumnWidth, ColumnCount, ColumnGap).
2. Sizing calculation: available inline size resolution into computed column-count (N) and used column-width (W):
   - W = max(0, min(available_inline, column-width))
   - N = max(1, floor((available_inline + column-gap) / (used_column-width + column-gap)))
   - Distribution of extra inline space across columns: W_used = (available_inline - (N - 1) * column-gap) / N.
3. Multi-pass column balancing loop: minimal column height search (binary search / iterative relaxation between total_block_size / N and max_child_block_size).
4. Mathematical formulas, invariants (space conservation across columns, monotonic column balancing convergence, non-negative column dimensions).
5. Edge cases and divergences between Blink ColumnLayoutAlgorithm and W3C CSS Multicol Level 1.
6. Provide concrete Rocq/Coq inductive definitions and theorems for formalizing this into BlinkMulticolBalancingSemantics.v."""
    },
    {
        "id": "agent2",
        "file": "agent2_subgrid.md",
        "topic": "Chromium Blink CSS Subgrid Layout (third_party/blink/renderer/core/layout/grid/grid_line_resolver.cc and grid_subtree.h)",
        "spec": "W3C CSS Grid Layout Module Level 2 (Section 2: Subgrids, Section 3: Subgrid Sizing)",
        "prompt": """You are Agent 2 auditing Chromium Blink CSS Subgrid Layout vs W3C CSS Grid Layout Module Level 2.
Detail:
1. Core data structures in Blink subgrid (GridSubtree, GridLineResolver, SubgridLineRange, ParentGridSizingContext).
2. Inherited track slice mapping: how subgrid maps its local line indices [1..k] to parent track indices [p_start..p_end].
3. Track sizing contribution: subgrid items participate directly in the parent grid's Track Sizing Algorithm (W3C Grid 1 §11 / Blink NGGridTrackCollection) across multiple spans.
4. Margin, border, and padding handling at subgrid boundaries (collapsing/adjusting the first and last inherited tracks).
5. Mathematical formulas, invariants (index range containment p_start <= p_end, monotonicity of subgrid coordinate offsets), edge cases, and divergences between Blink and W3C Grid 2.
6. Provide concrete Rocq/Coq inductive definitions and theorems for formalizing this into BlinkSubgridSemantics.v."""
    },
    {
        "id": "agent3",
        "file": "agent3_sticky_positioning.md",
        "topic": "Chromium Blink Sticky Positioning (third_party/blink/renderer/core/layout/sticky_position_scrolling_constraints.cc and sticky_position_scrolling_constraints.h)",
        "spec": "W3C CSS Positioned Layout Module Level 3 (Section 2.4: Sticky Positioning, Section 3: Insets)",
        "prompt": """You are Agent 3 auditing Chromium Blink Sticky Positioning vs W3C CSS Positioned Layout Module Level 3.
Detail:
1. Core data structures in Blink sticky positioning (StickyPositionScrollingConstraints, StickyConstraintsMap, PhysicalRect, ScrollContainerRelative).
2. 1D Sticky constraint equation:
   - Sticky offset calculation: sticky_offset = clamp(min_offset, scroll_offset + inset - static_position, max_offset).
   - Containment within enclosing scroll container and containing block rectangle (sticky box cannot escape containing block bottom/right edge).
3. Composition across multiple sticky ancestors and nested scrolling contexts.
4. Mathematical formulas, invariants (containment inside containing block, idempotence of clamping, monotonic sticky shift), edge cases, and divergences between Blink and W3C CSS Position 3.
5. Provide concrete Rocq/Coq inductive definitions and theorems for formalizing this into BlinkStickyPositioningSemantics.v."""
    },
    {
        "id": "agent4",
        "file": "agent4_baseline_alignment.md",
        "topic": "Chromium Blink Multi-Box Baseline Alignment (third_party/blink/renderer/core/layout/baseline_utils.cc and box_fragment.cc)",
        "spec": "W3C CSS Box Alignment Module Level 3 (Section 9: Baseline Alignment, Section 9.1: First vs Last Baseline, Section 9.3: Baseline Sharing Groups)",
        "prompt": """You are Agent 4 auditing Chromium Blink Baseline Alignment vs W3C CSS Box Alignment Module Level 3.
Detail:
1. Core data structures in Blink baseline alignment (BaselineUtils, FontBaseline, ItemPosition::kBaseline / kLastBaseline, BaselineGroup).
2. First baseline vs last baseline extraction from line boxes, replaced elements, inline blocks, flex items, and grid items.
3. Baseline sharing group algorithm:
   - Partitioning items sharing a common alignment context (e.g. flex line or grid row).
   - Computing group ascent: max(ascent_i) and group descent: max(descent_i).
   - Aligning box top edges to match baseline offsets: shift_i = group_ascent - ascent_i.
4. Mathematical formulas, invariants (group bounds conservation: height_group >= max(ascent_i + descent_i), non-negative shifting offsets), edge cases, and divergences between Blink and W3C CSS Box Alignment 3.
5. Provide concrete Rocq/Coq inductive definitions and theorems for formalizing this into BlinkBaselineAlignmentSemantics.v."""
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

print("Launching Wave 4: 4 concurrent Python3 agents using gemini-4-argon (thinking budget 1024)...")
with concurrent.futures.ThreadPoolExecutor(max_workers=4) as executor:
    results = list(executor.map(run_agent, tasks))

total_p = sum(r.get("prompt_tokens", 0) for r in results)
total_c = sum(r.get("candidates_tokens", 0) for r in results)
total_t = sum(r.get("total_tokens", 0) for r in results)

log_entry = {
    "timestamp": time.strftime("%Y-%m-%d %H:%M:%S"),
    "model": "gemini-4-argon",
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

print("\n=== WAVE 4 TOKEN USAGE REPORT ===")
print(f"Prompt Tokens:     {total_p}")
print(f"Candidate Tokens:  {total_c}")
print(f"Total Tokens Used: {total_t}")
print("Appended log entry to token_usage.log.")
