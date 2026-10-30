#!/usr/bin/env python3
"""
run_wave22_agents.py - Wave 22 (Iteration 7 of 8): CSS Cascade, Specificity & Media Queries
Benchmark-proven optimal strategy: 16 concurrent agents, gemini-4-argon, thinking_budget=2048, max_output_tokens=3500.
"""

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
        "id": "agent257",
        "file": "agent257_cascade_origin_rank.md",
        "topic": "Chromium Blink Cascade Origin 8-Tier Priority Ranking (core/css/resolver/cascade_priority.h)",
        "spec": "CSS Cascading 5 §3 (UA normal < User normal < Author normal < Animation < Author important < User important < UA important < Transition)",
        "prompt": """You are Agent 257 auditing Chromium Blink Cascade Origin Ranking vs CSS Cascading 5 §3.
Detail:
1. Origin ranks: UA normal (0), User normal (1), Author normal (2), Animation (3), Author important (4), User important (5), UA important (6), Transition (7).
2. Invariants: origin priority is strictly total and transitive; transition beats all; UA important beats author important.
3. Concrete Rocq/Coq definitions and theorems for BlinkCascadeOriginRankSemantics.v with 0 admits."""
    },
    {
        "id": "agent258",
        "file": "agent258_specificity_lexicographical.md",
        "topic": "Chromium Blink Specificity Tuple Lexicographical Comparison (core/css/css_selector.cc)",
        "spec": "CSS Selectors 4 §16 (A1, B1, C1) > (A2, B2, C2) by lexicographical order",
        "prompt": """You are Agent 258 auditing Chromium Blink Specificity Tuple Lexicographical Comparison vs CSS Selectors 4 §16.
Detail:
1. Tuple comparison: gt(t1, t2) iff a1 > a2 \/ (a1 = a2 /\ (b1 > b2 \/ (b1 = b2 /\ c1 > c2))).
2. Invariants: strict weak ordering (irreflexive, asymmetric, transitive).
3. Concrete Rocq/Coq definitions and theorems for BlinkSpecificityLexicographicalSemantics.v with 0 admits."""
    },
    {
        "id": "agent259",
        "file": "agent259_cascade_order_of_appearance.md",
        "topic": "Chromium Blink Document Order Tie-Breaking (core/css/resolver/cascade_priority.h)",
        "spec": "CSS Cascading 5 §3 (When origin and specificity match, later source order declaration wins: idx1 < idx2 -> idx2 wins)",
        "prompt": """You are Agent 259 auditing Chromium Blink Document Order Tie-Breaking vs CSS Cascading 5 §3.
Detail:
1. Tie-breaking: if origin and specificity are equal, winner = max(idx1, idx2).
2. Invariants: later appearance wins strictly, order of appearance resolution is deterministic and commutative in set join.
3. Concrete Rocq/Coq definitions and theorems for BlinkCascadeOrderOfAppearanceSemantics.v with 0 admits."""
    },
    {
        "id": "agent260",
        "file": "agent260_media_query_range_eval.md",
        "topic": "Chromium Blink Media Query Range Feature Evaluation (core/css/media_query_evaluator.cc)",
        "spec": "Media Queries 4 §2 (Range evaluation: min_w <= viewport_w <= max_w)",
        "prompt": """You are Agent 260 auditing Chromium Blink Media Query Range Evaluation vs Media Queries 4 §2.
Detail:
1. Range evaluation: eval(min_w, max_w, v_w) = (min_w <=? v_w) && (v_w <=? max_w).
2. Invariants: true iff v_w is in [min_w, max_w], monotone in range width.
3. Concrete Rocq/Coq definitions and theorems for BlinkMediaQueryRangeEvalSemantics.v with 0 admits."""
    },
    {
        "id": "agent261",
        "file": "agent261_container_query_eval.md",
        "topic": "Chromium Blink Container Query Nearest Ancestor Size (core/css/container_query_evaluator.cc)",
        "spec": "CSS Containment 3 §3 (Container query evaluates against nearest ancestor container with matching name/type)",
        "prompt": """You are Agent 261 auditing Chromium Blink Container Query Evaluation vs CSS Containment 3 §3.
Detail:
1. Container evaluation: container_w >= query_min_w.
2. Invariants: evaluated against container size, unaffected by viewport resize if container size constant.
3. Concrete Rocq/Coq definitions and theorems for BlinkContainerQueryEvalSemantics.v with 0 admits."""
    },
    {
        "id": "agent262",
        "file": "agent262_custom_property_inheritance.md",
        "topic": "Chromium Blink Custom Property Inheritance Pass-Through (core/css/resolver/style_cascade.cc)",
        "spec": "CSS Variables 1 §3 (Unset custom property inherits from parent; declared custom property overrides)",
        "prompt": """You are Agent 262 auditing Chromium Blink Custom Property Inheritance vs CSS Variables 1 §3.
Detail:
1. Resolution: resolve(decl, parent_val) = match decl with Some v => v | None => parent_val.
2. Invariants: declared value overrides parent; absent declaration preserves parent value identically.
3. Concrete Rocq/Coq definitions and theorems for BlinkCustomPropertyInheritanceSemantics.v with 0 admits."""
    },
    {
        "id": "agent263",
        "file": "agent263_color_alpha_composite.md",
        "topic": "Chromium Blink Color Alpha Blending & Porter-Duff Over (platform/graphics/color.cc)",
        "spec": "CSS Color 4 §13 (Porter-Duff Source Over: a_out = a_src + a_dst * (1 - a_src))",
        "prompt": """You are Agent 263 auditing Chromium Blink Alpha Composite vs CSS Color 4 §13.
Detail:
1. Alpha formula in [0, 255]: a_out = a_src + (a_dst * (255 - a_src)) / 255.
2. Invariants: 0 <= a_out <= 255 when inputs in [0, 255], a_src = 255 -> a_out = 255 (opaque overrides).
3. Concrete Rocq/Coq definitions and theorems for BlinkColorAlphaCompositeSemantics.v with 0 admits."""
    },
    {
        "id": "agent264",
        "file": "agent264_font_weight_clamping.md",
        "topic": "Chromium Blink Font-Weight Normalization & Clamping (core/css/css_font_face_source.cc)",
        "spec": "CSS Fonts 4 §5 (font-weight clamped in [1, 1000], normal=400, bold=700)",
        "prompt": """You are Agent 264 auditing Chromium Blink Font-Weight Normalization vs CSS Fonts 4 §5.
Detail:
1. Normalization: clamp(1, 1000, w).
2. Invariants: clamped weight is always in [1, 1000], identity on values in [1, 1000].
3. Concrete Rocq/Coq definitions and theorems for BlinkFontWeightClampingSemantics.v with 0 admits."""
    },
    {
        "id": "agent265",
        "file": "agent265_revert_layer_cascade.md",
        "topic": "Chromium Blink revert-layer Rollback (core/css/resolver/style_cascade.cc)",
        "spec": "CSS Cascading 5 §4 (revert-layer rolls back value to rule matching in preceding cascade layer)",
        "prompt": """You are Agent 265 auditing Chromium Blink revert-layer Rollback vs CSS Cascading 5 §4.
Detail:
1. Rollback: resolve_revert_layer(current_layer_val, prev_layer_val) = prev_layer_val.
2. Invariants: current layer declaration is ignored; value determined strictly by preceding layers.
3. Concrete Rocq/Coq definitions and theorems for BlinkRevertLayerCascadeSemantics.v with 0 admits."""
    },
    {
        "id": "agent266",
        "file": "agent266_supports_feature_query.md",
        "topic": "Chromium Blink @supports Feature Query Evaluation (core/css/css_supports_evaluator.cc)",
        "spec": "CSS Conditional 3 §3 (@supports boolean AST: and, or, not, property support)",
        "prompt": """You are Agent 266 auditing Chromium Blink @supports Feature Query vs CSS Conditional 3 §3.
Detail:
1. Boolean AST: SupportsAnd, SupportsOr, SupportsNot, SupportsDecl.
2. Invariants: De Morgan's laws hold over supports AST evaluation.
3. Concrete Rocq/Coq definitions and theorems for BlinkSupportsFeatureQuerySemantics.v with 0 admits."""
    },
    {
        "id": "agent267",
        "file": "agent267_keyframe_offset_monotonicity.md",
        "topic": "Chromium Blink Keyframe Offset Monotonicity & Normalization (core/animation/keyframe_effect_model.cc)",
        "spec": "Web Animations §5.3.1 (Keyframe offsets must be monotonically increasing in [0, 1])",
        "prompt": """You are Agent 267 auditing Chromium Blink Keyframe Offset Monotonicity vs Web Animations §5.3.1.
Detail:
1. Keyframe list: 0 <= offset_0 <= offset_1 <= ... <= offset_n <= 1000 (milli-units).
2. Invariants: pairwise monotonicity: for i < j, offset(i) <= offset(j).
3. Concrete Rocq/Coq definitions and theorems for BlinkKeyframeOffsetMonotonicitySemantics.v with 0 admits."""
    },
    {
        "id": "agent268",
        "file": "agent268_viewport_units_resolution.md",
        "topic": "Chromium Blink Viewport Units Resolution (core/css/css_to_length_conversion_data.cc)",
        "spec": "CSS Values 4 §6.1 (1vw = viewport_w / 100, 1vh = viewport_h / 100)",
        "prompt": """You are Agent 268 auditing Chromium Blink Viewport Units Resolution vs CSS Values 4 §6.1.
Detail:
1. Resolution: resolve_vw(vw_count, v_w) = (vw_count * v_w) / 100.
2. Invariants: 100vw = v_w, monotonic in viewport_w.
3. Concrete Rocq/Coq definitions and theorems for BlinkViewportUnitsResolutionSemantics.v with 0 admits."""
    },
    {
        "id": "agent269",
        "file": "agent269_font_size_relative_units.md",
        "topic": "Chromium Blink Font-Size Relative Units (em and rem) (core/css/css_to_length_conversion_data.cc)",
        "spec": "CSS Values 4 §6.2 (1em = element font size, 1rem = root font size)",
        "prompt": """You are Agent 269 auditing Chromium Blink Font-Size Relative Units vs CSS Values 4 §6.2.
Detail:
1. Resolution: resolve_em(em_count, font_size) = em_count * font_size; resolve_rem(rem_count, root_font_size) = rem_count * root_font_size.
2. Invariants: rem resolution is invariant to local font-size changes.
3. Concrete Rocq/Coq definitions and theorems for BlinkFontSizeRelativeUnitsSemantics.v with 0 admits."""
    },
    {
        "id": "agent270",
        "file": "agent270_is_pseudo_class_specificity.md",
        "topic": "Chromium Blink :is() Pseudo-Class Specificity Maximum (core/css/css_selector.cc)",
        "spec": "CSS Selectors 4 §4.2 (Specificity of :is(s1, s2) is the maximum specificity of its arguments)",
        "prompt": """You are Agent 270 auditing Chromium Blink :is() Specificity vs CSS Selectors 4 §4.2.
Detail:
1. Maximum specificity: spec(:is(s1, s2)) = max_specificity(spec(s1), spec(s2)).
2. Invariants: spec(:is) >= spec(s1) and spec(:is) >= spec(s2), symmetry of argument list.
3. Concrete Rocq/Coq definitions and theorems for BlinkIsPseudoClassSpecificitySemantics.v with 0 admits."""
    },
    {
        "id": "agent271",
        "file": "agent271_where_pseudo_class_zero_specificity.md",
        "topic": "Chromium Blink :where() Pseudo-Class Zero Specificity (core/css/css_selector.cc)",
        "spec": "CSS Selectors 4 §4.3 (Specificity of :where(...) is always (0, 0, 0))",
        "prompt": """You are Agent 271 auditing Chromium Blink :where() Specificity vs CSS Selectors 4 §4.3.
Detail:
1. Zero specificity: spec(:where(s)) = (0, 0, 0) regardless of argument complexity.
2. Invariants: :where() never adds to specificity sum; any non-empty selector has specificity >= :where().
3. Concrete Rocq/Coq definitions and theorems for BlinkWherePseudoClassZeroSpecificitySemantics.v with 0 admits."""
    },
    {
        "id": "agent272",
        "file": "agent272_important_origin_inversion.md",
        "topic": "Chromium Blink !important Origin Precedence Inversion (core/css/resolver/cascade_priority.h)",
        "spec": "CSS Cascading 5 §3 (!important inverts precedence between Author and User / UA)",
        "prompt": """You are Agent 272 auditing Chromium Blink !important Origin Inversion vs CSS Cascading 5 §3.
Detail:
1. Inversion: author normal > user normal, BUT user important > author important.
2. Invariants: UA important has highest priority among stylesheet origins.
3. Concrete Rocq/Coq definitions and theorems for BlinkImportantOriginInversionSemantics.v with 0 admits."""
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
                thinking_config=types.ThinkingConfig(thinking_budget=2048)
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
    print("Launching Wave 22 (Iteration 7 of 8): 16 concurrent Python3 agents using gemini-4-argon with benchmark-validated optimal Medium thinking budget (2048)...")
    with concurrent.futures.ThreadPoolExecutor(max_workers=16) as executor:
        results = list(executor.map(run_agent, tasks))

    total_p = sum(r.get("prompt_tokens", 0) for r in results)
    total_c = sum(r.get("candidates_tokens", 0) for r in results)
    total_t = sum(r.get("total_tokens", 0) for r in results)

    log_entry = {
        "timestamp": time.strftime("%Y-%m-%d %H:%M:%S"),
        "model": "gemini-4-argon",
        "wave": 22,
        "iteration": 7,
        "theme": "CSS Cascade, Specificity & Media Queries (Cascade Origin Ranking, Specificity Lexicographical Comparison, Document Order Tie-Breaking, Media Query Range Evaluation, Container Query Nearest Ancestor, Custom Property Inheritance, Color Alpha Blending, Font-Weight Normalization, Revert-Layer Rollback, @supports Feature Query, Keyframe Offset Monotonicity, Viewport Units Resolution, Font-Size Relative Units, :is() Specificity Maximum, :where() Zero Specificity, !important Origin Inversion)",
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

    print("\n=== WAVE 22 (ITERATION 7 OF 8) TOKEN USAGE REPORT ===")
    print(f"Prompt Tokens:     {total_p}")
    print(f"Candidate Tokens:  {total_c}")
    print(f"Total Tokens Used: {total_t}")
    print("Appended log entry to token_usage.log.")

