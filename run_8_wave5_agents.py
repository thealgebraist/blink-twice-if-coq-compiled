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
        "file": "agent1_counter_styles.md",
        "topic": "Chromium Blink CSS Counter Styles (third_party/blink/renderer/core/css/counter_style.cc and counter_style_map.cc)",
        "spec": "W3C CSS Counter Styles Level 3 (§2 Counter Style System, §3 Symbols, §4 Additive, §5 Cyclic)",
        "prompt": """You are Agent 1 auditing Chromium Blink Counter Styles vs W3C CSS Counter Styles Level 3.
Detail:
1. Core data structures in Blink counter styles (CounterStyle, CounterStyleMap, CounterStyleSystem: Cyclic, Fixed, Symbolic, Alphabetic, Numeric, Additive).
2. Counter integer string generation algorithm across all systems.
3. Fallback resolution mechanism when an integer falls outside a system's defined range.
4. Mathematical invariants (deterministic string generation, non-empty fallback chains), edge cases, and gaps between Blink and W3C Counter Styles 3.
5. Provide concrete Rocq/Coq inductive definitions and theorems for formalizing this into BlinkCounterStyleSemantics.v."""
    },
    {
        "id": "agent2",
        "file": "agent2_flex_wrap.md",
        "topic": "Chromium Blink Flexbox Multi-Line Wrapping (third_party/blink/renderer/core/layout/flex/flex_line.cc and flex_layout_algorithm.cc)",
        "spec": "W3C CSS Flexible Box Layout Level 1 (Section 9.3: Flex Line Breaking, Section 9.4: Cross Size Determination)",
        "prompt": """You are Agent 2 auditing Chromium Blink Multi-Line Flex Wrapping vs W3C CSS Flexible Box Layout Level 1 §9.3 & §9.4.
Detail:
1. Core data structures in Blink flex wrapping (FlexLine, Vector<FlexLine>, BreakTokens in multi-line flex).
2. Line breaking algorithm: greedy item accumulation, flex-wrap: nowrap vs wrap vs wrap-reverse.
3. Cross-size determination per line and align-content distribution (flex-start, flex-end, center, space-between, space-around, stretch).
4. Mathematical invariants (monotonic item line partitioning, container cross-size conservation), edge cases, and gaps between Blink and W3C Flexbox §9.3-9.4.
5. Provide concrete Rocq/Coq inductive definitions and theorems for formalizing this into BlinkFlexWrapSemantics.v."""
    },
    {
        "id": "agent3",
        "file": "agent3_masonry.md",
        "topic": "Chromium Blink CSS Masonry Layout (third_party/blink/renderer/core/layout/grid/masonry_layout_algorithm.cc)",
        "spec": "W3C CSS Grid Layout Module Level 3 / CSS Masonry Layout Level 1 (§2 Track Sizing, §3 Item Placement)",
        "prompt": """You are Agent 3 auditing Chromium Blink Masonry Layout vs W3C CSS Masonry Layout.
Detail:
1. Core data structures in Blink masonry (MasonryLayoutAlgorithm, MasonryTrackStack, RunningTrackLengths).
2. Placement algorithm: finding the track with the minimum running position, placing the item, and advancing the running position by item outer block size.
3. Cross-axis track sizing vs main-axis running stack accumulation.
4. Mathematical invariants (deterministic placement, monotonic running track heights, non-negativity), edge cases, and divergences.
5. Provide concrete Rocq/Coq inductive definitions and theorems for formalizing this into BlinkMasonrySemantics.v."""
    },
    {
        "id": "agent4",
        "file": "agent4_anchor_query.md",
        "topic": "Chromium Blink Anchor Size Query Evaluation (third_party/blink/renderer/core/layout/anchor_evaluator_impl.cc and anchor_query.cc)",
        "spec": "W3C CSS Anchor Positioning Level 1 (§4.2 The anchor-size() Function: width, height, inline, block)",
        "prompt": """You are Agent 4 auditing Chromium Blink Anchor Size Query vs W3C CSS Anchor Positioning Level 1 §4.2.
Detail:
1. Core data structures in Blink anchor queries (AnchorQuery, AnchorKey, AnchorEvaluatorImpl, PhysicalAnchorQuery).
2. Evaluation of anchor-size(target-anchor, size-axis, fallback-length).
3. Circular dependency detection and fallback substitution.
4. Mathematical invariants (size non-negativity, deterministic fallback, acyclic query resolution), edge cases, and divergences.
5. Provide concrete Rocq/Coq inductive definitions and theorems for formalizing this into BlinkAnchorSizeSemantics.v."""
    },
    {
        "id": "agent5",
        "file": "agent5_shape_outside.md",
        "topic": "Chromium Blink CSS Shapes and Exclusions (third_party/blink/renderer/core/layout/shapes/shape_outside_info.cc and box_shape.cc)",
        "spec": "W3C CSS Shapes Module Level 1 (§3 Shapes from Image, §4 Basic Shapes: circle, ellipse, polygon)",
        "prompt": """You are Agent 5 auditing Chromium Blink CSS Shapes vs W3C CSS Shapes Module Level 1.
Detail:
1. Core data structures in Blink shapes (ShapeOutsideInfo, BoxShape, PolygonShape, SegmentList, LineSegment).
2. Line segment calculation: computing available inline intervals (excluded line segments) at a given cursor Y offset.
3. Shape margin expansion: dilating basic shapes by shape-margin.
4. Mathematical invariants (interval ordering, non-empty inline segment preservation), edge cases, and divergences.
5. Provide concrete Rocq/Coq inductive definitions and theorems for formalizing this into BlinkShapeOutsideSemantics.v."""
    },
    {
        "id": "agent6",
        "file": "agent6_transform_origin.md",
        "topic": "Chromium Blink Transform & Coordinate Mapping (third_party/blink/renderer/core/layout/geometry/transform_state.cc and transformation_matrix.cc)",
        "spec": "W3C CSS Transforms Module Level 1 (§2 The 2D Transform Matrix, §3 The 3D Transform Matrix, §5 Transform Origin)",
        "prompt": """You are Agent 6 auditing Chromium Blink Transform Coordinate Mapping vs W3C CSS Transforms Level 1.
Detail:
1. Core data structures in Blink transforms (TransformState, TransformationMatrix, TransformOrigin).
2. 2D Affine transform application: translating to transform-origin, multiplying by matrix M (scale, rotate, translate, skew), and translating back.
3. Invertibility check and mapping physical bounding boxes through transformed space.
4. Mathematical invariants (identity transform neutrality, matrix multiplication associativity, bounding box containment), edge cases, and divergences.
5. Provide concrete Rocq/Coq inductive definitions and theorems for formalizing this into BlinkTransformOriginSemantics.v."""
    },
    {
        "id": "agent7",
        "file": "agent7_bidi_resolution.md",
        "topic": "Chromium Blink Unicode Bidirectional Algorithm (third_party/blink/renderer/core/layout/inline/bidi_paragraph.cc and line_info.cc)",
        "spec": "Unicode Standard Annex #9 (Unicode Bidirectional Algorithm) & W3C CSS Writing Modes 3 §2 (Inline Direction and BiDi)",
        "prompt": """You are Agent 7 auditing Chromium Blink BiDi Resolution vs UAX #9 and W3C CSS Writing Modes 3.
Detail:
1. Core data structures in Blink inline BiDi (BidiParagraph, BidiRun, Direction, ResolveParagraphDirection).
2. Resolving embedding levels (0..125) and reordering visual runs from logical character stream.
3. LTR vs RTL paragraph base direction heuristics (first strong directional character).
4. Mathematical invariants (involution of run reordering, level parity matching visual direction), edge cases, and divergences.
5. Provide concrete Rocq/Coq inductive definitions and theorems for formalizing this into BlinkBidiResolutionSemantics.v."""
    },
    {
        "id": "agent8",
        "file": "agent8_css_containment.md",
        "topic": "Chromium Blink CSS Containment & Size Containment (third_party/blink/renderer/core/layout/layout_box.cc and style_containment_scope.cc)",
        "spec": "W3C CSS Containment Module Level 2 (§2 Containment Types: size, layout, paint, style, inline-size)",
        "prompt": """You are Agent 8 auditing Chromium Blink CSS Containment vs W3C CSS Containment Module Level 2.
Detail:
1. Core data structures in Blink containment (ContainmentFlags, LayoutBox::ShouldApplySizeContainment, ShouldApplyInlineSizeContainment).
2. Sizing overrides under 'contain: size': layout occurs as if the box has no contents (intrinsic width and height evaluate to 0).
3. 'contain: inline-size': intrinsic inline size treats content as empty, but block size depends on normal layout.
4. Mathematical invariants (size containment monotonicity, independent formatting context isolation), edge cases, and divergences.
5. Provide concrete Rocq/Coq inductive definitions and theorems for formalizing this into BlinkCSSContainmentSemantics.v."""
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

print("Launching Wave 5: 8 concurrent Python3 agents using gemini-4-argon (thinking budget 1024)...")
with concurrent.futures.ThreadPoolExecutor(max_workers=8) as executor:
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

print("\n=== WAVE 5 (8 AGENTS) TOKEN USAGE REPORT ===")
print(f"Prompt Tokens:     {total_p}")
print(f"Candidate Tokens:  {total_c}")
print(f"Total Tokens Used: {total_t}")
print("Appended log entry to token_usage.log.")
