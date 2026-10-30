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
        "id": "agent25",
        "file": "agent25_float_exclusion.md",
        "topic": "Chromium Blink CSS Floats & Exclusion Space (third_party/blink/renderer/core/layout/exclusions/exclusion_space.cc and layout_opportunity.cc)",
        "spec": "CSS 2.1 (§9.5 Floats, §9.5.1 'clear', §9.5.2 Controlling flow next to floats)",
        "prompt": """You are Agent 25 auditing Chromium Blink Float Placement & Exclusion Space vs CSS 2.1 §9.5.
Detail:
1. Core data structures in Blink float exclusions (ExclusionSpace, ExclusionShapeData, LayoutOpportunity, BfcOffset, ExclusionType: FloatLeft, FloatRight).
2. Layout opportunity finding algorithm: calculating available inline intervals [left, right) between left and right floats at a given block offset y.
3. Clearance calculation (clear: left, right, both): advancing block cursor past preceding floats.
4. Mathematical invariants: left_offset <= right_offset for all layout opportunities, monotonicity of clearance offset, float non-overlapping property, determinism.
5. Provide concrete Rocq/Coq inductive definitions and theorems for formalizing this into BlinkFloatExclusionSemantics.v."""
    },
    {
        "id": "agent26",
        "file": "agent26_flex_basis.md",
        "topic": "Chromium Blink Flex-Basis & Transferred Size (third_party/blink/renderer/core/layout/flex/flexible_box_algorithm.cc)",
        "spec": "W3C CSS Flexible Box Layout Level 1 (§9.2 Determine the flex base size and hypothetical main size)",
        "prompt": """You are Agent 26 auditing Chromium Blink Flex Basis Resolution vs CSS Flexible Box Layout Level 1 §9.2.
Detail:
1. Core data structures in Blink flex basis resolution (FlexItem, FlexBasis, EFlexBasisType: Content, Auto, Length, Percent).
2. Transferred size resolution with aspect-ratio: resolving flex base size from cross size when flex-basis is content/auto.
3. Hypothetical main size determination: clamping flex base size by min-main-size and max-main-size (respecting CSS min overrides max).
4. Mathematical invariants: hypothetical main size satisfies min <= size <= max, monotonicity with respect to available space, non-negativity.
5. Provide concrete Rocq/Coq inductive definitions and theorems for formalizing this into BlinkFlexBasisSemantics.v."""
    },
    {
        "id": "agent27",
        "file": "agent27_ruby_layout.md",
        "topic": "Chromium Blink Ruby Annotation Layout (third_party/blink/renderer/core/layout/inline/ruby_utils.cc and ruby_layout_algorithm.cc)",
        "spec": "W3C CSS Ruby Layout Module Level 1 (§3 Ruby Structure: ruby, rt, rp, §4 Ruby Formatting)",
        "prompt": """You are Agent 27 auditing Chromium Blink Ruby Layout vs W3C CSS Ruby Layout Level 1.
Detail:
1. Core data structures in Blink ruby layout (RubyBlockPosition, RubyColumn, RubyTextPosition: Over, Under).
2. Ruby column pairing algorithm: pairing ruby base elements with ruby text (<rt>) annotation elements.
3. Ruby column inline size resolution: column inline size is max(base_inline_size, annotation_inline_size), centering or distributing space.
4. Mathematical invariants: column inline size >= base size, column inline size >= annotation size, non-negativity, determinism.
5. Provide concrete Rocq/Coq inductive definitions and theorems for formalizing this into BlinkRubyLayoutSemantics.v."""
    },
    {
        "id": "agent28",
        "file": "agent28_container_queries.md",
        "topic": "Chromium Blink CSS Container Queries (third_party/blink/renderer/core/css/container_query_evaluator.cc)",
        "spec": "W3C CSS Containment Module Level 3 (§3 Container Queries, @container, cq length units)",
        "prompt": """You are Agent 28 auditing Chromium Blink Container Query Evaluation vs W3C CSS Containment Level 3.
Detail:
1. Core data structures in Blink container queries (ContainerQueryEvaluator, ContainerSelector, PhysicalAxes, ContainerQueryUnit).
2. Container selection algorithm: finding the nearest ancestor establishing the queried container-type (size, inline-size, normal).
3. Size query evaluation against container dimensions (min-width, max-width, width ranges).
4. Mathematical invariants: query evaluation determinism, monotonicity of min/max container width queries, container tree acyclicity.
5. Provide concrete Rocq/Coq inductive definitions and theorems for formalizing this into BlinkContainerQuerySemantics.v."""
    },
    {
        "id": "agent29",
        "file": "agent29_grid_track_sizing_phase1.md",
        "topic": "Chromium Blink Grid Track Sizing Phase 1 (third_party/blink/renderer/core/layout/grid/grid_track_collection.cc and grid_layout_algorithm.cc)",
        "spec": "W3C CSS Grid Layout Module Level 1 (§11.5.1 Initialize Track Sizes, §11.5.2 Resolve Intrinsic Track Sizes)",
        "prompt": """You are Agent 29 auditing Chromium Blink Grid Track Sizing Phase 1 vs CSS Grid 1 §11.5.
Detail:
1. Core data structures in Blink grid track sizing (GridTrackSizingAlgorithm, GridSet, TrackSize, GridItemData).
2. Track initialization: resolving base size (0 for min-content/max-content/auto, fixed length for <length>) and growth limit (infinity for auto/max-content, fixed for <length>).
3. Distributing intrinsic size of items spanning multiple tracks across spanned track base sizes.
4. Mathematical invariants: base_size <= growth_limit whenever growth_limit is finite, monotonicity of base size expansion, space conservation.
5. Provide concrete Rocq/Coq inductive definitions and theorems for formalizing this into BlinkGridTrackPhase1Semantics.v."""
    },
    {
        "id": "agent30",
        "file": "agent30_inline_hyphenation.md",
        "topic": "Chromium Blink Inline Hyphenation & Opportunity Finding (third_party/blink/renderer/core/layout/inline/hyphenator.cc)",
        "spec": "W3C CSS Text Module Level 3 (§5.4 Hyphenation: hyphens property, hyphenation opportunities)",
        "prompt": """You are Agent 30 auditing Chromium Blink Inline Hyphenation vs W3C CSS Text Level 3 §5.4.
Detail:
1. Core data structures in Blink hyphenation (Hyphenator, HyphenationOpportunity, hyphen_penalty, hyphens: none, manual, auto).
2. Hyphenation boundary computation: minimum prefix length (min-prefix), minimum suffix length (min-suffix), and soft hyphen (&shy;) matching.
3. Width contribution of hyphen glyph (hyphen-string width added to line before break).
4. Mathematical invariants: valid hyphenation opportunities occur strictly between min-prefix and word_length - min-suffix, determinism.
5. Provide concrete Rocq/Coq inductive definitions and theorems for formalizing this into BlinkHyphenationSemantics.v."""
    },
    {
        "id": "agent31",
        "file": "agent31_rect_lattice_geometry.md",
        "topic": "Chromium Blink 2D Rect Operations & Bounding Lattices (third_party/blink/renderer/core/layout/geometry/physical_rect.cc and logical_rect.cc)",
        "spec": "CSS 2.1 (§8 Box Dimensions) & SVG 2 (§7.5 Rectangles and Bounding Boxes)",
        "prompt": """You are Agent 31 auditing Chromium Blink 2D Rect Operations vs 2D Geometry Specifications.
Detail:
1. Core data structures in Blink rect geometry (PhysicalRect, LogicalRect, PhysicalOffset, PhysicalSize).
2. 2D Rect operations: Intersect (meet semi-lattice), Unite (join semi-lattice, minimal bounding box), Contains, InclusiveIntersects.
3. Empty rect behavior (width <= 0 or height <= 0) and saturation during rectangular bounding.
4. Mathematical invariants: Intersect is commutative, associative, and idempotent; Unite is commutative, associative, and idempotent; Intersect(A, Unite(A, B)) = A (absorption law).
5. Provide concrete Rocq/Coq inductive definitions and theorems for formalizing this into BlinkRectLatticeSemantics.v."""
    },
    {
        "id": "agent32",
        "file": "agent32_masonry_placement_modes.md",
        "topic": "Chromium Blink Masonry Item Placement Modes (third_party/blink/renderer/core/layout/grid/masonry_layout_algorithm.cc)",
        "spec": "W3C CSS Masonry Layout Level 1 (§3 Item Placement: masonry-auto-flow: pack vs next)",
        "prompt": """You are Agent 32 auditing Chromium Blink Masonry Placement Modes vs CSS Masonry Layout Level 1.
Detail:
1. Core data structures in Blink masonry placement (MasonryPlacementState, MasonryAutoFlow: Pack, Next, DefiniteTrack).
2. Placement strategies: 'pack' scans all tracks for the minimum running height; 'next' places items sequentially across tracks wrapping around modulo track count.
3. Multi-track span placement: finding consecutive tracks [k, k + span) that minimize the maximum running position across the span.
4. Mathematical invariants: placed item position >= running track height, placed track index < track_count, determinism, non-negativity.
5. Provide concrete Rocq/Coq inductive definitions and theorems for formalizing this into BlinkMasonryPlacementSemantics.v."""
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
    print("Launching Wave 8: 8 concurrent Python3 agents using gemini-4-argon (thinking budget 1024) for Layout & CSS Core...")
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as executor:
        results = list(executor.map(run_agent, tasks))

    total_p = sum(r.get("prompt_tokens", 0) for r in results)
    total_c = sum(r.get("candidates_tokens", 0) for r in results)
    total_t = sum(r.get("total_tokens", 0) for r in results)

    log_entry = {
        "timestamp": time.strftime("%Y-%m-%d %H:%M:%S"),
        "model": "gemini-4-argon",
        "wave": 8,
        "theme": "Core Layout & CSS Foundations (Floats, Flex-Basis, Ruby, Container Queries, Grid Phase 1, Hyphenation, Rect Lattice, Masonry Modes)",
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

    print("\n=== WAVE 8 (8 AGENTS: CORE LAYOUT & CSS) TOKEN USAGE REPORT ===")
    print(f"Prompt Tokens:     {total_p}")
    print(f"Candidate Tokens:  {total_c}")
    print(f"Total Tokens Used: {total_t}")
    print("Appended log entry to token_usage.log.")

