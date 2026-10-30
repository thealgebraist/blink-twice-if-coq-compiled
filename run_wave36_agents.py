#!/usr/bin/env python3
"""
run_wave36_agents.py - Wave 36 (Iteration 5 of 8): HTML Form Controls, Validation & Accessibility Tree
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
        "id": "agent481",
        "file": "agent481_input_selection_range.md",
        "topic": "Chromium Blink Text Control Selection Bounds (core/html/forms/text_control_element.cc)",
        "spec": "HTML Standard §4.10.5 (selectionStart and selectionEnd clamped to [0, value.length])",
        "prompt": "You are Agent 481 auditing Blink input selection range bounds. Detail start and end clamping within value length."
    },
    {
        "id": "agent482",
        "file": "agent482_input_step_quantization.md",
        "topic": "Chromium Blink Input Step Quantization (core/html/forms/step_range.cc)",
        "spec": "HTML Standard §4.10.5.2 (stepped value quantizes: min + k * step)",
        "prompt": "You are Agent 482 auditing Blink input step range. Detail quantization arithmetic."
    },
    {
        "id": "agent483",
        "file": "agent483_validity_state_boolean.md",
        "topic": "Chromium Blink ValidityState Check (core/html/forms/validity_state.cc)",
        "spec": "HTML Standard §4.10.21 (validity.valid <-> conjunction of all error flags is false)",
        "prompt": "You are Agent 483 auditing Blink ValidityState. Detail validity boolean logic."
    },
    {
        "id": "agent484",
        "file": "agent484_form_data_append.md",
        "topic": "Chromium Blink FormData Entry Appending (core/html/forms/form_data.cc)",
        "spec": "XHR / Fetch §4 (append entry monotonically increments entry list size)",
        "prompt": "You are Agent 484 auditing Blink FormData. Detail monotonic entry list accumulation."
    },
    {
        "id": "agent485",
        "file": "agent485_radio_group_exclusion.md",
        "topic": "Chromium Blink Radio Group Mutual Exclusion (core/html/forms/radio_input_type.cc)",
        "spec": "HTML Standard §4.10.5.1 (at most one radio button checked per named radio group)",
        "prompt": "You are Agent 485 auditing Blink radio group exclusion. Detail mutual exclusion uniqueness."
    },
    {
        "id": "agent486",
        "file": "agent486_checkbox_tristate.md",
        "topic": "Chromium Blink Checkbox Indeterminate Tri-State (core/html/forms/checkbox_input_type.cc)",
        "spec": "HTML Standard §4.10.5.1 (checkbox state: checked, unchecked, indeterminate)",
        "prompt": "You are Agent 486 auditing Blink checkbox tri-state logic. Detail state transitions."
    },
    {
        "id": "agent487",
        "file": "agent487_select_index_bounds.md",
        "topic": "Chromium Blink Select Element selectedIndex Bounds (core/html/forms/select_type.cc)",
        "spec": "HTML Standard §4.10.7 (selectedIndex clamped within [-1, options.length - 1])",
        "prompt": "You are Agent 487 auditing Blink HTMLSelectElement selectedIndex. Detail index bounds clamping."
    },
    {
        "id": "agent488",
        "file": "agent488_file_list_length.md",
        "topic": "Chromium Blink FileList Allocation (core/html/forms/file_input_type.cc)",
        "spec": "File API §3 (FileList length is non-negative and elements indexed [0, length))",
        "prompt": "You are Agent 488 auditing Blink FileList length. Detail non-negativity and item indexing."
    },
    {
        "id": "agent489",
        "file": "agent489_ax_accessible_name.md",
        "topic": "Chromium Blink Accessible Name Fallback (modules/accessibility/ax_object.cc)",
        "spec": "Accessible Name and Description §2 (aria-labelledby -> aria-label -> native title -> content)",
        "prompt": "You are Agent 489 auditing Blink Accessible Name derivation. Detail precedence order."
    },
    {
        "id": "agent490",
        "file": "agent490_ax_role_determination.md",
        "topic": "Chromium Blink AXRole Determination (modules/accessibility/ax_node_object.cc)",
        "spec": "WAI-ARIA 1.2 §5 (explicit role overrides native HTML element default role)",
        "prompt": "You are Agent 490 auditing Blink AXRole determination. Detail role override precedence."
    },
    {
        "id": "agent491",
        "file": "agent491_ax_labelledby_graph.md",
        "topic": "Chromium Blink ARIA-labelledby Graph Traversal (modules/accessibility/ax_relation_cache.cc)",
        "spec": "Accessible Name §2 (cycle detection prevents infinite recursion in labelledby graph)",
        "prompt": "You are Agent 491 auditing Blink ARIA relation cache. Detail cycle-safe graph traversal."
    },
    {
        "id": "agent492",
        "file": "agent492_ax_unique_node_id.md",
        "topic": "Chromium Blink AXObjectCache Unique ID Monotonicity (modules/accessibility/ax_object_cache_impl.cc)",
        "spec": "Blink Accessibility §1 (each allocated AXID is strictly unique and monotonic)",
        "prompt": "You are Agent 492 auditing Blink AXID allocation. Detail monotonic unique ID generation."
    },
    {
        "id": "agent493",
        "file": "agent493_ax_position_bounds.md",
        "topic": "Chromium Blink AXPosition Text Offset Bounds (modules/accessibility/ax_position.cc)",
        "spec": "Blink Accessibility §2 (text offset clamped within [0, text.length])",
        "prompt": "You are Agent 493 auditing Blink AXPosition text bounds. Detail offset clamping."
    },
    {
        "id": "agent494",
        "file": "agent494_focus_tabindex_order.md",
        "topic": "Chromium Blink Sequential Focus Tabindex Ordering (core/page/focus_controller.cc)",
        "spec": "HTML Standard §7.3 (tabindex > 0 ordered by value, followed by tabindex == 0 in DOM order)",
        "prompt": "You are Agent 494 auditing Blink focus navigation order. Detail tabindex lexicographical ordering."
    },
    {
        "id": "agent495",
        "file": "agent495_dialog_focus_trap.md",
        "topic": "Chromium Blink Modal Dialog Focus Trap (core/html/html_dialog_element.cc)",
        "spec": "HTML Standard §4.11.4 (modal dialog confines tab focus cycle within its subtree)",
        "prompt": "You are Agent 495 auditing Blink HTMLDialogElement focus trap. Detail focus loop confinement."
    },
    {
        "id": "agent496",
        "file": "agent496_canvas_element_dimensions.md",
        "topic": "Chromium Blink HTMLCanvasElement Default Dimensions (core/html/canvas/html_canvas_element.cc)",
        "spec": "HTML Standard §4.12.5 (canvas default width 300, height 150 strictly positive)",
        "prompt": "You are Agent 496 auditing Blink canvas dimensions. Detail default positive dimensions."
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
    print("Launching Wave 36 (Iteration 5 of 8): 16 concurrent Python3 agents using gemini-4-argon with benchmark-validated optimal Medium thinking budget (2048)...")
    with concurrent.futures.ThreadPoolExecutor(max_workers=16) as executor:
        results = list(executor.map(run_agent, tasks))

    total_p = sum(r.get("prompt_tokens", 0) for r in results)
    total_c = sum(r.get("candidates_tokens", 0) for r in results)
    total_t = sum(r.get("total_tokens", 0) for r in results)

    log_entry = {
        "timestamp": time.strftime("%Y-%m-%d %H:%M:%S"),
        "model": "gemini-4-argon",
        "wave": 36,
        "iteration": 5,
        "theme": "HTML Form Controls, Validation & Accessibility Tree",
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

    print("\n=== WAVE 36 (ITERATION 5 OF 8) TOKEN USAGE REPORT ===")
    print(f"Prompt Tokens:     {total_p}")
    print(f"Candidate Tokens:  {total_c}")
    print(f"Total Tokens Used: {total_t}")
    print("Appended log entry to token_usage.log.")
