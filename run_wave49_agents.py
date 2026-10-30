import os
import time
import concurrent.futures
from google import genai
from google.genai import types

API_KEY = os.environ.get("GEMINI_API_KEY")
if not API_KEY and os.path.exists("key.txt"):
    with open("key.txt", "r") as f:
        API_KEY = f.read().strip()

client = genai.Client(api_key=API_KEY)
MODEL_NAME = "gemini-4-argon"

AGENTS = [
    {
        "id": 689,
        "filename": "agent689_grid_placement_dense_algorithm.md",
        "topic": "CSS Grid automatic placement dense vs sparse pack cursor advance",
        "source": "third_party/blink/renderer/core/layout/grid/grid_placement.cc",
        "spec": "CSS Grid Layout 1 §8.5 automatic grid item placement algorithm",
        "theory": "BlinkGridPlacementDenseAlgorithmSemantics.v",
        "math": "dense_placement resets cursor to (1, 1); sparse advances from current cursor."
    },
    {
        "id": 690,
        "filename": "agent690_grid_track_sizing_minmax_resolution.md",
        "topic": "minmax() track sizing resolution under min-content and max-content constraints",
        "source": "third_party/blink/renderer/core/layout/grid/grid_track_sizing_algorithm.cc",
        "spec": "CSS Grid Layout 1 §11.4 minmax(min, max) sizing resolution",
        "theory": "BlinkGridTrackSizingMinMaxResolutionSemantics.v",
        "math": "resolve_minmax(avail, min_t, max_t) = max(min_t, min(avail, max_t))."
    },
    {
        "id": 691,
        "filename": "agent691_subgrid_margin_padding_passthrough.md",
        "topic": "Subgrid margin and padding passthrough alignment into parent grid tracks",
        "source": "third_party/blink/renderer/core/layout/grid/grid_node.cc",
        "spec": "CSS Grid Layout 2 §3 subgrid margins aligned to first/last parent track",
        "theory": "BlinkSubgridMarginPaddingPassthroughSemantics.v",
        "math": "subgrid_start_offset = parent_track_start + subgrid_margin_start."
    },
    {
        "id": 692,
        "filename": "agent692_grid_masonry_running_height.md",
        "topic": "Masonry layout item allocation to track with minimum running height",
        "source": "third_party/blink/renderer/core/layout/grid/grid_layout_algorithm.cc",
        "spec": "CSS Grid Layout 3 / Masonry §4 find track with min running height",
        "theory": "BlinkGridMasonryRunningHeightSemantics.v",
        "math": "next_track = argmin(running_heights); updated_height = min_h + item_h."
    },
    {
        "id": 693,
        "filename": "agent693_grid_implicit_track_creation.md",
        "topic": "Implicit grid track automatic creation bounds and index clamping",
        "source": "third_party/blink/renderer/core/layout/grid/grid_line_resolver.cc",
        "spec": "CSS Grid Layout 1 §7.5 implicit grid line clamping",
        "theory": "BlinkGridImplicitTrackCreationSemantics.v",
        "math": "clamp_grid_line(line, max_lines) = max(1, min(line, max_lines))."
    },
    {
        "id": 694,
        "filename": "agent694_grid_fractional_space_conservation.md",
        "topic": "CSS Grid fr fractional track space conservation sum",
        "source": "third_party/blink/renderer/core/layout/grid/grid_track_collection.cc",
        "spec": "CSS Grid Layout 1 §11.7.1 find the size of an fr",
        "theory": "BlinkGridFractionalSpaceConservationSemantics.v",
        "math": "fr_share(fr_i, total_fr, avail) = (fr_i * avail) / total_fr; sum(fr_shares) <= avail."
    },
    {
        "id": 695,
        "filename": "agent695_table_collapsed_border_width_style_precedence.md",
        "topic": "Collapsed table border conflict resolution: border width and style precedence",
        "source": "third_party/blink/renderer/core/layout/table/table_borders.cc",
        "spec": "CSS 2.1 §17.6.2.1 border conflict resolution algorithm",
        "theory": "BlinkTableCollapsedBorderWidthStylePrecedenceSemantics.v",
        "math": "border_priority(b) = (b.is_hidden, b.width, b.style_precedence); max priority wins."
    },
    {
        "id": 696,
        "filename": "agent696_table_colgroup_span_clamping.md",
        "topic": "Table colgroup span attribute clamping and positive bounding",
        "source": "third_party/blink/renderer/core/layout/table/table_layout_algorithm_types.cc",
        "spec": "HTML Spec §4.9.3 colgroup span clamped to [1, 1000]",
        "theory": "BlinkTableColgroupSpanClampingSemantics.v",
        "math": "clamp_span(span) = max(1, min(span, 1000))."
    },
    {
        "id": 697,
        "filename": "agent697_table_row_span_height_distribution.md",
        "topic": "Table rowspan cell height distribution across consecutive rows",
        "source": "third_party/blink/renderer/core/layout/table/table_row_layout_algorithm.cc",
        "spec": "CSS 2.1 §17.5.3 rowspan height distribution algorithm",
        "theory": "BlinkTableRowSpanHeightDistributionSemantics.v",
        "math": "effective_row_height(rows, row_span, cell_h) = distribute_excess_evenly(rows, cell_h)."
    },
    {
        "id": 698,
        "filename": "agent698_table_caption_side_offset.md",
        "topic": "Table caption side positioning top vs bottom block offset",
        "source": "third_party/blink/renderer/core/layout/table/table_layout_algorithm.cc",
        "spec": "CSS 2.1 §17.4 caption-side top and bottom offsets",
        "theory": "BlinkTableCaptionSideOffsetSemantics.v",
        "math": "table_grid_offset(caption_side, caption_h) = if is_top then caption_h else 0."
    },
    {
        "id": 699,
        "filename": "agent699_table_auto_layout_column_width_floor.md",
        "topic": "Auto-table column width floor balancing under percentage constraints",
        "source": "third_party/blink/renderer/core/layout/table/table_layout_algorithm.cc",
        "spec": "CSS 2.1 §17.5.2 auto table layout column width floor",
        "theory": "BlinkTableAutoLayoutColumnWidthFloorSemantics.v",
        "math": "col_width = max(min_content, min(max_content, avail_share))."
    },
    {
        "id": 700,
        "filename": "agent700_shape_margin_expansion_geometry.md",
        "topic": "CSS shape-margin dilation expansion around shape geometry",
        "source": "third_party/blink/renderer/core/layout/shapes/shape.cc",
        "spec": "CSS Shapes 1 §3.2 shape-margin expansion",
        "theory": "BlinkShapeMarginExpansionGeometrySemantics.v",
        "math": "expanded_radius(r, margin) = r + max(0, margin); expanded >= r."
    },
    {
        "id": 701,
        "filename": "agent701_clip_path_svg_path_bounding_box.md",
        "topic": "clip-path: path() SVG bounding box containment",
        "source": "third_party/blink/renderer/core/layout/svg/svg_path_parser.cc",
        "spec": "CSS Masking 1 §3 clip-path basic shapes and path() bounds",
        "theory": "BlinkClipPathSVGPathBoundingBoxSemantics.v",
        "math": "path_bounds(p) = {| min_x, max_x, min_y, max_y |}; max_x >= min_x."
    },
    {
        "id": 702,
        "filename": "agent702_shape_outside_image_alpha_threshold.md",
        "topic": "shape-outside image alpha channel threshold cutoff",
        "source": "third_party/blink/renderer/core/layout/shapes/shape_outside_image.cc",
        "spec": "CSS Shapes 1 §3.3 shape-image-threshold alpha cutoff [0, 255]",
        "theory": "BlinkShapeOutsideImageAlphaThresholdSemantics.v",
        "math": "is_pixel_opaque(alpha, threshold) = (alpha >= threshold); monotone in alpha."
    },
    {
        "id": 703,
        "filename": "agent703_inset_shape_corner_radius_clamping.md",
        "topic": "inset() corner radius sum clamping to half-dimension",
        "source": "third_party/blink/renderer/core/layout/shapes/box_shape.cc",
        "spec": "CSS Shapes 1 §3.1 inset() round corner radius scaling",
        "theory": "BlinkInsetShapeCornerRadiusClampingSemantics.v",
        "math": "scale_factor = if r1 + r2 > w then w / (r1 + r2) else 1; clamped_r = r * scale_factor."
    },
    {
        "id": 704,
        "filename": "agent704_normative_layout_totality_soundness.md",
        "topic": "Grand Unification: Normative Layout Rules Joint Soundness Theorem",
        "source": "third_party/blink/renderer/core/layout/layout_box.cc",
        "spec": "W3C / WHATWG Normative Layout Specifications Totality",
        "theory": "BlinkNormativeLayoutTotalitySoundnessSemantics.v",
        "math": "unification theorem: Block, Inline, Flex, Grid, Tables, and Shapes are jointly sound."
    }
]

def run_agent(agent):
    prompt = f"""You are formal verification Agent {agent['id']} specializing in W3C/WHATWG Layout Rules (Grid, Tables, Shapes) in Chromium Blink.
Topic: {agent['topic']}
Chromium Source: {agent['source']}
Specification: {agent['spec']}
Formal Theory Target: {agent['theory']}
Mathematical Property: {agent['math']}

Write a comprehensive research report in Markdown covering:
1. Exact normative W3C Grid / Tables / Shapes specification requirements.
2. Blink implementation details and invariants in {agent['source']}.
3. Formal specification definitions in Rocq/Coq (types, functions, predicates).
4. Concrete theorems with complete, admitted-free Rocq/Coq proofs using ZArith/Lia/Bool/List.
5. Verification analysis proving 0 admits and preservation of layout invariants.

Respond with the report in Markdown format."""

    config = types.GenerateContentConfig(
        thinking_config=types.ThinkingConfig(thinking_budget=2048),
        max_output_tokens=3500,
        temperature=0.2,
    )
    
    t0 = time.time()
    try:
        response = client.models.generate_content(
            model=MODEL_NAME,
            contents=prompt,
            config=config,
        )
        duration = time.time() - t0
        content = response.text
        with open(agent["filename"], "w") as f:
            f.write(content)
        
        usage = response.usage_metadata
        prompt_tokens = usage.prompt_token_count if usage else 0
        cand_tokens = usage.candidates_token_count if usage else 0
        print(f"[Agent {agent['id']}] Done in {duration:.1f}s | tokens: in={prompt_tokens}, out={cand_tokens}")
        with open("token_usage.log", "a") as f:
            f.write(f"Wave49-Agent{agent['id']},{MODEL_NAME},{prompt_tokens},{cand_tokens},{duration:.2f}\n")
        return True
    except Exception as e:
        print(f"[Agent {agent['id']}] FAILED: {e}")
        return False

print(f"Launching 16 concurrent agents for Wave 49 using {MODEL_NAME}...")
with concurrent.futures.ThreadPoolExecutor(max_workers=16) as executor:
    futures = [executor.submit(run_agent, agent) for agent in AGENTS]
    results = [f.result() for f in concurrent.futures.as_completed(futures)]

print(f"Wave 49 complete: {sum(results)}/16 succeeded.")

