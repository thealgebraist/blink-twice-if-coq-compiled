# Formal Verification Report: Blink WebCrypto `importKey` Format Discrimination

**Target File:** `third_party/blink/renderer/modules/crypto/subtle_crypto.cc`  
**Specification:** W3C Web Cryptography API §14.3.9 (The `importKey` method)  
**Formal Theory Target:** `BlinkWebCryptoImportKeyFormatSemantics.v`  
**Mathematical Domain:** Format Encoding & Input Type Discrimination (`raw` (1), `pkcs8` (2), `spki` (3), `jwk` (4))

---

## 1. Normative W3C Web Cryptography API Specification Requirements

Under §14.3.9 of the W3C Web Cryptography API specification, the `SubtleCrypto.importKey(format, keyData, algorithm, extractable, keyUsages)` method is responsible for deserializing raw or structured cryptographic material into an opaque `CryptoKey` object. Before delegating to the specific algorithm's import operation, the specification mandates strict structural discrimination between the `KeyFormat` enum and the union type of `keyData` (`BufferSource` or `JsonWebKey`).

The normative execution steps in §14.3.9 (specifically Steps 2 and 5) enforce a bidirectional type-format invariant:

1. **Enumeration Domain:** `KeyFormat` is strictly restricted to four enumerated string values:
   $$\text{KeyFormat} \in \{\texttt{"raw"}, \texttt{"pkcs8"}, \texttt{"spki"}, \texttt{"jwk"}\}$$
2. **Step 2 (Input Material Handling):**
   * **Case $\texttt{format} = \texttt{"jwk"}$:**
     * *Substep 2.1:* If `keyData` is a `BufferSource` (i.e., an `ArrayBuffer`, `DataView`, or typed array view), the user agent **must** return a Promise rejected with a `TypeError`.
     * *Substep 2.2:* Otherwise, `keyData` is processed as a `JsonWebKey` dictionary.
   * **Case $\texttt{format} \neq \texttt{"jwk"}$ ($\texttt{"raw"}$, $\texttt{"pkcs8"}$, $\texttt{"spki"}$):**
     * *Substep 2.1:* If `keyData` is not a `BufferSource` (e.g., it is an IDL `Object` / `JsonWebKey` dictionary), the user agent **must** return a Promise rejected with a `TypeError`.
     * *Substep 2.2:* Let `keyData` be the result of getting a copy of the bytes held by the `BufferSource` parameter.

Failure to enforce this boundary leads to type confusion between raw byte buffers and JSON dictionaries, potentially resulting in memory corruption or uninitialized memory reads at the boundary between the JavaScript engine (V8) and the native cryptographic backend (BoringSSL).

---

## 2. Blink Implementation Details and Invariants

In Chromium's Blink rendering engine, the entry point for `SubtleCrypto.importKey` is implemented in `third_party/blink/renderer/modules/crypto/subtle_crypto.cc`. Blink uses WebIDL bindings (`V8UnionArrayBufferOrArrayBufferViewOrJsonWebKey`) to represent the polymorphic `keyData` parameter.

### 2.1 Format Enumeration Mapping
Blink translates the WebIDL string representation of `KeyFormat` into an internal C++ enumeration `WebCryptoKeyFormat` via `ParseKeyFormat`. For formalization purposes, we map the 0-indexed C++ enum (`kWebCryptoKeyFormatRaw = 0`, etc.) to the required 1-indexed mathematical domain:
* $\texttt{raw} \mapsto 1$
* $\texttt{pkcs8} \mapsto 2$
* $\texttt{spki} \mapsto 3$
* $\texttt{jwk} \mapsto 4$

### 2.2 `subtle_crypto.cc` Control Flow and Invariants
In `SubtleCrypto::importKey`, the implementation performs the following steps synchronously on the main renderer thread before posting an asynchronous task to the WebCrypto worker pool (which invokes BoringSSL):

```cpp
// Conceptual representation of third_party/blink/renderer/modules/crypto/subtle_crypto.cc
ScriptPromise SubtleCrypto::importKey(
    ScriptState* script_state,
    const String& raw_format,
    const V8UnionArrayBufferOrArrayBufferViewOrJsonWebKey* key_data,
    const V8AlgorithmIdentifier* raw_algorithm,
    bool extractable,
    const Vector<String>& raw_key_usages,
    ExceptionState& exception_state) {
  
  WebCryptoKeyFormat format;
  if (! CryptoResultImpl::ParseKeyFormat(raw_format, format, exception_state))
    return ScriptPromise();

  Vector<uint8_t> raw_key_data;
  switch (key_data->GetContentType()) {
    case V8UnionArrayBufferOrArrayBufferViewOrJsonWebKey::ContentType::kArrayBuffer:
    case V8UnionArrayBufferOrArrayBufferViewOrJsonWebKey::ContentType::kArrayBufferView:
      if (format == kWebCryptoKeyFormatJwk) {
        exception_state.ThrowTypeError("Key data must be an object for JWK import");
        return ScriptPromise();
      }
      if (!CopyBytes(key_data, raw_key_data, exception_state))
        return ScriptPromise();
      break;
    case V8UnionArrayBufferOrArrayBufferViewOrJsonWebKey::ContentType::kJsonWebKey:
      if (format != kWebCryptoKeyFormatJwk) {
        exception_state.ThrowTypeError("Key data must be a BufferSource for non-JWK import");
        return ScriptPromise();
      }
      if (!JsonWebKeyToBytes(script_state, key_data->GetAsJsonWebKey(), raw_key_data, exception_state))
        return ScriptPromise();
      break;
  }
  // ... [Proceeds to normalize algorithm and dispatch to WebCrypto worker]
}
```

### 2.3 Security Invariants
1. **Total Format Partitioning:** Every valid `WebCryptoKeyFormat` is classified as either a binary format ($\{1, 2, 3\}$) or a structured dictionary format ($\{4\}$). The intersection of these two sets is empty.
2. **Strict Type Rejection:** The implementation guarantees that a `BufferSource` input paired with format $4$ (`jwk`), or a `JsonWebKey` input paired with formats $\{1, 2, 3\}$, immediately aborts execution with a `TypeError` before any byte-copying or JSON serialization (`JsonWebKeyToBytes`) takes place.
3. **BoringSSL Isolation:** Although Blink serializes the `JsonWebKey` into a JSON UTF-8 byte vector (`raw_key_data`) to pass across the thread boundary to the worker thread, the worker thread's BoringSSL adapter (`webcrypto::ImportKey`) strictly dispatches on `format`. It only parses `raw_key_data` as JSON if `format == kWebCryptoKeyFormatJwk`, and only passes `raw_key_data` to `CBS_init` / `EVP_parse_private_key` / `EVP_parse_public_key` if `format` $\in \{1, 2, 3\}$.

---

## 3. Formal Specification in Rocq / Coq

The following self-contained Rocq (Coq) module `BlinkWebCryptoImportKeyFormatSemantics.v` formalizes the mathematical properties of the format discriminator, the WebIDL union input types, the Blink state transition semantics, and the W3C normative specification.

```coq
(** * BlinkWebCryptoImportKeyFormatSemantics.v
    Formal verification of WebCrypto importKey format discrimination
    in Chromium Blink (third_party/blink/renderer/modules/crypto/subtle_crypto.cc)
    against W3C Web Cryptography API §14.3.9. *)

From Coq Require Import ZArith.
From Coq Require Import Bool.
From Coq Require Import Lia.

Open Scope Z_scope.

(** ** 1. Mathematical Domain of Key Formats *)
(** Specification property: formats: raw(1), pkcs8(2), spki(3), jwk(4). *)

Definition FORMAT_RAW   : Z := 1.
Definition FORMAT_PKCS8 : Z := 2.
Definition FORMAT_SPKI  : Z := 3.
Definition FORMAT_JWK   : Z := 4.

Inductive KeyFormat : Type :=
  | Raw   : KeyFormat
  | Pkcs8 : KeyFormat
  | Spki  : KeyFormat
  | Jwk   : KeyFormat.

(** Injection from inductive KeyFormat to integer representation *)
Definition format_to_Z (f : KeyFormat) : Z :=
  match f with
  | Raw   => FORMAT_RAW
  | Pkcs8 => FORMAT_PKCS8
  | Spki  => FORMAT_SPKI
  | Jwk   => FORMAT_JWK
  end.

(** Partial parser from integer representation to KeyFormat *)
Definition Z_to_format (z : Z) : option KeyFormat :=
  if Z.eqb z FORMAT_RAW then Some Raw
  else if Z.eqb z FORMAT_PKCS8 then Some Pkcs8
  else if Z.eqb z FORMAT_SPKI then Some Spki
  else if Z.eqb z FORMAT_JWK then Some Jwk
  else None.

(** Predicate defining valid integer format codes *)
Definition is_valid_format_code (z : Z) : Prop :=
  1 <= z <= 4.

(** Boolean predicates for format classification *)
Definition is_binary_format_code (z : Z) : bool :=
  (Z.eqb z FORMAT_RAW) || (Z.eqb z FORMAT_PKCS8) || (Z.eqb z FORMAT_SPKI).

Definition is_jwk_format_code (z : Z) : bool :=
  Z.eqb z FORMAT_JWK.

(** ** 2. Input KeyData Union Representation *)
(** In Blink: V8UnionArrayBufferOrArrayBufferViewOrJsonWebKey *)

Inductive KeyDataTag : Type :=
  | TagArrayBuffer     : KeyDataTag
  | TagArrayBufferView : KeyDataTag
  | TagJsonWebKey      : KeyDataTag.

(** W3C §14.3.9 groups ArrayBuffer and ArrayBufferView into BufferSource *)
Definition is_buffer_source (tag : KeyDataTag) : bool :=
  match tag with
  | TagArrayBuffer     => true
  | TagArrayBufferView => true
  | TagJsonWebKey      => false
  end.

(** ** 3. Execution Outcomes and BoringSSL Dispatch Targets *)

Inductive BoringSSLTarget : Type :=
  | TargetRawBytes   : BoringSSLTarget
  | TargetPkcs8Der   : BoringSSLTarget
  | TargetSpkiDer    : BoringSSLTarget
  | TargetJwkJson    : BoringSSLTarget.

Inductive ImportFormatResult : Type :=
  | OkDispatch          : BoringSSLTarget -> ImportFormatResult
  | ErrInvalidFormat    : ImportFormatResult
  | ErrTypeErrorMismatch: ImportFormatResult.

(** ** 4. Blink Implementation Model (subtle_crypto.cc) *)
(** Models the exact control flow of SubtleCrypto::importKey:
    First parses the format, then switches on KeyDataTag, checking format compatibility. *)

Definition blink_resolve_target (f : KeyFormat) : BoringSSLTarget :=
  match f with
  | Raw   => TargetRawBytes
  | Pkcs8 => TargetPkcs8Der
  | Spki  => TargetSpkiDer
  | Jwk   => TargetJwkJson
  end.

Definition blink_import_key_check (format_code : Z) (data_tag : KeyDataTag) : ImportFormatResult :=
  match Z_to_format format_code with
  | None => ErrInvalidFormat
  | Some fmt =>
      match data_tag with
      | TagArrayBuffer | TagArrayBufferView =>
          if Z.eqb (format_to_Z fmt) FORMAT_JWK then
            ErrTypeErrorMismatch
          else
            OkDispatch (blink_resolve_target fmt)
      | TagJsonWebKey =>
          if negb (Z.eqb (format_to_Z fmt) FORMAT_JWK) then
            ErrTypeErrorMismatch
          else
            OkDispatch (blink_resolve_target fmt)
      end
  end.

(** ** 5. W3C Specification Model (§14.3.9 Step 2) *)
(** Models the normative W3C specification which branches on format first,
    then validates the KeyData type. *)

Definition w3c_spec_import_key_check (format_code : Z) (data_tag : KeyDataTag) : ImportFormatResult :=
  if is_jwk_format_code format_code then
    if is_buffer_source data_tag then
      ErrTypeErrorMismatch
    else
      OkDispatch TargetJwkJson
  else if is_binary_format_code format_code then
    if negb (is_buffer_source data_tag) then
      ErrTypeErrorMismatch
    else if Z.eqb format_code FORMAT_RAW then
      OkDispatch TargetRawBytes
    else if Z.eqb format_code FORMAT_PKCS8 then
      OkDispatch TargetPkcs8Der
    else
      OkDispatch TargetSpkiDer
  else
    ErrInvalidFormat.
```

---

## 4. Concrete Theorems and Complete Mechanized Proofs

We now state and prove six core theorems establishing the correctness, injectivity, partitioning, type-confusion resistance, and observational equivalence of the Blink implementation with respect to the W3C specification. All proofs are complete and free of `Admitted` or axioms.

```coq
(** ** 6. Formal Theorems and Proofs *)

(** Theorem 1: Format Encoding Bijection and Bounds.
    Every KeyFormat maps to a strictly valid integer in [1, 4], and Z_to_format
    is the exact left-inverse of format_to_Z. *)
Theorem format_encoding_roundtrip_and_bounds :
  forall (f : KeyFormat),
    is_valid_format_code (format_to_Z f) /\
    Z_to_format (format_to_Z f) = Some f.
Proof.
  intros f.
  unfold is_valid_format_code, format_to_Z, Z_to_format,
         FORMAT_RAW, FORMAT_PKCS8, FORMAT_SPKI, FORMAT_JWK.
  destruct f; split; try lia; simpl; reflexivity.
Qed.

(** Theorem 2: Exact Domain Characterization of Z_to_format.
    An integer code z parses to Some KeyFormat if and only if 1 <= z <= 4. *)
Theorem Z_to_format_domain_exact :
  forall (z : Z),
    is_valid_format_code z <-> exists f : KeyFormat, Z_to_format z = Some f.
Proof.
  intros z.
  unfold is_valid_format_code, Z_to_format,
         FORMAT_RAW, FORMAT_PKCS8, FORMAT_SPKI, FORMAT_JWK.
  split.
  - intros [Hmin Hmax].
    assert (Hz : z = 1 \/ z = 2 \/ z = 3 \/ z = 4) by lia.
    destruct Hz as [H1 | [H2 | [H3