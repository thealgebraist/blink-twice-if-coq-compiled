# Formal Verification Report: WebCrypto `deriveKey` Algorithm Constraint Check in Chromium Blink

**Author**: Formal Methods & Web Cryptography Research Group  
**Target Component**: `third_party/blink/renderer/modules/crypto/subtle_crypto.cc`  
**Normative Specification**: W3C Web Cryptography API §14.3.8 (`SubtleCrypto.prototype.deriveKey`)  
**Formal Theory Target**: `BlinkWebCryptoDeriveKeyAlgorithmSemantics.v`  
**Core Mathematical Property**: $\text{derive\_key\_allowed}(\text{base\_usage}) \iff \text{has\_key\_usage}(\text{base\_usage}, \text{USAGE\_DERIVE\_KEY})$

---

## 1. Normative W3C Web Cryptography API Specification Requirements

In the W3C Web Cryptography API, the `deriveKey` method derives a new cryptographic key from a master (base) key using a specified key derivation algorithm (such as ECDH, HKDF, or PBKDF2), and immediately imports those derived bytes into a new `CryptoKey` object tuned for a target algorithm (such as AES-GCM or HMAC).

According to **W3C Web Cryptography API §14.3.8 (`deriveKey` method)**, when invoked with arguments `(algorithm, baseKey, derivedKeyType, extractable, keyUsages)`, the implementation must execute a sequence of synchronous and asynchronous validation steps before delegating to the underlying cryptographic primitive. 

Specifically, steps 2 through 10 dictate the algorithm normalization, usage parsing, and access control constraints:

1. **Algorithm Normalization (Steps 2–5)**:
   * Let `normalizedAlgorithm` be the result of normalizing an algorithm, with `alg` set to `algorithm` and `op` set to `"deriveBits"`. (If an error occurs, return a Promise rejected with that error).
   * Let `normalizedDerivedKeyAlgorithm` be the result of normalizing an algorithm, with `alg` set to `derivedKeyType` and `op` set to `"importKey"`.
   * Let `normalizedDerivedKeyAlgorithmLength` be the result of normalizing an algorithm, with `alg` set to `derivedKeyType` and `op` set to `"get key length"`.

2. **Base Key Algorithm Match (Step 8)**:
   * If the `name` member of `normalizedAlgorithm` does not match the `name` attribute of the `[[algorithm]]` internal slot of `baseKey` (case-sensitive comparison after normalization), then throw an `InvalidAccessError` DOMException.

3. **Base Key Usage Constraint (Step 9)**:
   * **Normative Mandate**: *"If the `[[usages]]` internal slot of `baseKey` does not contain an entry that is `"deriveKey"`, then throw an `InvalidAccessError`."*
   * Crucially, although `deriveKey` internally relies on the `"deriveBits"` operation of the base algorithm and `"importKey"` / `"get key length"` operations of the derived key algorithm, the base key itself **must** explicitly possess the `"deriveKey"` usage permission (`USAGE_DERIVE_KEY`). Possessing `"deriveBits"` on the `baseKey` is neither necessary nor sufficient to authorize a `deriveKey` invocation.

4. **Execution Delegation (Steps 10–14)**:
   * Determine the required bit length `length` by executing the `"get key length"` operation on `normalizedDerivedKeyAlgorithmLength`.
   * Execute the `"deriveBits"` operation on `normalizedAlgorithm` using `baseKey` and `length` to produce `secret`.
   * Execute the `"importKey"` operation on `normalizedDerivedKeyAlgorithm` using `"raw"` format, `secret`, `extractable`, and `keyUsages` to produce the final `CryptoKey`.

---

## 2. Blink Implementation Details and Invariants

In Chromium, the WebIDL interface for `SubtleCrypto` is implemented in `third_party/blink/renderer/modules/crypto/subtle_crypto.cc`, which bridges the V8 JavaScript execution environment in the Blink renderer with the BoringSSL-backed WebCrypto implementation (`components/webcrypto/`).

### 2.1 Bitmask Representation of Key Usages

Blink and the Chromium WebCrypto layer represent the `[[usages]]` internal slot of a `CryptoKey` not as an array of strings, but as an unsigned bitmask (`blink::WebCryptoKeyUsageMask`, defined in `third_party/blink/public/platform/web_crypto_key.h`):

```cpp
enum WebCryptoKeyUsage {
  kWebCryptoKeyUsageEncrypt    = 1 << 0, // 0x01
  kWebCryptoKeyUsageDecrypt    = 1 << 1, // 0x02
  kWebCryptoKeyUsageSign       = 1 << 2, // 0x04
  kWebCryptoKeyUsageVerify     = 1 << 3, // 0x08
  kWebCryptoKeyUsageDeriveKey  = 1 << 4, // 0x10
  kWebCryptoKeyUsageDeriveBits = 1 << 5, // 0x20
  kWebCryptoKeyUsageWrapKey    = 1 << 6, // 0x40
  kWebCryptoKeyUsageUnwrapKey  = 1 << 7, // 0x80
};
typedef unsigned WebCryptoKeyUsageMask;
```

### 2.2 Control Flow in `SubtleCrypto::deriveKey`

When `SubtleCrypto::deriveKey` is called in `third_party/blink/renderer/modules/crypto/subtle_crypto.cc`:

```cpp
ScriptPromise SubtleCrypto::deriveKey(
    ScriptState* script_state,
    const V8AlgorithmIdentifier* raw_algorithm,
    CryptoKey* base_key,
    const V8AlgorithmIdentifier* raw_derived_key_type,
    bool extractable,
    const Vector<String>& raw_key_usages,
    ExceptionState& exception_state) {
  // Method Histogram and Promise setup...
  auto* result = MakeGarbageCollected<CryptoResultImpl>(script_state);
  ScriptPromise promise = result->Promise();

  // 1. Parse target usages for the newly derived key
  WebCryptoKeyUsageMask key_usages;
  if (!CryptoKey::ParseUsageMask(raw_key_usages, key_usages, result))
    return promise;

  // 2. Normalize base algorithm with kWebCryptoOperationDeriveBits
  WebCryptoAlgorithm normalized_algorithm;
  if (!NormalizeAlgorithm(script_state->GetIsolate(), raw_algorithm,
                          kWebCryptoOperationDeriveBits, normalized_algorithm,
                          result))
    return promise;

  // 3. Normalize derived key type with kWebCryptoOperationImportKey
  WebCryptoAlgorithm normalized_derived_key_algorithm;
  if (!NormalizeAlgorithm(script_state->GetIsolate(), raw_derived_key_type,
                          kWebCryptoOperationImportKey,
                          normalized_derived_key_algorithm, result))
    return promise;

  // 4. Normalize derived key type with kWebCryptoOperationGetKeyLength
  WebCryptoAlgorithm key_length_algorithm;
  if (!NormalizeAlgorithm(script_state->GetIsolate(), raw_derived_key_type,
                          kWebCryptoOperationGetKeyLength, key_length_algorithm,
                          result))
    return promise;

  // 5. Validate baseKey algorithm match and USAGE_DERIVE_KEY constraint
  if (!base_key->CanBeUsedForAlgorithm(normalized_algorithm,
                                       kWebCryptoKeyUsageDeriveKey, result))
    return promise;

  // 6. Dispatch asynchronous task to WebCrypto worker pool (BoringSSL)
  // ...
  return promise;
}
```

### 2.3 Invariants in `CryptoKey::CanBeUsedForAlgorithm`

The method `CryptoKey::CanBeUsedForAlgorithm` (located in `third_party/blink/renderer/modules/crypto/crypto_key.cc`) enforces both Step 8 and Step 9 of the W3C specification:

```cpp
bool CryptoKey::CanBeUsedForAlgorithm(const WebCryptoAlgorithm& algorithm,
                                      WebCryptoKeyUsage usage,
                                      CryptoResult* result) const {
  if (key_.Algorithm().Id() != algorithm.Id()) {
    result->CompleteWithError(kWebCryptoErrorTypeInvalidAccess,
                              "key.algorithm does not match that of operation");
    return false;
  }

  if (!(key_.Usages() & usage)) {
    result->CompleteWithError(kWebCryptoErrorTypeInvalidAccess,
                              "key.usages does not permit this operation");
    return false;
  }

  return true;
}
```

#### Critical Security Invariants:
1. **Operation vs. Usage Decoupling**: Even though `raw_algorithm` is normalized against `kWebCryptoOperationDeriveBits`, the usage check in `CanBeUsedForAlgorithm` explicitly passes `kWebCryptoKeyUsageDeriveKey` (`1 << 4 = 16`).
2. **Bitwise Usage Isolation**: Because `kWebCryptoKeyUsageDeriveKey` is a single-bit flag ($2^4$), the C++ bitwise expression `(key_.Usages() & usage) != 0` is strictly equivalent to testing whether bit 4 of `key_.Usages()` is set.
3. **Fail-Closed Rejection**: If either the algorithm ID check or the bitwise usage check fails, `CanBeUsedForAlgorithm` synchronously completes the `CryptoResult` with `kWebCryptoErrorTypeInvalidAccess` (mapping to `InvalidAccessError` DOMException) and returns `false`, preventing any IPC/task dispatch to the BoringSSL worker thread.

---

## 3. Formal Specification Definitions in Rocq/Coq

Below is the self-contained formalization of Blink's `deriveKey` algorithm normalization and key constraint semantics in Rocq/Coq (`BlinkWebCryptoDeriveKeyAlgorithmSemantics.v`). We model the bitmask operations over exact binary integers (`Z`) and establish equivalences between the specification-level set/predicate semantics and Blink's low-level bitwise implementation.

```coq
(** * BlinkWebCryptoDeriveKeyAlgorithmSemantics.v
    Formal verification of Chromium Blink's WebCrypto deriveKey
    algorithm and key usage constraint checks (W3C WebCrypto API §14.3.8). *)

From Coq Require Import ZArith.
From Coq Require Import Bool.
From Coq Require Import List.
From Coq Require Import Lia.
Import ListNotations.

Open Scope Z_scope.

(** ** 1. WebCrypto Key Usage Bitmask Definitions *)

(** Bit positions corresponding to blink::WebCryptoKeyUsage *)
Definition BIT_ENCRYPT     : Z := 0.
Definition BIT_DECRYPT     : Z := 1.
Definition BIT_SIGN        : Z := 2.
Definition BIT_VERIFY      : Z := 3.
Definition BIT_DERIVE_KEY  : Z := 4.
Definition BIT_DERIVE_BITS : Z := 5.
Definition BIT_WRAP_KEY    : Z := 6.
Definition BIT_UNWRAP_KEY  : Z := 7.

(** Concrete bitmask values (1 << bit) *)
Definition USAGE_ENCRYPT     : Z := 1.   (* 1 << 0 = 0x01 *)
Definition USAGE_DECRYPT     : Z := 2.   (* 1 << 1 = 0x02 *)
Definition USAGE_SIGN        : Z := 4.   (* 1 << 2 = 0x04 *)
Definition USAGE_VERIFY      : Z := 8.   (* 1 << 3 = 0x08 *)
Definition USAGE_DERIVE_KEY  : Z := 16.  (* 1 << 4 = 0x10 *)
Definition USAGE_DERIVE_BITS : Z := 32.  (* 1 << 5 = 0x20 *)
Definition USAGE_WRAP_KEY    : Z := 64.  (* 1 << 6 = 0x40 *)
Definition USAGE_UNWRAP_KEY  : Z := 128. (* 1 << 7 = 0x80 *)

Definition MAX_USAGE_MASK    : Z := 255. (* 0xFF *)

(** Well-formedness predicate for a WebCryptoKeyUsageMask *)
Definition valid_usage_mask (mask : Z) : Prop :=
  0 <= mask <= MAX_USAGE_MASK.

(** ** 2. Key Usage Inspection Semantics *)

(** C++ implementation in CryptoKey::CanBeUsedForAlgorithm:
    !(key_.Usages() & usage) == false  <==>  (base_usage & usage_flag) <> 0 *)
Definition has_key_usage (base_usage : Z) (usage_flag : Z) : bool :=
  negb (Z.eqb (Z.land base_usage usage_flag) 0).

(** Specification-level predicate: does base_usage allow deriveKey? *)
Definition derive_key_allowed (base_usage : Z) : bool :=
  has_key_usage base_usage USAGE_DERIVE_KEY.

(** High-level bit test corresponding to W3C [[usages]] containing "deriveKey" *)
Definition spec_has_derive_key (base_usage : Z) : bool :=
  Z.testbit base_usage BIT_DERIVE_KEY.

(** ** 3. WebCrypto Algorithms and Operations Model *)

Inductive WebCryptoAlgorithmId : Type :=
  | AlgAesCbc
  | AlgAesCtr
  | AlgAesGcm
  | AlgAesKw
  | AlgHmac
  | AlgRsaSsaPkcs1v1_5
  | AlgRsaPss
  | AlgRsaOaep
  | AlgEcdsa
  | AlgEcdh
  | AlgHkdf
  | AlgPbkdf2.

Scheme Equality for WebCryptoAlgorithmId.

Inductive WebCryptoOperation : Type :=
  | OpEncrypt
  | OpDecrypt
  | OpSign
  | OpVerify
  | OpDeriveBits
  | OpImportKey
  | OpGetKeyLength
  | OpWrapKey
  | OpUnwrapKey.

Scheme Equality for WebCryptoOperation.

(** Algorithm registry table: maps (AlgorithmId, Operation) to support status
    as defined in Blink's NormalizeAlgorithm registry. *)
Definition supports_operation (alg : WebCryptoAlgorithmId) (op : WebCryptoOperation) : bool :=
  match alg, op with
  (* Key derivation algorithms support DeriveBits *)
  | AlgEcdh,   OpDeriveBits => true
  | AlgHkdf,   OpDeriveBits => true
  | AlgPbkdf2, OpDeriveBits => true
  (* Target derived key algorithms support ImportKey and GetKeyLength *)
  | AlgAesCbc, OpImportKey    => true
  | AlgAesCbc, OpGetKeyLength => true
  | AlgAesCtr, OpImportKey    => true
  | AlgAesCtr, OpGetKeyLength => true
  | AlgAesGcm, OpImportKey    => true
  | AlgAesGcm, OpGetKeyLength => true
  | AlgAesKw,  OpImportKey    => true
  | AlgAesKw,  OpGetKeyLength => true
  | AlgHmac,   OpImportKey    => true
  | AlgHmac,   OpGetKeyLength => true
  | AlgHkdf,   OpImportKey    => true
  | AlgPbkdf2, OpImportKey    => true
  (* Other combinations omitted/unsupported in deriveKey context *)
  