#!/usr/bin/env python3
"""
run_wave34_agents.py - Wave 34 (Iteration 3 of 8): DOM Tree, Shadow DOM & Event Dispatch Pipeline
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
        "id": "agent449",
        "file": "agent449_dom_parent_child_consistency.md",
        "topic": "Chromium Blink DOM Tree Bidirectional Consistency (core/dom/node.cc)",
        "spec": "DOM Standard §4.2 (child.parentNode == parent <-> parent.childNodes.contains(child))",
        "prompt": "You are Agent 449 auditing Blink DOM tree consistency. Detail parent-child bidirectional consistency."
    },
    {
        "id": "agent450",
        "file": "agent450_container_node_append.md",
        "topic": "Chromium Blink ContainerNode Child Count Monotonicity (core/dom/container_node.cc)",
        "spec": "DOM Standard §4.2.3 (appendChild strictly increments childNodes length)",
        "prompt": "You are Agent 450 auditing Blink ContainerNode appendChild. Detail child count monotonic progression."
    },
    {
        "id": "agent451",
        "file": "agent451_shadow_root_encapsulation.md",
        "topic": "Chromium Blink ShadowRoot Encapsulation (core/dom/tree_scope.cc)",
        "spec": "DOM Standard §4.2.2 (elements in shadow tree not retrievable via light DOM getElementById)",
        "prompt": "You are Agent 451 auditing Blink ShadowRoot encapsulation. Detail shadow boundary isolation."
    },
    {
        "id": "agent452",
        "file": "agent452_slot_assignment_matching.md",
        "topic": "Chromium Blink HTMLSlotElement Name Matching (core/dom/slot_assignment.cc)",
        "spec": "DOM Standard §4.2.2 (slotted child matches slot name attribute or default slot)",
        "prompt": "You are Agent 452 auditing Blink HTMLSlotElement assignment. Detail slot name matching logic."
    },
    {
        "id": "agent453",
        "file": "agent453_event_path_composed.md",
        "topic": "Chromium Blink Event composedPath Traversal (core/dom/events/event_dispatcher.cc)",
        "spec": "DOM Standard §2.8 (composed: false clips event path at shadow root boundary)",
        "prompt": "You are Agent 453 auditing Blink composedPath event traversal. Detail shadow boundary path clipping."
    },
    {
        "id": "agent454",
        "file": "agent454_event_phase_progression.md",
        "topic": "Chromium Blink Event Dispatch 3-Phase Progression (core/dom/events/event_dispatcher.cc)",
        "spec": "DOM Standard §2.9 (CAPTURING_PHASE(1) -> AT_TARGET(2) -> BUBBLING_PHASE(3) ordering)",
        "prompt": "You are Agent 454 auditing Blink event dispatch phases. Detail 3-phase strict ordering."
    },
    {
        "id": "agent455",
        "file": "agent455_event_stop_propagation.md",
        "topic": "Chromium Blink stopPropagation Termination (core/dom/events/event_dispatcher.cc)",
        "spec": "DOM Standard §2.7 (stopPropagation() halts event bubbling to parent nodes)",
        "prompt": "You are Agent 455 auditing Blink stopPropagation termination. Detail dispatch loop cessation."
    },
    {
        "id": "agent456",
        "file": "agent456_event_listener_priority.md",
        "topic": "Chromium Blink EventListener Invocation Order (core/dom/events/event_target.cc)",
        "spec": "DOM Standard §2.6 (listeners invoked in order of registration insertion)",
        "prompt": "You are Agent 456 auditing Blink EventListener invocation order. Detail registration FIFO order."
    },
    {
        "id": "agent457",
        "file": "agent457_mutation_observer_queue.md",
        "topic": "Chromium Blink MutationObserver Record Queue (core/dom/mutation_observer_interest_group.cc)",
        "spec": "DOM Standard §4.3 (mutation records queued and drained before next microtask checkpoint)",
        "prompt": "You are Agent 457 auditing Blink MutationObserver record queue. Detail queue accumulation and drainage."
    },
    {
        "id": "agent458",
        "file": "agent458_document_ready_state.md",
        "topic": "Chromium Blink Document readyState Progression (core/dom/document.cc)",
        "spec": "HTML Standard §7.4 (readyState transitions loading(1) -> interactive(2) -> complete(3))",
        "prompt": "You are Agent 458 auditing Blink Document readyState. Detail monotonic readyState progression."
    },
    {
        "id": "agent459",
        "file": "agent459_element_child_count.md",
        "topic": "Chromium Blink childElementCount Non-Negativity (core/dom/element_traversal.cc)",
        "spec": "DOM Standard §4.2 (childElementCount >= 0 and bounded by childNodes count)",
        "prompt": "You are Agent 459 auditing Blink childElementCount. Detail non-negativity and upper bounds."
    },
    {
        "id": "agent460",
        "file": "agent460_domtokenlist_uniqueness.md",
        "topic": "Chromium Blink DOMTokenList Class Uniqueness (core/dom/class_collection.cc)",
        "spec": "DOM Standard §7.1 (DOMTokenList set representation has no duplicate tokens)",
        "prompt": "You are Agent 460 auditing Blink DOMTokenList set uniqueness. Detail duplicate deduplication."
    },
    {
        "id": "agent461",
        "file": "agent461_attribute_case_matching.md",
        "topic": "Chromium Blink Attribute Name Case-Insensitive Matching (core/dom/attribute_collection.cc)",
        "spec": "DOM Standard §4.9 (HTML element attribute lookup matches ASCII lowercased name)",
        "prompt": "You are Agent 461 auditing Blink attribute matching. Detail ASCII case folding equivalence."
    },
    {
        "id": "agent462",
        "file": "agent462_custom_element_tag_validity.md",
        "topic": "Chromium Blink Custom Element Name Validity (core/dom/custom_element_registry.cc)",
        "spec": "HTML Standard §4.13.1 (valid custom element name must contain at least one hyphen '-')",
        "prompt": "You are Agent 462 auditing Blink custom element registration. Detail hyphen validation requirement."
    },
    {
        "id": "agent463",
        "file": "agent463_shadow_root_mode_access.md",
        "topic": "Chromium Blink ShadowRoot Open vs Closed Access (core/dom/shadow_root.cc)",
        "spec": "DOM Standard §4.2.2 (element.shadowRoot returns null if mode == 'closed')",
        "prompt": "You are Agent 463 auditing Blink shadowRoot mode access. Detail closed mode null pointer projection."
    },
    {
        "id": "agent464",
        "file": "agent464_flat_tree_traversal.md",
        "topic": "Chromium Blink Flat Tree Traversal Projection (core/dom/flat_tree_traversal.cc)",
        "spec": "DOM Standard §4.2.2 (flat tree traversal maps slotted nodes into rendered composition tree)",
        "prompt": "You are Agent 464 auditing Blink flat tree traversal. Detail slotted tree flattening projection."
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
    print("Launching Wave 34 (Iteration 3 of 8): 16 concurrent Python3 agents using gemini-4-argon with benchmark-validated optimal Medium thinking budget (2048)...")
    with concurrent.futures.ThreadPoolExecutor(max_workers=16) as executor:
        results = list(executor.map(run_agent, tasks))

    total_p = sum(r.get("prompt_tokens", 0) for r in results)
    total_c = sum(r.get("candidates_tokens", 0) for r in results)
    total_t = sum(r.get("total_tokens", 0) for r in results)

    log_entry = {
        "timestamp": time.strftime("%Y-%m-%d %H:%M:%S"),
        "model": "gemini-4-argon",
        "wave": 34,
        "iteration": 3,
        "theme": "DOM Tree, Shadow DOM & Event Dispatch Pipeline",
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

    print("\n=== WAVE 34 (ITERATION 3 OF 8) TOKEN USAGE REPORT ===")
    print(f"Prompt Tokens:     {total_p}")
    print(f"Candidate Tokens:  {total_c}")
    print(f"Total Tokens Used: {total_t}")
    print("Appended log entry to token_usage.log.")
