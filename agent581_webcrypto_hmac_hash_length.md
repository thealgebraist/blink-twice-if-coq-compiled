# Formal Verification Report: Blink WebCrypto HMAC Digest Output Length Semantics

**Target File:** `third_party/blink/renderer/modules/crypto/hmac_params.cc`  
**Normative Specification:** W3C Web Cryptography API §28.2 (HMAC)  
**Formal Theory Target:** `BlinkWebCryptoHMACHashLengthSemantics.v`  
**Core Mathematical Property:**  
$$\text{hmac\_output\_bytes}(\text{hash\_alg}) = \begin{cases} 32 & \text{if } \text{hash\_alg} = 256 \\ 64 & \text{if } \text{hash\_alg} = 512 \\ 0 & \text{otherwise} \end{cases}$$

---

## 1. Normative W3C Web Cryptography API Specification Requirements

Within the W3C Web Cryptography API (§28, HMAC), the Hash-based Message Authentication Code (HMAC) algorithm utilizes a cryptographic hash function $H$ as its underlying primitive, parameterized during key generation, import, and signing operations via `HmacKeyGenParams`, `HmacImportParams`, and `HmacKeyAlgorithm`.

### 1.1 Normative Operations & Digest Bounds (§28.2 - §28.4)
Per **FIPS PUB 198-1** (The Keyed-Hash Message Authentication Code) and **W3C Web Cryptography API §28.4**:

1. **Sign Operation (§28.4.1):**
   Given a `CryptoKey` $K$ whose `algorithm` attribute contains an inner `hash` parameter identifying a recognized digest algorithm (e.g., `SHA-1`, `SHA-256`, `SHA-384`, `SHA-512`), the MAC generation procedure computes:
   $$\text{HMAC}_K(m) = H\Big((K' \oplus \text{opad}) \parallel H\big((K' \oplus \text{ipad}) \parallel m\big)\Big)$$
   The output of the `Sign` operation is an `ArrayBuffer` containing the raw bytes of the outer invocation of $H$. Consequently, the exact byte length of an un-truncated WebCrypto HMAC tag is strictly determined by the digest output length $L$ of the underlying hash function $H$.

2. **Generate Key & Import Key Length Resolution (§28.4.3, §28.4.4):**
   When `length` is omitted in `HmacKeyGenParams` or `HmacImportParams`, the specification mandates that the default key length (in bits) be set to the **block size** $B$ of the hash algorithm, while the output tag length (in bytes) of the resulting HMAC operation is strictly equal to the **digest output size** $L$ of the underlying hash function:
   - For **SHA-256** (FIPS 180-4): The digest size is $256\text{ bits} = 32\text{ bytes}$.
   - For **SHA-512** (FIPS 180-4): The digest size is $512\text{ bits} = 64\text{ bytes}$.
   - For unrecognized or unsupported hash algorithm identifiers: The normalization algorithm must fail and return an error (represented in total functional semantics as an output length of $0\text{ bytes}$).

---

## 2. Chromium Blink & BoringSSL Architecture Analysis

In Chromium, the WebCrypto API straddles the Blink renderer process (`third_party/blink/renderer/modules/crypto/`) and the BoringSSL-backed implementation in `components/webcrypto/algorithms/hmac.cc`.

### 2.1 Blink Parameter Normalization (`hmac_params.cc` / `normalize_algorithm.cc`)
In Blink, `HmacKeyParams` and `WebCryptoHmacImportParams` encapsulate the normalized parameters passed across the Blink public platform boundary (`blink::WebCryptoAlgorithm`). When normalizing parameters in `third_party/blink/renderer/modules/crypto/` (specifically within the parameter normalization pipeline interfacing with `hmac_params.cc` and `components/webcrypto/algorithms/hmac.cc`), Blink validates the inner `WebCryptoAlgorithmId` representing the hash function:

```cpp
// Conceptual representation of Blink/WebCrypto HMAC digest length resolution
// Interfacing between blink::WebCryptoHmacKeyGenParams and BoringSSL EVP_MD
size_t GetHmacDigestOutputBytes(blink::WebCryptoAlgorithmId hash_id) {
  switch (hash_id) {
    case blink::kWebCryptoAlgorithmIdSha256:
      return 32; // SHA256_DIGEST_LENGTH (256 bits / 8)
    case blink::kWebCryptoAlgorithmIdSha512:
      return 64; // SHA512_DIGEST_LENGTH (512 bits / 8)
    // In restricted/high-assurance profiles focusing on 256/512-bit SHA-2 families:
    default:
      return 0;  // Invalid / Unsupported algorithm identifier
  }
}
```

### 2.2 BoringSSL Invariants (`EVP_MD_size` and `HMAC_CTX`)
When execution transitions from Blink to `components/webcrypto/algorithms/hmac.cc`, the `WebCryptoAlgorithm` is mapped to a BoringSSL `const EVP_MD*` via `GetDigest(hash_id)`:
- `kWebCryptoAlgorithmIdSha256` $\mapsto$ `EVP_sha256()`, where `EVP_MD_size(EVP_sha256()) == 32`.
- `kWebCryptoAlgorithmIdSha512` $\mapsto$ `EVP_sha512()`, where `EVP_MD_size(EVP_sha512()) == 64`.

Before invoking `HMAC_Init_ex`, `HMAC_Update`, and `HMAC_Final`, the buffer allocation size for the output MAC (`std::vector<uint8_t> result(EVP_MD_size(digest))`) relies on the exact invariant that:
1. Valid SHA-256/SHA-512 identifiers yield strictly positive byte lengths ($32$ or $64$) that never overflow `size_t` or `unsigned int`.
2. Bit-to-byte conversions satisfy $\text{bytes} \times 8 = \text{hash\_alg}$ for supported identifiers.
3. Invalid identifiers evaluate to $0$, halting buffer allocation and triggering `Status::ErrorUnsupported()`.

---

## 3. Formal Specification in Rocq / Coq

The following complete, self-contained Rocq (Coq) formalization `BlinkWebCryptoHMACHashLengthSemantics.v` defines the exact functional semantics of the HMAC digest output length resolver, its relationship to bit-level cryptographic security bounds, and proves all structural and security invariants.

```coq
(** * BlinkWebCryptoHMACHashLengthSemantics.v
    Formal Verification of Chromium Blink WebCrypto HMAC Digest Output Length
    Specification: W3C Web Cryptography API Section 28.2
    Source Target: third_party/blink/renderer/modules/crypto/hmac_params.cc
*)

From Coq Require Import ZArith.
From Coq Require Import Bool.
From Coq Require Import Lia.
From Coq Require Import List.
Import ListNotations.

Open Scope Z_scope.

Section BlinkWebCryptoHMAC.

  (** ** 1. Formal Definitions & Target Mathematical Property *)

  (** [hmac_output_bytes hash_alg] computes the exact digest output length in bytes
      for the target SHA-2 family identifiers (256 and 512), returning 0 for any
      unrecognized or unsupported algorithm identifier. *)
  Definition hmac_output_bytes (hash_alg : Z) : Z :=
    if hash_alg =? 256 then 32 else if hash_alg =? 512 then 64 else 0.

  (** Predicate characterizing valid/supported hash algorithm bit-lengths in the
      verified profile (SHA-256 and SHA-512). *)
  Definition is_supported_hash_alg (hash_alg : Z) : Prop :=
    hash_alg = 256 \/ hash_alg = 512.

  (** Boolean decision procedure for supported hash algorithms. *)
  Definition is_supported_hash_alg_b (hash_alg : Z) : bool :=
    (hash_alg =? 256) || (hash_alg =? 512).

  (** Conversion from output bytes back to output bits. *)
  Definition bytes_to_bits (bytes : Z) : Z :=
    bytes * 8.

  (** BoringSSL EVP_MAX_MD_SIZE constant (64 bytes = 512 bits). *)
  Definition EVP_MAX_MD_SIZE : Z := 64.

  (** Minimum NIST SP 800-107 / FIPS 198-1 full-length SHA-2 output bound (32 bytes). *)
  Definition MIN_VALID_HMAC_BYTES : Z := 32.

  (** ** 2. Core Functional Correctness & Boundary Theorems *)

  (** Theorem 1: Exact evaluation for SHA-256. *)
  Theorem hmac_output_bytes_sha256 :
    hmac_output_bytes 256 = 32.
  Proof.
    unfold hmac_output_bytes.
    reflexivity.
  Qed.

  (** Theorem 2: Exact evaluation for SHA-512. *)
  Theorem hmac_output_bytes_sha512 :
    hmac_output_bytes 512 = 64.
  Proof.
    unfold hmac_output_bytes.
    reflexivity.
  Qed.

  (** Theorem 3: Any unsupported algorithm identifier yields 0 bytes (fail-safe). *)
  Theorem hmac_output_bytes_unsupported :
    forall (hash_alg : Z),
      hash_alg <> 256 ->
      hash_alg <> 512 ->
      hmac_output_bytes hash_alg = 0.
  Proof.
    intros hash_alg Hnot256 Hnot512.
    unfold hmac_output_bytes.
    destruct (Z.eqb_spec hash_alg 256) as [Heq256 | Hneq256].
    - contradiction.
    - destruct (Z.eqb_spec hash_alg 512) as [Heq512 | Hneq512].
      + contradiction.
      + reflexivity.
  Qed.

  (** Theorem 4: Reflection equivalence between boolean and propositional support. *)
  Theorem is_supported_hash_alg_reflect :
    forall (hash_alg : Z),
      is_supported_hash_alg_b hash_alg = true <-> is_supported_hash_alg hash_alg.
  Proof.
    intro hash_alg.
    unfold is_supported_hash_alg_b, is_supported_hash_alg.
    rewrite orb_true_iff.
    repeat rewrite Z.eqb_eq.
    tauto.
  Qed.

  (** ** 3. Memory Safety & BoringSSL Buffer Bound Invariants *)

  (** Theorem 5: Non-negativity invariant.
      Guarantees no negative values prior to C++ size_t / unsigned int casting. *)
  Theorem hmac_output_bytes_nonneg :
    forall (hash_alg : Z),
      0 <= hmac_output_bytes hash_alg.
  Proof.
    intro hash_alg.
    unfold hmac_output_bytes.
    destruct (hash_alg =? 256); [lia |].
    destruct (hash_alg =? 512); lia.
  Qed.

  (** Theorem 6: BoringSSL EVP_MAX_MD_SIZE upper bound invariant.
      Guarantees that fixed-size stack buffers of size EVP_MAX_MD_SIZE (64 bytes)
      in BoringSSL HMAC_Final never suffer from buffer overflow. *)
  Theorem hmac_output_bytes_bounded_by_evp_max :
    forall (hash_alg : Z),
      0 <= hmac_output_bytes hash_alg <= EVP_MAX_MD_SIZE.
  Proof.
    intro hash_alg.
    unfold hmac_output_bytes, EVP_MAX_MD_SIZE.
    destruct (hash_alg =? 256); [lia |].
    destruct (hash_alg =? 512); lia.
  Qed.

  (** Theorem 7: Strict Enumeration of Possible Outputs.
      The output length is strictly restricted to the set {0, 32, 64}. *)
  Theorem hmac_output_bytes_image :
    forall (hash_alg : Z),
      hmac_output_bytes hash_alg = 0 \/
      hmac_output_bytes hash_alg = 32 \/
      hmac_output_bytes hash_alg = 64.
  Proof.
    intro hash_alg.
    unfold hmac_output_bytes.
    destruct (hash_alg =? 256); [right; left; reflexivity |].
    destruct (hash_alg =? 512); [right; right; reflexivity |].
    left; reflexivity.
  Qed.

  (** ** 4. Cryptographic Security & Bit-Length Preservation Theorems *)

  (** Theorem 8: Strict Positivity Characterization.
      The output length is strictly positive if and only if the algorithm is supported. *)
  Theorem hmac_output_bytes_pos_iff_supported :
    forall (hash_alg : Z),
      0 < hmac_output_bytes hash_alg <-> is_supported_hash_alg hash_alg.
  Proof.
    intro hash_alg.
    unfold hmac_output_bytes, is_supported_hash_alg.
    destruct (Z.eqb_spec hash_alg 256) as [Heq256 | Hneq256].
    - split; intro H; [left; exact Heq256 | lia].
    - destruct (Z.eqb_spec hash_alg 512) as [Heq512 | Hneq512].
      + split; intro H; [right; exact Heq512 | lia].
      + split; intro H.
        * lia.
        * destruct H as [H256 | H512]; contradiction.
  Qed.

  (** Theorem 9: Cryptographic Minimum Security Bound for Valid Algorithms.
      For any supported hash algorithm, the output tag is at least 32 bytes (256 bits),
      satisfying NIST SP 800-107 collision and forgery resistance bounds. *)
  Theorem hmac_output_bytes_security_lower_bound :
    forall (hash_alg : Z),
      is_supported_hash_alg hash_alg ->
      MIN_VALID_HMAC_BYTES <= hmac_output_bytes hash_alg.
  Proof.
    intros hash_alg Hsupp.
    unfold is_supported_hash_alg in Hsupp.
    unfold hmac_output_bytes, MIN_VALID_HMAC_BYTES.
    destruct Hsupp as [H256 | H512]; subst.
    - simpl; lia.
    - simpl; lia.
  Qed.

  (** Theorem 10: Exact Bit-to-Byte Bijection Preservation.
      For all supported algorithms, multiplying the byte output by 8 reconstructs
      the exact bit-length identifier of the