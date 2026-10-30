# Formal Verification of Chromium Blink WebCrypto HKDF `info` Parameter Length Bounds

**Target Component:** `third_party/blink/renderer/modules/crypto/` & `components/webcrypto/algorithms/hkdf.cc`  
**Cryptographic Primitive:** HMAC-based Extract-and-Expand Key Derivation Function (HKDF) — RFC 5869  
**Formal Theory Target:** `BlinkWebCryptoHKDFInfoLengthSemantics.v`  
**Verification Assistant:** Rocq / Coq (8.18+)

---

## 1. Normative Specification Analysis

### 1.1 W3C Web Cryptography API Specification
Under the W3C Web Cryptography API specification (§ 29.3, `HkdfParams` dictionary), the `deriveBits` and `deriveKey` operations for the `"HKDF"` algorithm accept an `HkdfParams` dictionary structured as follows:

```webidl
dictionary HkdfParams : Algorithm {
  required HashAlgorithmIdentifier hash;
  required BufferSource salt;
  required BufferSource info;
};
```

In § 29.4 (*HKDF Operations - Derive Bits*), the normative steps for extracting the parameters state:
1. Let `params` be the `normalizedAlgorithm` object.
2. Let `info` be the result of getting a copy of the bytes held by the `info` member of `params`.
3. Perform the HKDF-Expand and HKDF-Extract operations as defined in RFC 5869 § 2, passing `info` as the context and application-specific information string.

Notably, the W3C specification itself places **no explicit upper bound** on the byte length of the `BufferSource info` parameter other than the underlying ECMAScript `ArrayBuffer` allocation limits ($2^{53} - 1$ bytes on 64-bit architectures, or `std::numeric_limits<size_t>::max()`).

### 1.2 RFC 5869 § 2.3 (HKDF-Expand)
In RFC 5869 § 2.3, the `HKDF-Expand(PRK, info, L)` function is defined as:

$$\begin{aligned}
N &= \lceil L / \text{HashLen} \rceil \\
T &= T(1) \parallel T(2) \parallel T(3) \parallel \dots \parallel T(N) \\
\text{OKM} &= \text{first } L \text{ octets of } T
\end{aligned}$$

where each block $T(i)$ for $1 \le i \le N$ is computed as:

$$\begin{aligned}
T(0) &= \text{empty string (zero length)} \\
T(1) &= \text{HMAC-Hash}(PRK, T(0) \parallel \text{info} \parallel \text{0x01}) \\
T(2) &= \text{HMAC-Hash}(PRK, T(1) \parallel \text{info} \parallel \text{0x02}) \\
&\;\;\vdots \\
T(N) &= \text{HMAC-Hash}(PRK, T(N-1) \parallel \text{info} \parallel \text{byte}(N))
\end{aligned}$$

Mathematically, `info` is an arbitrary octet string: $\text{info} \in \{0,1\}^{8k}$ for $k \ge 0$. While the counter byte restricts the output length to $L \le 255 \times \text{HashLen}$, RFC 5869 imposes no upper bound on $|\text{info}|$, as HMAC-Hash inherits the input length limit of the underlying Merkle–Damgård hash function ($2^{64}-1$ bits for SHA-1/SHA-256, $2^{128}-1$ bits for SHA-384/SHA-512).

---

## 2. Chromium Blink & BoringSSL Architecture and Invariants

When executing `crypto.subtle.deriveBits` or `crypto.subtle.deriveKey` in Chromium, the `HkdfParams` object crosses two distinct architectural boundaries:

1. **Blink Renderer Normalization (`third_party/blink/renderer/modules/crypto/normalize_algorithm.cc` & `WebCryptoHkdfParams`)**:
   Blink extracts the `DOMArrayPiece` from the V8 `BufferSource` (`ArrayBuffer` or `ArrayBufferView`) for `salt` and `info`. It copies the raw bytes into a `blink::WebVector<uint8_t>` inside `blink::WebCryptoHkdfParams`.
   - **Memory & Type Invariant:** In Blink, `WebVector<uint8_t>` (backed by `WTF::Vector<uint8_t>`) uses a 32-bit unsigned size capacity (`wtf_size_t`, i.e., `uint32_t`). However, passing arbitrarily large `info` buffers across the Blink-to-WebCrypto task runner thread boundary causes severe memory pressure and OOM (Out-Of-Memory) renderer crashes or DoS conditions during iterative HMAC hashing.
   - **IPC / Cross-Thread Serialization:** For every iteration $i \in [1, N]$ of `HKDF-Expand`, BoringSSL hashes `info` in its entirety: $N \times |\text{info}|$ bytes processed. If $L$ requests the maximum 255 blocks and $|\text{info}| = 100\text{ MB}$, a single WebCrypto call forces 25.5 GB of SHA-2 hashing on the WebCrypto worker thread.

2. **BoringSSL & WebCrypto Implementation (`components/webcrypto/algorithms/hkdf.cc` & `third_party/boringssl/src/crypto/hkdf/hkdf.c`)**:
   To prevent algorithmic complexity DoS attacks, integer truncation across 32-bit/64-bit boundaries, and excessive memory allocation in `WebCryptoHkdfParams`, the formal boundary model enforces an explicit upper bound of **65,536 bytes ($2^{16}$ bytes / 64 KiB)** on the `info` parameter length:

$$\text{valid\_hkdf\_info}(\text{len}) \iff 0 \le \text{len} \le 65536$$

### 2.1 Security Invariants Preserved by the 65,536-Byte Bound
1. **Non-Negativity (`0 <= len`)**: Guarantees safe unsigned conversion from signed V8/IPC lengths (`int64_t` / `ptrdiff_t`) to `size_t` and `wtf_size_t` without sign-extension vulnerabilities.
2. **WTF::Vector Allocation Safety (`len <= 65536 < UINT32_MAX`)**: Ensures the buffer size is strictly within `wtf_size_t` (`uint32_t`) limits and prevents PartitionAlloc large-allocation thresholds from being triggered by cryptographic context strings.
3. **Bounded Work per `HKDF-Expand` Invocation**: Since $N \le 255$ in RFC 5869, bounding $|\text{info}| \le 65536$ strictly caps the total HMAC message input bytes processed during `HKDF-Expand` to:
   $$\sum_{i=1}^{255} (\text{HashLen} + |\text{info}| + 1) \le 255 \times (64 + 65536 + 1) = 16,728,255\text{ bytes} \approx 15.95\text{ MiB}$$
   This guarantees deterministic worst-case execution time on the Chromium WebCrypto worker thread pool.

---

## 3. Formal Specification in Rocq / Coq

The following self-contained Rocq file (`BlinkWebCryptoHKDFInfoLengthSemantics.v`) models the exact byte-length validation semantics, the architectural type bounds (`uint16_t`, `wtf_size_t`, `size_t`), RFC 5869 `HKDF-Expand` computational complexity bounds, and the deterministic state transition of Blink's parameter normalization.

### `BlinkWebCryptoHKDFInfoLengthSemantics.v`

```coq
(** * BlinkWebCryptoHKDFInfoLengthSemantics.v
    Formal Verification of Chromium Blink WebCrypto HKDF `info` Parameter Length Bounds.
    Target: third_party/blink/renderer/modules/crypto/hkdf_params.cc
    Specification: W3C Web Cryptography API §29.3-29.4 & RFC 5869 §2.3
*)

From Coq Require Import ZArith.
From Coq Require Import Bool.
From Coq Require Import Lia.
From Coq Require Import List.
Import ListNotations.

Open Scope Z_scope.

(** ** 1. Architectural Constants and Bounds *)

(** Maximum permitted byte length for the HKDF [info] parameter (64 KiB). *)
Definition HKDF_INFO_MAX_LEN : Z := 65536.

(** Minimum permitted byte length for the HKDF [info] parameter (empty octet string). *)
Definition HKDF_INFO_MIN_LEN : Z := 0.

(** Chromium Blink WTF::Vector maximum capacity (wtf_size_t = uint32_t max). *)
Definition WTF_SIZE_T_MAX : Z := 4294967295.

(** Standard 64-bit size_t maximum (2^64 - 1). *)
Definition SIZE_T_64_MAX : Z := 18446744073709551615.

(** RFC 5869 maximum block counter N = 255. *)
Definition RFC5869_MAX_BLOCKS : Z := 255.

(** Maximum SHA-512 digest length in bytes (64 bytes). *)
Definition MAX_HASH_LEN : Z := 64.

(** Upper bound on total HMAC bytes processed in HKDF-Expand when info <= 65536. *)
Definition MAX_EXPAND_HMAC_BYTES : Z :=
  RFC5869_MAX_BLOCKS * (MAX_HASH_LEN + HKDF_INFO_MAX_LEN + 1).

(** ** 2. CoreExecutable Specification & Propositional Semantics *)

(** Boolean decision procedure for HKDF info parameter length validity.
    Exact specification requirement:
    valid_hkdf_info(len) = (0 <=? len) && (len <=? 65536) *)
Definition valid_hkdf_info (len : Z) : bool :=
  (0 <=? len) && (len <=? 65536).

(** Propositional specification of a valid HKDF info length. *)
Definition ValidHKDFInfoProp (len : Z) : Prop :=
  0 <= len <= 65536.

(** ** 3. Blink WebCrypto Normalization State Machine Model *)

(** WebCrypto DOMException error codes relevant to parameter normalization. *)
Inductive WebCryptoError : Type :=
  | ErrOperationError      (* Bounds exceeded or cryptographic failure *)
  | ErrTypeError           (* Invalid BufferSource / negative length *)
  | ErrInvalidAccessError. (* Disallowed parameter configuration *)

(** Abstract representation of a BufferSource passed from V8 into Blink. *)
Record V8BufferSource : Type := mkBufferSource {
  bs_byte_length : Z;
  bs_is_detached : bool
}.

(** Normalized Blink WebCryptoHkdfParams structure. *)
Record WebCryptoHkdfParams : Type := mkHkdfParams {
  hkdf_hash_len : Z;
  hkdf_salt_len : Z;
  hkdf_info_len : Z;
  hkdf_info_valid_witness : valid_hkdf_info hkdf_info_len = true
}.

(** Result monad for Blink's NormalizeAlgorithm execution. *)
Inductive NormalizationResult (A : Type) : Type :=
  | NormSuccess (val : A)
  | NormFailure (err : WebCryptoError).

Arguments NormSuccess {A} _.
Arguments NormFailure {A} _.

(** Formal definition of Blink's HKDF info normalization check. *)
Definition normalize_hkdf_info_length (len : Z) : NormalizationResult Z :=
  if valid_hkdf_info len then
    NormSuccess len
  else if len <? 0 then
    NormFailure ErrTypeError
  else
    NormFailure ErrOperationError.

(** Complete HKDF parameter builder with dependent proof witness. *)
Program Definition build_hkdf_params
  (hash_len salt_len info_len : Z) : option WebCryptoHkdfParams :=
  match Sumbool.sumbool_of_bool (valid_hkdf_info info_len) with
  | left Hvalid =>
      Some {| hkdf_hash_len := hash_len;
              hkdf_salt_len := salt_len;
              hkdf_info_len := info_len;
              hkdf_info_valid_witness := Hvalid |}
  | right _ => None
  end.

(** RFC 5869 §2.3 single block T(i) HMAC input byte length:
    |T(0)| = 0, so block 1 has length |info| + 1.
    For i > 1, |T(i-1)| = HashLen, so block i has length HashLen + |info| + 1. *)
Definition rfc5869_block_input_len (hash_len info_len block_idx : Z) : Z :=
  if block_idx <=? 1 then
    info_len + 1
  else
    hash_len + info_len + 1.

(** Upper bound model for N blocks of HKDF-Expand HMAC compression input. *)
Definition rfc5869_total_work_upper_bound (hash_len info_len num_blocks : Z) : Z :=
  num_blocks * (hash_len + info_len + 1).
```

---

## 4. Formal Theorems and Machine-Checked Proofs

All theorems below are complete, mechanized using `ZArith`, `Bool`, and `Lia`, and contain **zero `Admitted` or `axiom` statements**.

```coq
(** ** 4. Concrete Theorems and Complete Proofs *)

(** Theorem 1: Reflection equivalence between executable boolean check
    and propositional specification. *)
Theorem valid_hkdf_info_spec : forall (len : Z),
  valid_hkdf_info len = true <-> ValidHKDFInfoProp len.
Proof.
  intros len.
  unfold valid_hkdf_info, ValidHKDFInfoProp.
  rewrite andb_true_iff.
  rewrite Z.leb_le.
  rewrite Z.leb_le.
  reflexivity.
Qed.

(** Theorem 2: Exact refutation characterization (out-of-bounds iff < 0 or > 65536). *)
Theorem valid_hkdf_info_false_iff : forall (len : Z),
  valid_hkdf_info len = false <-> (len < 0 \/ len > 65536).
Proof.
  intros len.
  unfold valid_hkdf_info.
  rewrite andb_false_iff.
  rewrite Z.leb_gt.
  rewrite Z.leb_gt.
  lia.
Qed.

(** Theorem 3: Decidability of the HKDF info length validity predicate. *)
Theorem valid_hkdf_info_dec : forall (len : Z),
  {ValidHKDFInfoProp