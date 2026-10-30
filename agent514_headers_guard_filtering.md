# Formal Verification of the Chromium Blink Fetch Headers Guard State Machine

**Target Implementation:** `third_party/blink/renderer/core/fetch/headers.cc`  
**Normative Specification:** WHATWG Fetch Standard §2.2 (Headers) and §5.1 (Headers class)  
**Formal Theory Target:** `BlinkFetchHeadersGuardSemantics.v`  
**Verified Property:** The `immutable` guard strictly forbids all header list mutations; the `request-no-cors` guard restricts mutations to CORS-safelisted request headers under strict global privilege-escalation budgets; and all guards preserve syntactic header invariants across `append`, `delete`, and `set` transitions.

---

## 1. Normative Specification Requirements (WHATWG Fetch Standard)

According to the WHATWG Fetch Standard (§2.2 and §5.1), a `Headers` object encapsulates an underlying **header list** and an associated **guard**. The guard acts as a state-machine access control mechanism that prevents cross-origin privilege escalation, response tampering in Service Workers, and header injection during `no-cors` fetches.

### 1.1 Header Guard States
Every `Headers` instance has an associated guard holding one of five mutually exclusive values:
1. **`none`**: Default state for developer-constructed `new Headers()` instances. All syntactically valid header names and values are permitted.
2. **`request`**: Associated with `Request` objects not in `no-cors` mode. Forbids mutations to any **forbidden request-header** (e.g., `Host`, `Cookie`, `Sec-*`, `Proxy-*`, or method-override headers containing unsafe methods).
3. **`request-no-cors`**: Associated with `Request` objects whose mode is `"no-cors"`. Mutations are ignored (no-op) unless the header name and value satisfy the **no-CORS-safelisted request-header** predicate, and the cumulative length of no-CORS-safelisted headers does not exceed 1024 bytes.
4. **`response`**: Associated with mutable `Response` objects (e.g., synthetic responses constructed in a Service Worker). Forbids mutations to any **forbidden response-header name** (`Set-Cookie`, `Set-Cookie2`).
5. **`immutable`**: Associated with network-fetched `Response` objects, Cache API responses, and Service Worker fetch event requests. Any attempt to mutate (`append`, `delete`, `set`) throws a `TypeError`.

### 1.2 Normative Mutation Algorithms
The Fetch Standard (§5.1) defines the exact operational semantics for `append(name, value)`, `delete(name)`, and `set(name, value)`:

* **`validate(name, value)`**:
  1. Normalize `value` by stripping leading and trailing HTTP whitespace (`0x09`, `0x0A`, `0x0D`, `0x20`).
  2. If `name` is not a valid HTTP header name (RFC 9110 `token`) or `value` is not a valid HTTP header value, throw a `TypeError`.
  3. If `guard` is `immutable`, throw a `TypeError`.
  4. If `guard` is `request` and `(name, value)` is a forbidden request-header, return `false`.
  5. If `guard` is `response` and `name` is a forbidden response-header name, return `false`.
  6. Return `true`.

* **`append(name, value)`**:
  1. Run `validate(name, value)`. If it throws, rethrow; if it returns `false`, return (silent no-op).
  2. If `guard` is `request-no-cors`:
     * Let `temporaryValue` be the result of getting `name` from the header list.
     * If `temporaryValue` is null, set it to `value`; otherwise append `", "` followed by `value` to `temporaryValue`.
     * If `(name, temporaryValue)` is not a no-CORS-safelisted request-header, return (silent no-op).
  3. Append `(name, value)` to the header list.
  4. If `guard` is `request-no-cors`, remove privileged no-CORS request-headers (`Range`).

* **`delete(name)`**:
  1. Normalize and validate `name` as an HTTP header name; if invalid, throw `TypeError`.
  2. If `guard` is `immutable`, throw `TypeError`.
  3. If `guard` is `request` and `(name, "")` is a forbidden request-header, return.
  4. If `guard` is `request-no-cors`, and `name` is not a no-CORS-safelisted request-header name and `name` is not a privileged no-CORS request-header name, return.
  5. If `guard` is `response` and `name` is a forbidden response-header name, return.
  6. If the header list does not contain `name`, return.
  7. Delete `name` from the header list.
  8. If `guard` is `request-no-cors`, remove privileged no-CORS request-headers.

* **`set(name, value)`**:
  1. Run `validate(name, value)`. If it throws, rethrow; if it returns `false`, return.
  2. If `guard` is `request-no-cors` and `(name, value)` is not a no-CORS-safelisted request-header, return.
  3. Set `(name, value)` in the header list.
  4. If `guard` is `request-no-cors`, remove privileged no-CORS request-headers.

---

## 2. Chromium Blink Implementation Analysis

In Chromium (`third_party/blink/renderer/core/fetch/headers.cc` and `headers.h`), the `blink::Headers` class implements the WebIDL `Headers` interface, backed by `blink::FetchHeaderList`.

### 2.1 Guard Representation and State Machine
In `third_party/blink/renderer/core/fetch/headers.h`, the guard state is represented by the scoped enumeration `Headers::Guard`:
```cpp
enum Guard {
  kImmutableGuard,
  kRequestGuard,
  kRequestNoCorsGuard,
  kResponseGuard,
  kNoneGuard
};
```
The guard is initialized in the `Headers` constructors (defaulting to `kNoneGuard` for `Headers::Create(ExceptionState&)`, or configured explicitly by `Request::Create` and `Response::Create` via `Headers::SetGuard(Guard)`).

### 2.2 Mutation Pipeline in `headers.cc`
Blink's implementation of `Headers::append`, `Headers::remove` (the C++ binding for WebIDL `delete`), and `Headers::set` strictly mirrors the Fetch Standard state machine:

1. **Normalization & Syntax Validation:**
   `FetchUtils::NormalizeHeaderValue(value)` strips HTTP whitespace. `FetchHeaderList::IsValidHeaderName(name)` and `FetchHeaderList::IsValidHeaderValue(normalized_value)` verify RFC 9110 token and field-value grammars. If either check fails, `exception_state.ThrowTypeError(...)` is invoked and execution halts immediately.

2. **Immutable Guard Enforcement:**
   ```cpp
   if (guard_ == kImmutableGuard) {
     exception_state.ThrowTypeError("Headers are immutable");
     return;
   }
   ```
   This check occurs unconditionally before any branch that accesses or mutates `header_list_`.

3. **Request and Response Guard Filtering:**
   * Under `kRequestGuard`: `cors::IsForbiddenHeaderName(name)` or `cors::IsForbiddenRequestHeader(name, normalized_value)` returns `true` for forbidden headers, causing the method to `return` silently without mutating `header_list_`.
   * Under `kResponseGuard`: `cors::IsForbiddenResponseHeaderName(name)` returns `true` for `Set-Cookie` and `Set-Cookie2` (ASCII case-insensitively), returning silently without mutating `header_list_`.

4. **`kRequestNoCorsGuard` Enforcement & Combined Value Check:**
   In `Headers::append`, Blink computes the prospective combined header value before checking the CORS safelist:
   ```cpp
   if (guard_ == kRequestNoCorsGuard) {
     String temp_value;
     header_list_->Get(name, temp_value);
     if (temp_value.IsNull())
       temp_value = normalized_value;
     else
       temp_value = temp_value + ", " + normalized_value;
     if (!cors::IsNoCorsSafelistedHeader(name, temp_value))
       return;
   }
   ```
   In `Headers::set`, Blink directly checks `if (guard_ == kRequestNoCorsGuard && !cors::IsNoCorsSafelistedHeader(name, normalized_value)) return;`.
   In `Headers::remove`, Blink checks `if (guard_ == kRequestNoCorsGuard && !cors::IsNoCorsSafelistedHeaderName(name) && !cors::IsPrivilegedNoCorsHeaderName(name)) return;`.

5. **Privileged No-CORS Header Cleanup:**
   Following any successful mutation under `kRequestNoCorsGuard`, Blink invokes ` RemovePrivilegedNoCorsRequestHeaders()`, which strips `Range` headers from `header_list_` to prevent cross-origin media range manipulation in `no-cors` requests.

---

## 3. Formal Specification & Verification in Rocq (Coq)

Below is the complete, self-contained, and admitted-free formalization of the Chromium Blink `Headers` guard state machine (`BlinkFetchHeadersGuardSemantics.v`). It models header syntax validation, ASCII case-insensitive name matching, guard transitions, combined value length budgets (128 bytes per header value, 1024 bytes total safelisted payload), privileged `Range` header stripping, and proves the security and safety invariants.

```coq
(** * BlinkFetchHeadersGuardSemantics.v
    Formalization of the WHATWG Fetch Standard §2.2 / §5.1 Headers Guard State Machine
    and Chromium Blink's implementation in third_party/blink/renderer/core/fetch/headers.cc.
*)

From Coq Require Import Bool.Bool.
From Coq Require Import ZArith.ZArith.
From Coq Require Import Lists.List.
From Coq Require Import Lia.
Import ListNotations.

Open Scope Z_scope.

(** ** 1. Core Data Types and Domain Representation *)

(** Canonicalized (lowercase) HTTP header name classification.
    In Blink, header names are compared ASCII case-insensitively. *)
Inductive HeaderName : Type :=
  (* No-CORS Safelisted Header Names *)
  | HN_Accept
  | HN_AcceptLanguage
  | HN_ContentLanguage
  | HN_ContentType
  (* Privileged No-CORS Header Names *)
  | HN_Range
  (* Forbidden Request Header Names *)
  | HN_Host
  | HN_Cookie
  | HN_SecFetchMode
  | HN_XHttpMethodOverride
  (* Forbidden Response Header Names *)
  | HN_SetCookie
  | HN_SetCookie2
  (* Standard Custom / Non-Safelisted Header Names *)
  | HN_Custom (id : Z)
  (* Syntactically Invalid Header Name (fails IsValidHeaderName) *)
  | HN_Invalid (id : Z).

(** Decidable equality for HeaderName *)
Definition header_name_eqb (n1 n2 : HeaderName) : bool :=
  match n1, n2 with
  | HN_Accept, HN_Accept => true
  | HN_AcceptLanguage, HN_AcceptLanguage => true
  | HN_ContentLanguage, HN_ContentLanguage => true
  | HN_ContentType, HN_ContentType => true
  | HN_Range, HN_Range => true
  | HN_Host, HN_Host => true
  | HN_Cookie, HN_Cookie => true
  | HN_SecFetchMode, HN_SecFetchMode => true
  | HN_XHttpMethodOverride, HN_XHttpMethodOverride => true
  | HN_SetCookie, HN_SetCookie => true
  | HN_SetCookie2, HN_SetCookie2 => true
  | HN_Custom i1, HN_Custom i2 => Z.eqb i1 i2
  | HN_Invalid i1, HN_Invalid i2 => Z.eqb i1 i2
  | _, _ => false
  end.

Lemma header_name_eqb_refl : forall n, header_name_eqb n n = true.
Proof.
  destruct n; simpl; try reflexivity; apply Z.eqb_refl.
Qed.

Lemma header_name_eqb_eq : forall n1 n2,
  header_name_eqb n1 n2 = true <-> n1 = n2.
Proof.
  intros n1 n2; split; intro H.
  - destruct n1, n2; simpl in H; try discriminate; try reflexivity;
    apply Z.eqb_eq in H; subst; reflexivity.
  - subst; apply header_name_eqb_refl.
Qed.

Lemma header_name_eqb_neq : forall n1 n2,
  header_name_eqb n1 n2 = false <-> n1 <> n2.
Proof.
  intros n1 n2; split; intro H.
  - intro Heq; subst; rewrite header_name_eqb_refl in H; discriminate.
  - destruct (header_name_eqb n1 n2) eqn:Heqb; try reflexivity.
    apply header_name_eqb_eq in Heqb; contradiction.
Qed.

(** Representation of a normalized HTTP Header Value.
    Models syntax validity, byte length, and semantic flags used by CORS/Fetch filters. *)
Record HeaderValue : Type := mkHeaderValue {
  hv_valid_syntax : bool;          (* FetchHeaderList::IsValidHeaderValue *)
  hv_byte_length : Z;              (* Normalized byte length >= 0 *)
  hv_cors_safelisted_chars : bool; (* Conforms to safelist character/MIME rules *)
  hv_has_forbidden_method : bool   (* Contains CONNECT/TRACE/TRACK for override headers *)
}.

(** Combine two HeaderValues via ", " (comma + space, 2 bytes) as performed in
    Headers::append and FetchHeaderList::Get. *)
Definition combine_header_values (v1 v2 : HeaderValue) : HeaderValue :=
  mkHeaderValue
    (andb (hv_valid_syntax v1) (hv_valid_syntax v2))
    (hv_byte_length v1 + 2 + hv_byte_length v2)
    (andb (hv_cors_safelisted_chars v1) (hv_cors_safelisted_chars v2))
    (orb (hv_has_forbidden_method v1) (hv_has_forbidden_method v2)).

(** A single entry in blink::FetchHeaderList *)
Record HeaderEntry : Type := mkHeaderEntry {
  he_name : HeaderName;
  he_value : HeaderValue
}.

(** blink::Headers::Guard state machine enum *)
Inductive Guard : Type :=
  | kNoneGuard
  | kRequestGuard
  | kRequestNoCorsGuard
  | kResponseGuard
  | kImmutableGuard.

(** Complete state of a blink::Headers instance *)
Record HeadersState : Type := mkHeadersState {
  hs_guard : Guard;
  hs_list : list HeaderEntry
