# Formal Analysis of CORS Preflight Origin Validation in Chromium's Network Service

**Author:** Formal Methods & Web Platform Security Research Group  
**Target Component:** `services/network/cors/cors_url_loader.cc` (and helper `services/network/public/cpp/cors/cors.cc`)  
**Specification:** WHATWG Fetch Standard §3.2 (CORS protocol) & §4.9 (CORS check)  
**Formal Artifact:** `BlinkCORSPreflightOriginMatchSemantics.v`  

---

## 1. Normative Specification Requirements

The Cross-Origin Resource Sharing (CORS) protocol, defined in the WHATWG Fetch Standard, governs how a user agent permits scripts running inside a web origin to interact with resources hosted on a distinct origin. When a cross-origin request uses non-safelisted methods (e.g., `PUT`, `DELETE`) or non-safelisted headers, the user agent must execute a **CORS-preflight fetch** before transmitting the actual request.

### 1.1 WHATWG Fetch Standard §3.2.2 & §4.9 (CORS Check)
According to the Fetch Standard (§4.9 "CORS check" and §4.7 "CORS-preflight fetch-0"), given a `request` (containing a serialized `origin` header value $O_{req}$ and a `credentials mode` $C_{mode}$) and a `response` (containing the `Access-Control-Allow-Origin` header value $H_{acao}$), the validation steps are strictly defined as follows:

1. Let `origin` be the result of extracting header list values given `` `Access-Control-Allow-Origin` `` and `response`’s header list.
2. If `origin` is null, or `origin` contains more than one item, then return failure.
3. If `request`’s credentials mode is not `"include"` and `origin` is `` `*` ``, then return success.
4. If **[ASCII serialization of an origin](https://html.spec.whatwg.org/multipage/origin.html#ascii-serialisation-of-an-origin)** of `request`’s `origin` is not `origin` (byte-for-byte exact match), then return failure.
5. If `request`’s credentials mode is `"include"` and `origin` is `` `*` ``, then return failure. *(Note: Step 4 implicitly rejects `*` if credentials mode is `"include"` unless the serialized request origin were literally `*`, which is impossible for a valid tuple or opaque origin serialization `null`. However, the specification calls out the wildcard restriction explicitly).*
6. Return success.

### 1.2 Opaque Origin and `"null"` Serialization Nuances
In the HTML Standard, an **opaque origin** (such as a sandboxed `<iframe>` without `allow-same-origin` or a `data:` URL) serializes to the ASCII string `"null"`. 
* If a request originates from an opaque origin, its `Origin` request header is `"null"`.
* Under the baseline mathematical property `cors_origin_allowed(req_origin, allow_header) = (allow_header == '*' || allow_header == req_origin)`, if `req_origin` is serialized to `"null"` and the server responds with `Access-Control-Allow-Origin: null`, the equality check holds.
* Crucially, if the origin is an invalid/uninitialized URL that cannot be serialized, or if multiple `Access-Control-Allow-Origin` headers are merged via commas, the check must fail unconditionally.

---

## 2. Chromium Implementation Details and Invariants

In modern Chromium (post-Network Service architectural migration), CORS preflight orchestration and header validation were moved out of Blink's `blink::DocumentThreadableLoader` into the out-of-process Network Service: specifically within `services/network/cors/cors_url_loader.cc`, `services/network/cors/preflight_controller.cc`, and `services/network/public/cpp/cors/cors.cc`.

### 2.1 Execution Path in `cors_url_loader.cc`
When `CorsURLLoader::StartRequest()` intercepts a cross-origin request requiring a CORS check:

1. **Preflight Evaluation:** `CorsURLLoader::NeedsPreflight(request_)` determines whether a preflight `OPTIONS` request is required.
2. **Preflight Dispatch:** If needed, `PreflightController::PerformPreflightCheck` sends the `OPTIONS` request and receives the preflight response.
3. **Header Validation (`CheckAccess`):** Both the preflight response and the subsequent actual response pass through `cors::CheckAccess` (implemented in `services/network/public/cpp/cors/cors.cc` and invoked by `CorsURLLoader::CheckAccessAndReportMetrics` and `PreflightController::CreatePreflightResult`).

### 2.2 Core Implementation Logic (`CheckAccessInternal`)
The implementation of `CheckAccessInternal` enforces the exact origin-matching invariant:

```cpp
// Conceptual representation of services/network/public/cpp/cors/cors.cc
base::expected<void, CorsErrorStatus> CheckAccessInternal(
    const GURL& response_url,
    const std::optional<std::string>& allow_origin_header,
    const std::optional<std::string>& allow_credentials_header,
    mojom::CredentialsMode credentials_mode,
    const url::Origin& origin) {
  
  if (allow_origin_header == kAsterisk) {
    // A wildcard Access-Control-Allow-Origin is allowed only when
    // credentials mode is not kInclude.
    if (credentials_mode != mojom::CredentialsMode::kInclude)
      return base::ok();
    
    // Exception for non-HTTP/HTTPS or specific internal schemes omitted,
    // standard web traffic rejects wildcard with credentials:
    return base::unexpected(
        CorsErrorStatus(mojom::CorsError::kWildcardOriginNotAllowed));
  }

  if (!allow_origin_header) {
    return base::unexpected(
        CorsErrorStatus(mojom::CorsError::kMissingAllowOriginHeader));
  }

  // If the origin is opaque, its serialization is "null".
  // url::Origin::Serialize() returns "null" for opaque origins,
  // or "scheme://host[:port]" for tuple origins.
  if (*allow_origin_header != origin.Serialize()) {
    // Check for comma-separated list of origins to emit a more specific error
    if (allow_origin_header->find(',') != std::string::npos) {
      return base::unexpected(
          CorsErrorStatus(mojom::CorsError::kMultipleAllowOriginValues));
    }
    // Check if it's a valid URL just for diagnostic error reporting
    if (!GURL(*allow_origin_header).is_valid()) {
      return base::unexpected(
          CorsErrorStatus(mojom::CorsError::kInvalidAllowOriginValue));
    }
    return base::unexpected(
        CorsErrorStatus(mojom::CorsError::kAllowOriginMismatch));
  }

  // Additional Check: Access-Control-Allow-Credentials
  if (credentials_mode == mojom::CredentialsMode::kInclude &&
      allow_credentials_header != kLowerCaseTrue) {
    return base::unexpected(
        CorsErrorStatus(mojom::CorsError::kInvalidAllowCredentials));
  }

  return base::ok();
}
```

### 2.3 Security Invariants in `cors_url_loader.cc`
1. **Invariant 1 (No Substring or Suffix Matching):** Origin validation uses strict `std::string::operator!=` against `origin.Serialize()`. There is no regex, globbing, or suffix matching (unlike `document.domain` or cookie domain matching).
2. **Invariant 2 (Single-Origin Serialization Bound):** Because `url::Origin::Serialize()` produces a canonical ASCII string without spaces or commas (either `scheme://host[:port]` or `"null"`), and `origin.Serialize()` can never output `"*"`, the sets of headers matching `*` and matching `origin.Serialize()` are strictly disjoint.
3. **Invariant 3 (Wildcard Disallowance under Credentials):** When `credentials_mode == kInclude`, `allow_origin_header == "*"` is unconditionally rejected before reaching the `origin.Serialize()` comparison. Even if it fell through, `origin.Serialize()` is never `"*"`, preserving rejection.

---

## 3. Formal Specification in Rocq / Coq

Below is the complete, self-contained formalization of the CORS Origin Match semantics (`BlinkCORSPreflightOriginMatchSemantics.v`). It models both the pure uncredentialed origin-matching property specified in the prompt and the full credential-aware state machine implemented in Chromium's `cors_url_loader.cc`.

```coq
(** * BlinkCORSPreflightOriginMatchSemantics.v
    Formal verification of CORS Preflight Origin Validation in Chromium.
    Target: services/network/cors/cors_url_loader.cc & cors.cc
    Specification: WHATWG Fetch Standard §3.2 & §4.9
*)

From Coq Require Import Bool.Bool.
From Coq Require Import ZArith.ZArith.
From Coq Require Import Micega.Lia.
From Coq Require Import Lists.List.
Import ListNotations.

Open Scope Z_scope.
Open Scope bool_scope.

(** ** 1. Fundamental Domain Models *)

(** We represent strings/serialized origins as integer identifiers (Z)
    with distinguished constants for the wildcard '*' (1), the serialized
    opaque origin 'null' (2), and invalid/comma-separated values (< 0).
    Valid tuple origins are represented by Z values >= 10. *)

Definition SerializedString := Z.

Definition STR_WILDCARD : SerializedString := 1.
Definition STR_NULL     : SerializedString := 2.

(** A well-formed serialized request origin from `url::Origin::Serialize()`
    is either "null" (for opaque origins) or a canonical tuple (>= 10).
    Crucially, `url::Origin::Serialize()` NEVER produces "*". *)
Definition wf_serialized_origin (s : SerializedString) : Prop :=
  s = STR_NULL \/ s >= 10.

(** Request Origin structured representation *)
Inductive Origin : Type :=
  | OpaqueOrigin (nonce : Z)
  | TupleOrigin (id : Z).

(** Valid tuple origins have IDs >= 10 *)
Definition wf_origin (o : Origin) : Prop :=
  match o with
  | OpaqueOrigin _ => True
  | TupleOrigin id => id >= 10
  end.

(** Chromium's `url::Origin::Serialize()` method *)
Definition serialize_origin (o : Origin) : SerializedString :=
  match o with
  | OpaqueOrigin _ => STR_NULL
  | TupleOrigin id => id
  end.

(** Credentials Mode per WHATWG Fetch Standard *)
Inductive CredentialsMode : Type :=
  | CredOmit
  | CredSameOrigin
  | CredInclude.

Definition cred_mode_eqb (c1 c2 : CredentialsMode) : bool :=
  match c1, c2 with
  | CredOmit, CredOmit => true
  | CredSameOrigin, CredSameOrigin => true
  | CredInclude, CredInclude => true
  | _, _ => false
  end.

(** Optional Header representation *)
Inductive OptionalHeader : Type :=
  | HeaderMissing
  | HeaderPresent (val : SerializedString).

(** Chromium `mojom::CorsError` subset relevant to Origin matching *)
Inductive CorsOriginError : Type :=
  | ErrMissingAllowOriginHeader
  | ErrWildcardOriginNotAllowed
  | ErrAllowOriginMismatch
  | ErrInvalidAllowCredentials.

Inductive CorsCheckResult : Type :=
  | CorsOk
  | CorsFailed (err : CorsOriginError).

(** ** 2. Mathematical Specification Property (Baseline & Credentialed) *)

(** Target Mathematical Property (Exact uncredentialed origin match predicate):
    cors_origin_allowed(req_origin, allow_header) =
      (allow_header == '*' || allow_header == req_origin) *)
Definition cors_origin_allowed (req_origin allow_header : SerializedString) : bool :=
  (allow_header =? STR_WILDCARD) || (allow_header =? req_origin).

(** Full WHATWG Fetch §4.9 CORS Check Specification Predicate *)
Definition spec_cors_check (req_origin : SerializedString)
                           (cred_mode : CredentialsMode)
                           (acao_header : OptionalHeader)
                           (acac_true : bool) : bool :=
  match acao_header with
  | HeaderMissing => false
  | HeaderPresent allow_header =>
      match cred_mode with
      | CredInclude =>
          (* Wildcard is forbidden when credentials mode is "include".
             Also requires Access-Control-Allow-Credentials: true *)
          negb (allow_header =? STR_WILDCARD) &&
          (allow_header =? req_origin) &&
          acac_true
      | CredOmit | CredSameOrigin =>
          cors_origin_allowed req_origin allow_header
      end
  end.

(** ** 3. Chromium Implementation Model (`CheckAccessInternal`) *)

Definition blink_check_access_internal (o : Origin)
                                       (cred_mode : CredentialsMode)
                                       (acao_header : OptionalHeader)
                                       (acac_true : bool) : CorsCheckResult :=
  match acao_header with
  | HeaderPresent allow_header =>
      if allow_header =? STR_WILDCARD then
        if negb (cred_mode_eqb cred_mode CredInclude) then
          CorsOk
        else
          CorsFailed ErrWildcardOriginNotAllowed
      else
        if negb (allow_header =? serialize_origin o) then
          CorsFailed ErrAllowOriginMismatch
        else
          if cred_mode_eqb cred_mode CredInclude && negb acac_true then
            CorsFailed ErrInvalidAllowCredentials
          else
            CorsOk
  | HeaderMissing =>
      CorsFailed ErrMissingAllowOriginHeader
  end.

Definition is_cors_ok (res : CorsCheckResult) : bool :=
  match res with
  | CorsOk => true
  | CorsFailed _ => false
  end.
```

---

## 4. Concrete Theorems and Complete Proofs

The following Coq module continues directly from Section 3 and proves the core functional correctness, equivalence, and security isolation properties with zero `Admitted` statements.

```coq
(** ** 4. Formal Verification & Security Proofs *)

(** Lemma 1: Any well-formed Origin serializes to a well-formed SerializedString. *)
Lemma serialize_wf_origin : forall (o : Origin),
  wf_origin o ->
  wf_serialized_origin (serialize_origin o).
Proof.
  intros o Hwf.
  destruct o as [nonce | id]; simpl in *.
  - left. reflexivity.
  - right. exact Hwf.
Qed.

(** Lemma 2: A well-formed serialized origin is NEVER equal to the wildcard '*'.
    This proves Invariant 2: `origin.Serialize() != "*"` for all valid origins. *)
Lemma wf_origin_never_wildcard : forall (o : Origin),
  wf_origin o ->
  (serialize_origin o =? STR_WILDCARD) = false.
Proof.
  intros o Hwf.
  apply serialize_wf_origin in Hwf.
  un