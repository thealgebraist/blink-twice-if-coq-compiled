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
        "id": 657,
        "filename": "agent657_file_system_handle_kind.md",
        "topic": "File System Access API handle kind enum semantics",
        "source": "third_party/blink/renderer/modules/file_system_access/file_system_handle.cc",
        "spec": "File System Access API §4 FileSystemHandle.kind {file, directory}",
        "theory": "BlinkFileSystemHandleKindSemantics.v",
        "math": "kind_to_int: distinct enum values for file and directory."
    },
    {
        "id": 658,
        "filename": "agent658_file_system_name_validation.md",
        "topic": "File System Access API name validity and path separator safety",
        "source": "third_party/blink/renderer/modules/file_system_access/file_system_handle.cc",
        "spec": "File System Access API §4 name validation (no path separators or dot-dot)",
        "theory": "BlinkFileSystemNameValidationSemantics.v",
        "math": "is_valid_file_name(name) = non_empty && no_slash && no_backslash && name != '..' && name != '.'."
    },
    {
        "id": 659,
        "filename": "agent659_file_system_writable_seek_clamping.md",
        "topic": "File System Access API writable stream seek non-negative clamping",
        "source": "third_party/blink/renderer/modules/file_system_access/file_system_writable_file_stream.cc",
        "spec": "File System Access API §5 seek(position) non-negative clamp",
        "theory": "BlinkFileSystemWritableSeekClampingSemantics.v",
        "math": "clamp_seek_pos(pos) = max(0, pos)."
    },
    {
        "id": 660,
        "filename": "agent660_file_system_truncate_size.md",
        "topic": "File System Access API truncate size non-negativity",
        "source": "third_party/blink/renderer/modules/file_system_access/file_system_writable_file_stream.cc",
        "spec": "File System Access API §5 truncate(size) must be >= 0",
        "theory": "BlinkFileSystemTruncateSizeSemantics.v",
        "math": "is_valid_truncate(sz) = (sz >= 0)."
    },
    {
        "id": 661,
        "filename": "agent661_file_system_directory_create_idempotence.md",
        "topic": "File System Access API getDirectoryHandle create idempotence",
        "source": "third_party/blink/renderer/modules/file_system_access/file_system_directory_handle.cc",
        "spec": "File System Access API §6 getDirectoryHandle(create: true) idempotence",
        "theory": "BlinkFileSystemDirectoryCreateIdempotenceSemantics.v",
        "math": "create_dir(dir, name) is idempotent on existing entry."
    },
    {
        "id": 662,
        "filename": "agent662_file_system_remove_recursive_safety.md",
        "topic": "File System Access API removeEntry recursive safety check",
        "source": "third_party/blink/renderer/modules/file_system_access/file_system_directory_handle.cc",
        "spec": "File System Access API §6 removeEntry(name, recursive: false) fails on non-empty",
        "theory": "BlinkFileSystemRemoveRecursiveSafetySemantics.v",
        "math": "can_remove(is_empty, recursive) = is_empty || recursive."
    },
    {
        "id": 663,
        "filename": "agent663_sync_access_handle_lock_exclusivity.md",
        "topic": "File System SyncAccessHandle exclusive file locking semantics",
        "source": "third_party/blink/renderer/modules/file_system_access/file_system_sync_access_handle.cc",
        "spec": "File System Access API §7 createSyncAccessHandle exclusive file lock",
        "theory": "BlinkSyncAccessHandleLockExclusivitySemantics.v",
        "math": "acquire_lock(locked) = if locked then None else Some true."
    },
    {
        "id": 664,
        "filename": "agent664_compression_stream_format.md",
        "topic": "Compression Streams format validation semantics",
        "source": "third_party/blink/renderer/modules/compression/compression_stream.cc",
        "spec": "Compression Streams §3 format enum {deflate, gzip, deflate-raw}",
        "theory": "BlinkCompressionStreamFormatSemantics.v",
        "math": "is_valid_format: distinct supported format enum."
    },
    {
        "id": 665,
        "filename": "agent665_decompression_stream_roundtrip.md",
        "topic": "Compression Streams decompression roundtrip length preservation",
        "source": "third_party/blink/renderer/modules/compression/decompression_stream.cc",
        "spec": "Compression Streams §3 roundtrip decompression preserves uncompressed length",
        "theory": "BlinkDecompressionStreamRoundtripSemantics.v",
        "math": "decompress_len(compress(raw)) = raw_len."
    },
    {
        "id": 666,
        "filename": "agent666_crc32_checksum_polynomial.md",
        "topic": "GZIP CRC-32 IEEE 802.3 checksum calculation bounds",
        "source": "third_party/zlib/crc32.c",
        "spec": "RFC 1952 §2.3.1 CRC-32 polynomial 0xEDB88320 non-negative 32-bit",
        "theory": "BlinkCRC32ChecksumPolynomialSemantics.v",
        "math": "0 <= crc32(bytes) < 4294967296."
    },
    {
        "id": 667,
        "filename": "agent667_barcode_detection_format.md",
        "topic": "Shape Detection API BarcodeFormat enum distinctness",
        "source": "third_party/blink/renderer/modules/shape_detection/barcode_detector.cc",
        "spec": "Shape Detection API §3 BarcodeFormat enum",
        "theory": "BlinkBarcodeDetectionFormatSemantics.v",
        "math": "barcode_format_distinct: enum values map to unique integers."
    },
    {
        "id": 668,
        "filename": "agent668_shape_detection_bounding_box.md",
        "topic": "Shape Detection API detected bounding box coordinate positivity",
        "source": "third_party/blink/renderer/modules/shape_detection/shape_detector.cc",
        "spec": "Shape Detection API §3 DOMRectReadOnly bounding box dimensions >= 0",
        "theory": "BlinkShapeDetectionBoundingBoxSemantics.v",
        "math": "rect_valid(r) = (r.width >= 0 /\ r.height >= 0)."
    },
    {
        "id": 669,
        "filename": "agent669_screen_wake_lock_sentinel.md",
        "topic": "Screen Wake Lock API WakeLockSentinel release idempotence",
        "source": "third_party/blink/renderer/modules/wake_lock/wake_lock_sentinel.cc",
        "spec": "Screen Wake Lock API §4 release() sets released to true idempotently",
        "theory": "BlinkScreenWakeLockSentinelSemantics.v",
        "math": "release(state) = released; release(release(state)) = release(state)."
    },
    {
        "id": 670,
        "filename": "agent670_navigation_preload_header_length.md",
        "topic": "Navigation Preload header byte length bounding",
        "source": "third_party/blink/renderer/modules/service_worker/navigation_preload_manager.cc",
        "spec": "Navigation Preload §4 Service-Worker-Navigation-Preload length <= 8192 bytes",
        "theory": "BlinkNavigationPreloadHeaderLengthSemantics.v",
        "math": "is_valid_header_val_len(len) = (0 <= len <= 8192)."
    },
    {
        "id": 671,
        "filename": "agent671_reporting_api_credential_filter.md",
        "topic": "Reporting API URL credential sanitization",
        "source": "third_party/blink/renderer/core/frame/reporting_context.cc",
        "spec": "Reporting API §3 report URL must have username and password stripped",
        "theory": "BlinkReportingAPICredentialFilterSemantics.v",
        "math": "sanitize_url(url) strips userinfo and fragment."
    },
    {
        "id": 672,
        "filename": "agent672_ultimate_totality_of_web_soundness.md",
        "topic": "Ultimate Grand Totality of Web Platform Soundness",
        "source": "third_party/blink/renderer/core/layout/layout_object.cc",
        "spec": "W3C / WHATWG Web Platform Specifications Totality",
        "theory": "BlinkUltimateTotalityOfWebSoundness.v",
        "math": "unification theorem: layout, dom, css, security, media, and hardware are jointly sound."
    }
]

def run_agent(agent):
    prompt = f"""You are formal verification Agent {agent['id']} specializing in Web Platform File System, Streams, Shape Detection, and Platform Totality in Chromium Blink.
Topic: {agent['topic']}
Chromium Source: {agent['source']}
Specification: {agent['spec']}
Formal Theory Target: {agent['theory']}
Mathematical Property: {agent['math']}

Write a comprehensive research report in Markdown covering:
1. Exact normative W3C/WHATWG specification requirements.
2. Blink implementation details and invariants in {agent['source']}.
3. Formal specification definitions in Rocq/Coq (types, functions, predicates).
4. Concrete theorems with complete, admitted-free Rocq/Coq proofs using ZArith/Lia/Bool/List.
5. Verification analysis proving 0 admits and preservation of web platform invariants.

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
            f.write(f"Wave47-Agent{agent['id']},{MODEL_NAME},{prompt_tokens},{cand_tokens},{duration:.2f}\n")
        return True
    except Exception as e:
        print(f"[Agent {agent['id']}] FAILED: {e}")
        return False

print(f"Launching 16 concurrent agents for Wave 47 using {MODEL_NAME}...")
with concurrent.futures.ThreadPoolExecutor(max_workers=16) as executor:
    futures = [executor.submit(run_agent, agent) for agent in AGENTS]
    results = [f.result() for f in concurrent.futures.as_completed(futures)]

print(f"Wave 47 complete: {sum(results)}/16 succeeded.")
