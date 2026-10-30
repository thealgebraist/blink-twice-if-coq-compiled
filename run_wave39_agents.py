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
        "id": 529,
        "filename": "agent529_wasm_linear_memory_page.md",
        "topic": "WebAssembly linear memory page allocation (64KiB per page)",
        "source": "v8/src/wasm/wasm-objects.cc",
        "spec": "WebAssembly Core Specification §5.4",
        "theory": "BlinkWasmMemoryPageAllocationSemantics.v",
        "math": "page_bytes = pages * 65536; page size is constant 65536 bytes."
    },
    {
        "id": 530,
        "filename": "agent530_wasm_memory_grow_monotonic.md",
        "topic": "WebAssembly memory.grow monotonicity and bounds",
        "source": "v8/src/wasm/wasm-memory.cc",
        "spec": "WebAssembly Core Specification §5.4",
        "theory": "BlinkWasmMemoryGrowMonotonicitySemantics.v",
        "math": "new_pages = old_pages + delta; new_pages >= old_pages; clamped at max_pages."
    },
    {
        "id": 531,
        "filename": "agent531_wasm_table_indirect_bounds.md",
        "topic": "WebAssembly Table indirect call bounds checking",
        "source": "v8/src/wasm/wasm-objects.cc",
        "spec": "WebAssembly Core Specification §5.4",
        "theory": "BlinkWasmTableIndirectCallBoundsSemantics.v",
        "math": "call_indirect valid iff 0 <= table_index < table_size."
    },
    {
        "id": 532,
        "filename": "agent532_wasm_global_preservation.md",
        "topic": "WebAssembly mutable global variable preservation",
        "source": "v8/src/wasm/wasm-objects.cc",
        "spec": "WebAssembly Core Specification §5.4",
        "theory": "BlinkWasmGlobalVariablePreservationSemantics.v",
        "math": "updating global variable preserves type and signed bitwidth bounds."
    },
    {
        "id": 533,
        "filename": "agent533_worker_structured_clone.md",
        "topic": "Worker postMessage structured clone identity",
        "source": "third_party/blink/renderer/bindings/core/v8/serialization/v8_script_value_serializer.cc",
        "spec": "HTML Standard §2.7",
        "theory": "BlinkWorkerStructuredCloneIdentitySemantics.v",
        "math": "deserialize(serialize(v)) == v; structured clone preserves value identity."
    },
    {
        "id": 534,
        "filename": "agent534_worker_task_queue_fifo.md",
        "topic": "DedicatedWorker FIFO task queue execution",
        "source": "third_party/blink/renderer/core/workers/worker_thread.cc",
        "spec": "HTML Standard §10.2",
        "theory": "BlinkWorkerTaskQueueFIFOSemantics.v",
        "math": "task execution order is strictly FIFO: dequeue pops earliest arrival."
    },
    {
        "id": 535,
        "filename": "agent535_shared_worker_port_entanglement.md",
        "topic": "SharedWorker MessagePort bidirectional entanglement",
        "source": "third_party/blink/renderer/core/workers/shared_worker.cc",
        "spec": "HTML Standard §10.3",
        "theory": "BlinkSharedWorkerPortEntanglementSemantics.v",
        "math": "entangle(p1) = p2 /\\ entangle(p2) = p1; entanglement is an involution."
    },
    {
        "id": 536,
        "filename": "agent536_event_loop_task_priority.md",
        "topic": "Blink Event Loop microtask draining before macro task",
        "source": "third_party/blink/renderer/platform/scheduler/main_thread/main_thread_scheduler_impl.cc",
        "spec": "HTML Standard §8.1",
        "theory": "BlinkEventLoopMicrotaskDrainingSemantics.v",
        "math": "microtask queue length must reach 0 before next macro task begins."
    },
    {
        "id": 537,
        "filename": "agent537_timer_background_throttling.md",
        "topic": "Background tab timer minimum interval clamping",
        "source": "third_party/blink/renderer/core/frame/dom_timer.cc",
        "spec": "HTML Standard §8.6",
        "theory": "BlinkTimerBackgroundThrottlingSemantics.v",
        "math": "effective_interval = max(requested_interval, 1000) when page is in background."
    },
    {
        "id": 538,
        "filename": "agent538_performance_now_monotonic.md",
        "topic": "performance.now() strictly monotonic progression",
        "source": "third_party/blink/renderer/core/timing/performance.cc",
        "spec": "High Resolution Time §4",
        "theory": "BlinkPerformanceNowMonotonicitySemantics.v",
        "math": "time_now(t2) >= time_now(t1) for t2 >= t1; strictly non-decreasing."
    },
    {
        "id": 539,
        "filename": "agent539_performance_observer_buffer.md",
        "topic": "PerformanceObserver buffer capacity bounding",
        "source": "third_party/blink/renderer/core/timing/performance_observer.cc",
        "spec": "Performance Timeline §3",
        "theory": "BlinkPerformanceObserverBufferBoundsSemantics.v",
        "math": "entries_stored <= buffer_max_size; excess entries dropped."
    },
    {
        "id": 540,
        "filename": "agent540_request_animation_frame_timing.md",
        "topic": "requestAnimationFrame pre-paint execution order",
        "source": "third_party/blink/renderer/core/dom/scripted_animation_controller.cc",
        "spec": "HTML Standard §8.1",
        "theory": "BlinkRequestAnimationFramePrePaintSemantics.v",
        "math": "raf_step < style_recalc_step < layout_step < paint_step."
    },
    {
        "id": 541,
        "filename": "agent541_scrolling_coordinator_sync.md",
        "topic": "ScrollingCoordinator main-thread to compositor sync",
        "source": "third_party/blink/renderer/core/page/scrolling/scrolling_coordinator.cc",
        "spec": "Blink Scrolling Architecture §2",
        "theory": "BlinkScrollingCoordinatorSyncSemantics.v",
        "math": "compositor_scroll_offset == main_thread_scroll_offset after commit."
    },
    {
        "id": 542,
        "filename": "agent542_hit_test_coordinate_transform.md",
        "topic": "Hit testing coordinate inverse transformation",
        "source": "third_party/blink/renderer/core/layout/hit_test_location.cc",
        "spec": "Blink Hit Testing §2",
        "theory": "BlinkHitTestingCoordinateTransformSemantics.v",
        "math": "point_in_box(p - offset, box_rect) iff point p hits transformed box."
    },
    {
        "id": 543,
        "filename": "agent543_pointer_event_id_tracking.md",
        "topic": "PointerEvent unique pointerId tracking",
        "source": "third_party/blink/renderer/core/events/pointer_event_factory.cc",
        "spec": "Pointer Events 3 §5",
        "theory": "BlinkPointerEventIdentifierTrackingSemantics.v",
        "math": "at most 1 active pointer is designated as isPrimary."
    },
    {
        "id": 544,
        "filename": "agent544_grand_unified_soundness.md",
        "topic": "Grand Unified Theory of Web Platform Soundness",
        "source": "third_party/blink/renderer/core/page/page.cc",
        "spec": "The Entire Blink Formal Engine Specification (571 Theories)",
        "theory": "BlinkGrandUnifiedTheoryOfWebSoundness.v",
        "math": "Every stage of Blink (DOM, CSS, Layout, Paint, Fetch, Streams, Security, Wasm) executes soundly with zero admits."
    }
]

def run_agent(agent):
    prompt = f"""You are a formal methods expert and Web Platform architect analyzing Chromium Blink's WebAssembly, worklets, scheduling, and grand unified engine pipeline.
Topic: {agent['topic']}
Chromium Source: {agent['source']}
Specification: {agent['spec']}
Formal Theory Target: {agent['theory']}
Mathematical Property: {agent['math']}

Write a comprehensive research report in Markdown covering:
1. Exact normative W3C/WHATWG/WebAssembly specification requirements.
2. Blink implementation details and invariants in {agent['source']}.
3. Formal specification definitions in Rocq/Coq (types, functions, predicates).
4. Concrete theorems with complete, admitted-free Rocq/Coq proofs using ZArith/Lia/Bool.
5. Verification analysis proving 0 admits and preservation of grand unified soundness.

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
            f.write(f"Wave39-Agent{agent['id']},{MODEL_NAME},{prompt_tokens},{cand_tokens},{duration:.2f}\n")
        return True
    except Exception as e:
        print(f"[Agent {agent['id']}] FAILED: {e}")
        return False

print(f"Launching 16 concurrent agents for Wave 39 using {MODEL_NAME}...")
with concurrent.futures.ThreadPoolExecutor(max_workers=16) as executor:
    futures = [executor.submit(run_agent, agent) for agent in AGENTS]
    results = [f.result() for f in concurrent.futures.as_completed(futures)]

print(f"Wave 39 complete: {sum(results)}/16 succeeded.")
