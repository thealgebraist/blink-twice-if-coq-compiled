# Formal Verification Report: WebCrypto AES-CBC Initialization Vector (IV) Length Invariant in Chromium Blink

**Author**: Formal Methods & Web Cryptography Research Group  
**Target Component**: Chromium Blink (`third_party/blink/renderer/modules/crypto/aes_cbc_params.cc`)  
**Specification**: W3C Web Cryptography API §20.2 (AES-CBC)  
**Formal Artifact**: `BlinkWebCryptoAESCBCIVLengthSemantics.v`  
**Proof Assistant**: Rocq / Coq (8.18+)

---

## 1. Normative W3C Web Cryptography API Specification Requirements

The Web Cryptography API defines the low-level cryptographic primitives exposed to web applications via the `window.crypto.subtle` interface. Section 20 of the specification defines the **AES-CBC** (Advanced Encryption Standard in Cipher Block Chaining mode) algorithm.

### 1.1 Dictionary Definition (§20.2)
Parameters passed to the `encrypt` and `decrypt` operations for AES-CBC must conform to the `AesCbcParams` IDL dictionary:

```webidl
dictionary AesCbcParams : Algorithm {
  required BufferSource iv;
};
```

### 1.2 Operational Semantics (§20.3)
In Section 20.3 ("AES-CBC Operations"), both the **Encrypt** and **Decrypt** procedures specify an identical, strict validation step on the Initialization Vector (`iv`) prior to invoking the underlying cryptographic primitive:

> **Encrypt (§20.3.1) / Decrypt (§20.3.2):**
> 1. Let *normalizedAlgorithm* be the result of normalizing an algorithm, with `alg` set to *algorithm* and `op` set to `"encrypt"` (or `"decrypt"`).
> 2. If the `iv` member of *normalizedAlgorithm* does not have a length of 16 bytes, then throw an `OperationError`.

### 1.3 Cryptographic Rationale
AES is a 128-bit block cipher regardless of key size (AES-128, AES-192, or AES-256). Consequently, the block size $B$ is strictly fixed at $B = 128\text{ bits} = 16\text{ bytes}$. 

In Cipher Block Chaining (CBC) mode (NIST SP 800-38A), the first plaintext block $P_1$ is XORed with the Initialization Vector ($IV$) prior to the forward cipher operation:
$$C_1 = E_K(P_1 \oplus IV)$$
For the bitwise $\oplus$ operation to be well-defined and memory-safe without implicit padding or truncation, $|IV|$ must exactly equal the block size $B = 16\text{ bytes}$.

---

## 2. Chromium Blink Implementation Analysis

In Chromium, the Web Cryptography API is split across the Blink renderer layer (responsible for WebIDL normalization, parameter validation, and type conversion) and the `components/webcrypto` layer (which bridges Blink to BoringSSL).

### 2.1 Parameter Normalization in Blink
During algorithm normalization (`third_party/blink/renderer/modules/crypto/normalize_algorithm.cc` and `aes_cbc_params.cc`), Blink extracts the raw bytes of the `BufferSource` (`ArrayBuffer`, `ArrayBufferView`) provided in the JavaScript `AesCbcParams` dictionary and constructs a `blink::WebCryptoAesCbcParams` object.

In the Blink normalization pipeline:
```cpp
// Conceptual representation of Blink's normalization check for AesCbcParams
bool NormalizeAesCbcParams(const V8AesCbcParams* raw_params,
                           WebCryptoAlgorithmParams** params,
                           ExceptionState& exception_state) {
  DOMArrayPiece iv_piece(raw_params->iv());
  if (iv_piece.ByteLength() != 16) {
    exception_state.ThrowDOMException(
        DOMExceptionCode::kOperationError,
        "The provided iv must be 16 bytes long.");
    return false;
  }
  *params = new WebCryptoAesCbcParams(iv_piece.Bytes(), iv_piece.ByteLength());
  return true;
}
```

Furthermore, at the boundary between Blink and BoringSSL (`components/webcrypto/algorithms/aes_cbc.cc`), a defense-in-depth check is executed before calling `EVP_CipherInit_ex`:

```cpp
Status AesCbcEncryptDecrypt(EncryptOrDecrypt mode,
                            const blink::WebCryptoAlgorithm& algorithm,
                            const blink::WebCryptoKey& key,
                            base::span<const uint8_t> data,
                            std::vector<uint8_t>* buffer) {
  const blink::WebCryptoAesCbcParams* params = algorithm.AesCbcParams();
  if (params->Iv().size() != 16)
    return Status::ErrorUnexpected();
  // ... proceeds to BoringSSL EVP_CipherInit_ex ...
}
```

### 2.2 Implementation Invariants
1. **Type Safety & Non-negativity**: The `ByteLength()` of a `DOMArrayPiece` or `base::span` is represented as `size_t` (unsigned integer), ensuring $l \ge 0$.
2. **Exact Length Enforcement**: The boolean predicate guarding execution is `l == 16`.
3. **Failure Mode**: If `l != 16`, control flow immediately aborts via an `OperationError` DOMException, preventing uninitialized memory reads or buffer over-reads inside BoringSSL's `EVP_CIPHER_CTX` initialization (which assumes the `iv` pointer references at least `EVP_CIPHER_iv_length(cipher) == 16` contiguous bytes).

---

## 3. Formal Specification in Rocq/Coq

We model the parameter normalization semantics, the W3C specification requirements, and the BoringSSL memory safety preconditions in Rocq/Coq.

The formalization uses `Z` (arbitrary-precision integers) from `ZArith` to capture both abstract mathematical lengths and bounded machine integers (`size_t`), ensuring no wrap-around anomalies distort the specification.

### 3.1 Formal Theory: `BlinkWebCryptoAESCBCIVLengthSemantics.v`

```coq
(** * BlinkWebCryptoAESCBCIVLengthSemantics.v
    Formal verification of W3C Web Cryptography API §20.2 AES-CBC IV length
    validation in Chromium Blink. *)

From Coq Require Import ZArith.
From Coq Require Import Bool.
From Coq Require Import Lia.
From Coq Require Import List.
Import ListNotations.

Open Scope Z_scope.

(** ** 1. Cryptographic Constants and Types *)

(** AES block size in bits as defined by FIPS 197. *)
Definition AES_BLOCK_BITS : Z := 128.

(** Number of bits per byte. *)
Definition BITS_PER_BYTE : Z := 8.

(** AES block size in bytes (16 bytes). *)
Definition AES_BLOCK_BYTES : Z := AES_BLOCK_BITS / BITS_PER_BYTE.

(** Representation of WebIDL BufferSource in Blink after extraction.
    Modeled as a list of bytes (abstracted as Z) and its explicit byte length. *)
Record BufferSource := mkBufferSource {
  bs_data : list Z;
  bs_length : Z;
  bs_length_correct : Z.of_nat (List.length bs_data) = bs_length;
  bs_nonneg : 0 <= bs_length
}.

(** WebCrypto Exception / Status codes per W3C §20.3. *)
Inductive WebCryptoError : Type :=
  | OperationError : WebCryptoError
  | InvalidAccessError : WebCryptoError
  | DataError : WebCryptoError.

(** Result monad for WebCrypto normalization and operations. *)
Inductive WebCryptoResult (A : Type) : Type :=
  | Ok : A -> WebCryptoResult A
  | Err : WebCryptoError -> WebCryptoResult A.

Arguments Ok {A} _.
Arguments Err {A} _.

(** Validated Blink internal WebCryptoAesCbcParams structure. *)
Record WebCryptoAesCbcParams := mkAesCbcParams {
  iv_bytes : list Z;
  iv_len : Z
}.

(** ** 2. Mathematical Property & Blink Implementation Model *)

(** Target Mathematical Property:
    is_valid_iv_length(l) = (l =? 16) *)
Definition is_valid_iv_length (l : Z) : bool :=
  l =? 16.

(** Blink's normalization function for AesCbcParams
    (third_party/blink/renderer/modules/crypto/aes_cbc_params.cc). *)
Definition blink_normalize_aes_cbc_params (iv : BufferSource) 
  : WebCryptoResult WebCryptoAesCbcParams :=
  if is_valid_iv_length (bs_length iv) then
    Ok (mkAesCbcParams (bs_data iv) (bs_length iv))
  else
    Err OperationError.

(** ** 3. W3C Specification & BoringSSL Preconditions *)

(** W3C Web Cryptography API §20.3 propositional specification for AES-CBC IV. *)
Definition w3c_spec_valid_iv (iv : BufferSource) : Prop :=
  bs_length iv = 16.

(** BoringSSL EVP_CipherInit_ex memory-safety precondition for AES-CBC:
    The IV buffer must contain at least AES_BLOCK_BYTES (16) bytes to prevent
    out-of-bounds reads, and exactly AES_BLOCK_BYTES to prevent silent truncation. *)
Definition boringssl_aes_cbc_iv_safe (params : WebCryptoAesCbcParams) : Prop :=
  Z.of_nat (List.length (iv_bytes params)) = AES_BLOCK_BYTES /\
  iv_len params = AES_BLOCK_BYTES.
```

---

## 4. Formal Theorems and Complete Proofs

Below are the concrete theorems establishing the correctness, completeness, decidability, and cryptographic safety of Blink's IV validation logic. All proofs are complete and free of `Admitted` or axioms.

```coq
(** ** 4. Formal Verification Theorems and Proofs *)

(** Theorem 1: The derived AES_BLOCK_BYTES constant is strictly 16. *)
Theorem aes_block_bytes_is_16 : AES_BLOCK_BYTES = 16.
Proof.
  unfold AES_BLOCK_BYTES, AES_BLOCK_BITS, BITS_PER_BYTE.
  reflexivity.
Qed.

(** Theorem 2: Boolean Reflection Equivalence.
    The boolean check `is_valid_iv_length l = true` is logically equivalent
    to the propositional equality `l = 16`. *)
Theorem is_valid_iv_length_iff : forall (l : Z),
  is_valid_iv_length l = true <-> l = 16.
Proof.
  intros l.
  unfold is_valid_iv_length.
  rewrite Z.eqb_eq.
  reflexivity.
Qed.

(** Theorem 3: Soundness and Completeness of Rejections.
    `is_valid_iv_length l = false` if and only if `l <> 16`. *)
Theorem is_valid_iv_length_false_iff : forall (l : Z),
  is_valid_iv_length l = false <-> l <> 16.
Proof.
  intros l.
  unfold is_valid_iv_length.
  rewrite Z.eqb_neq.
  reflexivity.
Qed.

(** Theorem 4: Strict Rejection of Out-of-Bounds Lengths.
    Any IV length strictly less than 16 (underflow) or strictly greater than 16
    (overflow/truncation risk) is rejected by the validator. *)
Theorem iv_length_underflow_overflow_rejected : forall (l : Z),
  (l < 16 \/ l > 16) -> is_valid_iv_length l = false.
Proof.
  intros l H_bounds.
  apply is_valid_iv_length_false_iff.
  lia.
Qed.

(** Theorem 5: Common Misuse Resistance.
    Specifically proves that standard IV/nonce lengths from other modes
    (e.g., 0 bytes for empty IV, 8 bytes for DES/3DES, 12 bytes for AES-GCM)
    are unconditionally rejected in AES-CBC mode. *)
Theorem common_non_cbc_iv_lengths_rejected :
  is_valid_iv_length 0 = false /\
  is_valid_iv_length 8 = false /\
  is_valid_iv_length 12 = false /\
  is_valid_iv_length 24 = false /\
  is_valid_iv_length 32 = false.
Proof.
  unfold is_valid_iv_length.
  repeat split; reflexivity.
Qed.

(** Theorem 6: W3C §20.3 Compliance (Normalization Soundness & Completeness).
    Blink's normalization succeeds if and only if the W3C specification
    predicate holds, and fails with `OperationError` if and only if the
    predicate does not hold. *)
Theorem blink_normalization_w3c_compliance : forall (iv : BufferSource),
  (w3c_spec_valid_iv iv ->
    blink_normalize_aes_cbc_params iv =
      Ok (mkAesCbcParams (bs_data iv) (bs_length iv))) /\
  (~ w3c_spec_valid_iv iv ->
    blink_normalize_aes_cbc_params iv = Err OperationError).
Proof.
  intros iv.
  unfold w3c_spec_valid_iv, blink_normalize_aes_cbc_params.
  split.
  - intros H_valid.
    apply is_valid_iv_length_iff in H_valid.
    rewrite H_valid.
    reflexivity.
  - intros H_invalid.
    apply is_valid_iv_length_false_iff in H_invalid.
    rewrite H_invalid.
    reflexivity.
Qed.

(** Theorem 7: Exclusivity of OperationError on Normalization Failure.
    Blink normalization for AesCbcParams never throws an error other than
    OperationError (as mandated by W3C §20.3). *)
Theorem blink_normalization_error_exclusivity :
  forall (iv : BufferSource) (e : WebCryptoError),
  blink_normalize_aes_cbc_params iv = Err e ->
  e = OperationError.
Proof.
  intros iv e H_err.
  unfold blink_normalize_aes_cbc_params in H_err.
  destruct (is_valid_iv_length (bs_length iv)) eqn:H_cond.
  - discriminate H_err.
  - injection H_err as H_eq.
    symmetry.
    exact H_eq.
Qed.

(** Theorem 8: BoringSSL Memory and Cryptographic Safety Preservation.
    If Blink normalization succeeds and yields `params`, then `params` strictly
    satisfies BoringSSL's memory-safety and block-alignment precondition. *)
Theorem blink_to_boringssl_safety_preservation :
  forall (iv : BufferSource) (params : WebCryptoAesCbcParams),
  blink_normalize_aes_cbc_params iv = Ok params ->
  boringssl_aes_cbc_iv_safe params.
Proof.
  intros iv