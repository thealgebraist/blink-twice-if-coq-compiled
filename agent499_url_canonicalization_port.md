# Formal Verification of URL Default Port Elision in Chromium’s URL Canonicalization Engine

**Research Target:** `url/url_canon_stdurl.cc` & `url/url_canon_etc.cc`  
**Specification:** WHATWG URL Standard § 4.1, § 4.2, § 4.4  
**Formal Theory:** `BlinkURLDefaultPortCanonicalizationSemantics.v`  
**Verification Engine:** Rocq (Coq) 8.18+ (`ZArith`, `Lia`, `Bool`, `List`)

---

## 1. Normative Specification Analysis

In the Web Platform, the Same-Origin Policy (SOP), Cookie security boundaries (RFC 6265bis), and Storage Partitioning rely on the canonical representation of URLs. A critical normalization step is the elision of default ports for special schemes. Failing to elide a default port—or erroneously eliding a non-default port—causes origin tuple `(scheme, host, port)` divergence, leading to SOP bypasses or cross-origin state leakage.

### 1.1 WHATWG URL Standard § 4.2 (URL Miscellaneous) & § 4.4 (URL Parsing)

The WHATWG URL Standard defines "special schemes" and their corresponding default ports:

| Scheme | Default Port |
| :--- | :--- |
| `"ftp"` | `21` |
| `"file"` | `null` |
| `"http"` | `80` |
| `"https"` | `443` |
| `"ws"` | `80` |
| `"wss"` | `443` |

During the **port state** of the basic URL parser (WHATWG URL § 4.4):
1. Let `port` be the parsed 16-bit unsigned integer ($0 \le \text{port} \le 65535$).
2. If `port` is equal to the `url`’s scheme’s default port, set `port` to `null` (elision).
3. Otherwise, set `url`’s port to `port`.

During **URL Serialization** (WHATWG URL § 4.5):
* If `url`’s port is non-null, append `U+003A (:)` followed by `url`’s port, serialized, to output.
* Because default ports are normalized to `null` during parsing/canonicalization, the `:port` component is completely omitted from the canonical string representation and the structural component offset table.

### 1.2 IETF RFC 6454 (The Web Origin Concept) & HTML Standard
Under HTML's serialization of an origin and RFC 6454 § 4, the port component of an origin tuple is determined by the parsed URL's port, falling back to the default port if null. Because `http://example.com:80` and `http://example.com` both canonicalize their port component to `null` (default), string-based and component-based origin comparisons remain isomorphic.

---

## 2. Chromium Implementation & Invariants (`url/`)

Chromium’s `GURL` and `blink::KURL` rely on the underlying `url` component library (`//url`). Standard URL canonicalization is orchestrated in `url/url_canon_stdurl.cc` and `url/url_canon_etc.cc`.

### 2.1 Execution Path in `url/url_canon_stdurl.cc`

In `DoCanonicalizeStandardURL` (`url/url_canon_stdurl.cc`), the engine resolves the scheme's default port via `DefaultPortForScheme` and delegates port canonicalization to `CanonicalizePort`:

```cpp
// url/url_canon_stdurl.cc
int default_port = DefaultPortForScheme(
    &output. view()[new_parsed->scheme.begin],
    new_parsed->scheme.len);
success &= CanonicalizePort(source.port, parsed.port, default_port,
                             output, &new_parsed->port);
```

### 2.2 Port Parsing and Elision in `url/url_canon_etc.cc`

The core state machine in `CanonicalizePort` (`url/url_canon_etc.cc`) relies on `ParsePort` (`url/url_parse.cc`) and status flags:

```cpp
// url/url_parse.h
#define PORT_UNSPECIFIED -1
#define PORT_INVALID -2

// url/url_canon_etc.cc
bool CanonicalizePort(const CHAR* spec,
                      const Component& port,
                      int default_port_for_scheme,
                      CanonOutput* output,
                      Component* out_port) {
  int port_num = ParsePort(spec, port);
  if (port_num == PORT_UNSPECIFIED || port_num == default_port_for_scheme) {
    *out_port = Component(); // Sets begin = 0, len = -1 (Elided / Null)
    return true;
  }
  if (port_num == PORT_INVALID) {
    // Invalid port: copied verbatim to output for error reporting, returns false.
    ...
    return false;
  }
  // Valid non-default port: write ':' and the base-10 digits to CanonOutput.
  output->push_back(':');
  out_port->begin = output->length();
  IntToString(port_num, output);
  out_port->len = output->length() - out_port->begin;
  return true;
}
```

### 2.3 Structural Invariants

1. **Component Representation (`url::Component`):** An unpopulated or elided component is represented by `begin = 0, len = -1`. A present component has `len >= 0`.
2. **Idempotence:** Re-canonicalizing an already canonicalized URL preserves the exact `Component` state and `CanonOutput` buffer.
3. **Origin Equivalence:** `url::SchemeHostPort` and `blink::SecurityOrigin` normalize port values such that an elided port (`PORT_UNSPECIFIED`) resolves to `DefaultPortForScheme(scheme)`.

---

## 3. Formal Specification & Verification in Rocq (Coq)

Below is the complete, self-contained, and admitted-free Rocq formalization (`BlinkURLDefaultPortCanonicalizationSemantics.v`). It models the WHATWG specification, Chromium's integer sentinel architecture (`PORT_UNSPECIFIED`, `PORT_INVALID`), component output structures, and origin tuple equivalence.

```coq
(** * BlinkURLDefaultPortCanonicalizationSemantics.v
    Formal Verification of Chromium's URL Port Canonicalization Engine
    Source: url/url_canon_stdurl.cc, url/url_canon_etc.cc
    Specification: WHATWG URL Standard § 4.2, § 4.4
*)

From Coq Require Import ZArith.
From Coq Require Import Lia.
From Coq Require Import Bool.
From Coq Require Import List.
Import ListNotations.

Open Scope Z_scope.

(** ** 1. Architectural Constants and Types *)

(** Sentinel values defined in Chromium's url/url_parse.h *)
Definition PORT_UNSPECIFIED : Z := -1.
Definition PORT_INVALID     : Z := -2.
Definition MAX_PORT         : Z := 65535.

(** URL Schemes modeled in Chromium's url/url_canon_stdurl.cc *)
Inductive Scheme : Type :=
  | Scheme_HTTP
  | Scheme_HTTPS
  | Scheme_WS
  | Scheme_WSS
  | Scheme_FTP
  | Scheme_FILE
  | Scheme_Custom (id : Z).

(** Scheme equality decidability *)
Definition scheme_eq_dec (s1 s2 : Scheme) : {s1 = s2} + {s1 <> s2}.
Proof.
  decide equality; apply Z.eq_dec.
Defined.

(** Raw input port passed to the parser *)
Inductive RawPortInput : Type :=
  | Input_Empty                (* Port component length <= 0 *)
  | Input_Valid (p : Z)        (* Parsed integer in [0, 65535] *)
  | Input_Malformed.           (* Non-digit characters or overflow > 65535 *)

(** Canonical Port Semantic Model (WHATWG Null vs Non-Null uint16) *)
Inductive CanonicalPort : Type :=
  | Port_DefaultElided         (* Represents null in WHATWG / Component(0, -1) in Blink *)
  | Port_Explicit (p : Z)      (* Represents explicit non-default port in [0, 65535] *)
  | Port_Error.                (* Represents invalid port failure state *)

(** Chromium's url::Component structure (begin, len) *)
Record Component : Type := mkComponent {
  comp_begin : Z;
  comp_len   : Z
}.

(** Unpopulated component constructor: Component() -> begin = 0, len = -1 *)
Definition EmptyComponent : Component := mkComponent 0 (-1).

(** Check if a Component is valid/populated (is_valid() in url_parse.h) *)
Definition is_component_populated (c : Component) : bool :=
  Z.geb (comp_len c) 0.

(** Canonicalization Execution Result modeling CanonOutput and out_port *)
Record CanonPortResult : Type := mkCanonResult {
  res_success   : bool;
  res_port_sem  : CanonicalPort;
  res_component : Component
}.

(** ** 2. Chromium Implementation Semantics *)

(** DefaultPortForScheme in url/url_canon_etc.cc *)
Definition DefaultPortForScheme (s : Scheme) : Z :=
  match s with
  | Scheme_HTTP  => 80
  | Scheme_HTTPS => 443
  | Scheme_WS    => 80
  | Scheme_WSS   => 443
  | Scheme_FTP   => 21
  | Scheme_FILE  => PORT_UNSPECIFIED
  | Scheme_Custom _ => PORT_UNSPECIFIED
  end.

(** ParsePort in url/url_parse.cc *)
Definition ParsePort (input : RawPortInput) : Z :=
  match input with
  | Input_Empty => PORT_UNSPECIFIED
  | Input_Valid p =>
      if (0 <=? p) && (p <=? MAX_PORT) then p else PORT_INVALID
  | Input_Malformed => PORT_INVALID
  end.

(** Helper: abstract length of base-10 string representation of a valid port *)
Definition port_digits_len (p : Z) : Z :=
  if p <? 10 then 1
  else if p <? 100 then 2
  else if p <? 1000 then 3
  else if p <? 10000 then 4
  else 5.

(** CanonicalizePort in url/url_canon_etc.cc
    Models both the semantic result and the exact url::Component mutation *)
Definition CanonicalizePort_Impl (scheme : Scheme)
                                 (input : RawPortInput)
                                 (current_output_len : Z) : CanonPortResult :=
  let default_port := DefaultPortForScheme scheme in
  let port_num := ParsePort input in
  if (port_num =? PORT_UNSPECIFIED) || (port_num =? default_port) then
    mkCanonResult true Port_DefaultElided EmptyComponent
  else if port_num =? PORT_INVALID then
    mkCanonResult false Port_Error (mkComponent (current_output_len + 1) 1)
  else
    let new_begin := current_output_len + 1 in (* after ':' *)
    let d_len := port_digits_len port_num in
    mkCanonResult true (Port_Explicit port_num) (mkComponent new_begin d_len).

(** Simplified semantic projection of CanonicalizePort *)
Definition canonicalize_port (scheme : Scheme) (port : Z) : CanonicalPort :=
  res_port_sem (CanonicalizePort_Impl scheme (Input_Valid port) 0).

(** ** 3. Origin Tuple and Effective Port Semantics *)

(** Effective port calculation used by blink::SecurityOrigin and url::SchemeHostPort *)
Definition EffectivePort (s : Scheme) (cp : CanonicalPort) : option Z :=
  match cp with
  | Port_DefaultElided =>
      let dp := DefaultPortForScheme s in
      if dp =? PORT_UNSPECIFIED then None else Some dp
  | Port_Explicit p => Some p
  | Port_Error => None
  end.

(** Web Origin Tuple (Scheme, HostID, EffectivePort) *)
Record OriginTuple : Type := mkOrigin {
  orig_scheme : Scheme;
  orig_host   : Z;
  orig_port   : option Z
}.

Definition DeriveOrigin (s : Scheme) (host : Z) (raw_port : RawPortInput) : option OriginTuple :=
  let res := CanonicalizePort_Impl s raw_port 0 in
  if res_success res then
    Some (mkOrigin s host (EffectivePort s (res_port_sem res)))
  else
    None.
```

---

## 4. Concrete Theorems and Complete Proofs

We now prove the core functional correctness, security boundary preservation, and structural invariants of Chromium's implementation. Every theorem is completely proven using standard `ZArith`, `Lia`, and boolean reflection tactics with **zero `Admitted` statements**.

```coq
(** ** 4. Formal Verification & Security Proofs *)

(** *** Theorem 1: Default Port Elision for HTTP (80) and HTTPS (443)
    Directly proves the primary mathematical property required by WHATWG § 4.2. *)
Theorem canonicalize_http_80_elided :
  canonicalize_port Scheme_HTTP 80 = Port_DefaultElided.
Proof.
  unfold canonicalize_port, CanonicalizePort_Impl.
  simpl. reflexivity.
Qed.

Theorem canonicalize_https_443_elided :
  canonicalize_port Scheme_HTTPS 443 = Port_DefaultElided.
Proof.
  unfold canonicalize_port, CanonicalizePort_Impl.
  simpl. reflexivity.
Qed.

Theorem canonicalize_ws_80_elided :
  canonicalize_port Scheme_WS 80 = Port_DefaultElided.
Proof.
  unfold canonicalize_port, CanonicalizePort_Impl.
  simpl. reflexivity.
Qed.

Theorem canonicalize_wss_443_elided :
  canonicalize_port Scheme_WSS 443 = Port_DefaultElided.
Proof.
  unfold canonicalize_port, CanonicalizePort_Impl.
  simpl. reflexivity.
Qed.

Theorem canonicalize_ftp_21_elided :
  canonicalize_port Scheme_FTP 21 = Port_DefaultElided.
Proof.
  unfold canonicalize_port, CanonicalizePort_Impl.
  simpl. reflexivity.
Qed.

(** *** Theorem 2: General Default Port Elision across All Special Schemes
    Any valid port matching its scheme's default port is guaranteed to be elided
    and its url::Component set to EmptyComponent (0, -1). *)
Theorem default_port_always_elided :
  forall (s : Scheme) (p : Z) (out_len : Z),
