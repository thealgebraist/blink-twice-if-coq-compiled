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
        "file": "agent1_scrollable_overflow.md",
        "topic": "Chromium Blink Scrollable Overflow (third_party/blink/renderer/core/paint/paint_layer_scrollable_area.cc and scrollable_overflow_calculator.cc)",
        "spec": "W3C CSS Overflow Module Level 3 (Section 3: Scrollable Overflow, Section 3.1: Scroll Origin, Section 3.2: Reaching Overflow Extent)",
        "prompt": """You are Agent 1 auditing Chromium Blink Scrollable Overflow vs W3C CSS Overflow Module Level 3 Section 3.
Detail:
1. Core data structures in Blink scrollable overflow (PaintLayerScrollableArea, ScrollableOverflowCalculator, PhysicalRect, ScrollOffset).
2. Calculation of scrollable overflow rectangle: inclusion of in-flow children, out-of-flow positioned descendants, transformed elements, and exclusion of unreached negative margins or non-scrollable overflow.
3. Scroll origin offset resolution under LTR vs RTL / vertical writing modes (scroll origin at top-left vs top-right/bottom-left).
4. Mathematical formulas, invariants (scroll origin non-negativity in positive directions, overflow rect containment of border-box), edge cases, and divergences between Blink and W3C CSS Overflow Level 3.
5. Provide concrete Rocq/Coq inductive definitions and theorems for formalizing this into BlinkScrollableOverflow.v."""
    },
    {
        "id": "agent2",
        "file": "agent2_writing_modes.md",
        "topic": "Chromium Blink Writing Modes & Logical Coordinate Geometry (third_party/blink/renderer/core/layout/geometry/logical_size.h, writing_mode_converter.cc, and writing_mode.h)",
        "spec": "W3C CSS Writing Modes Level 3 (Section 3: Introduction to Vertical Text, Section 7: Abstract Box Terminology, Section 7.4: Coordinate Transformations)",
        "prompt": """You are Agent 2 auditing Chromium Blink Writing Modes vs W3C CSS Writing Modes Level 3.
Detail:
1. Core data structures in Blink writing modes (WritingMode, TextDirection, LogicalSize, LogicalOffset, PhysicalSize, PhysicalOffset, WritingModeConverter).
2. Coordinate transform calculus between logical coordinates (inline, block) and physical coordinates (X, Y) across all 4 writing mode orientations:
   - horizontal-tb (LTR vs RTL)
   - vertical-rl (LTR vs RTL)
   - vertical-lr (LTR vs RTL)
   - sideways-rl / sideways-lr
3. Mathematical formulas for bijection: Converter::ToPhysicalOffset(logical_offset, inner_size) and Converter::ToLogicalOffset(physical_offset, inner_size).
4. Invariants (bijective involution: ToLogical(ToPhysical(L)) == L, non-negativity preservation, container size dependency).
5. Edge cases and divergences between Blink LayoutNG geometry and W3C CSS Writing Modes Level 3.
6. Provide concrete Rocq/Coq inductive definitions and theorems for formalizing this into BlinkWritingModeSemantics.v."""
    },
    {
        "id": "agent3",
        "file": "agent3_media_queries.md",
        "topic": "Chromium Blink Media Query Evaluation (third_party/blink/renderer/core/css/media_query_evaluator.cc and media_query_exp.cc)",
        "spec": "W3C Media Queries Level 4 & Level 5 (Section 3: Syntax, Section 4: Media Features: width, height, aspect-ratio, orientation, resolution, prefers-color-scheme)",
        "prompt": """You are Agent 3 auditing Chromium Blink Media Query Evaluation vs W3C Media Queries Level 4 and Level 5.
Detail:
1. Core AST data structures in Blink media queries (MediaQueryExp, MediaQueryExpValue, MediaQueryEvaluator, MediaFeaturePrefix: min, max, none, range).
2. Range context evaluation (<, <=, =, >=, >) vs legacy prefix evaluation (min-width, max-width).
3. Discrete vs continuous media features, ratio comparison (aspect-ratio: num / den), length comparisons with viewport dimensions (em, rem, px).
4. Three-valued logic calculus (true, false, unknown) under CSS Media Queries 4 §3.1 boolean operations (and, or, not).
5. Invariants (monotonicity of min-width: w1 <= w2 implies min-width(w1) <= min-width(w2), boolean algebra soundness, de Morgan laws in three-valued logic).
6. Edge cases, quirks, and divergences between Blink's evaluator and W3C Media Queries 4/5.
7. Provide concrete Rocq/Coq inductive definitions and theorems for formalizing this into BlinkMediaQuerySemantics.v."""
    },
    {
        "id": "agent4",
        "file": "agent4_list_markers.md",
        "topic": "Chromium Blink List Marker Layout & Counter Sizing (third_party/blink/renderer/core/layout/list/layout_list_marker.cc, list_marker.cc, and list_item_layout_algorithm.cc)",
        "spec": "W3C CSS Lists and Counters Module Level 3 (Section 3: Markers: ::marker pseudo-element, Section 4: Marker Position: inside vs outside, Section 5: Counter Styles)",
        "prompt": """You are Agent 4 auditing Chromium Blink List Marker Layout vs W3C CSS Lists and Counters Module Level 3.
Detail:
1. Core data structures in Blink list markers (ListMarker, LayoutListMarker, ListItemType, MarkerType: Symbol, Number, Image).
2. Layout mechanics for 'list-style-position: inside' (inline child preceding list-item content) vs 'list-style-position: outside' (out-of-flow relative marker offset to the left/right of the line box).
3. Sizing calculation: intrinsic text extent, margin offset calculation, baseline alignment between marker text and the first line box of the list item.
4. Counter string formatting and symbol resolution (decimal, disc, circle, square).
5. Invariants (marker width non-negativity, outside offset equation $x_{marker} + w_{marker} \le x_{content}$, deterministic position resolution).
6. Edge cases and divergences between Blink LayoutNG list marker placement and W3C CSS Lists 3.
7. Provide concrete Rocq/Coq inductive definitions and theorems for formalizing this into BlinkListMarkerSemantics.v."""
    }
]

token_log = {}

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

print("Launching Wave 3: 4 concurrent Python3 agents using gemini-4-argon (thinking budget 1024)...")
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

print("\n=== WAVE 3 TOKEN USAGE REPORT ===")
print(f"Prompt Tokens:     {total_p}")
print(f"Candidate Tokens:  {total_c}")
print(f"Total Tokens Used: {total_t}")
print("Appended log entry to token_usage.log.")
