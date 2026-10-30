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
        "id": 513,
        "filename": "agent513_fetch_request_mode.md",
        "topic": "Fetch Request modes and header restrictions",
        "source": "third_party/blink/renderer/core/fetch/request.cc",
        "spec": "Fetch Standard §5.4",
        "theory": "BlinkFetchRequestModeSemantics.v",
        "math": "no-cors mode restricts methods to GET, HEAD, POST; other methods rejected."
    },
    {
        "id": 514,
        "filename": "agent514_headers_guard_filtering.md",
        "topic": "Headers guard state machine",
        "source": "third_party/blink/renderer/core/fetch/headers.cc",
        "spec": "Fetch Standard §2.2",
        "theory": "BlinkFetchHeadersGuardSemantics.v",
        "math": "immutable guard forbids all mutation; request-no-cors allows only safelisted headers."
    },
    {
        "id": 515,
        "filename": "agent515_response_status_bounds.md",
        "topic": "HTTP Response status code bounds and null body",
        "source": "third_party/blink/renderer/core/fetch/response.cc",
        "spec": "Fetch Standard §5.5",
        "theory": "BlinkFetchResponseStatusBoundsSemantics.v",
        "math": "status in [100, 599]; status in {101, 204, 205, 304} has null body."
    },
    {
        "id": 516,
        "filename": "agent516_readable_stream_state.md",
        "topic": "ReadableStream state machine transitions",
        "source": "third_party/blink/renderer/core/streams/readable_stream.cc",
        "spec": "Streams Standard §3.3",
        "theory": "BlinkStreamsReadableStreamStateSemantics.v",
        "math": "closed and errored states are terminal; no further state transitions permitted."
    },
    {
        "id": 517,
        "filename": "agent517_writable_stream_backpressure.md",
        "topic": "WritableStream backpressure signaling",
        "source": "third_party/blink/renderer/core/streams/writable_stream_default_controller.cc",
        "spec": "Streams Standard §4.2",
        "theory": "BlinkStreamsWritableStreamBackpressureSemantics.v",
        "math": "desired_size = high_water_mark - queue_size; backpressure iff desired_size <= 0."
    },
    {
        "id": 518,
        "filename": "agent518_transform_stream_identity.md",
        "topic": "TransformStream pipe throughput conservation",
        "source": "third_party/blink/renderer/core/streams/transform_stream.cc",
        "spec": "Streams Standard §5.2",
        "theory": "BlinkStreamsTransformStreamConservationSemantics.v",
        "math": "identity transform preserves total chunks: chunks_out = chunks_in - queued."
    },
    {
        "id": 519,
        "filename": "agent519_byob_reader_buffer_transfer.md",
        "topic": "BYOB reader buffer detachment & transfer clamping",
        "source": "third_party/blink/renderer/core/streams/readable_byte_stream_controller.cc",
        "spec": "Streams Standard §3.8",
        "theory": "BlinkStreamsBYOBReaderBufferTransferSemantics.v",
        "math": "transferred_bytes <= buffer_byte_length; transferred buffer detached."
    },
    {
        "id": 520,
        "filename": "agent520_cache_storage_match_url.md",
        "topic": "Cache Storage request URL matching",
        "source": "third_party/blink/renderer/modules/cache_storage/cache.cc",
        "spec": "Service Workers §5.4",
        "theory": "BlinkCacheStorageRequestMatchingSemantics.v",
        "math": "cache match satisfies exact URL equality reflexivity and soundness."
    },
    {
        "id": 521,
        "filename": "agent521_cache_control_max_age.md",
        "topic": "HTTP Cache-Control max-age freshness lifetime",
        "source": "net/http/http_response_headers.cc",
        "spec": "RFC 9111 §4.2",
        "theory": "BlinkHTTPCacheFreshnessLifetimeSemantics.v",
        "math": "freshness = max_age - current_age; is_fresh iff freshness > 0."
    },
    {
        "id": 522,
        "filename": "agent522_http_method_idempotence.md",
        "topic": "HTTP Method classification: safe and idempotent",
        "source": "services/network/public/cpp/resource_request.cc",
        "spec": "RFC 9110 §9.2",
        "theory": "BlinkHTTPMethodClassificationSemantics.v",
        "math": "safe(m) -> idempotent(m); GET, HEAD, OPTIONS are safe; PUT, DELETE idempotent."
    },
    {
        "id": 523,
        "filename": "agent523_resource_priority_order.md",
        "topic": "Blink ResourceLoadPriority total ordering",
        "source": "third_party/blink/renderer/platform/loader/fetch/resource_load_priority.h",
        "spec": "Blink Resource Loading §2",
        "theory": "BlinkResourceLoadPriorityOrderSemantics.v",
        "math": "priority rank: VeryLow(0) < Low(1) < Medium(2) < High(3) < VeryHigh(4)."
    },
    {
        "id": 524,
        "filename": "agent524_memory_cache_lru_eviction.md",
        "topic": "Blink MemoryCache LRU monotonic eviction",
        "source": "third_party/blink/renderer/platform/loader/fetch/memory_cache.cc",
        "spec": "Blink Caching Architecture §3",
        "theory": "BlinkMemoryCacheLRUEvictionSemantics.v",
        "math": "evicting entry of size s reduces total cache bytes by s: cache' = cache - s."
    },
    {
        "id": 525,
        "filename": "agent525_websocket_masking_xor.md",
        "topic": "WebSocket client frame masking XOR symmetry",
        "source": "net/websockets/websocket_frame.cc",
        "spec": "RFC 6455 §5.3",
        "theory": "BlinkWebSocketFrameMaskingXORSymmetrySemantics.v",
        "math": "Z.lxor (Z.lxor b k) k = b; XOR masking is an involution."
    },
    {
        "id": 526,
        "filename": "agent526_webtransport_stream_id.md",
        "topic": "WebTransport stream ID classification and multiplexing",
        "source": "third_party/blink/renderer/modules/webtransport/web_transport.cc",
        "spec": "RFC 9000 §2.1",
        "theory": "BlinkWebTransportStreamIDMultiplexSemantics.v",
        "math": "stream_id mod 4 specifies initiator (client/server) and directionality (uni/bidi)."
    },
    {
        "id": 527,
        "filename": "agent527_service_worker_scope_match.md",
        "topic": "Service Worker scope prefix matching",
        "source": "third_party/blink/renderer/modules/service_worker/service_worker_container.cc",
        "spec": "Service Workers §3.1",
        "theory": "BlinkServiceWorkerScopePrefixMatchSemantics.v",
        "math": "request matched by scope iff request path starts with scope prefix."
    },
    {
        "id": 528,
        "filename": "agent528_service_worker_lifecycle.md",
        "topic": "Service Worker registration lifecycle states",
        "source": "content/browser/service_worker/service_worker_version.cc",
        "spec": "Service Workers §3.2",
        "theory": "BlinkServiceWorkerLifecycleStateSemantics.v",
        "math": "monotonic rank: parsed(0) < installing(1) < installed(2) < activating(3) < activated(4) < redundant(5)."
    }
]

def run_agent(agent):
    prompt = f"""You are a formal methods expert and Web Platform networking researcher analyzing Chromium Blink's network fetch, streams, cache, and service worker engines.
Topic: {agent['topic']}
Chromium Source: {agent['source']}
Specification: {agent['spec']}
Formal Theory Target: {agent['theory']}
Mathematical Property: {agent['math']}

Write a comprehensive research report in Markdown covering:
1. Exact normative W3C/WHATWG/IETF specification requirements.
2. Blink implementation details and invariants in {agent['source']}.
3. Formal specification definitions in Rocq/Coq (types, functions, predicates).
4. Concrete theorems with complete, admitted-free Rocq/Coq proofs using ZArith/Lia/Bool.
5. Verification analysis proving 0 admits and preservation of stream, cache, and networking invariants.

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
            f.write(f"Wave38-Agent{agent['id']},{MODEL_NAME},{prompt_tokens},{cand_tokens},{duration:.2f}\n")
        return True
    except Exception as e:
        print(f"[Agent {agent['id']}] FAILED: {e}")
        return False

print(f"Launching 16 concurrent agents for Wave 38 using {MODEL_NAME}...")
with concurrent.futures.ThreadPoolExecutor(max_workers=16) as executor:
    futures = [executor.submit(run_agent, agent) for agent in AGENTS]
    results = [f.result() for f in concurrent.futures.as_completed(futures)]

print(f"Wave 38 complete: {sum(results)}/16 succeeded.")

