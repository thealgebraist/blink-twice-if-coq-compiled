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
        "id": 497,
        "filename": "agent497_same_origin_tuple.md",
        "topic": "Same-origin tuple equivalence (protocol, host, port)",
        "source": "services/network/public/cpp/origin.cc",
        "spec": "HTML Standard §7.5 / RFC 6454",
        "theory": "BlinkOriginSameOriginTupleSemantics.v",
        "math": "Tuple equivalence (scheme1 = scheme2 /\\ host1 = host2 /\\ port1 = port2) is reflexive, symmetric, and transitive."
    },
    {
        "id": 498,
        "filename": "agent498_opaque_origin_unique.md",
        "topic": "Opaque origin uniqueness",
        "source": "services/network/public/cpp/origin.cc",
        "spec": "HTML Standard §7.5",
        "theory": "BlinkOriginOpaqueUniquenessSemantics.v",
        "math": "Every newly allocated opaque origin has a distinct unique nonce id: id1 <> id2 -> opaque_origin(id1) <> opaque_origin(id2)."
    },
    {
        "id": 499,
        "filename": "agent499_url_canonicalization_port.md",
        "topic": "URL default port elision during canonicalization",
        "source": "url/url_canon_stdurl.cc",
        "spec": "WHATWG URL Standard §4.2",
        "theory": "BlinkURLDefaultPortCanonicalizationSemantics.v",
        "math": "canonicalize_port(http, 80) = default_port; canonicalize_port(https, 443) = default_port; non-default ports are preserved."
    },
    {
        "id": 500,
        "filename": "agent500_storage_quota_bounding.md",
        "topic": "LocalStorage / Storage Quota Bounding",
        "source": "storage/browser/quota/quota_manager_impl.cc",
        "spec": "Storage Standard §3",
        "theory": "BlinkStorageQuotaBoundingSemantics.v",
        "math": "written_size(curr + delta) <= quota iff curr + delta <= quota; rejected writes preserve curr <= quota."
    },
    {
        "id": 501,
        "filename": "agent501_idb_key_range_interval.md",
        "topic": "IndexedDB IDBKeyRange interval containment",
        "source": "third_party/blink/renderer/modules/indexeddb/idb_key_range.cc",
        "spec": "IndexedDB 3 §4",
        "theory": "BlinkIDBKeyRangeIntervalSemantics.v",
        "math": "in_range(k, lower, upper) = (lower <= k /\\ k <= upper) for closed bounds."
    },
    {
        "id": 502,
        "filename": "agent502_idb_cursor_direction.md",
        "topic": "IndexedDB IDBCursor direction monotonicity",
        "source": "third_party/blink/renderer/modules/indexeddb/idb_cursor.cc",
        "spec": "IndexedDB 3 §5",
        "theory": "BlinkIDBCursorMonotonicitySemantics.v",
        "math": "cursor_next(key) > key for 'next'; cursor_prev(key) < key for 'prev'."
    },
    {
        "id": 503,
        "filename": "agent503_cookie_domain_path_matching.md",
        "topic": "Cookie domain and path prefix matching",
        "source": "net/cookies/cookie_monster.cc",
        "spec": "RFC 6265bis §5.4",
        "theory": "BlinkCookieDomainPathMatchingSemantics.v",
        "math": "cookie path matching is prefix matching on directory boundaries: path_match('/foo', '/foo/bar') = true."
    },
    {
        "id": 504,
        "filename": "agent504_csp_directive_intersection.md",
        "topic": "Content Security Policy directive list intersection",
        "source": "third_party/blink/renderer/core/frame/csp/content_security_policy.cc",
        "spec": "CSP Level 3 §4",
        "theory": "BlinkCSPDirectiveIntersectionSemantics.v",
        "math": "effective_csp(p1, p2) allows action iff both p1 allows and p2 allows (monotonically stricter)."
    },
    {
        "id": 505,
        "filename": "agent505_csp_nonce_matching.md",
        "topic": "CSP script-src nonce matching soundness",
        "source": "third_party/blink/renderer/core/frame/csp/csp_directive_list.cc",
        "spec": "CSP Level 3 §5",
        "theory": "BlinkCSPNonceMatchingSemantics.v",
        "math": "nonce_matches(source_nonce, script_nonce) = (source_nonce =? script_nonce)."
    },
    {
        "id": 506,
        "filename": "agent506_csp_host_wildcard.md",
        "topic": "CSP host source wildcard matching",
        "source": "third_party/blink/renderer/core/frame/csp/source_list_directive.cc",
        "spec": "CSP Level 3 §6",
        "theory": "BlinkCSPHostSourceWildcardSemantics.v",
        "math": "wildcard match (*.domain.com) matches any subdomain depth >= 1."
    },
    {
        "id": 507,
        "filename": "agent507_permissions_policy_delegation.md",
        "topic": "Permissions Policy feature delegation",
        "source": "third_party/blink/renderer/core/permissions_policy/permissions_policy.cc",
        "spec": "Permissions Policy §4",
        "theory": "BlinkPermissionsPolicyDelegationSemantics.v",
        "math": "iframe_feature_allowed = parent_allowed && delegated_in_allow_attribute."
    },
    {
        "id": 508,
        "filename": "agent508_coep_isolation_check.md",
        "topic": "Cross-Origin-Embedder-Policy (COEP) require-corp boundary check",
        "source": "services/network/public/cpp/cross_origin_embedder_policy.cc",
        "spec": "HTML Standard §7.4",
        "theory": "BlinkCOEPIsolationEnforcementSemantics.v",
        "math": "coep_blocked = (coep_require_corp && !is_same_origin && !has_corp)."
    },
    {
        "id": 509,
        "filename": "agent509_coop_browsing_context_group.md",
        "topic": "Cross-Origin-Opener-Policy (COOP) browsing context group switch",
        "source": "content/browser/renderer_host/cross_origin_opener_policy_status.cc",
        "spec": "HTML Standard §7.4",
        "theory": "BlinkCOOPBrowsingContextGroupSwitchSemantics.v",
        "math": "coop_swap = (coop_same_origin && !same_origin_opener)."
    },
    {
        "id": 510,
        "filename": "agent510_cross_origin_window_proxy.md",
        "topic": "Cross-origin window proxy restricted property access",
        "source": "third_party/blink/renderer/core/frame/dom_window.cc",
        "spec": "HTML Standard §7.2",
        "theory": "BlinkCrossOriginWindowProxyRestrictionsSemantics.v",
        "math": "property_accessible(prop, is_cross_origin) = (!is_cross_origin || is_safelisted(prop))."
    },
    {
        "id": 511,
        "filename": "agent511_iframe_sandbox_flags.md",
        "topic": "Iframe sandbox flags bitmask accumulation",
        "source": "third_party/blink/renderer/core/html/html_iframe_element.cc",
        "spec": "HTML Standard §4.8.5",
        "theory": "BlinkIFrameSandboxBitmaskSemantics.v",
        "math": "has_flag(mask | flag, flag) = true; bitwise OR preserves existing flags."
    },
    {
        "id": 512,
        "filename": "agent512_cors_preflight_origin.md",
        "topic": "CORS preflight header validation",
        "source": "services/network/cors/cors_url_loader.cc",
        "spec": "Fetch Standard §3.2",
        "theory": "BlinkCORSPreflightOriginMatchSemantics.v",
        "math": "cors_origin_allowed(req_origin, allow_header) = (allow_header == '*' || allow_header == req_origin)."
    }
]

def run_agent(agent):
    prompt = f"""You are a formal methods expert and Web Platform security researcher analyzing Chromium Blink's security, origin, cookie, and storage boundary engine.
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
5. Verification analysis proving 0 admits and preservation of security bounds.

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
            f.write(f"Wave37-Agent{agent['id']},{MODEL_NAME},{prompt_tokens},{cand_tokens},{duration:.2f}\n")
        return True
    except Exception as e:
        print(f"[Agent {agent['id']}] FAILED: {e}")
        return False

print(f"Launching 16 concurrent agents for Wave 37 using {MODEL_NAME}...")
with concurrent.futures.ThreadPoolExecutor(max_workers=16) as executor:
    futures = [executor.submit(run_agent, agent) for agent in AGENTS]
    results = [f.result() for f in concurrent.futures.as_completed(futures)]

print(f"Wave 37 complete: {sum(results)}/16 succeeded.")
