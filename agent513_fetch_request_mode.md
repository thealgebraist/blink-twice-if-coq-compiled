# Formal Verification of Fetch Request Modes and Method Restrictions in Chromium Blink

## 1. Normative Specification Requirements

The WHATWG Fetch Standard (§ 5.4, "Request class") defines the construction and mutation semantics of `Request` objects exposed to JavaScript and Service Worker contexts. A central security boundary in the Web Platform is the enforcement of CORS (Cross-Origin Resource Sharing) capabilities via the request `mode` attribute, specifically when transitioning to or initializing with `"no-cors"`.

### 1.1. The `new Request(input, init)` Constructor Steps
In **Fetch Standard § 5.4**, the `Request(input, init)` constructor executes a strict sequence of validation and state-transition steps. The normative invariants governing `mode`, `method`, and `headers` (specifically `guard`) are extracted below:

1. **Fallback Mode Initialization (Step 7):** If `input` is a string (URL), the internal `request` is initialized with `mode` set to `"cors"` and `fallbackMode` set to `"cors"`. If `input` is an existing `Request` object, its internal `mode` is cloned, and `fallbackMode` is `null`.
2. **Mode Override (Step 24):** If `init["mode"]` is present, let `mode` be `init["mode"]`.
   - **Step 24.1:** If `mode` is `"navigate"`, throw a `TypeError`.
   - **Step 24.2:** If `mode` is non-null, set `request`’s `mode` to `mode`.
3. **Method Normalization and Override (Step 33):** If `init["method"]` is present:
   - **Step 33.1:** Let `method` be `init["method"]`.
   - **Step 33.2:** If `method` is not a valid HTTP method token or is a forbidden method (`CONNECT`, `TRACE`, `TRACK` case-insensitively), throw a `TypeError`.
   - **Step 33.3:** Normalize `method` (uppercase `DELETE`, `GET`, `HEAD`, `OPTIONS`, `POST`, `PUT`).
   - **Step 33.4:** Set `request`’s `method` to `method`.
4. **`no-cors` Method and Integrity Invariant (Step 36):**
   - **Step 36.1:** If `request`’s `mode` is `"no-cors"`, then:
     - **Step 36.1.1:** If `request`’s `method` is not a *CORS-safelisted method* (`GET`, `HEAD`, or `POST`), throw a `TypeError`.
     - **Step 36.1.2:** If `request`’s `integrity` metadata is not the empty string, throw a `TypeError`.
     - **Step 36.2:** Set `headers`’s `guard` to `"request-no-cors"`.

### 1.2. Header Guard Semantics (`request-no-cors`)
When the `Request` object's `Headers` instance has its guard transitioned to `"request-no-cors"`, **Fetch Standard § 5.1 ("Headers class")** mandates:
- Any subsequent `append(name, value)` or `set(name, value)` operation checks if `(name, value)` is a *no-cors-safelisted request-header*. If it is not, the operation silently returns without modifying the header list (as opposed to throwing a `TypeError`, which occurs for invalid header names/values).
- During `Request` initialization (Step 40), existing headers (either cloned from `input` or passed in `init["headers"]`) are re-appended into the newly guarded `Headers` object, automatically stripping non-safelisted headers when `mode` is `"no-cors"`.

---

## 2. Chromium Blink Implementation Analysis

In Chromium, the Web IDL `Request` interface is implemented in `third_party/blink/renderer/core/fetch/request.cc` (backed by `FetchRequestData` in `fetch_request_data.h` and Mojo types from `services/network/public/mojom/fetch_api.mojom-blink.h`).

### 2.1. Code Structure in `third_party/blink/renderer/core/fetch/request.cc`
The core factory function responsible for enforcing § 5.4 is `Request::CreateRequestWithRequestOrString`:

```cpp
// third_party/blink/renderer/core/fetch/request.cc

Request* Request::CreateRequestWithRequestOrString(
    ScriptState* script_state,
    Request* input_request,
    const String& input_string,
    const RequestInit* init,
    ExceptionState& exception_state) {
  // ... [Steps 1-23: URL parsing, origin, credentials, destination setup] ...

  // Step 24: Mode validation and assignment
  if (init->hasMode()) {
    if (init->mode() == "navigate") {
      exception_state.ThrowTypeError(
          "Cannot construct a Request with a RequestInit whose mode member is "
          "set as 'navigate'.");
      return nullptr;
    }
    request->SetMode(StringToRequestMode(init->mode()));
  }

  // ... [Steps 25-32: Credentials, Cache, Redirect, Integrity] ...

  // Step 33: Method validation and normalization
  if (init->hasMethod()) {
    String method = init->method();
    if (!IsValidHTTPToken(method)) {
      exception_state.ThrowTypeError("'" + method +
                                     "' is not a valid HTTP method.");
      return nullptr;
    }
    if (FetchUtils::IsForbiddenMethod(method)) {
      exception_state.ThrowTypeError("'" + method +
                                     "' HTTP method is unsupported.");
      return nullptr;
    }
    request->SetMethod(
        AtomicString(FetchUtils::NormalizeMethod(method)));
  }

  // Step 36: "no-cors" mode invariants
  if (request->Mode() == network::mojom::RequestMode::kNoCors) {
    if (!FetchUtils::IsCorsSafelistedMethod(request->Method())) {
      exception_state.ThrowTypeError("'" + request->Method() +
                                     "' is unsupported in no-cors mode.");
      return nullptr;
    }
    if (!request->Integrity().empty()) {
      exception_state.ThrowTypeError(
          "Integrity metadata is unsupported in no-cors mode.");
      return nullptr;
    }
  }

  // Step 38-41: Header Guard assignment and header population
  Headers* headers = Headers::Create(r->HeaderList());
  headers->SetGuard(Headers::kRequestGuard);
  if (request->Mode() == network::mojom::RequestMode::kNoCors) {
    headers->SetGuard(Headers::kRequestNoCorsGuard);
  }
  // Filling headers enforces kRequestNoCorsGuard filtering automatically.
  // ...
}
```

### 2.2. Blink-Specific Architectural Invariants
1. **Method Normalization Precedence:** `FetchUtils::NormalizeMethod` converts case-insensitive matches of `GET`, `HEAD`, `POST`, `DELETE`, `OPTIONS`, and `PUT` to uppercase `AtomicString`s *prior* to `FetchUtils::IsCorsSafelistedMethod(request->Method())`. `IsCorsSafelistedMethod` checks exact case-sensitive equality against `"GET"`, `"HEAD"`, and `"POST"`. Consequently, `"post"` in `init->method()` is normalized to `"POST"`, which subsequently passes the `kNoCors` check.
2. **State Inheritance Vulnerability Mitigation:** A `Request` can be constructed from an existing `input_request` that had `mode: "cors"` and `method: "PUT"`. If the caller invokes `new Request(input_request, { mode: "no-cors" })` without specifying `init.method`, `request->Method()` retains `"PUT"` from `input_request`. Because Step 36 executes unconditionally on the *resolved* `request->Mode()` and `request->Method()`, Blink correctly rejects this combination with a `TypeError`.
3. **Header Stripping via Guard Transition:** Blink clones `r->HeaderList()` into a temporary `FetchHeaderList`, clears the request's underlying header list, sets the `kRequestNoCorsGuard` on the wrapper `Headers` object, and re-populates it via `headers->FillWith(...)`. This guarantees that if `input_request` had custom non-safelisted headers (e.g., `X-Custom-Auth: secret`) under `"cors"` mode, transitioning to `"no-cors"` mode strips those headers before the `Request` is handed to the network service or Service Worker `CacheStorage`.

---

## 3. Formal Specification in Rocq/Coq (`BlinkFetchRequestModeSemantics.v`)

Below is the complete, self-contained formalization of Blink's `Request` construction semantics, focusing on mode transitions, method normalization, `no-cors` restrictions, and header guard filtering.

```coq
(** * BlinkFetchRequestModeSemantics.v
    Formal verification of WHATWG Fetch Standard §5.4 and Chromium Blink's
    third_party/blink/renderer/core/fetch/request.cc implementation. *)

From Coq Require Import Bool.Bool.
From Coq Require Import ZArith.ZArith.
From Coq Require Import Lists.List.
From Coq Require Import Lia.
Import ListNotations.

Open Scope Z_scope.

(** ** 1. Core Domain Types *)

(** Mojo network::mojom::RequestMode representation *)
Inductive RequestMode : Type :=
  | ModeSameOrigin
  | ModeNoCors
  | ModeCors
  | ModeNavigate
  | ModeWebsocket.

Scheme Equality for RequestMode.

(** HTTP Methods modeled after Blink's FetchUtils *)
Inductive HttpMethod : Type :=
  (* Standard CORS-safelisted methods (normalized) *)
  | MethodGET
  | MethodHEAD
  | MethodPOST
  (* Un-normalized variants of safelisted methods *)
  | MethodGetLower
  | MethodHeadLower
  | MethodPostLower
  (* Non-safelisted standard methods *)
  | MethodPUT
  | MethodDELETE
  | MethodOPTIONS
  | MethodPATCH
  (* Forbidden methods: CONNECT, TRACE, TRACK *)
  | MethodCONNECT
  | MethodTRACE
  | MethodTRACK
  (* Invalid HTTP token (e.g. contains spaces/delimiters) *)
  | MethodInvalidToken
  (* Arbitrary valid token (e.g. WebDAV MKCOL) *)
  | MethodCustomValid (id : Z).

(** Equality decision procedure for HttpMethod *)
Definition http_method_eqb (m1 m2 : HttpMethod) : bool :=
  match m1, m2 with
  | MethodGET, MethodGET => true
  | MethodHEAD, MethodHEAD => true
  | MethodPOST, MethodPOST => true
  | MethodGetLower, MethodGetLower => true
  | MethodHeadLower, MethodHeadLower => true
  | MethodPostLower, MethodPostLower => true
  | MethodPUT, MethodPUT => true
  | MethodDELETE, MethodDELETE => true
  | MethodOPTIONS, MethodOPTIONS => true
  | MethodPATCH, MethodPATCH => true
  | MethodCONNECT, MethodCONNECT => true
  | MethodTRACE, MethodTRACE => true
  | MethodTRACK, MethodTRACK => true
  | MethodInvalidToken, MethodInvalidToken => true
  | MethodCustomValid id1, MethodCustomValid id2 => Z.eqb id1 id2
  | _, _ => false
  end.

Lemma http_method_eqb_eq : forall m1 m2,
  http_method_eqb m1 m2 = true <-> m1 = m2.
Proof.
  intros m1 m2; split; intro H.
  - destruct m1, m2; simpl in H; try discriminate; try reflexivity.
    apply Z.eqb_eq in H; subst; reflexivity.
  - subst; destruct m2; simpl; try reflexivity.
    apply Z.eqb_refl.
Qed.

(** Blink Headers::Guard representation *)
Inductive HeaderGuard : Type :=
  | GuardImmutable
  | GuardRequest
  | GuardRequestNoCors
  | GuardResponse
  | GuardNone.

Scheme Equality for HeaderGuard.

(** Abstract representation of an HTTP Header *)
Record Header : Type := mkHeader {
  hdr_id : Z;
  hdr_valid_token : bool;
  hdr_forbidden : bool;
  hdr_no_cors_safelisted : bool
}.

(** Internal FetchRequestData state *)
Record FetchRequestData : Type := mkFetchRequestData {
  req_mode : RequestMode;
  req_method : HttpMethod;
  req_has_integrity : bool;
  req_guard : HeaderGuard;
  req_headers : list Header
}.

(** Input to Request constructor: either a URL string (default state) or an existing Request *)
Inductive RequestInput : Type :=
  | InputString
  | InputRequest (r : FetchRequestData).

(** RequestInit dictionary passed to new Request(input, init) *)
Record RequestInit : Type := mkRequestInit {
  init_mode : option RequestMode;
  init_method : option HttpMethod;
  init_has_integrity : option bool;
  init_headers : option (list Header)
}.

(** Result of Request::CreateRequestWithRequestOrString *)
Inductive BlinkResult (A : Type) : Type :=
  | Ok (val : A)
  | TypeError.

Arguments Ok {A} _.
Arguments TypeError {A}.

(** ** 2. Blink Helper Predicates and Transformers (FetchUtils) *)

(** FetchUtils::IsValidHTTPToken *)
Definition is_valid_http_token (m : HttpMethod) : bool :=
  match m with
  | MethodInvalidToken => false
  | _ => true
  end.

(** FetchUtils::IsForbiddenMethod *)
Definition is_forbidden_method (m : HttpMethod) : bool :=
  match m with
  | MethodCONNECT | MethodTRACE | MethodTRACK => true
  | _ => false
  end.

(** FetchUtils::NormalizeMethod *)
Definition normalize_method (m : HttpMethod) : HttpMethod :=
  match m with
  | MethodGetLower => MethodGET
  | MethodHeadLower => MethodHEAD
  | MethodPostLower => MethodPOST
  | _ => m
  end.

(** FetchUtils::IsCorsSafelistedMethod
    Note: Expects already-normalized method in Blink! *)
Definition is_cors_safelisted_method (m : HttpMethod) : bool :=
  match m with
  | MethodGET | MethodHEAD | MethodPOST => true
  | _ => false
  end.

(** Header append logic under a specific HeaderGuard (Blink Headers::Append) *)
Definition append_header_guarded (g : HeaderGuard) (h : Header) (acc : list Header) : BlinkResult (list Header) :=
  if negb (hdr_valid_token h) then TypeError
  else match g with
       | GuardImmutable => TypeError
       | GuardNone => Ok (acc ++ [h])
       | GuardRequest =>
           if hdr_forbidden h then Ok acc
           else Ok (acc ++ [h])
       | GuardRequestNoCors =>
           if hdr_no_cors_safelisted h then Ok (acc ++