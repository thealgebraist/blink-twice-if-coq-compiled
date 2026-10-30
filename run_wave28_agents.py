#!/usr/bin/env python3
"""
run_wave28_agents.py - Wave 28 (Iteration 5 of 8): Blink CSS Paged Media & FragmentationNG
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
        "id": "agent353",
        "file": "agent353_page_size_resolution.md",
        "topic": "Chromium Blink @page Size Resolution (core/css/resolver/style_resolver.cc)",
        "spec": "CSS Paged Media 3 §3.1 (@page size resolution for standard page sizes like A4, Letter and custom dimensions)",
        "prompt": "You are Agent 353 auditing Blink @page size resolution. Detail page dimension lookup and non-negativity."
    },
    {
        "id": "agent354",
        "file": "agent354_page_margin_box.md",
        "topic": "Chromium Blink Page Margin Box Available Space (core/layout/fragmentation/page_fragment.cc)",
        "spec": "CSS Paged Media 3 §4 (page content available space = page_dim - (margin_start + margin_end))",
        "prompt": "You are Agent 354 auditing Blink page margin box available space. Detail available space calculation."
    },
    {
        "id": "agent355",
        "file": "agent355_page_break_opportunity.md",
        "topic": "Chromium Blink Page Break Opportunity Classification (core/layout/fragmentation/break_token.cc)",
        "spec": "CSS Fragmentation 3 §3.1 (break opportunity classes Class A between siblings, Class B inside, Class C lines)",
        "prompt": "You are Agent 355 auditing Blink page break opportunity classification. Detail class classification."
    },
    {
        "id": "agent356",
        "file": "agent356_break_inside_avoid_penalty.md",
        "topic": "Chromium Blink Break Inside Avoid Penalty (core/layout/fragmentation/fragmentation_algorithm.cc)",
        "spec": "CSS Fragmentation 3 §3.3 (break-inside: avoid assigns maximum penalty against breaking)",
        "prompt": "You are Agent 356 auditing Blink break-inside: avoid penalty. Detail penalty assignment and minimization."
    },
    {
        "id": "agent357",
        "file": "agent357_break_before_forced.md",
        "topic": "Chromium Blink Forced Break Before Page (core/layout/fragmentation/break_token.cc)",
        "spec": "CSS Fragmentation 3 §3.2 (break-before: page forces fragmentation break before box)",
        "prompt": "You are Agent 357 auditing Blink forced break before page. Detail forced break transition."
    },
    {
        "id": "agent358",
        "file": "agent358_break_after_forced.md",
        "topic": "Chromium Blink Forced Break After Page (core/layout/fragmentation/break_token.cc)",
        "spec": "CSS Fragmentation 3 §3.2 (break-after: page forces fragmentation break after box)",
        "prompt": "You are Agent 358 auditing Blink forced break after page. Detail forced break transition."
    },
    {
        "id": "agent359",
        "file": "agent359_orphan_line_count.md",
        "topic": "Chromium Blink Orphan Line Count Enforcement (core/layout/inline/inline_layout_algorithm.cc)",
        "spec": "CSS Fragmentation 3 §4.1 (orphans integer >= 1; requires minimum lines before fragment break)",
        "prompt": "You are Agent 359 auditing Blink orphan line count enforcement. Detail minimum line count constraint."
    },
    {
        "id": "agent360",
        "file": "agent360_widow_line_count.md",
        "topic": "Chromium Blink Widow Line Count Enforcement (core/layout/inline/inline_layout_algorithm.cc)",
        "spec": "CSS Fragmentation 3 §4.1 (widows integer >= 1; requires minimum lines after fragment break)",
        "prompt": "You are Agent 360 auditing Blink widow line count enforcement. Detail minimum line count constraint."
    },
    {
        "id": "agent361",
        "file": "agent361_table_pagination_thead.md",
        "topic": "Chromium Blink Table Thead Pagination Reservation (core/layout/table/table_layout_algorithm.cc)",
        "spec": "CSS Table 3 §8 (repeated table headers reserve thead height at the top of each page fragment)",
        "prompt": "You are Agent 361 auditing Blink table thead pagination reservation. Detail top space reservation."
    },
    {
        "id": "agent362",
        "file": "agent362_table_pagination_tfoot.md",
        "topic": "Chromium Blink Table Tfoot Pagination Reservation (core/layout/table/table_layout_algorithm.cc)",
        "spec": "CSS Table 3 §8 (repeated table footers reserve tfoot height at the bottom of each page fragment)",
        "prompt": "You are Agent 362 auditing Blink table tfoot pagination reservation. Detail bottom space reservation."
    },
    {
        "id": "agent363",
        "file": "agent363_page_counter_increment.md",
        "topic": "Chromium Blink Page Counter Monotonic Increment (core/layout/fragmentation/page_fragment.cc)",
        "spec": "CSS Paged Media 3 §5 (page counter strictly monotonically increments by 1 per page fragment)",
        "prompt": "You are Agent 363 auditing Blink page counter monotonic increment. Detail strict monotonicity page(n+1) = page(n) + 1."
    },
    {
        "id": "agent364",
        "file": "agent364_multicol_page_break_token.md",
        "topic": "Chromium Blink Multicol Page Break Token Propagation (core/layout/fragmentation/multicol_break_token.cc)",
        "spec": "CSS Fragmentation 3 §5.1 (column break token propagates consumed block-size into subsequent page)",
        "prompt": "You are Agent 364 auditing Blink multicol page break token propagation. Detail token chaining across pages."
    },
    {
        "id": "agent365",
        "file": "agent365_break_token_consumed_block_size.md",
        "topic": "Chromium Blink Consumed Block Size Accumulation (core/layout/fragmentation/break_token.cc)",
        "spec": "Blink LayoutNG Fragmentation (consumed_block_size accumulates sequentially: consumed_{n+1} = consumed_n + size_n)",
        "prompt": "You are Agent 365 auditing Blink break token consumed block-size. Detail monotonic accumulation."
    },
    {
        "id": "agent366",
        "file": "agent366_remaining_block_size_calculation.md",
        "topic": "Chromium Blink Remaining Block Size Calculation (core/layout/fragmentation/fragmentation_utils.cc)",
        "spec": "Blink LayoutNG Fragmentation (remaining_block_size = max(0, total_block_size - consumed_block_size))",
        "prompt": "You are Agent 366 auditing Blink remaining block size. Detail non-negativity and depletion."
    },
    {
        "id": "agent367",
        "file": "agent367_fragment_container_monotonicity.md",
        "topic": "Chromium Blink Fragment Container Monotonicity (core/layout/fragmentation/fragment_builder.cc)",
        "spec": "Blink LayoutNG Fragmentation (fragment index in fragmented container strictly monotonic 0, 1, 2...)",
        "prompt": "You are Agent 367 auditing Blink fragment container sequence. Detail sequence monotonicity."
    },
    {
        "id": "agent368",
        "file": "agent368_paged_fragmentation_assembly.md",
        "topic": "Chromium Blink Paged Fragmentation Assembly Soundness (core/layout/fragmentation/page_container.cc)",
        "spec": "CSS Paged Media 3 §6 (sum of fragment heights bounded by document total block size)",
        "prompt": "You are Agent 368 auditing Blink paged fragmentation assembly soundness. Detail conservation of total block size."
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
    print("Launching Wave 28 (Iteration 5 of 8): 16 concurrent Python3 agents using gemini-4-argon with benchmark-validated optimal Medium thinking budget (2048)...")
    with concurrent.futures.ThreadPoolExecutor(max_workers=16) as executor:
        results = list(executor.map(run_agent, tasks))

    total_p = sum(r.get("prompt_tokens", 0) for r in results)
    total_c = sum(r.get("candidates_tokens", 0) for r in results)
    total_t = sum(r.get("total_tokens", 0) for r in results)

    log_entry = {
        "timestamp": time.strftime("%Y-%m-%d %H:%M:%S"),
        "model": "gemini-4-argon",
        "wave": 28,
        "iteration": 5,
        "theme": "Blink CSS Paged Media & FragmentationNG (Page Size, Margin Box, Break Opportunity, Break Avoid Penalty, Break Before, Break After, Orphan Lines, Widow Lines, Table Thead Pagination, Table Tfoot Pagination, Page Counter, Multicol Break Token, Consumed Block Size, Remaining Block Size, Fragment Container, Assembly Soundness)",
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

    print("\n=== WAVE 28 (ITERATION 5 OF 8) TOKEN USAGE REPORT ===")
    print(f"Prompt Tokens:     {total_p}")
    print(f"Candidate Tokens:  {total_c}")
    print(f"Total Tokens Used: {total_t}")
    print("Appended log entry to token_usage.log.")
