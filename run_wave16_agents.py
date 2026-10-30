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
        "id": "agent161",
        "file": "agent161_grid_auto_repeat.md",
        "topic": "Chromium Blink CSS Grid Repeat Auto-Fill vs Auto-Fit (core/layout/grid/grid_track_collection.cc)",
        "spec": "CSS Grid Layout 1 §7.2.2 (repeat(auto-fill, ...), repeat(auto-fit, ...), empty track collapsing)",
        "prompt": """You are Agent 161 auditing Chromium Blink CSS Grid Repeat Auto-Fill vs Auto-Fit vs CSS Grid 1 §7.2.2.
Detail:
1. GridTrackCollection calculation of track count for auto-fill: N = max(1, floor((W_avail + gap) / (track_size + gap))).
2. Auto-fit difference: tracks that have no grid items are collapsed to 0px used size.
3. Invariants: N >= 1 whenever W_avail >= track_size, total used track space <= W_avail, empty track collapsing preserves occupied tracks.
4. Concrete Rocq/Coq definitions and theorems for BlinkGridAutoRepeatSemantics.v."""
    },
    {
        "id": "agent162",
        "file": "agent162_grid_dense_placement.md",
        "topic": "Chromium Blink Grid Auto-Placement Dense Algorithm (core/layout/grid/grid_placement.cc)",
        "spec": "CSS Grid Layout 1 §8.5 (grid-auto-flow: dense, back-filling cursor reset)",
        "prompt": """You are Agent 162 auditing Chromium Blink Grid Auto-Placement Dense vs CSS Grid 1 §8.5.
Detail:
1. GridPlacement cursor management: non-dense maintains monotonically advancing cursor; dense resets cursor to (0, 0) for each item.
2. Invariants: all placed items occupy non-overlapping cell intervals, dense placement never leaves fillable holes before the end.
3. Concrete Rocq/Coq definitions and theorems for BlinkGridDensePlacementSemantics.v."""
    },
    {
        "id": "agent163",
        "file": "agent163_grid_min_max_content.md",
        "topic": "Chromium Blink CSS Grid Min-Content & Max-Content Track Contribution (core/layout/grid/grid_layout_algorithm.cc)",
        "spec": "CSS Grid Layout 1 §11.5 (Track sizing algorithm, item contributions to min/max content)",
        "prompt": """You are Agent 163 auditing Chromium Blink Grid Track Min/Max Content Contribution vs CSS Grid 1 §11.5.
Detail:
1. Calculation of base track size from min-content contributions and growth limit from max-content.
2. Invariant: base_size <= growth_limit, track base size is lower-bounded by largest spanning item's min-content contribution.
3. Concrete Rocq/Coq definitions and theorems for BlinkGridMinMaxContentSemantics.v."""
    },
    {
        "id": "agent164",
        "file": "agent164_grid_gap_distribution.md",
        "topic": "Chromium Blink Grid Gap / Gutter Inline and Block Distribution (core/layout/grid/grid_layout_algorithm.cc)",
        "spec": "CSS Box Alignment 3 §8 (column-gap, row-gap, gap bounds, space consumption)",
        "prompt": """You are Agent 164 auditing Chromium Blink Grid Gap Distribution vs CSS Box Alignment 3 §8.
Detail:
1. Gap allocation: between N tracks there are exactly max(0, N - 1) gaps.
2. Total gap space = max(0, N - 1) * gap. Available space for tracks W_tracks = max(0, W_total - Total_gap).
3. Invariants: track offsets strictly advance by track_size + gap; total span covers sum(tracks) + (N - 1)*gap.
4. Concrete Rocq/Coq definitions and theorems for BlinkGridGapDistributionSemantics.v."""
    },
    {
        "id": "agent165",
        "file": "agent165_flex_baseline_alignment.md",
        "topic": "Chromium Blink Flex Baseline Alignment across Items (core/layout/flex/flexible_box_algorithm.cc)",
        "spec": "CSS Flexible Box Layout 1 §8.3 (align-items: baseline, max ascent/descent)",
        "prompt": """You are Agent 165 auditing Chromium Blink Flex Baseline Alignment vs CSS Flexbox 1 §8.3.
Detail:
1. Baseline calculation: max_ascent = max(item_baseline), max_descent = max(item_cross_size - item_baseline).
2. Flex line cross size = max_ascent + max_descent.
3. Invariant: each item's baseline aligns to max_ascent, item cross offset = max_ascent - item_baseline >= 0.
4. Concrete Rocq/Coq definitions and theorems for BlinkFlexBaselineAlignmentSemantics.v."""
    },
    {
        "id": "agent166",
        "file": "agent166_flex_min_size_auto.md",
        "topic": "Chromium Blink Flexbox Min-Size: Auto Clamping (core/layout/flex/flex_layout_algorithm.cc)",
        "spec": "CSS Flexible Box Layout 1 §4.5 (Automatic minimum size of flex items, min-width: auto)",
        "prompt": """You are Agent 166 auditing Chromium Blink Flex Min-Size: Auto Clamping vs CSS Flexbox 1 §4.5.
Detail:
1. Automatic minimum size resolution: min(specified_size, min_content).
2. Clamping: flex item used main size >= auto_min_size.
3. Invariant: used size is non-negative and bounded below by intrinsic min-content when specified size is auto.
4. Concrete Rocq/Coq definitions and theorems for BlinkFlexMinSizeAutoSemantics.v."""
    },
    {
        "id": "agent167",
        "file": "agent167_flex_reverse_axis.md",
        "topic": "Chromium Blink Flex Reverse Main Axis Placement (core/layout/flex/flexible_box_algorithm.cc)",
        "spec": "CSS Flexible Box Layout 1 §5.1 (flex-direction: row-reverse, column-reverse)",
        "prompt": """You are Agent 167 auditing Chromium Blink Flex Reverse Main Axis Placement vs CSS Flexbox 1 §5.1.
Detail:
1. Coordinate mapping for reverse direction: x_item = W_line - (x_normal + W_item).
2. Invariants: item intervals remain disjoint and in reverse order, total occupied span is identical between normal and reverse.
3. Concrete Rocq/Coq definitions and theorems for BlinkFlexReverseAxisSemantics.v."""
    },
    {
        "id": "agent168",
        "file": "agent168_flex_cross_stretch.md",
        "topic": "Chromium Blink Flex Cross Axis Stretch Sizing under Constraints (core/layout/flex/flex_layout_algorithm.cc)",
        "spec": "CSS Flexible Box Layout 1 §8.3 (align-self: stretch, cross size clamping)",
        "prompt": """You are Agent 168 auditing Chromium Blink Flex Cross Axis Stretch vs CSS Flexbox 1 §8.3.
Detail:
1. Stretch sizing: when align-self is stretch and cross size is auto, used_cross_size = clamp(min_cross, max_cross, line_cross_size).
2. Invariant: used_cross_size matches line_cross_size if line_cross_size is within [min_cross, max_cross].
3. Concrete Rocq/Coq definitions and theorems for BlinkFlexCrossStretchSemantics.v."""
    },
    {
        "id": "agent169",
        "file": "agent169_grid_fit_content_clamp.md",
        "topic": "Chromium Blink CSS Grid Fit-Content Track Sizing (core/layout/grid/grid_track_collection.cc)",
        "spec": "CSS Grid Layout 1 §11.5.1 (fit-content(argument) track sizing clamp)",
        "prompt": """You are Agent 169 auditing Chromium Blink Grid fit-content() Track Clamping vs CSS Grid 1 §11.5.1.
Detail:
1. fit-content(L) formula: min(max(min_content, available_space), max(min_content, L)).
2. Invariants: track size is bounded above by max(min_content, L) and below by min_content.
3. Concrete Rocq/Coq definitions and theorems for BlinkGridFitContentClampSemantics.v."""
    },
    {
        "id": "agent170",
        "file": "agent170_grid_span_overlap.md",
        "topic": "Chromium Blink CSS Grid Span Line Overlap & Normalization (core/layout/grid/grid_placement.cc)",
        "spec": "CSS Grid Layout 1 §8.3 (grid-column: span N, line normalization [1, 10000])",
        "prompt": """You are Agent 170 auditing Chromium Blink Grid Span Overlap & Normalization vs CSS Grid 1 §8.3.
Detail:
1. Span resolution: end_line = start_line + span.
2. Normalization: start_line >= 1, end_line <= 10000.
3. Invariant: end_line > start_line, span length is strictly preserved under line shifts within bounds.
4. Concrete Rocq/Coq definitions and theorems for BlinkGridSpanOverlapSemantics.v."""
    },
    {
        "id": "agent171",
        "file": "agent171_flex_auto_margin_main.md",
        "topic": "Chromium Blink Flex Main Axis Auto Margin Absorption (core/layout/flex/flexible_box_algorithm.cc)",
        "spec": "CSS Flexible Box Layout 1 §8.1 (Aligning with auto margins along main axis)",
        "prompt": """You are Agent 171 auditing Chromium Blink Flex Main Axis Auto Margins vs CSS Flexbox 1 §8.1.
Detail:
1. Free space absorption: free_space = W_line - sum(item_sizes). If auto_margin_count > 0, each auto margin gets free_space / count.
2. Invariants: sum of allocated auto margins equals free_space (minus integer remainder), justify-content has no effect when auto margins exist.
3. Concrete Rocq/Coq definitions and theorems for BlinkFlexAutoMarginMainSemantics.v."""
    },
    {
        "id": "agent172",
        "file": "agent172_flex_auto_margin_cross.md",
        "topic": "Chromium Blink Flex Cross Axis Auto Margin Absorption (core/layout/flex/flexible_box_algorithm.cc)",
        "spec": "CSS Flexible Box Layout 1 §8.1 (Aligning with auto margins along cross axis)",
        "prompt": """You are Agent 172 auditing Chromium Blink Flex Cross Axis Auto Margins vs CSS Flexbox 1 §8.1.
Detail:
1. Cross auto margin absorption: remaining_cross = line_cross_size - item_cross_size.
2. Invariants: if both top/bottom auto margins exist, each gets remaining_cross / 2 (centered); align-self is suppressed.
3. Concrete Rocq/Coq definitions and theorems for BlinkFlexAutoMarginCrossSemantics.v."""
    },
    {
        "id": "agent173",
        "file": "agent173_grid_item_stretch.md",
        "topic": "Chromium Blink CSS Grid Item Stretch Alignment in Grid Area (core/layout/grid/grid_item.cc)",
        "spec": "CSS Box Alignment 3 §6.2 (justify-self: stretch, align-self: stretch)",
        "prompt": """You are Agent 173 auditing Chromium Blink Grid Item Stretch Alignment vs CSS Box Alignment 3 §6.2.
Detail:
1. Cell area calculation: area_w = track_end_x - track_start_x - margins.
2. Item stretch: item_w = max(min_w, min(max_w, area_w)).
3. Invariant: stretched item fills cell area if cell area is within [min_w, max_w]; margins are preserved.
4. Concrete Rocq/Coq definitions and theorems for BlinkGridItemStretchSemantics.v."""
    },
    {
        "id": "agent174",
        "file": "agent174_grid_aspect_ratio_stretch.md",
        "topic": "Chromium Blink Grid Item Aspect Ratio Preservation under Single-Axis Stretch (core/layout/grid/grid_item.cc)",
        "spec": "CSS Grid Layout 1 §10.4 & CSS Sizing 4 §3.3 (Aspect ratio with stretch alignment)",
        "prompt": """You are Agent 174 auditing Chromium Blink Grid Item Aspect Ratio with Stretch vs CSS Grid 1 §10.4.
Detail:
1. Aspect ratio cross-resolution: if inline axis is stretched to W, block axis auto height becomes round(W / ratio).
2. Invariant: aspect ratio is preserved: |W * ratio_den - H * ratio_num| < ratio_den.
3. Concrete Rocq/Coq definitions and theorems for BlinkGridAspectRatioStretchSemantics.v."""
    },
    {
        "id": "agent175",
        "file": "agent175_flex_fragment_break.md",
        "topic": "Chromium Blink Flexbox Fragmentation Break Token Continuation (core/layout/flex/flex_break_token.cc)",
        "spec": "CSS Fragmentation 3 §4 & CSS Flexbox 1 §10 (Breaking flex containers across pages)",
        "prompt": """You are Agent 175 auditing Chromium Blink Flexbox Fragmentation Continuation vs CSS Fragmentation 3 §4.
Detail:
1. FlexBreakToken representation: current flex line index, item fragment index, consumed block size.
2. Resumption: subsequent fragment continues layout from (line_index, item_index).
3. Invariants: consumed block sizes are strictly monotonic, total fragments encompass all items.
4. Concrete Rocq/Coq definitions and theorems for BlinkFlexFragmentBreakSemantics.v."""
    },
    {
        "id": "agent176",
        "file": "agent176_grid_fragment_break.md",
        "topic": "Chromium Blink Grid Fragmentation Row Continuation (core/layout/grid/grid_break_token.cc)",
        "spec": "CSS Fragmentation 3 §4 & CSS Grid 1 §10 (Breaking grid containers across pages)",
        "prompt": """You are Agent 176 auditing Chromium Blink Grid Fragmentation Continuation vs CSS Fragmentation 3 §4.
Detail:
1. GridBreakToken representation: broken row index, row offset offset within broken row.
2. Resumption: subsequent fragment starts at broken row index.
3. Invariants: row indices strictly advance, sum of fragment heights >= total grid height.
4. Concrete Rocq/Coq definitions and theorems for BlinkGridFragmentBreakSemantics.v."""
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
    print("Launching Wave 16 (Iteration 1 of 8): 16 concurrent Python3 agents using gemini-4-argon (low thinking budget 512)...")
    with concurrent.futures.ThreadPoolExecutor(max_workers=16) as executor:
        results = list(executor.map(run_agent, tasks))

    total_p = sum(r.get("prompt_tokens", 0) for r in results)
    total_c = sum(r.get("candidates_tokens", 0) for r in results)
    total_t = sum(r.get("total_tokens", 0) for r in results)

    log_entry = {
        "timestamp": time.strftime("%Y-%m-%d %H:%M:%S"),
        "model": "gemini-4-argon",
        "wave": 16,
        "iteration": 1,
        "theme": "Advanced CSS Grid & Flexbox Constraints (Auto-Repeat, Dense Placement, Min/Max Track Contributions, Gap Distribution, Baseline Alignment, Min-Size Auto, Reverse Axis, Cross Stretch, Fit-Content Clamp, Span Overlap, Main Auto Margins, Cross Auto Margins, Item Stretch, Aspect Ratio Stretch, Flex Break Tokens, Grid Break Tokens)",
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

    print("\n=== WAVE 16 (ITERATION 1 OF 8) TOKEN USAGE REPORT ===")
    print(f"Prompt Tokens:     {total_p}")
    print(f"Candidate Tokens:  {total_c}")
    print(f"Total Tokens Used: {total_t}")
    print("Appended log entry to token_usage.log.")

