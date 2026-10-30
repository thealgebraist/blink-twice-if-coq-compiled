# Formal Verification of Chromium's Cross-Origin-Embedder-Policy (`require-corp`) Isolation Boundary

**Formal Theory Target:** `BlinkCOEPIsolationEnforcementSemantics.v`  
**Chromium Subsystem:** `services/network/public/cpp/cross_origin_embedder_policy.cc` & `services/network/public/cpp/cross_origin_resource_policy.cc`  
**Normative Specification:** WHATWG HTML Standard §7.4 (Cross-Origin Embedder Policies) & WHATWG Fetch Standard §4.9 (Cross-Origin Resource Policy)  
**Core Mathematical Invariant:** $\text{coep\_blocked} \iff (\text{coep\_require\_corp} \land \neg\text{is\_same\_origin} \land \neg\text{has\_corp})$

---

## 1. Normative Specification Requirements

Cross-Origin-Embedder-Policy (COEP) is a foundational security mechanism designed to mitigate speculative execution side-channel attacks (e.g., Spectre) by allowing an execution context to achieve a `crossOriginIsolated` state. By enforcing COEP, a document guarantees that no cross-origin resources are loaded into its browsing context process without explicit opt-in from the resource owner via either Cross-Origin Resource Sharing (CORS) or Cross-Origin Resource Policy (CORP).

### 1.1 WHATWG HTML Standard §7.4.2 (Embedder Policy Values)
According to HTML Standard §7.4.2, an *embedder policy value* is one of three enumerated states:
1. `"unsafe-none"`: The default policy. No cross-origin embedding restrictions are enforced beyond baseline Web platform rules.
2. `"require-corp"`: The context requires that all loaded cross-origin resources explicitly grant permission via CORP or CORS.
3. `"credentialless"`: Cross-origin `no-cors` requests are sent without credentials, alleviating the need for an explicit CORP header on public resources.

An environment's **embedder policy** consists of two distinct values:
* **Value** (`value`): The actively enforced policy.
* **Report-Only Value** (`report_only_value`): A shadow policy evaluated purely for violation telemetry without blocking network responses.

### 1.2 WHATWG Fetch Standard §4.9 (Cross-Origin Resource Policy Check)
During the **HTTP-network-or-cache fetch** algorithm (Fetch Standard §4.6), every response fetched in `no-cors` mode undergoes the **Cross-Origin-Resource-Policy check** (Fetch Standard §4.9.2). Given an origin $O_{\text{embedder}}$, a response origin $O_{\text{resource}}$, an embedder policy value $P_{\text{coep}}$, and a `Cross-Origin-Resource-Policy` header value $H_{\text{corp}} \in \{\text{None}, \text{same-origin}, \text{same-site}, \text{cross-origin}\}$:

1. **Policy Upgrade Step:** If $H_{\text{corp}} = \text{None}$ and $P_{\text{coep}} = \text{"require-corp"}$ (or `"credentialless"` for credentialed requests), the algorithm upgrades $H_{\text{corp}} \leftarrow \text{same-origin}$.
2. **Evaluation Step:**
   * If $H_{\text{corp}} = \text{None}$ or $H_{\text{corp}} = \text{cross-origin}$, return **allowed**.
   * If $H_{\text{corp}} = \text{same-origin}$:
     * If $O_{\text{embedder}} = O_{\text{resource}}$ (Exact tuple match: scheme, host, port), return **allowed**.
     * Otherwise, return **blocked**.
   * If $H_{\text{corp}} = \text{same-site}$:
     * If $O_{\text{embedder}}$ is *schemelessly same-site* with $O_{\text{resource}}$ and ($O_{\text{embedder}}.\text{scheme} = \text{https}$ or $O_{\text{resource}}.\text{scheme} \neq \text{https}$), return **allowed**.
     * Otherwise, return **blocked**.

### 1.3 Mathematical Reduction to the Core Property
In the strict boundary case where COEP is configured to `require-corp` ($\text{coep\_require\_corp} = \text{true}$) and the resource does not provide an explicit opt-in via a valid CORP header ($\text{has\_corp} = \text{false}$, meaning $H_{\text{corp}} = \text{None}$), the upgrade step forces $H_{\text{corp}} \leftarrow \text{same-origin}$. Consequently, the resource is **blocked** if and only if $O_{\text{embedder}} \neq O_{\text{resource}}$ ($\neg\text{is\_same\_origin}$).

Thus, across the `require-corp` boundary, the normative blocking condition reduces exactly to the Boolean algebraic equivalence:
$$\text{coep\_blocked} = \text{coep\_require\_corp} \land \neg\text{is\_same\_origin} \land \neg\text{has\_corp}$$

---

## 2. Chromium & Blink Implementation Analysis

In Chromium's multi-process architecture, COEP state is parsed and enforced inside the Network Service (`services/network/public/cpp/`) before response payloads are committed to the Blink renderer process (`third_party/blink/renderer/core/loader/`). This prevents cross-origin bytes from ever entering the renderer's address space where they could be read via Spectre gadgets.

### 2.1 Data Structures in `cross_origin_embedder_policy.h` / `.cc`
In `services/network/public/cpp/cross_origin_embedder_policy.h` (backed by Mojo definitions in `services/network/public/mojom/cross_origin_embedder_policy.mojom`), the policy is represented as:

```cpp
namespace network {

enum class mojom::CrossOriginEmbedderPolicyValue {
  kNone,
  kCredentialless,
  kRequireCorp,
};

struct COMPONENT_EXPORT(NETWORK_CPP_BASE) CrossOriginEmbedderPolicy {
  CrossOriginEmbedderPolicy();
  ~CrossOriginEmbedderPolicy();
  
  mojom::CrossOriginEmbedderPolicyValue value =
      mojom::CrossOriginEmbedderPolicyValue::kNone;
  absl::optional<std::string> reporting_endpoint;
  mojom::CrossOriginEmbedderPolicyValue report_only_value =
      mojom::CrossOriginEmbedderPolicyValue::kNone;
  absl::optional<std::string> report_only_reporting_endpoint;
};

} // namespace network
```

In `services/network/public/cpp/cross_origin_embedder_policy.cc`, Chromium implements canonical equality operators and value-default constructors. Meanwhile, the parser (`cross_origin_embedder_policy_parser.cc`) parses the `Cross-Origin-Embedder-Policy` Structured Header (RFC 8941) token item, mapping `"require-corp"` strictly to `mojom::CrossOriginEmbedderPolicyValue::kRequireCorp` and defaulting all unrecognized tokens or malformed headers to `kNone` (fail-safe to default, while `kRequireCorp` fail-closes on missing CORP).

### 2.2 Boundary Enforcement in `cross_origin_resource_policy.cc`
The runtime enforcement of `CrossOriginEmbedderPolicy` occurs in `CrossOriginResourcePolicy::IsBlocked` and its internal helper `IsBlockedInternalWithReporting` located in `services/network/public/cpp/cross_origin_resource_policy.cc`:

```cpp
// Simplified control-flow abstraction of Chromium's IsBlockedInternal
absl::optional<mojom::BlockedByResponseReason> IsBlockedInternal(
    CrossOriginResourcePolicy::ParsedHeader policy,
    const GURL& request_url,
    const absl::optional<url::Origin>& request_initiator,
    mojom::RequestMode request_mode,
    bool request_include_credentials,
    mojom::CrossOriginEmbedderPolicyValue embedder_policy) {

  // 1. CORS requests already enforce explicit Access-Control-Allow-Origin opt-in.
  if (request_mode == mojom::RequestMode::kNavigate)
    return absl::nullopt;

  // 2. COEP "require-corp" upgrades kNoHeader to kSameOrigin.
  const bool upgrade_to_same_origin =
      (embedder_policy == mojom::CrossOriginEmbedderPolicyValue::kRequireCorp) ||
      (embedder_policy == mojom::CrossOriginEmbedderPolicyValue::kCredentialless &&
       request_include_credentials);

  if (policy == CrossOriginResourcePolicy::kNoHeader) {
    if (upgrade_to_same_origin) {
      policy = CrossOriginResourcePolicy::kSameOrigin;
    } else {
      return absl::nullopt; // Allowed
    }
  }

  if (policy == CrossOriginResourcePolicy::kCrossOrigin)
    return absl::nullopt; // Explicit CORP opt-in: Allowed

  // 3. Same-Origin Check
  const url::Origin target_origin = url::Origin::Create(request_url);
  if (request_initiator.has_value() &&
      request_initiator->IsSameOriginWith(target_origin)) {
    return absl::nullopt; // Same-Origin: Allowed
  }

  // 4. Same-Site Check (if policy == kSameSite)
  if (policy == CrossOriginResourcePolicy::kSameSite && 
       ShouldAllowSameSite(request_initiator, target_origin)) {
    return absl::nullopt; // Explicit Same-Site CORP opt-in: Allowed
  }

  // 5. Block the response with exact COEP/CORP telemetry reason.
  if (upgrade_to_same_origin) {
    return mojom::BlockedByResponseReason::
        kCorpNotSameOriginAfterDefaultedToSameOriginByCoep;
  }
  return mojom::BlockedByResponseReason::kCorpNotSameOrigin;
}
```

### 2.3 Key Security Invariants in Chromium
1. **Opaque Origin Non-Reflexivity (`url::Origin`):** In Chromium's `url::Origin::IsSameOriginWith`, two opaque origins (e.g., sandboxed `<iframe>` without `allow-same-origin` or `data:` URLs) are only equal if they share the exact same internal `base::UnguessableToken` nonce. A newly synthesized opaque origin is never same-origin with a tuple origin.
2. **Upgraded Failure Attribution:** When `embedder_policy == kRequireCorp` upgrades `kNoHeader` to `kSameOrigin`, a failure in `IsSameOriginWith` specifically returns `kCorpNotSameOriginAfterDefaultedToSameOriginByCoep`. This isolates pure COEP boundary blocks from explicit CORP blocks (`kCorpNotSameOrigin`).
3. **Dual Evaluation for Report-Only:** Chromium executes `IsBlockedInternal` twice: once against `coep.report_only_value` (emitting a report to `coep.report_only_reporting_endpoint` on failure without aborting the `URLLoader`), and once against `coep.value` (aborting the `URLLoader` with `net::ERR_BLOCKED_BY_RESPONSE` on failure).

---

## 3. Formal Specification in Rocq / Coq

Below is the complete, self-contained formalization of the `BlinkCOEPIsolationEnforcementSemantics` theory in Rocq/Coq. It models both the concrete origin/header state space of Chromium's Network Service and the abstract Boolean algebra of the `require-corp` boundary, proving their exact behavioral isomorphism.

```coq
(** * BlinkCOEPIsolationEnforcementSemantics.v
    Formal Verification of Chromium's Cross-Origin-Embedder-Policy (COEP)
    `require-corp` Isolation Boundary.
    
    Target: services/network/public/cpp/cross_origin_embedder_policy.cc
    Specification: WHATWG HTML Standard §7.4 & Fetch Standard §4.9
*)

From Coq Require Import Bool.Bool.
From Coq Require Import ZArith.ZArith.
From Coq Require Import Lia.

Open Scope bool_scope.
Open Scope Z_scope.

(* ========================================================================== *)
(* SECTION 1: Abstract Security Boundary Model                                *)
(* ========================================================================== *)

(** The core mathematical specification of the COEP require-corp boundary:
    coep_blocked = (coep_require_corp && !is_same_origin && !has_corp) *)
Definition coep_blocked_spec (coep_require_corp is_same_origin has_corp : bool) : bool :=
  coep_require_corp && (negb is_same_origin) && (negb has_corp).

(* ========================================================================== *)
(* SECTION 2: Concrete Chromium Network Service Types                         *)
(* ========================================================================== *)

(** Schemes modeled with integer identifiers; 1 represents HTTPS, 0 HTTP. *)
Inductive Scheme : Type :=
  | SchemeHttp
  | SchemeHttps
  | SchemeOther (id : Z).

Definition scheme_eqb (s1 s2 : Scheme) : bool :=
  match s1, s2 with
  | SchemeHttp, SchemeHttp => true
  | SchemeHttps, SchemeHttps => true
  | SchemeOther i1, SchemeOther i2 => Z.eqb i1 i2
  | _, _ => false
  end.

(** Representation of url::Origin in Chromium.
    Tuple origins have (scheme, host, port, registrable_domain).
    Opaque origins carry a unique UnguessableToken nonce. *)
Inductive Origin : Type :=
  | TupleOrigin (scheme : Scheme) (host : Z) (port : Z) (site : Z)
  | OpaqueOrigin (nonce : Z).

(** Chromium's url::Origin::IsSameOriginWith implementation. *)
Definition is_same_origin_origin (o1 o2 : Origin) : bool :=
  match o1, o2 with
  | TupleOrigin s1 h1 p1 _, TupleOrigin s2 h2 p2 _ =>
      scheme_eqb s1 s2 && Z.eqb h1 h2 && Z.eqb p1 p2
  | OpaqueOrigin n1, OpaqueOrigin n2 =>
      Z.eqb n1 n2
  | _, _ => false
  end.

(** Chromium's ShouldAllowSameSite check in cross_origin_resource_policy.cc *)
Definition is_same_site_allowed (initiator target : Origin) : bool :=
  match initiator, target with
  | TupleOrigin s_init _ _ site_init, TupleOrigin s_target _ _ site_target =>
      Z.eqb site_init site_target &&
      match s_init, s_target with
      | SchemeHttps, _ => true
      | _, SchemeHttps => false (* HTTP cannot embed HTTPS via same-site CORP *)
      | _, _ => true
      end
  | _, _ => false
  end.

(** network::mojom::CrossOriginEmbedderPolicyValue *)
Inductive COEPValue : Type :=
  | COEP_None
  | COEP_Credentialless
  | COEP_RequireCorp.

Definition coep_value_eqb (v1 v2 : COEPValue) : bool :=
  match v1, v2 with
  | COEP_None, COEP_None => true
  