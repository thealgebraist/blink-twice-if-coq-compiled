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
        "id": "agent193",
        "file": "agent193_absolute_insets_resolution.md",
        "topic": "Chromium Blink Absolute Positioned Insets Resolution (core/layout/absolute_utils.cc)",
        "spec": "CSS Positioned Layout 3 §5 (top + height + bottom = containing_block_height)",
        "prompt": """You are Agent 193 auditing Chromium Blink Absolute Positioned Insets Resolution vs CSS Positioned 3 §5.
Detail:
1. Insets equation: top + height + bottom = cb_height (when both top, bottom, and height are specified).
2. Over-constrained resolution: in LTR / top-to-bottom, ignore bottom: bottom = cb_height - (top + height).
3. Invariants: used bottom satisfies the insets equality, height is preserved.
4. Concrete Rocq/Coq definitions and theorems for BlinkAbsoluteInsetsResolutionSemantics.v."""
    },
    {
        "id": "agent194",
        "file": "agent194_absolute_auto_margins.md",
        "topic": "Chromium Blink Absolute Positioned Auto Margins Centering (core/layout/absolute_utils.cc)",
        "spec": "CSS Positioned Layout 3 §5.2 (Auto margins on abspos boxes, equal centering)",
        "prompt": """You are Agent 194 auditing Chromium Blink Absolute Auto Margins Centering vs CSS Positioned 3 §5.2.
Detail:
1. Free space: free = cb_width - (left + width + right). If both margins are auto, each margin = free / 2.
2. Invariants: left_margin + right_margin <= free, element is centered within the insets.
3. Concrete Rocq/Coq definitions and theorems for BlinkAbsoluteAutoMarginsSemantics.v."""
    },
    {
        "id": "agent195",
        "file": "agent195_multicol_balancing.md",
        "topic": "Chromium Blink Multi-Column Column Count Calculation (core/layout/column_layout_algorithm.cc)",
        "spec": "CSS Multi-column 1 §3.4 (column-width, column-count: N = max(1, floor((W + gap) / (col_w + gap))))",
        "prompt": """You are Agent 195 auditing Chromium Blink Multicol Column Count vs CSS Multi-column 1 §3.4.
Detail:
1. Column count formula: N = max(1, floor((W_avail + gap) / (col_width + gap))).
2. Invariants: N >= 1, used column space <= W_avail when W_avail >= col_width.
3. Concrete Rocq/Coq definitions and theorems for BlinkMulticolBalancingSemantics.v."""
    },
    {
        "id": "agent196",
        "file": "agent196_multicol_column_rule.md",
        "topic": "Chromium Blink Multi-Column Rule Placement between Columns (core/layout/column_layout_algorithm.cc)",
        "spec": "CSS Multi-column 1 §4 (column-rule-width, column-rule-style, centered in column gap)",
        "prompt": """You are Agent 196 auditing Chromium Blink Column Rule Placement vs CSS Multi-column 1 §4.
Detail:
1. Rule placement: positioned in the middle of each column gap: rule_x = col_end_x + (gap - rule_width) / 2.
2. Invariants: rule is centered within gap, rule does not overlap adjacent column content when rule_width <= gap.
3. Concrete Rocq/Coq definitions and theorems for BlinkMulticolColumnRuleSemantics.v."""
    },
    {
        "id": "agent197",
        "file": "agent197_transform_matrix_3d.md",
        "topic": "Chromium Blink 3D Transformation Matrix Composition (platform/transforms/transformation_matrix.cc)",
        "spec": "CSS Transforms 2 §5 (4x4 homogeneous transformation matrix multiplication)",
        "prompt": """You are Agent 197 auditing Chromium Blink 3D Transformation Matrix Multiplication vs CSS Transforms 2 §5.
Detail:
1. 4x4 matrix representation and matrix product M1 * M2.
2. Invariants: identity matrix is neutral element (M * I = M, I * M = M), multiplication is associative.
3. Concrete Rocq/Coq definitions and theorems for BlinkTransformMatrix3DSemantics.v."""
    },
    {
        "id": "agent198",
        "file": "agent198_perspective_projection.md",
        "topic": "Chromium Blink Perspective Projection Matrix (platform/transforms/perspective_transform.cc)",
        "spec": "CSS Transforms 2 §4 (perspective(d) matrix, z-projection: z' = 1 / (1 - z / d))",
        "prompt": """You are Agent 198 auditing Chromium Blink Perspective Projection vs CSS Transforms 2 §4.
Detail:
1. Perspective scale factor: scale(z) = d / (d - z) for z < d.
2. Invariants: scale(0) = 1 (neutral at z=0), scale is strictly monotonic in z for z < d.
3. Concrete Rocq/Coq definitions and theorems for BlinkPerspectiveProjectionSemantics.v."""
    },
    {
        "id": "agent199",
        "file": "agent199_transform_state_point_map.md",
        "topic": "Chromium Blink Point Transformation through 2D Matrix (core/layout/geometry/transform_state.cc)",
        "spec": "CSS Transforms 1 §5 (Point mapping: x' = a*x + c*y + e, y' = b*x + d*y + f)",
        "prompt": """You are Agent 199 auditing Chromium Blink Point Transformation vs CSS Transforms 1 §5.
Detail:
1. Point mapping: (x', y') = map_point(T, x, y).
2. Composition: map_point(T2, map_point(T1, x, y)) = map_point(T2 * T1, x, y).
3. Invariants: map_point with identity is identity, translation only shifts point additively.
4. Concrete Rocq/Coq definitions and theorems for BlinkTransformStatePointMapSemantics.v."""
    },
    {
        "id": "agent200",
        "file": "agent200_multicol_break_avoidance.md",
        "topic": "Chromium Blink Column Break Avoidance (core/layout/column_layout_algorithm.cc)",
        "spec": "CSS Fragmentation 3 §3 (break-inside: avoid, column overflow movement)",
        "prompt": """You are Agent 200 auditing Chromium Blink Column Break Avoidance vs CSS Fragmentation 3 §3.
Detail:
1. When block height h > remaining column height, move block to top of next column (y_new = 0, col_idx + 1).
2. Invariants: column index increases, block fits entirely in next column if h <= column_height.
3. Concrete Rocq/Coq definitions and theorems for BlinkMulticolBreakAvoidanceSemantics.v."""
    },
    {
        "id": "agent201",
        "file": "agent201_fixed_position_viewport.md",
        "topic": "Chromium Blink Fixed Position Viewport Resolution (core/layout/absolute_utils.cc)",
        "spec": "CSS Positioned 3 §3 (Fixed positioning containing block is viewport rect (0, 0, vw, vh))",
        "prompt": """You are Agent 201 auditing Chromium Blink Fixed Position Viewport Resolution vs CSS Positioned 3 §3.
Detail:
1. Viewport containing block: origin is strictly (0, 0), dimensions are (vw, vh).
2. Fixed coordinate: x = left, y = top.
3. Invariants: fixed box position is independent of document scroll offset.
4. Concrete Rocq/Coq definitions and theorems for BlinkFixedPositionViewportSemantics.v."""
    },
    {
        "id": "agent202",
        "file": "agent202_logical_offset_mapping.md",
        "topic": "Chromium Blink Logical to Physical Offset Mapping (core/layout/geometry/logical_offset.cc)",
        "spec": "CSS Writing Modes 3 §4 (Mapping inline/block offsets to physical X/Y for horizontal-tb, vertical-rl, vertical-lr)",
        "prompt": """You are Agent 202 auditing Chromium Blink Logical to Physical Offset Mapping vs CSS Writing Modes 3 §4.
Detail:
1. Mapping: horizontal-tb (x = inline, y = block); vertical-lr (x = block, y = inline); vertical-rl (x = outer_w - (block + box_w), y = inline).
2. Invariants: bijective mapping between logical and physical coordinates, physical coordinates remain in bounds.
3. Concrete Rocq/Coq definitions and theorems for BlinkLogicalOffsetMappingSemantics.v."""
    },
    {
        "id": "agent203",
        "file": "agent203_logical_size_orthogonal.md",
        "topic": "Chromium Blink Orthogonal Writing Modes Size Transposition (core/layout/geometry/logical_size.cc)",
        "spec": "CSS Writing Modes 3 §7.3 (Orthogonal flows: inline size maps to physical height, block to width)",
        "prompt": """You are Agent 203 auditing Chromium Blink Orthogonal Size Transposition vs CSS Writing Modes 3 §7.3.
Detail:
1. Size transposition: for orthogonal writing mode, physical_w = logical_block, physical_h = logical_inline.
2. Invariants: transposition is an involution (transposing twice restores original size), area is preserved.
3. Concrete Rocq/Coq definitions and theorems for BlinkLogicalSizeOrthogonalSemantics.v."""
    },
    {
        "id": "agent204",
        "file": "agent204_transform_rotation_2d.md",
        "topic": "Chromium Blink 2D Rotation Matrix Preservation (platform/transforms/rotation_transform.cc)",
        "spec": "CSS Transforms 1 §5.1 (rotate(angle) matrix, determinant preservation det(R) = 1)",
        "prompt": """You are Agent 204 auditing Chromium Blink 2D Rotation Matrix vs CSS Transforms 1 §5.1.
Detail:
1. 2D rotation matrix: [cos, sin, -sin, cos, 0, 0]. Determinant: cos^2 + sin^2 = 1.
2. Invariants: determinant equals 1 (area preservation), rotation by 0 is identity.
3. Concrete Rocq/Coq definitions and theorems for BlinkTransformRotation2DSemantics.v."""
    },
    {
        "id": "agent205",
        "file": "agent205_transform_skew_2d.md",
        "topic": "Chromium Blink 2D Skew Matrix Composition (platform/transforms/skew_transform.cc)",
        "spec": "CSS Transforms 1 §5.1 (skew(alpha, beta) matrix [1, tan beta, tan alpha, 1, 0, 0])",
        "prompt": """You are Agent 205 auditing Chromium Blink 2D Skew Matrix vs CSS Transforms 1 §5.1.
Detail:
1. Skew matrix: a=1, b=tan(beta), c=tan(alpha), d=1.
2. Invariants: skew(0, 0) is identity matrix, area scaling factor |1 - tan(alpha)*tan(beta)|.
3. Concrete Rocq/Coq definitions and theorems for BlinkTransformSkew2DSemantics.v."""
    },
    {
        "id": "agent206",
        "file": "agent206_sticky_scroller_chain.md",
        "topic": "Chromium Blink Multi-Nested Sticky Scroller Constraint Accumulation (core/layout/sticky_position_data.cc)",
        "spec": "CSS Positioned 3 §6 (Nested sticky elements across multiple scroll containers)",
        "prompt": """You are Agent 206 auditing Chromium Blink Nested Sticky Constraints vs CSS Positioned 3 §6.
Detail:
1. Cumulative sticky offset: offset = clamp(min1, max1, scroll1) + clamp(min2, max2, scroll2).
2. Invariants: cumulative offset bounded by sum of individual bounds, monotonicity in individual scrollers.
3. Concrete Rocq/Coq definitions and theorems for BlinkStickyScrollerChainSemantics.v."""
    },
    {
        "id": "agent207",
        "file": "agent207_multicol_column_fill.md",
        "topic": "Chromium Blink Multi-Column Column Fill Balance vs Auto (core/layout/column_layout_algorithm.cc)",
        "spec": "CSS Multi-column 1 §7 (column-fill: balance | auto, binary search for balanced column height)",
        "prompt": """You are Agent 207 auditing Chromium Blink Column Fill Balance vs CSS Multi-column 1 §7.
Detail:
1. Balanced height: H_col = max(1, (total_content_height + N - 1) / N).
2. Invariants: N * H_col >= total_content_height, H_col is minimal integer height accommodating all content.
3. Concrete Rocq/Coq definitions and theorems for BlinkMulticolColumnFillSemantics.v."""
    },
    {
        "id": "agent208",
        "file": "agent208_box_sides_rotation.md",
        "topic": "Chromium Blink Logical Box Sides Directional Rotation (core/layout/geometry/box_sides.cc)",
        "spec": "CSS Writing Modes 3 §4.2 (Logical sides inline-start, inline-end, block-start, block-end to physical top/right/bottom/left)",
        "prompt": """You are Agent 208 auditing Chromium Blink Box Sides Directional Rotation vs CSS Writing Modes 3 §4.2.
Detail:
1. Logical to physical sides mapping: for horizontal-tb (bs->top, be->bottom, is->left, ie->right); vertical-rl (bs->right, be->left, is->top, ie->bottom).
2. Invariants: total perimeter sum is preserved under rotation (top+bottom+left+right = bs+be+is+ie).
3. Concrete Rocq/Coq definitions and theorems for BlinkBoxSidesRotationSemantics.v."""
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
    print("Launching Wave 18 (Iteration 3 of 8): 16 concurrent Python3 agents using gemini-4-argon (low thinking budget 512)...")
    with concurrent.futures.ThreadPoolExecutor(max_workers=16) as executor:
        results = list(executor.map(run_agent, tasks))

    total_p = sum(r.get("prompt_tokens", 0) for r in results)
    total_c = sum(r.get("candidates_tokens", 0) for r in results)
    total_t = sum(r.get("total_tokens", 0) for r in results)

    log_entry = {
        "timestamp": time.strftime("%Y-%m-%d %H:%M:%S"),
        "model": "gemini-4-argon",
        "wave": 18,
        "iteration": 3,
        "theme": "CSS Positioned Layout, Transforms & Multi-Column (Absolute Insets Resolution, Auto Margins Centering, Multicol Balancing, Column Rule Placement, 3D Matrix Multiplication, Perspective Projection, Transform Point Mapping, Column Break Avoidance, Fixed Viewport Resolution, Logical Offset Mapping, Orthogonal Size Transposition, 2D Rotation Determinant, 2D Skew Matrix, Sticky Scroller Chains, Column Fill Balance, Box Sides Rotation)",
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

    print("\n=== WAVE 18 (ITERATION 3 OF 8) TOKEN USAGE REPORT ===")
    print(f"Prompt Tokens:     {total_p}")
    print(f"Candidate Tokens:  {total_c}")
    print(f"Total Tokens Used: {total_t}")
    print("Appended log entry to token_usage.log.")

