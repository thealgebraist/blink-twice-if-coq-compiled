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
        "id": "agent177",
        "file": "agent177_harfbuzz_glyph_advance.md",
        "topic": "Chromium Blink HarfBuzz Glyph Advance Accumulation & Cluster Mapping (platform/fonts/shaping/harfbuzz_shaper.cc)",
        "spec": "OpenType & CSS Text 3 §5 (Glyph advance vectors, cluster monotonic advance, total text width)",
        "prompt": """You are Agent 177 auditing Chromium Blink HarfBuzz Glyph Advance Accumulation vs CSS Text 3 §5.
Detail:
1. Glyph advance accumulation: W_total = sum(glyph.advance.x).
2. Cluster mapping: glyph clusters correspond to input character index ranges.
3. Invariants: glyph advances are non-negative, total advance is strictly monotonic in glyph count.
4. Concrete Rocq/Coq definitions and theorems for BlinkHarfBuzzGlyphAdvanceSemantics.v."""
    },
    {
        "id": "agent178",
        "file": "agent178_font_metrics_half_leading.md",
        "topic": "Chromium Blink Font Ascent, Descent & Half-Leading Distribution (platform/fonts/font_metrics.cc)",
        "spec": "CSS Inline Layout 3 §3.2 (Line height, half-leading: L = (H - (A + D)) / 2)",
        "prompt": """You are Agent 178 auditing Chromium Blink Font Half-Leading vs CSS Inline 3 §3.2.
Detail:
1. Half-leading calculation: L = (line_height - (ascent + descent)) / 2.
2. Effective above/below baseline: top_offset = ascent + L, bottom_offset = descent + (line_height - (ascent + descent) - L).
3. Invariants: top_offset + bottom_offset = line_height, baseline is uniquely positioned between top and bottom.
4. Concrete Rocq/Coq definitions and theorems for BlinkFontMetricsHalfLeadingSemantics.v."""
    },
    {
        "id": "agent179",
        "file": "agent179_shape_result_run_split.md",
        "topic": "Chromium Blink ShapeResult Run Splitting & Subsegment Bounding (platform/fonts/shaping/shape_result.cc)",
        "spec": "CSS Text 3 §5 & CSS Inline 3 §2 (Subsegment advance, run splitting at character offsets)",
        "prompt": """You are Agent 179 auditing Chromium Blink ShapeResult Run Splitting vs CSS Text 3 §5.
Detail:
1. Run splitting at offset i: returns (left_run, right_run) where left_run has characters [start, i) and right has [i, end).
2. Invariants: left_width + right_width = total_width, left_chars + right_chars = total_chars.
3. Concrete Rocq/Coq definitions and theorems for BlinkShapeResultRunSplitSemantics.v."""
    },
    {
        "id": "agent180",
        "file": "agent180_inline_box_vertical_align.md",
        "topic": "Chromium Blink Inline Box Vertical Alignment (core/layout/inline/inline_box_state.cc)",
        "spec": "CSS Inline Layout 3 §5 (vertical-align: baseline, sub, super, top, bottom, middle)",
        "prompt": """You are Agent 180 auditing Chromium Blink Inline Box Vertical Align vs CSS Inline 3 §5.
Detail:
1. Shift computation: baseline (shift 0), sub (shift +sub_offset), super (shift -super_offset), middle (centered on x-height).
2. Invariants: shifts preserve inline box height, top/bottom alignments clamp within line box boundaries.
3. Concrete Rocq/Coq definitions and theorems for BlinkInlineBoxVerticalAlignSemantics.v."""
    },
    {
        "id": "agent181",
        "file": "agent181_text_tab_stop_advance.md",
        "topic": "Chromium Blink Tab Stop Expansion (platform/text/text_run.cc)",
        "spec": "CSS Text 3 §4.2 (tab-size: advance to next multiple of tab_width)",
        "prompt": """You are Agent 181 auditing Chromium Blink Tab Stop Expansion vs CSS Text 3 §4.2.
Detail:
1. Next tab position: next_x = ((current_x / tab_width) + 1) * tab_width.
2. Advance: tab_advance = next_x - current_x.
3. Invariants: 0 < tab_advance <= tab_width, next_x > current_x, next_x mod tab_width = 0.
4. Concrete Rocq/Coq definitions and theorems for BlinkTextTabStopAdvanceSemantics.v."""
    },
    {
        "id": "agent182",
        "file": "agent182_ruby_annotation_placement.md",
        "topic": "Chromium Blink Ruby Base & Annotation Placement (core/layout/inline/ruby_layout_algorithm.cc)",
        "spec": "CSS Ruby Layout 1 §3 (ruby-position: over | under, overhang clamping)",
        "prompt": """You are Agent 182 auditing Chromium Blink Ruby Annotation Placement vs CSS Ruby 1 §3.
Detail:
1. Ruby column inline size: max(base_width, annotation_width).
2. Vertical stacking: annotation placed above (or below) ruby base without overlap.
3. Invariants: ruby column width >= base_width, annotation and base vertical intervals are strictly disjoint.
4. Concrete Rocq/Coq definitions and theorems for BlinkRubyAnnotationPlacementSemantics.v."""
    },
    {
        "id": "agent183",
        "file": "agent183_text_offset_range_slice.md",
        "topic": "Chromium Blink Text Offset Range Slice Intersection (core/layout/inline/text_offset_range.cc)",
        "spec": "DOM & CSS Text 3 (TextOffsetRange [start, end), slice intersection)",
        "prompt": """You are Agent 183 auditing Chromium Blink TextOffsetRange Slicing.
Detail:
1. Range intersection: [max(start1, start2), min(end1, end2)). Empty if start >= end.
2. Invariants: intersection length <= min(len1, len2), intersection is contained within both parent ranges.
3. Concrete Rocq/Coq definitions and theorems for BlinkTextOffsetRangeSliceSemantics.v."""
    },
    {
        "id": "agent184",
        "file": "agent184_east_asian_width_spacing.md",
        "topic": "Chromium Blink East Asian Width Property Categorization & Spacing (platform/text/character.cc)",
        "spec": "UAX #11 (East Asian Width: Fullwidth, Wide, Halfwidth, Narrow, Neutral) & CSS Text 3 §8",
        "prompt": """You are Agent 184 auditing Chromium Blink East Asian Width vs UAX #11 & CSS Text 3 §8.
Detail:
1. Width classification: Fullwidth/Wide characters have 1em advance; Halfwidth/Narrow have 0.5em advance.
2. Invariants: Fullwidth character advance = 2 * Halfwidth character advance, advances are non-negative.
3. Concrete Rocq/Coq definitions and theorems for BlinkEastAsianWidthSpacingSemantics.v."""
    },
    {
        "id": "agent185",
        "file": "agent185_text_ellipsis_truncation.md",
        "topic": "Chromium Blink Text Ellipsis Truncation Point Selection (core/layout/inline/line_truncator.cc)",
        "spec": "CSS Overflow 3 §4.2 (text-overflow: ellipsis, available line width reduction)",
        "prompt": """You are Agent 185 auditing Chromium Blink Text Ellipsis Truncation vs CSS Overflow 3 §4.2.
Detail:
1. Truncation: find largest character index i such that width([0, i)) + ellipsis_width <= available_width.
2. Invariants: truncated text width + ellipsis_width <= available_width, truncation index is bounded in [0, total_chars].
3. Concrete Rocq/Coq definitions and theorems for BlinkTextEllipsisTruncationSemantics.v."""
    },
    {
        "id": "agent186",
        "file": "agent186_font_fallback_chain.md",
        "topic": "Chromium Blink Font Fallback Selection Chain (platform/fonts/font_fallback_iterator.cc)",
        "spec": "CSS Fonts 3 §5 (Font matching algorithm, fallback priority, generic fallback)",
        "prompt": """You are Agent 186 auditing Chromium Blink Font Fallback Chain vs CSS Fonts 3 §5.
Detail:
1. Fallback chain traversal: iterates list of candidate font families; returns first font that supports character U.
2. Invariants: fallback index monotonically increases, fallback terminates either at matching font or system default.
3. Concrete Rocq/Coq definitions and theorems for BlinkFontFallbackChainSemantics.v."""
    },
    {
        "id": "agent187",
        "file": "agent187_inline_item_classification.md",
        "topic": "Chromium Blink Inline Item Segment Classification (core/layout/inline/inline_item.cc)",
        "spec": "CSS Inline 3 §2 (Inline items: Text, Control, OpenTag, CloseTag, AtomicInline)",
        "prompt": """You are Agent 187 auditing Chromium Blink InlineItem Classification vs CSS Inline 3 §2.
Detail:
1. Inline item types: Text (measurable text), Control (line breaks, tab), OpenTag/CloseTag (styling span), AtomicInline (replaced/inline-block).
2. Invariants: total character offset range of items forms a continuous partition of the input paragraph text without gaps.
3. Concrete Rocq/Coq definitions and theorems for BlinkInlineItemClassificationSemantics.v."""
    },
    {
        "id": "agent188",
        "file": "agent188_bidi_visual_reorder_l1.md",
        "topic": "Chromium Blink BiDi Visual Run Reordering Rule L1 (platform/text/bidi_paragraph.cc)",
        "spec": "Unicode Bidirectional Algorithm UAX #9 §3.4 (Rule L1: Resetting whitespace levels to paragraph base)",
        "prompt": """You are Agent 188 auditing Chromium Blink BiDi Rule L1 vs UAX #9 §3.4.
Detail:
1. Rule L1: any trailing sequence of whitespace characters at the end of a line has its embedding level reset to the paragraph base level.
2. Invariants: reset levels match paragraph base level, non-trailing characters retain their resolved embedding levels.
3. Concrete Rocq/Coq definitions and theorems for BlinkBidiVisualReorderL1Semantics.v."""
    },
    {
        "id": "agent189",
        "file": "agent189_inline_break_token_offset.md",
        "topic": "Chromium Blink Inline Break Token Offset Continuation (core/layout/inline/inline_break_token.cc)",
        "spec": "CSS Fragmentation 3 §4 & CSS Inline 3 §3 (Inline break token character and item offset resumption)",
        "prompt": """You are Agent 189 auditing Chromium Blink InlineBreakToken Offset Continuation vs CSS Fragmentation 3 §4.
Detail:
1. Break token fields: text_offset, item_index.
2. Resumption: next line begins exactly at text_offset.
3. Invariants: text_offset strictly increases across non-empty lines, final break token matches total paragraph length.
4. Concrete Rocq/Coq definitions and theorems for BlinkInlineBreakTokenOffsetSemantics.v."""
    },
    {
        "id": "agent190",
        "file": "agent190_shaping_line_breaker_hyphen.md",
        "topic": "Chromium Blink Shaping Line Breaker with Hyphen Insertion (platform/fonts/shaping/shaping_line_breaker.cc)",
        "spec": "CSS Text 3 §5.4 (Hyphen insertion, remaining width fit, hyphen advance accounting)",
        "prompt": """You are Agent 190 auditing Chromium Blink Shaping Line Breaker Hyphen Insertion vs CSS Text 3 §5.4.
Detail:
1. Hyphen line break: candidate break at character i fits if prefix_width(i) + hyphen_width <= available_width.
2. Invariants: total broken line advance <= available_width, break index i strictly positive.
3. Concrete Rocq/Coq definitions and theorems for BlinkShapingLineBreakerHyphenSemantics.v."""
    },
    {
        "id": "agent191",
        "file": "agent191_text_justify_inter_word.md",
        "topic": "Chromium Blink Text Justification Inter-Word Space Distribution (core/layout/inline/justification_utils.cc)",
        "spec": "CSS Text 3 §7.3.3 (text-align: justify, text-justify: inter-word, expansion opportunity)",
        "prompt": """You are Agent 191 auditing Chromium Blink Text Justification vs CSS Text 3 §7.3.3.
Detail:
1. Justification expansion: free_space = available_width - line_width. If spaces_count > 0, extra_per_space = free_space / spaces_count.
2. Invariants: total extra space distributed <= free_space, word spacing is non-negative and monotonic in free space.
3. Concrete Rocq/Coq definitions and theorems for BlinkTextJustifyInterWordSemantics.v."""
    },
    {
        "id": "agent192",
        "file": "agent192_font_matching_distance.md",
        "topic": "Chromium Blink CSS Font-Matching Distance Metric (platform/fonts/font_selection_algorithm.cc)",
        "spec": "CSS Fonts 3 §5.2 (Font matching algorithm, distance metric for stretch, style, and weight)",
        "prompt": """You are Agent 192 auditing Chromium Blink Font Matching Distance vs CSS Fonts 3 §5.2.
Detail:
1. Distance calculation: D = w_weight * |req_weight - cand_weight| + w_slant * |req_slant - cand_slant|.
2. Invariants: distance D >= 0, distance D = 0 iff candidate exactly matches requested properties, triangle inequality holds.
3. Concrete Rocq/Coq definitions and theorems for BlinkFontMatchingDistanceSemantics.v."""
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
    print("Launching Wave 17 (Iteration 2 of 8): 16 concurrent Python3 agents using gemini-4-argon (low thinking budget 512)...")
    with concurrent.futures.ThreadPoolExecutor(max_workers=16) as executor:
        results = list(executor.map(run_agent, tasks))

    total_p = sum(r.get("prompt_tokens", 0) for r in results)
    total_c = sum(r.get("candidates_tokens", 0) for r in results)
    total_t = sum(r.get("total_tokens", 0) for r in results)

    log_entry = {
        "timestamp": time.strftime("%Y-%m-%d %H:%M:%S"),
        "model": "gemini-4-argon",
        "wave": 17,
        "iteration": 2,
        "theme": "CSS Text, Font Shaping & Typography Engine (HarfBuzz Glyph Advance, Font Half-Leading, ShapeResult Run Split, Inline Box Vertical Align, Tab Stop Expansion, Ruby Annotation Placement, TextOffsetRange Slice, East Asian Width, Text Ellipsis Truncation, Font Fallback Chain, Inline Item Classification, BiDi Rule L1, Inline Break Tokens, Hyphen Line Breaking, Text Justification, Font Matching Distance)",
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

    print("\n=== WAVE 17 (ITERATION 2 OF 8) TOKEN USAGE REPORT ===")
    print(f"Prompt Tokens:     {total_p}")
    print(f"Candidate Tokens:  {total_c}")
    print(f"Total Tokens Used: {total_t}")
    print("Appended log entry to token_usage.log.")

