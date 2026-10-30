# Formal Verification Report: Blink WebCrypto `getRandomValues` Quota Bounding

**Formal Theory Target:** `BlinkWebCryptoGetRandomValuesQuotaSemantics.v`  
**Chromium Component:** `third_party/blink/renderer/modules/crypto/crypto.cc`  
**Normative Specification:** W3C Web Cryptography API §10.1 (`Crypto.getRandomValues`)  
**Mathematical Invariant:** $\text{valid\_random\_bytes}(sz) \equiv (sz \le 65536) \land (0 \le sz)$

---

## 1. Normative W3C Web Cryptography API Specification

According to the W3C Web Cryptography API Specification, Section 10.1 (`The Crypto interface` - `getRandomValues` method), the synchronous generation of cryptographically strong pseudo-random values is bounded by strict type and quota invariants to prevent entropy pool exhaustion or denial-of-service (DoS) via synchronous main-thread blocking inside the user agent.

The normative algorithm for `Crypto.getRandomValues(array)` states:

1. **Type Constraint:** If `array` is not an `Int8Array`, `Uint8Array`, `Uint8ClampedArray`, `Int16Array`, `Uint16Array`, `Int32Array`, `Uint32Array`, `BigInt64Array`, or `BigUint64Array` (i.e., not an integer-based `ArrayBufferView`), throw a `TypeMismatchError` `DOMException` and terminate the algorithm.
2. **Quota Constraint:** If the `byteLength` of `array` is greater than $65536$ ($2^{16}$ bytes), throw a `QuotaExceededError` `DOMException` and terminate the algorithm.
3. **Buffer Write:** Overwrite all elements of `array` with cryptographically strong random values of the appropriate type.
4. **Return Value:** Return `array`.

Mathematically, let $B$ be the set of valid `ArrayBufferView` types, and let $\text{byteLength}: B \to \mathbb{Z}$ denote the byte length of the view. The normative pre-condition for invoking the underlying Cryptographically Secure Pseudo-Random Number Generator (CSPRNG) is:

$$\text{IsIntegerTypedArray}(v) \land 0 \le \text{byteLength}(v) \le 65536$$

---

## 2. Chromium Blink Implementation & BoringSSL Architecture

In Chromium, the WebIDL interface for `Crypto` maps `crypto.getRandomValues()` to `Crypto::getRandomValues` inside `third_party/blink/renderer/modules/crypto/crypto.cc`. The cryptographic primitives are backed by BoringSSL's `RAND_bytes` exposed through Chromium's `base/rand_util.h` (`base::RandBytes`).

### 2.1 Source Analysis (`crypto.cc`)

```cpp
// third_party/blink/renderer/modules/crypto/crypto.cc

namespace blink {

namespace {

bool IsIntegerArray(DOMArrayBufferView::ViewType type) {
  return type == DOMArrayBufferView::kTypeInt8 ||
         type == DOMArrayBufferView::kTypeUint8 ||
         type == DOMArrayBufferView::kTypeUint8Clamped ||
         type == DOMArrayBufferView::kTypeInt16 ||
         type == DOMArrayBufferView::kTypeUint16 ||
         type == DOMArrayBufferView::kTypeInt32 ||
         type == DOMArrayBufferView::kTypeUint32 ||
         type == DOMArrayBufferView::kTypeBigInt64 ||
         type == DOMArrayBufferView::kTypeBigUint64;
}

}  // namespace

NotShared<DOMArrayBufferView> Crypto::getRandomValues(
    NotShared<DOMArrayBufferView> array,
    ExceptionState& exception_state) {
  if (!array) {
    exception_state.ThrowDOMException(DOMExceptionCode::kTypeMismatchError,
                                      "The provided ArrayBufferView is null.");
    return NotShared<DOMArrayBufferView>(nullptr);
  }
  if (!IsIntegerArray(array->GetType())) {
    exception_state.ThrowDOMException(
        DOMExceptionCode::kTypeMismatchError,
        String::Format("The provided ArrayBufferView is of type '%s', which is "
                       "not an integer array type.",
                       array->TypeName()));
    return NotShared<DOMArrayBufferView>(nullptr);
  }
  if (array->byteLength() > 65536) {
    exception_state.ThrowDOMException(
        DOMExceptionCode::kQuotaExceededError,
        String::Format("The ArrayBufferView's byte length (%zu) exceeds the "
                       "number of bytes of entropy available via this API "
                       "(65536).",
                       array->byteLength()));
    return NotShared<DOMArrayBufferView>(nullptr);
  }
  base::RandBytes(array->ByteSpan());
  return array;
}

}  // namespace blink
```

### 2.2 Architectural Invariants
1. **Unsigned Size Representation:** `DOMArrayBufferView::byteLength()` returns a `size_t`, which is an unsigned integer type guaranteeing $0 \le \text{byteLength}()$ at the C++ type level. When lifting to arbitrary-precision integers ($\mathbb{Z}$) in formal verification, both the lower bound ($0 \le sz$) and upper bound ($sz \le 65536$) must be explicitly asserted to prevent negative-length underflow vulnerabilities during FFI/span conversion.
2. **Order of Evaluation:** The type check (`IsIntegerArray`) strictly precedes the quota check (`byteLength() > 65536`). Passing a `Float64Array` of size $131072$ bytes must throw `TypeMismatchError`, not `QuotaExceededError`.
3. **BoringSSL CSPRNG Invocation:** `base::RandBytes(base::span<uint8_t>)` calls `CRYPTO_sysrand` / `RAND_bytes` in BoringSSL. In BoringSSL (`crypto/fipsmodule/rand/rand.c`), `RAND_bytes` draws from a thread-local ChaCha20-based DRBG seeded by OS entropy (`getrandom` / `RtlGenRandom`). Bounding the synchronous IPC/syscall surface in the renderer to $\le 65536$ bytes guarantees bounded execution time per JS call and safe conversion across `size_t` and `int` interfaces.

---

## 3. Formal Specification in Rocq / Coq

We construct the complete, self-contained formalization in Rocq (`BlinkWebCryptoGetRandomValuesQuotaSemantics.v`), modeling the DOM exception states, `ArrayBufferView` types, the quota decision procedure, and the operational semantics of `Crypto::getRandomValues`.

```coq
(** * BlinkWebCryptoGetRandomValuesQuotaSemantics.v
    Formal verification of Chromium Blink's WebCrypto getRandomValues
    quota bounding and exception semantics (W3C Web Cryptography API §10.1). *)

From Coq Require Import ZArith.
From Coq Require Import Bool.
From Coq Require Import Lia.
From Coq Require Import List.
Import ListNotations.

Open Scope Z_scope.
Open Scope bool_scope.

(** ** 1. Constants and Quota Predicate *)

Definition MAX_RANDOM_BYTES : Z := 65536.

(** The core mathematical property governing valid byte lengths for CSPRNG fills. *)
Definition valid_random_bytes (sz : Z) : bool :=
  (sz <=? MAX_RANDOM_BYTES) && (0 <=? sz).

(** Propositional counterpart to [valid_random_bytes]. *)
Definition ValidRandomBytesProp (sz : Z) : Prop :=
  0 <= sz <= MAX_RANDOM_BYTES.

(** ** 2. Blink DOM Types and Exception Modeling *)

Inductive ViewType : Type :=
  | kTypeInt8
  | kTypeUint8
  | kTypeUint8Clamped
  | kTypeInt16
  | kTypeUint16
  | kTypeInt32
  | kTypeUint32
  | kTypeBigInt64
  | kTypeBigUint64
  | kTypeFloat32
  | kTypeFloat64
  | kTypeDataView.

Definition is_integer_array (t : ViewType) : bool :=
  match t with
  | kTypeInt8
  | kTypeUint8
  | kTypeUint8Clamped
  | kTypeInt16
  | kTypeUint16
  | kTypeInt32
  | kTypeUint32
  | kTypeBigInt64
  | kTypeBigUint64 => true
  | kTypeFloat32
  | kTypeFloat64
  | kTypeDataView => false
  end.

Inductive DOMExceptionCode : Type :=
  | kTypeMismatchError
  | kQuotaExceededError.

Record DOMArrayBufferView : Type := mkView {
  view_type : ViewType;
  byte_length : Z;
  (** Represents the abstract state of the underlying memory buffer *)
  buffer_entropy_tag : Z
}.

(** Well-formed C++ DOMArrayBufferView instances have non-negative size_t lengths. *)
Definition wf_view (v : DOMArrayBufferView) : Prop :=
  0 <= byte_length v.

(** Result of executing Crypto::getRandomValues *)
Inductive CryptoResult : Type :=
  | CryptoSuccess (v : DOMArrayBufferView) (bytes_drawn : Z)
  | CryptoException (code : DOMExceptionCode).

(** ** 3. Operational Semantics of Blink's Crypto::getRandomValues *)

(** Models base::RandBytes mutating the view's span with fresh entropy. *)
Definition apply_rand_bytes (v : DOMArrayBufferView) (new_entropy_tag : Z) : DOMArrayBufferView :=
  mkView (view_type v) (byte_length v) new_entropy_tag.

(** Faithful model of blink::Crypto::getRandomValues in crypto.cc.
    Note: To ensure total soundness over Z, we explicitly check negativity
    alongside the quota bound via [valid_random_bytes], and prove equivalence
    to the C++ implementation under the [wf_view] (size_t) invariant. *)
Definition blink_get_random_values
  (opt_view : option DOMArrayBufferView)
  (entropy_stream_tag : Z) : CryptoResult :=
  match opt_view with
  | None => CryptoException kTypeMismatchError
  | Some v =>
      if negb (is_integer_array (view_type v)) then
        CryptoException kTypeMismatchError
      else if negb (valid_random_bytes (byte_length v)) then
        CryptoException kQuotaExceededError
      else
        CryptoSuccess (apply_rand_bytes v entropy_stream_tag) (byte_length v)
  end.

(** Exact syntactic mirror of the C++ check `array->byteLength() > 65536` *)
Definition cpp_blink_get_random_values
  (opt_view : option DOMArrayBufferView)
  (entropy_stream_tag : Z) : CryptoResult :=
  match opt_view with
  | None => CryptoException kTypeMismatchError
  | Some v =>
      if negb (is_integer_array (view_type v)) then
        CryptoException kTypeMismatchError
      else if byte_length v >? MAX_RANDOM_BYTES then
        CryptoException kQuotaExceededError
      else
        CryptoSuccess (apply_rand_bytes v entropy_stream_tag) (byte_length v)
  end.
```

---

## 4. Formal Theorems and Complete Proofs

Below is the complete verification suite proving reflection, boundary exactness, C++ implementation equivalence under `size_t` invariants, exception precedence, and BoringSSL CSPRNG quota safety. Every theorem is proven without `admit` or `Admitted`.

```coq
(** ** 4. Formal Verification Theorems and Proofs *)

(** Theorem 1: Boolean-to-Proposition Reflection for valid_random_bytes. *)
Theorem valid_random_bytes_iff : forall sz : Z,
  valid_random_bytes sz = true <-> ValidRandomBytesProp sz.
Proof.
  intros sz.
  unfold valid_random_bytes, ValidRandomBytesProp, MAX_RANDOM_BYTES.
  rewrite andb_true_iff.
  rewrite Z.leb_le.
  rewrite Z.leb_le.
  lia.
Qed.

(** Theorem 2: Exact characterization of quota violation / invalid byte lengths. *)
Theorem valid_random_bytes_false_iff : forall sz : Z,
  valid_random_bytes sz = false <-> (sz < 0 \/ sz > MAX_RANDOM_BYTES).
Proof.
  intros sz.
  unfold valid_random_bytes, MAX_RANDOM_BYTES.
  rewrite andb_false_iff.
  rewrite Z.leb_gt.
  rewrite Z.leb_gt.
  lia.
Qed.

(** Theorem 3: Boundary Conditions Verification (0, 65536, -1, 65537). *)
Theorem valid_random_bytes_boundaries :
  valid_random_bytes 0 = true /\
  valid_random_bytes 65536 = true /\
  valid_random_bytes (-1) = false /\
  valid_random_bytes 65537 = false.
Proof.
  unfold valid_random_bytes, MAX_RANDOM_BYTES.
  repeat split; reflexivity.
Qed.

(** Theorem 4: Equivalence of the C++ > 65536 check and valid_random_bytes
    for all well-formed views (where byteLength is an unsigned size_t >= 0). *)
Theorem cpp_check_equiv_valid_random_bytes : forall v : DOMArrayBufferView,
  wf_view v ->
  negb (valid_random_bytes (byte_length v)) = (byte_length v >? MAX_RANDOM_BYTES).
Proof.
  intros v Hwf.
  unfold wf_view in Hwf.
  unfold valid_random_bytes, MAX_RANDOM_BYTES.
  destruct (Z.leb_spec0 0 (byte_length v)) as [Hge | Hlt].
  - rewrite andb_true_r.
    rewrite Z.gtb_ltb.
    destruct (Z.leb_spec0 (byte_length v) 65536) as [Hle | Hgt];
    destruct (Z.ltb_spec0 65536 (byte_length v)) as [Hlt2 | Hge2];
    simpl; try reflexivity; lia.
  - exfalso. lia.
Qed.

(** Theorem 5: Semantic Observational Equivalence between C++ implementation
    and the total formal model for all well-formed DOMArrayBufferViews. *)
Theorem cpp_and_formal_semantics_equiv :
  forall (v : DOMArrayBufferView) (tag : Z),
    wf_view v ->
    cpp_blink_get_random_values (Some v) tag = blink_get_random_values (Some v) tag.
Proof.
  intros v tag Hwf.
  unfold cpp_blink_get_random_values, blink_get_random_values.
  destruct (negb (is_integer_array (view_type v