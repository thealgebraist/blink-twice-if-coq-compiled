#!/usr/bin/env python3
"""
run_wave27_agents.py - Wave 27 (Iteration 4 of 8): Blink Text Shaping & Advanced Typography
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
        "id": "agent337",
        "file": "agent337_opentype_gpos_value_record.md",
        "topic": "Chromium Blink OpenType GPOS ValueRecord Translation (platform/fonts/shaping/harfbuzz_shaper.cc)",
        "spec": "OpenType GPOS §2 (ValueRecord: x_placement, y_placement, x_advance, y_advance position shifts)",
        "prompt": "You are Agent 337 auditing Blink OpenType GPOS ValueRecord application. Detail position translation and advance addition."
    },
    {
        "id": "agent338",
        "file": "agent338_opentype_gsub_single.md",
        "topic": "Chromium Blink OpenType GSUB Single Substitution (platform/fonts/shaping/harfbuzz_shaper.cc)",
        "spec": "OpenType GSUB §2 (Format 1 & 2 single glyph substitution lookup identity)",
        "prompt": "You are Agent 338 auditing Blink OpenType GSUB Single Substitution. Detail glyph ID replacement mapping."
    },
    {
        "id": "agent339",
        "file": "agent339_opentype_gsub_multiple.md",
        "topic": "Chromium Blink OpenType GSUB Multiple Substitution (platform/fonts/shaping/harfbuzz_shaper.cc)",
        "spec": "OpenType GSUB §3 (Multiple substitution: one glyph decomposes to sequence of glyphs)",
        "prompt": "You are Agent 339 auditing Blink OpenType GSUB Multiple Substitution. Detail glyph sequence expansion."
    },
    {
        "id": "agent340",
        "file": "agent340_opentype_gsub_ligature.md",
        "topic": "Chromium Blink OpenType GSUB Ligature Substitution (platform/fonts/shaping/harfbuzz_shaper.cc)",
        "spec": "OpenType GSUB §4 (Ligature substitution: sequence of glyphs collapses into single ligature glyph)",
        "prompt": "You are Agent 340 auditing Blink OpenType GSUB Ligature Substitution. Detail sequence prefix reduction."
    },
    {
        "id": "agent341",
        "file": "agent341_harfbuzz_cluster_formation.md",
        "topic": "Chromium Blink HarfBuzz Cluster Formation (platform/fonts/shaping/harfbuzz_shaper.cc)",
        "spec": "HarfBuzz Cluster Architecture (cluster level 0/1/2 monotonicity in LTR vs RTL)",
        "prompt": "You are Agent 341 auditing Blink HarfBuzz cluster formation. Detail monotonic cluster index progression."
    },
    {
        "id": "agent342",
        "file": "agent342_kerning_pair_advance.md",
        "topic": "Chromium Blink Kerning Pair Advance (platform/fonts/shaping/font_features.cc)",
        "spec": "CSS Text 4 §4 (pair kerning adjustment: advance' = advance + kern(g1, g2))",
        "prompt": "You are Agent 342 auditing Blink kerning pair advance adjustment. Detail kerning addition to glyph advance."
    },
    {
        "id": "agent343",
        "file": "agent343_word_spacing_application.md",
        "topic": "Chromium Blink Word Spacing Application (platform/fonts/shaping/shaping_line_breaker.cc)",
        "spec": "CSS Text 3 §8.1 (word-spacing applied to space characters U+0020 and U+00A0 only)",
        "prompt": "You are Agent 343 auditing Blink word spacing application. Detail conditional spacing on space codepoints."
    },
    {
        "id": "agent344",
        "file": "agent344_letter_spacing_application.md",
        "topic": "Chromium Blink Letter Spacing Application (platform/fonts/shaping/shape_result.cc)",
        "spec": "CSS Text 3 §8.2 (letter-spacing applied to all grapheme cluster advance boundaries)",
        "prompt": "You are Agent 344 auditing Blink letter spacing application. Detail spacing addition at cluster boundaries."
    },
    {
        "id": "agent345",
        "file": "agent345_font_feature_settings.md",
        "topic": "Chromium Blink Font Feature Settings (platform/fonts/font_feature_settings.cc)",
        "spec": "CSS Fonts 4 §7.1 (four-character OpenType feature tag parsing and value matching)",
        "prompt": "You are Agent 345 auditing Blink font feature settings. Detail tag equality and feature activation."
    },
    {
        "id": "agent346",
        "file": "agent346_font_variation_axis_clamping.md",
        "topic": "Chromium Blink Font Variation Axis Clamping (platform/fonts/font_variation_settings.cc)",
        "spec": "OpenType fvar §2 (axis coordinate clamped within [min_value, max_value])",
        "prompt": "You are Agent 346 auditing Blink font variation axis clamping. Detail axis coordinate clamping."
    },
    {
        "id": "agent347",
        "file": "agent347_emoji_zwj_collation.md",
        "topic": "Chromium Blink Emoji ZWJ Sequence Collation (platform/fonts/shaping/harfbuzz_shaper.cc)",
        "spec": "Unicode UTS #51 §2 (Emoji ZWJ sequence collation into single compound glyph)",
        "prompt": "You are Agent 347 auditing Blink Emoji ZWJ sequence collation. Detail glyph sequence collapse."
    },
    {
        "id": "agent348",
        "file": "agent348_variation_selector_branch.md",
        "topic": "Chromium Blink Variation Selector Branching (platform/fonts/font_fallback_iterator.cc)",
        "spec": "Unicode Standard §23.4 (VS15 selects text presentation; VS16 selects emoji presentation)",
        "prompt": "You are Agent 348 auditing Blink variation selector branching. Detail VS15 vs VS16 presentation branching."
    },
    {
        "id": "agent349",
        "file": "agent349_font_optical_sizing.md",
        "topic": "Chromium Blink Font Optical Sizing Derivation (platform/fonts/font_description.cc)",
        "spec": "CSS Fonts 4 §6.12 (font-optical-sizing: auto sets opsz axis equal to font-size in points)",
        "prompt": "You are Agent 349 auditing Blink font optical sizing. Detail opsz axis value derivation from font size."
    },
    {
        "id": "agent350",
        "file": "agent350_text_emphasis_position.md",
        "topic": "Chromium Blink Text Emphasis Position (core/paint/text_emphasis_painter.cc)",
        "spec": "CSS Text Decoration 3 §3.2 (text-emphasis mark offset above text over/under baseline)",
        "prompt": "You are Agent 350 auditing Blink text emphasis mark positioning. Detail mark offset calculation."
    },
    {
        "id": "agent351",
        "file": "agent351_text_underline_metrics.md",
        "topic": "Chromium Blink Text Underline Metrics (core/paint/text_decoration_painter.cc)",
        "spec": "CSS Text Decoration 4 §2 (underline offset and thickness derived from font OS/2 table metrics)",
        "prompt": "You are Agent 351 auditing Blink text underline metrics. Detail underline position and thickness bounds."
    },
    {
        "id": "agent352",
        "file": "agent352_text_strikethrough_metrics.md",
        "topic": "Chromium Blink Text Strikethrough Metrics (core/paint/text_decoration_painter.cc)",
        "spec": "CSS Text Decoration 4 §2 (strikethrough position and thickness derived from OS/2 yStrikeoutPosition)",
        "prompt": "You are Agent 352 auditing Blink text strikethrough metrics. Detail strikethrough offset calculation."
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
    print("Launching Wave 27 (Iteration 4 of 8): 16 concurrent Python3 agents using gemini-4-argon with benchmark-validated optimal Medium thinking budget (2048)...")
    with concurrent.futures.ThreadPoolExecutor(max_workers=16) as executor:
        results = list(executor.map(run_agent, tasks))

    total_p = sum(r.get("prompt_tokens", 0) for r in results)
    total_c = sum(r.get("candidates_tokens", 0) for r in results)
    total_t = sum(r.get("total_tokens", 0) for r in results)

    log_entry = {
        "timestamp": time.strftime("%Y-%m-%d %H:%M:%S"),
        "model": "gemini-4-argon",
        "wave": 27,
        "iteration": 4,
        "theme": "Blink Text Shaping & Advanced Typography (GPOS ValueRecord, GSUB Single, GSUB Multiple, GSUB Ligature, Cluster Formation, Kerning Advance, Word Spacing, Letter Spacing, Feature Settings, Variation Axis Clamping, Emoji ZWJ Collation, Variation Selector Branch, Optical Sizing, Text Emphasis, Underline Metrics, Strikethrough Metrics)",
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

    print("\n=== WAVE 27 (ITERATION 4 OF 8) TOKEN USAGE REPORT ===")
    print(f"Prompt Tokens:     {total_p}")
    print(f"Candidate Tokens:  {total_c}")
    print(f"Total Tokens Used: {total_t}")
    print("Appended log entry to token_usage.log.")
