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
        "id": 673,
        "filename": "agent673_block_fragmentation_break_token.md",
        "topic": "Block fragmentation break token continuation across fragmentainers",
        "source": "third_party/blink/renderer/core/layout/block_break_token.cc",
        "spec": "CSS Fragmentation 3 §4 / §5 break token consumed block size",
        "theory": "BlinkBlockFragmentationBreakTokenSemantics.v",
        "math": "consumed_block_size(token) <= total_block_size; remaining = total - consumed."
    },
    {
        "id": 674,
        "filename": "agent674_adjoining_floats_clearance.md",
        "topic": "Clearance math over adjoining margins with left/right/both floats",
        "source": "third_party/blink/renderer/core/layout/floats_utils.cc",
        "spec": "CSS 2.1 §9.5.2 clear property clearance calculation",
        "theory": "BlinkAdjoiningFloatsClearanceSemantics.v",
        "math": "clearance = max(0, float_bottom - (hypothetical_top + margin_top))."
    },
    {
        "id": 675,
        "filename": "agent675_block_child_iterator_ordering.md",
        "topic": "Block child iterator sequencing and block-end margin strut propagation",
        "source": "third_party/blink/renderer/core/layout/block_child_iterator.cc",
        "spec": "CSS 2.1 §8.3.1 block formatting context margin collapsing chain",
        "theory": "BlinkBlockChildIteratorOrderingSemantics.v",
        "math": "cursor_y(n+1) = cursor_y(n) + collapsed_margin(n) + height(n)."
    },
    {
        "id": 676,
        "filename": "agent676_block_stretch_fit_content.md",
        "topic": "Block stretch sizing vs fit-content sizing resolution",
        "source": "third_party/blink/renderer/core/layout/length_utils.cc",
        "spec": "CSS Box Sizing 3 §5.1 stretch vs fit-content formulas",
        "theory": "BlinkBlockStretchFitContentSemantics.v",
        "math": "fit_content(avail, min_c, max_c) = max(min_c, min(avail, max_c))."
    },
    {
        "id": 677,
        "filename": "agent677_block_cyclic_percentage_height.md",
        "topic": "Cyclic percentage height resolution in block containers",
        "source": "third_party/blink/renderer/core/layout/layout_box.cc",
        "spec": "CSS 2.1 §10.5 indefinite containing block percentage height fallback",
        "theory": "BlinkBlockCyclicPercentageHeightSemantics.v",
        "math": "resolve_pct_height(pct, cb_height) = if is_definite(cb) then pct * cb else content_height."
    },
    {
        "id": 678,
        "filename": "agent678_block_margin_strut_negative_cancel.md",
        "topic": "Negative and positive margin strut algebraic cancellation",
        "source": "third_party/blink/renderer/core/layout/margin_strut.cc",
        "spec": "CSS 2.1 §8.3.1 max(positive) + min(negative) margin collapsing rule",
        "theory": "BlinkBlockMarginStrutNegativeCancelSemantics.v",
        "math": "collapsed_margin(pos, neg) = pos + neg; where pos >= 0 and neg <= 0."
    },
    {
        "id": 679,
        "filename": "agent679_ruby_base_text_alignment.md",
        "topic": "Ruby base and ruby text alignment and auto-expansion",
        "source": "third_party/blink/renderer/core/layout/inline/ruby_layout_algorithm.cc",
        "spec": "CSS Ruby Layout 1 §3 ruby-align space-around distribution",
        "theory": "BlinkRubyBaseTextAlignmentSemantics.v",
        "math": "ruby_column_width = max(base_width, text_width); center_offset = (col_w - w) / 2."
    },
    {
        "id": 680,
        "filename": "agent680_unicode_bidi_levels_resolution.md",
        "topic": "Unicode Bidirectional Algorithm UBA embedding levels resolution",
        "source": "third_party/blink/renderer/core/layout/inline/bidi_paragraph.cc",
        "spec": "Unicode Standard Annex #9 / CSS Writing Modes 3 §3 UBA levels",
        "theory": "BlinkUnicodeBidiLevelsResolutionSemantics.v",
        "math": "resolved_level in [0, 125]; rtl = (level % 2 == 1)."
    },
    {
        "id": 681,
        "filename": "agent681_inline_hyphenation_opportunity.md",
        "topic": "Inline soft hyphen and hyphenation opportunity offsets",
        "source": "third_party/blink/renderer/core/layout/inline/inline_break_token.cc",
        "spec": "CSS Text 3 §5.4 soft hyphens and hyphenate-character width",
        "theory": "BlinkInlineHyphenationOpportunitySemantics.v",
        "math": "hyphenated_line_width = text_segment_width + hyphen_width <= avail_width."
    },
    {
        "id": 682,
        "filename": "agent682_line_box_half_leading_distribution.md",
        "topic": "Line box metrics half-leading distribution and strut accumulation",
        "source": "third_party/blink/renderer/core/layout/inline/line_box_fragment_builder.cc",
        "spec": "CSS 2.1 §10.8.1 half-leading = (line_height - font_height) / 2",
        "theory": "BlinkLineBoxHalfLeadingDistributionSemantics.v",
        "math": "ascent = font_ascent + half_leading; descent = font_descent + half_leading."
    },
    {
        "id": 683,
        "filename": "agent683_inline_box_atomic_fragment_bounds.md",
        "topic": "Atomic inline fragment bounds and baseline alignment",
        "source": "third_party/blink/renderer/core/layout/inline/inline_box_state.cc",
        "spec": "CSS 2.1 §10.8.1 inline-block baseline falls on bottom margin edge if no in-flow line",
        "theory": "BlinkInlineBoxAtomicFragmentBoundsSemantics.v",
        "math": "atomic_baseline(has_line, line_b, box_h) = if has_line then line_b else box_h."
    },
    {
        "id": 684,
        "filename": "agent684_flexbox_multiline_wrap_line_breaking.md",
        "topic": "Multiline flexbox line breaking and cross-size distribution",
        "source": "third_party/blink/renderer/core/layout/flex/flexible_box_algorithm.cc",
        "spec": "CSS Flexbox 1 §9.3 multiline flex container line breaking algorithm",
        "theory": "BlinkFlexboxMultilineWrapLineBreakingSemantics.v",
        "math": "new_line_created(sum_hypothetical, avail) = (sum_hypothetical > avail && count > 0)."
    },
    {
        "id": 685,
        "filename": "agent685_flex_item_order_property_sorting.md",
        "topic": "Flex item order property stable sorting",
        "source": "third_party/blink/renderer/core/layout/flex/flex_item_iterator.cc",
        "spec": "CSS Flexbox 1 §5.4 order property reordering preserves document order on ties",
        "theory": "BlinkFlexItemOrderPropertySortingSemantics.v",
        "math": "order_key(item) = (item.order, item.dom_index); lexicographical order."
    },
    {
        "id": 686,
        "filename": "agent686_flex_reverse_layout_coordinate_mirroring.md",
        "topic": "Flex row-reverse and column-reverse coordinate mirroring",
        "source": "third_party/blink/renderer/core/layout/flex/flex_layout_algorithm.cc",
        "spec": "CSS Flexbox 1 §5.1 reverse direction coordinate transformation",
        "theory": "BlinkFlexReverseLayoutCoordinateMirroringSemantics.v",
        "math": "reverse_offset(offset, item_size, container_size) = container_size - offset - item_size."
    },
    {
        "id": 687,
        "filename": "agent687_flexbox_first_last_baseline_alignment.md",
        "topic": "Flex container first and last baseline alignment",
        "source": "third_party/blink/renderer/core/layout/flex/flex_layout_algorithm.cc",
        "spec": "CSS Flexbox 1 §8.3 align-items: baseline / last baseline",
        "theory": "BlinkFlexboxFirstLastBaselineAlignmentSemantics.v",
        "math": "baseline_offset(item_b, max_b) = max_b - item_b >= 0."
    },
    {
        "id": 688,
        "filename": "agent688_flexbox_cross_axis_stretch_min_max_clamping.md",
        "topic": "Flex cross-axis stretch alignment under min/max height bounds",
        "source": "third_party/blink/renderer/core/layout/flex/flex_layout_algorithm.cc",
        "spec": "CSS Flexbox 1 §9.4 cross-size determination with stretch and min/max clamping",
        "theory": "BlinkFlexboxCrossAxisStretchMinMaxClampingSemantics.v",
        "math": "stretched_cross(line_cross, min_c, max_c) = max(min_c, min(line_cross, max_c))."
    }
]

def run_agent(agent):
    prompt = f"""You are formal verification Agent {agent['id']} specializing in W3C/WHATWG Layout Rules (Block, Inline, Flexbox) in Chromium Blink.
Topic: {agent['topic']}
Chromium Source: {agent['source']}
Specification: {agent['spec']}
Formal Theory Target: {agent['theory']}
Mathematical Property: {agent['math']}

Write a comprehensive research report in Markdown covering:
1. Exact normative W3C Block / Inline / Flexbox specification requirements.
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
            f.write(f"Wave48-Agent{agent['id']},{MODEL_NAME},{prompt_tokens},{cand_tokens},{duration:.2f}\n")
        return True
    except Exception as e:
        print(f"[Agent {agent['id']}] FAILED: {e}")
        return False

print(f"Launching 16 concurrent agents for Wave 48 using {MODEL_NAME}...")
with concurrent.futures.ThreadPoolExecutor(max_workers=16) as executor:
    futures = [executor.submit(run_agent, agent) for agent in AGENTS]
    results = [f.result() for f in concurrent.futures.as_completed(futures)]

print(f"Wave 48 complete: {sum(results)}/16 succeeded.")

