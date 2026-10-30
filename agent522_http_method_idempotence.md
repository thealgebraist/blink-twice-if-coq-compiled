# Formal Verification Report: HTTP Method Classification Semantics in Chromium Blink

## 1. Normative Specification Requirements

The classification of HTTP request methods into *safe* and *idempotent* sets forms the foundational state machine invariant for network caching, speculative prefetching, automatic connection retries, and Cross-Origin Resource Sharing (CORS) preflight calculations across the Web Platform.

### 1.1 IETF RFC 9110 (HTTP Semantics)
* **Section 9.2.1 (Safe Methods)**: Request methods are considered "safe" if their defined semantics are essentially read-only; the client does not request, and does not expect, any state change on the origin server as a result of applying a safe method to a target resource. Formally:
  $$\text{Safe} = \{\text{GET}, \text{HEAD}, \text{OPTIONS}, \text{TRACE}\}$$
* **Section 9.2.2 (Idempotent Methods)**: A request method is considered "idempotent" if the intended effect on the server of multiple identical requests with that method is the same as the effect for a single such request. Formally:
  $$\text{Idempotent} = \text{Safe} \cup \{\text{PUT}, \text{DELETE}\}$$
* **Fundamental Subtyping Invariant**: RFC 9110 §9.2.2 explicitly mandates that all safe methods are idempotent:
  $$\forall m \in \text{Method}, \quad \text{Safe}(m) \implies \text{Idempotent}(m)$$

### 1.2 WHATWG Fetch Living Standard
* **Section 2.2 (Methods)**: Fetch refines the IETF definitions for the browser security model:
  * A **CORS-safelisted method** is a method that is `GET`, `HEAD`, or `POST`.
  * A **forbidden method** is a method that is a byte-case-insensitive match for `CONNECT`, `TRACE`, or `TRACK`.
* Because `TRACE` is a forbidden method in the Fetch specification (to mitigate Cross-Site Tracing attacks), the effective set of safe methods reachable by unprivileged web script execution in Blink is restricted to $\{\text{GET}, \text{HEAD}, \text{OPTIONS}\}$.

---

## 2. Chromium & Blink Implementation Analysis

In Chromium's multiprocess architecture, the boundary between Blink (`third_party/blink/renderer/platform/loader/fetch/`) and the Network Service (`services/network/`) is governed by `network::ResourceRequest` defined in `services/network/public/cpp/resource_request.cc` and `net/http/http_util.cc`.

### 2.1 Source Code Representation
In `services/network/public/cpp/resource_request.cc` and its underlying `net::HttpUtil` primitives (`net/http/http_util.cc`), method classification is implemented via string comparison over canonicalized ASCII method tokens:

```cpp
// net/http/http_util.cc (invoked during ResourceRequest initialization and validation)
bool HttpUtil::IsMethodSafe(std::string_view method) {
  return method == "GET" || method == "HEAD" || method == "OPTIONS" ||
         method == "TRACE";
}

bool HttpUtil::IsMethodIdempotent(std::string_view method) {
  return IsMethodSafe(method) || method == "PUT" || method == "DELETE";
}
```

Within Blink's renderer layer (`third_party/blink/renderer/platform/network/http_parsers.cc` and `fetch_utils.cc`), method normalization occurs prior to populating `network::ResourceRequest::method`:

```cpp
// third_party/blink/renderer/platform/loader/fetch/fetch_utils.cc
bool FetchUtils::IsForbiddenMethod(const String& method) {
  return EqualIgnoringASCIICase(method, " CONNECT") ||
         EqualIgnoringASCIICase(method, "TRACE") ||
         EqualIgnoringASCIICase(method, "TRACK");
}
```

### 2.2 Engine Architectural Invariants
1. **HTTP Cache Invalidation (`net::HttpCache::Transaction`)**: Non-safe methods (`!IsMethodSafe(request.method)`) trigger cache invalidation for the target URI and `Location` / `Content-Location` headers upon receiving a 2xx or 3xx response (RFC 9111 §4.4).
2. **Network Transaction Retries (`net::HttpNetworkTransaction`)**: If a persistent socket (HTTP/1.1 keep-alive or HTTP/2 GOAWAY) closes after a request is written but before response headers are received, the network service will only automatically retry the transaction if `IsMethodIdempotent(request.method)` holds (or if explicit `Idempotency-Key` semantics apply).
3. **Service Worker Fetch Event Routing (`content::ServiceWorkerMainResourceLoader`)**: Safe methods permit stream body teeing optimization and speculative cache lookup without locking underlying storage transactions against concurrent mutations.

---

## 3. Formal Specification in Rocq (Coq)

 below is the complete, self-contained formalization of `BlinkHTTPMethodClassificationSemantics.v`. It models the IETF RFC 9110 method taxonomy, the WHATWG Fetch security filters, and the state machine invariants for Chromium's `ResourceRequest`, HTTP Cache, and Network Retry pipelines.

```coq
(** * BlinkHTTPMethodClassificationSemantics.v
    Formal verification of HTTP Method Classification (RFC 9110 §9.2 & WHATWG Fetch)
    targeting Chromium's services/network/public/cpp/resource_request.cc
*)

From Coq Require Import Bool.Bool.
From Coq Require Import ZArith.ZArith.
From Coq Require Import Strings.String.
From Coq Require Import Lists.List.
From Coq Require Import Micromechanics.Lia.
Import ListNotations.

Open Scope bool_scope.
Open Scope Z_scope.

(** ** 1. Syntax and Domain Definitions *)

(** Exhaustive representation of standard HTTP methods and custom extension tokens *)
Inductive HttpMethod : Type :=
  | GET
  | HEAD
  | OPTIONS
  | TRACE
  | PUT
  | DELETE
  | POST
  | PATCH
  | CONNECT
  | TRACK
  | EXTENSION (token : string).

(** Decidable equality for HttpMethod *)
Definition http_method_eqb (m1 m2 : HttpMethod) : bool :=
  match m1, m2 with
  | GET, GET => true
  | HEAD, HEAD => true
  | OPTIONS, OPTIONS => true
  | TRACE, TRACE => true
  | PUT, PUT => true
  | DELETE, DELETE => true
  | POST, POST => true
  | PATCH, PATCH => true
  | CONNECT, CONNECT => true
  | TRACK, TRACK => true
  | EXTENSION s1, EXTENSION s2 => String.eqb s1 s2
  | _, _ => false
  end.

Lemma http_method_eqb_refl : forall m : HttpMethod,
  http_method_eqb m m = true.
Proof.
  destruct m; simpl; try reflexivity.
  apply String.eqb_refl.
Qed.

Lemma http_method_eqb_eq : forall m1 m2 : HttpMethod,
  http_method_eqb m1 m2 = true <-> m1 = m2.
Proof.
  intros m1 m2; split; intro H.
  - destruct m1, m2; simpl in H; try discriminate; try reflexivity.
    apply String.eqb_eq in H. subst. reflexivity.
  - subst. apply http_method_eqb_refl.
Qed.

(** ** 2. RFC 9110 §9.2 & WHATWG Fetch Classification Functions *)

(** RFC 9110 §9.2.1: Safe Methods
    Matches net::HttpUtil::IsMethodSafe in net/http/http_util.cc *)
Definition is_safe_b (m : HttpMethod) : bool :=
  match m with
  | GET | HEAD | OPTIONS | TRACE => true
  | _ => false
  end.

(** RFC 9110 §9.2.2: Idempotent Methods
    Matches net::HttpUtil::IsMethodIdempotent in net/http/http_util.cc *)
Definition is_idempotent_b (m : HttpMethod) : bool :=
  match m with
  | GET | HEAD | OPTIONS | TRACE | PUT | DELETE => true
  | _ => false
  end.

(** Chromium's structural implementation of IsMethodIdempotent:
    IsMethodSafe(method) || method == "PUT" || method == "DELETE" *)
Definition chromium_is_idempotent_b (m : HttpMethod) : bool :=
  is_safe_b m || http_method_eqb m PUT || http_method_eqb m DELETE.

(** WHATWG Fetch §2.2: Forbidden Methods
    Matches blink::FetchUtils::IsForbiddenMethod *)
Definition is_forbidden_b (m : HttpMethod) : bool :=
  match m with
  | CONNECT | TRACE | TRACK => true
  | _ => false
  end.

(** WHATWG Fetch §2.2: CORS-safelisted Methods
    Matches services/network/public/cpp/cors/cors.cc: IsCorsSafelistedMethod *)
Definition is_cors_safelisted_b (m : HttpMethod) : bool :=
  match m with
  | GET | HEAD | POST => true
  | _ => false
  end.

(** Effective Safe Method in Blink after Fetch Forbidden Method filtering *)
Definition is_blink_fetch_safe_b (m : HttpMethod) : bool :=
  is_safe_b m && negb (is_forbidden_b m).

(** Propositional Predicates *)
Definition Safe (m : HttpMethod) : Prop := is_safe_b m = true.
Definition Idempotent (m : HttpMethod) : Prop := is_idempotent_b m = true.
Definition Forbidden (m : HttpMethod) : Prop := is_forbidden_b m = true.
Definition CorsSafelisted (m : HttpMethod) : Prop := is_cors_safelisted_b m = true.
Definition BlinkFetchSafe (m : HttpMethod) : Prop := is_blink_fetch_safe_b m = true.

(** ** 3. ResourceRequest and Network State Machine Models *)

Record ResourceRequest : Type := mkResourceRequest {
  req_method : HttpMethod;
  req_has_upload_stream : bool;
  req_load_flags : Z;
  req_keepalive : bool
}.

(** Server state modeled as an abstract state version integer *)
Definition ServerState : Type := Z.

(** Abstract semantics of applying a method to a server state.
    - Safe methods produce zero state transition (delta = 0).
    - Idempotent non-safe methods set state to a deterministic target value.
    - Non-idempotent methods increment the state counter on every invocation. *)
Definition apply_method_semantics (m : HttpMethod) (target_val : Z) (s : ServerState) : ServerState :=
  if is_safe_b m then s
  else if is_idempotent_b m then target_val
  else s + 1.

(** Cache Entry State *)
Record CacheEntry : Type := mkCacheEntry {
  cache_valid : bool;
  cache_payload_hash : Z
}.

(** RFC 9111 §4.4: Cache Invalidation upon unsafe method execution *)
Definition update_cache_on_request (m : HttpMethod) (c : CacheEntry) : CacheEntry :=
  if is_safe_b m then c
  else mkCacheEntry false (cache_payload_hash c).

(** Network Transaction Retry Policy in services/network/ *)
Definition can_retry_after_connection_close (req : ResourceRequest) : bool :=
  is_idempotent_b (req_method req) && negb (req_has_upload_stream req).
```

---

## 4. Concrete Theorems and Complete Proofs

The following Rocq module continues directly from the specification above and proves the core mathematical properties required for the verification target, alongside operational behavioral theorems for Chromium's cache, stream, and retry engines.

```coq
(** ** 4. Formal Verification of Taxonomic and Operational Invariants *)

(** Theorem 1: Fundamental Subtyping Invariant (RFC 9110 §9.2.2)
    safe(m) -> idempotent(m) *)
Theorem safe_implies_idempotent : forall m : HttpMethod,
  Safe m -> Idempotent m.
Proof.
  intros m Hsafe.
  unfold Safe in Hsafe.
  unfold Idempotent.
  destruct m; simpl in *; try reflexivity; try discriminate.
Qed.

(** Boolean reflection version of Theorem 1 *)
Theorem safe_b_implies_idempotent_b : forall m : HttpMethod,
  is_safe_b m = true -> is_idempotent_b m = true.
Proof.
  exact safe_implies_idempotent.
Qed.

(** Theorem 2: Equivalence of Specification Idempotency and Chromium's Implementation *)
Theorem chromium_idempotent_equiv : forall m : HttpMethod,
  chromium_is_idempotent_b m = is_idempotent_b m.
Proof.
  intro m.
  unfold chromium_is_idempotent_b.
  destruct m; simpl; reflexivity.
Qed.

(** Theorem 3: Concrete Method Classifications (GET, HEAD, OPTIONS are safe; PUT, DELETE idempotent) *)
Theorem concrete_method_classifications :
  Safe GET /\
  Safe HEAD /\
  Safe OPTIONS /\
  Idempotent PUT /\
  Idempotent DELETE /\
  ~ Safe PUT /\
  ~ Safe DELETE /\
  ~ Idempotent POST /\
  ~ Idempotent PATCH.
Proof.
  unfold Safe, Idempotent, not.
  repeat split; simpl; intros H; try discriminate.
Qed.

(** Theorem 4: Exact Characterization of Blink Fetch-Safe Methods
    Proves that after WHATWG Fetch forbidden method filtering, the set of safe methods
    is exactly {GET, HEAD, OPTIONS}. *)
Theorem blink_fetch_safe_characterization : forall m : HttpMethod,
  BlinkFetchSafe m <-> (m = GET \/ m = HEAD \/ m = OPTIONS).
Proof.
  intro m; unfold BlinkFetchSafe, is_blink_fetch_safe_b; split; intro H.
  - destruct m; simpl in H; try discriminate.
    + left; reflexivity.
    + right; left; reflexivity.
    + right; right; reflexivity.
  - destruct H as [H | [H | H]]; subst; simpl; reflexivity.
Qed.

(** Theorem 5: Operational Read-Only Semantics of Safe Methods
    Applying any safe method preserves the exact server state (delta = 0). *)
Theorem safe_method_preserves_server_state : forall (m : HttpMethod) (target : Z) (s : ServerState),
  Safe m ->
  apply_method_semantics m target s = s.
Proof.
  intros m target s Hsafe.
  unfold apply_method_semantics, Safe in *.
  rewrite Hsafe.
  reflexivity.
Qed.

(** Theorem 6: Operational Idempotence of Idempotent Methods
    Applying an idempotent method N >= 1 times yields the exact same server state
    as applying it once. *)
Theorem idempotent_method_operational_idempotence :
  forall (m : HttpMethod) (target : Z) (s : ServerState),
  Idempotent m ->
