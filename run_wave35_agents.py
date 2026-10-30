#!/usr/bin/env python3
"""
run_wave35_agents.py - Wave 35 (Iteration 4 of 8): CSS Selectors 4, Specificity & Style Invalidation
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
        "id": "agent465",
        "file": "agent465_selector_specificity_tuple.md",
        "topic": "Chromium Blink Selector Specificity Lexicographical Order (core/css/css_selector.cc)",
        "spec": "CSS Selectors 4 §16 (specificity tuple (A, B, C) packed integer total order)",
        "prompt": "You are Agent 465 auditing Blink selector specificity tuple calculation. Detail specificity integer packing and ordering."
    },
    {
        "id": "agent466",
        "file": "agent466_is_not_max_specificity.md",
        "topic": "Chromium Blink :is() and :not() Maximum Specificity (core/css/parser/css_selector_parser.cc)",
        "spec": "CSS Selectors 4 §4.2 (specificity of :is(s1, s2) equals max(spec(s1), spec(s2)))",
        "prompt": "You are Agent 466 auditing Blink :is()/:not() specificity. Detail maximum argument specificity selection."
    },
    {
        "id": "agent467",
        "file": "agent467_where_zero_specificity.md",
        "topic": "Chromium Blink :where() Zero Specificity (core/css/parser/css_selector_parser.cc)",
        "spec": "CSS Selectors 4 §4.3 (specificity of :where(...) is identically 0)",
        "prompt": "You are Agent 467 auditing Blink :where() specificity. Detail 0-specificity guarantee."
    },
    {
        "id": "agent468",
        "file": "agent468_has_relative_selector.md",
        "topic": "Chromium Blink :has() Relative Selector Matching (core/css/parser/css_selector_parser.cc)",
        "spec": "CSS Selectors 4 §4.4 (:has() matches if relative selector matches descendant)",
        "prompt": "You are Agent 468 auditing Blink :has() selector matching. Detail relative anchor traversal."
    },
    {
        "id": "agent469",
        "file": "agent469_nth_child_progression.md",
        "topic": "Chromium Blink :nth-child(An+B) Step Formula (core/css/parser/css_selector_parser.cc)",
        "spec": "CSS Selectors 4 §8.1 (index matches An+B <-> exists non-negative k: index = A*k + B)",
        "prompt": "You are Agent 469 auditing Blink :nth-child(An+B) evaluation. Detail arithmetic progression match formula."
    },
    {
        "id": "agent470",
        "file": "agent470_dir_selector_matching.md",
        "topic": "Chromium Blink :dir() Directionality Matching (core/css/parser/css_selector_parser.cc)",
        "spec": "CSS Selectors 4 §11 (:dir(ltr) vs :dir(rtl) matching based on effective directionality)",
        "prompt": "You are Agent 470 auditing Blink :dir() selector matching. Detail directionality boolean branching."
    },
    {
        "id": "agent471",
        "file": "agent471_class_invalidation_bitset.md",
        "topic": "Chromium Blink Class Invalidation Set Union (core/css/invalidation/style_invalidator.cc)",
        "spec": "Blink Style Invalidation §2 (invalidation set union covers all affected elements)",
        "prompt": "You are Agent 471 auditing Blink class invalidation sets. Detail bitset union coverage."
    },
    {
        "id": "agent472",
        "file": "agent472_id_invalidation_propagation.md",
        "topic": "Chromium Blink ID Invalidation Propagation (core/css/invalidation/style_invalidator.cc)",
        "spec": "Blink Style Invalidation §2 (ID mutation propagates invalidation to descendants)",
        "prompt": "You are Agent 472 auditing Blink ID invalidation. Detail descendant propagation."
    },
    {
        "id": "agent473",
        "file": "agent473_ruleset_bucket_hashing.md",
        "topic": "Chromium Blink RuleSet Bucket Hash Selection (core/css/rule_set.cc)",
        "spec": "Blink CSS Engine §3 (rules indexed into ID, class, tag buckets for fast candidate lookup)",
        "prompt": "You are Agent 473 auditing Blink RuleSet bucket hashing. Detail bucket index derivation."
    },
    {
        "id": "agent474",
        "file": "agent474_cascade_origin_priority.md",
        "topic": "Chromium Blink Cascade Origin Priority Ordering (core/css/resolver/match_result.cc)",
        "spec": "CSS Cascading 4 §3 (UA < User < Author < Author !important < User !important < UA !important)",
        "prompt": "You are Agent 474 auditing Blink cascade origin priority. Detail total ordering across origins."
    },
    {
        "id": "agent475",
        "file": "agent475_shadow_dom_cascade_order.md",
        "topic": "Chromium Blink Shadow DOM Tree Order Cascade (core/css/resolver/scoped_style_resolver.cc)",
        "spec": "CSS Scoping 1 §3 (outer tree scopes take precedence over inner tree scopes for normal rules)",
        "prompt": "You are Agent 475 auditing Blink shadow DOM cascade order. Detail tree scope depth ordering."
    },
    {
        "id": "agent476",
        "file": "agent476_bloom_filter_fast_reject.md",
        "topic": "Chromium Blink Ancestor Bloom Filter Fast Reject (core/css/element_rule_collector.cc)",
        "spec": "Blink CSS Selector Matching §4 (Bloom filter false positive allowed, false negative strictly 0)",
        "prompt": "You are Agent 476 auditing Blink ancestor Bloom filter fast reject. Detail zero false-negative guarantee."
    },
    {
        "id": "agent477",
        "file": "agent477_media_query_evaluation.md",
        "topic": "Chromium Blink Media Query Boolean Expression Evaluation (core/css/parser/media_query_evaluator.cc)",
        "spec": "Media Queries 4 §3 (min-width condition width >= threshold evaluation soundness)",
        "prompt": "You are Agent 477 auditing Blink media query evaluation. Detail threshold comparison soundness."
    },
    {
        "id": "agent478",
        "file": "agent478_container_query_evaluation.md",
        "topic": "Chromium Blink Container Query Condition Matching (core/css/parser/container_query_evaluator.cc)",
        "spec": "CSS Containment 3 §2 (container query matches when container width satisfies query range)",
        "prompt": "You are Agent 478 auditing Blink container query evaluation. Detail range satisfaction."
    },
    {
        "id": "agent479",
        "file": "agent479_computed_style_equality.md",
        "topic": "Chromium Blink ComputedStyle Equality Equivalence Relation (core/css/css_property_equality.cc)",
        "spec": "Blink ComputedStyle §1 (ComputedStyle diffing is reflexive, symmetric, and transitive)",
        "prompt": "You are Agent 479 auditing Blink ComputedStyle equality. Detail equivalence relation properties."
    },
    {
        "id": "agent480",
        "file": "agent480_display_contents_suppression.md",
        "topic": "Chromium Blink display:contents Box Generation Suppression (core/css/resolver/style_adjuster.cc)",
        "spec": "CSS Display 3 §2 (display: contents element produces 0 box fragments in layout tree)",
        "prompt": "You are Agent 480 auditing Blink display: contents box suppression. Detail 0 layout box generation invariant."
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
    print("Launching Wave 35 (Iteration 4 of 8): 16 concurrent Python3 agents using gemini-4-argon with benchmark-validated optimal Medium thinking budget (2048)...")
    with concurrent.futures.ThreadPoolExecutor(max_workers=16) as executor:
        results = list(executor.map(run_agent, tasks))

    total_p = sum(r.get("prompt_tokens", 0) for r in results)
    total_c = sum(r.get("candidates_tokens", 0) for r in results)
    total_t = sum(r.get("total_tokens", 0) for r in results)

    log_entry = {
        "timestamp": time.strftime("%Y-%m-%d %H:%M:%S"),
        "model": "gemini-4-argon",
        "wave": 35,
        "iteration": 4,
        "theme": "CSS Selectors 4, Specificity & Style Invalidation",
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

    print("\n=== WAVE 35 (ITERATION 4 OF 8) TOKEN USAGE REPORT ===")
    print(f"Prompt Tokens:     {total_p}")
    print(f"Candidate Tokens:  {total_c}")
    print(f"Total Tokens Used: {total_t}")
    print("Appended log entry to token_usage.log.")
