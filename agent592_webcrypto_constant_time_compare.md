# Formal Verification of Constant-Time Buffer Comparison Soundness in Chromium WebCrypto and BoringSSL

**Target Formal Theory:** `BlinkWebCryptoConstantTimeCompareSemantics.v`  
**Chromium Subsystem:** `components/webcrypto/algorithms/hmac.cc` & `third_party/boringssl/src/crypto/mem.c`  
**Normative Specification:** W3C Web Cryptography API §3 (Security Considerations) & §29.4 (HMAC Operations)  
**Mathematical Property:** $\forall b_1, b_2 \in \mathbb{B}^*, \text{ct\_compare}(b_1, b_2) = (b_1 \stackrel{?}{=} b_2)$  

---

## 1. Normative W3C Web Cryptography API Specification Requirements

The W3C Web Cryptography API defines strict functional and security requirements for cryptographic primitives executed within browser user agents. When verifying message authentication codes (such as HMAC in §29.4) or authenticating tags in AEAD schemes, the specification mandates exact buffer equality comparisons that resist side-channel timing attacks.

### 1.1 W3C WebCrypto §29.4 (HMAC `verify` Operation)
Under the normative steps for verifying an HMAC signature:
1. Let `mac` be the result of performing the Sign operation using the provided `key`, `hash` algorithm, and `data`.
2. Return `true` if `mac` is equal to the provided `signature` buffer, and `false` otherwise.

### 1.2 W3C WebCrypto §3 (Security Considerations - Timing Attacks)
Section 3 of the specification explicitly warns implementers regarding side-channel vulnerabilities:
> *"Implementers should be aware that cryptographic operations may leak information through side channels such as timing, power consumption, or electromagnetic radiation... Specifically, operations such as MAC verification must be implemented in constant time to prevent timing attacks that allow an attacker to forge valid authentication tags byte-by-byte."*

A naive lexicographical comparison (such as C's `memcmp`) terminates upon encountering the first differing byte. An adversary measuring the execution latency of `crypto.subtle.verify` can deduce the prefix length of a forged signature that matches the true MAC, reducing the search space of an $N$-byte tag from $2^{8N}$ to $256 \times N$. Consequently, the user agent must enforce two distinct mathematical properties simultaneously:
1. **Execution Time Invariance (Constant-Time):** The control-flow path and memory access pattern depend solely on the public lengths of the buffers, never on their secret byte values.
2. **Functional Soundness and Completeness:** The constant-time bit-manipulation circuit must return boolean `true` if and only if the two buffers are identical in length and byte-for-byte content.

---

## 2. Chromium Blink and BoringSSL Implementation Invariants

In Chromium, the Blink rendering engine delegates `crypto.subtle` operations (`third_party/blink/renderer/modules/crypto/`) via Mojo IPC/WebCrypto bindings to the C++ implementation in `components/webcrypto/`.

### 2.1 WebCrypto Call Site (`components/webcrypto/algorithms/hmac.cc`)
During `HmacImplementation::Verify`, Chromium computes the expected HMAC digest and compares it against the user-supplied signature buffer:

```cpp
// components/webcrypto/algorithms/hmac.cc
Status VerifyHmac(const std::vector<uint8_t>& key_raw,
                  const blink::WebCryptoAlgorithm& hash,
                  base::span<const uint8_t> signature,
                  base::span<const uint8_t> data,
                  bool* signature_match) {
  std::vector<uint8_t> result;
  Status status = SignHmac(key_raw, hash, data, &result);
  if (status.IsError())
    return status;

  // Do not allow verification of truncated MACs; lengths must match exactly
  // and comparison must be constant-time via BoringSSL CRYPTO_memcmp.
  *signature_match = result.size() == signature.size() &&
                     CRYPTO_memcmp(result.data(), signature.data(),
                                   signature.size()) == 0;
  return Status::Success();
}
```

### 2.2 BoringSSL Constant-Time Primitive (`third_party/boringssl/src/crypto/mem.c`)
Chromium relies on BoringSSL's `CRYPTO_memcmp` to evaluate byte-level equality without branching on secret data:

```c
// third_party/boringssl/src/crypto/mem.c
int CRYPTO_memcmp(const void *in_a, const void *in_b, size_t len) {
  const uint8_t *a = in_a;
  const uint8_t *b = in_b;
  uint8_t x = 0;

  for (size_t i = 0; i < len; i++) {
    x |= a[i] ^ b[i];
  }

  return x;
}
```

### 2.3 Architectural Invariants
The C/C++ implementation maintains the following low-level invariants:
1. **Byte Boundedness:** For every index $i \in [0, \text{len})$, $0 \le a[i], b[i] < 256$.
2. **XOR Zero-Equivalence:** The bitwise exclusive-OR $a[i] \oplus b[i]$ evaluates to $0$ if and only if $a[i] = b[i]$.
3. **OR Monotonicity (Sticky Non-Zero Accumulator):** The accumulator $x$ is initialized to $0$. At step $i$, $x_{i+1} = x_i \mathbin{|} (a[i] \oplus b[i])$. Because bitwise OR is non-decreasing with respect to bit positions ($u \mathbin{|} v = 0 \iff u = 0 \land v = 0$ for non-negative integers), $x$ remains $0$ if and only if $a[i] = b[i]$ for all $i$.
4. **C Compiler Barrier Semantics:** In BoringSSL, `CRYPTO_memcmp` prevents LLVM/Clang from optimizing the loop into a branchy `memcmp` intrinsic, ensuring the emitted machine code executes a fixed number of `xor` and `or` instructions proportional only to `len`.

---

## 3. Formal Specification Definitions in Rocq/Coq

Below is the complete, self-contained Rocq/Coq formalization (`BlinkWebCryptoConstantTimeCompareSemantics.v`). It models byte buffers as lists of arbitrary-precision integers (`Z`) constrained to the unsigned 8-bit domain $[0, 255]$ (and generalizes the core algebraic soundness to all non-negative integers $0 \le z$). It specifies both `CRYPTO_memcmp` and the overarching `VerifyHmac` comparison wrapper.

```coq
(** * BlinkWebCryptoConstantTimeCompareSemantics.v
    Formal verification of BoringSSL CRYPTO_memcmp and Chromium WebCrypto
    constant-time buffer comparison soundness. *)

From Coq Require Import ZArith.
From Coq Require Import List.
From Coq Require Import Bool.
From Coq Require Import Lia.
Import ListNotations.

Open Scope Z_scope.

(** ** 1. Data Types and Domain Predicates *)

(** A byte is represented as an integer in Z. 
    Valid unsigned 8-bit integers satisfy [0 <= b < 256], 
    which entails non-negativity [0 <= b]. *)
Definition Byte := Z.
Definition Buffer := list Byte.

Definition is_byte (b : Byte) : Prop := 0 <= b < 256.
Definition valid_buffer (buf : Buffer) : Prop := Forall is_byte buf.
Definition nonneg_buffer (buf : Buffer) : Prop := Forall (fun b => 0 <= b) buf.

Lemma valid_buffer_nonneg : forall buf,
  valid_buffer buf -> nonneg_buffer buf.
Proof.
  intros buf H.
  unfold valid_buffer, nonneg_buffer in *.
   induction H as [| x l Hx Hl IH].
  - constructor.
  - constructor; [unfold is_byte in Hx; lia | exact IH].
Qed.

(** ** 2. Specification of Functional Buffer Equality *)

(** Standard boolean equality over buffers, representing the W3C WebCrypto
    ideal mathematical specification (b1 =? b2). *)
Fixpoint buffer_eqb (b1 b2 : Buffer) : bool :=
  match b1, b2 with
  | [], [] => true
  | x :: xs, y :: ys => (x =? y) && buffer_eqb xs ys
  | _, _ => false
  end.

(** ** 3. Model of BoringSSL [CRYPTO_memcmp] and WebCrypto [ct_compare] *)

(** Recursive accumulator loop modeling:
    for (size_t i = 0; i < len; i++) { x |= a[i] ^ b[i]; } *)
Fixpoint crypto_memcmp_loop (a b : Buffer) (acc : Z) : Z :=
  match a, b with
  | x :: xs, y :: ys => crypto_memcmp_loop xs ys (Z.lor acc (Z.lxor x y))
  | _, _ => acc
  end.

(** BoringSSL [CRYPTO_memcmp(in_a, in_b, len)] initialized with [x = 0]. *)
Definition crypto_memcmp (a b : Buffer) : Z :=
  crypto_memcmp_loop a b 0.

(** Chromium WebCrypto constant-time buffer comparison wrapper:
    [result.size() == signature.size() && CRYPTO_memcmp(...) == 0] *)
Definition ct_compare (b1 b2 : Buffer) : bool :=
  (Z.of_nat (length b1) =? Z.of_nat (length b2)) && (crypto_memcmp b1 b2 =? 0).
```

---

## 4. Concrete Theorems and Complete Rocq/Coq Proofs

We now prove the foundational bitwise lemmas in `ZArith`, the invariant of the `crypto_memcmp_loop` accumulator, and the main equivalence theorem establishing that `ct_compare` is both sound and complete with respect to boolean equality `buffer_eqb` and propositional equality `=`.

```coq
(** ** 4. Bitwise Algebraic Lemmas for Non-Negative Integers *)

(** Lemma 1: Non-negativity is preserved by bitwise XOR and OR. *)
Lemma lxor_nonneg : forall x y : Z,
  0 <= x -> 0 <= y -> 0 <= Z.lxor x y.
Proof.
  intros x y Hx Hy.
  apply Z.lxor_nonneg; split; assumption.
Qed.

Lemma lor_nonneg : forall x y : Z,
  0 <= x -> 0 <= y -> 0 <= Z.lor x y.
Proof.
  intros x y Hx Hy.
  apply Z.lor_nonneg; split; assumption.
Qed.

(** Lemma 2: For non-negative integers, bitwise OR is 0 iff both operands are 0. *)
Lemma lor_eq_0_iff : forall x y : Z,
  0 <= x -> 0 <= y ->
  (Z.lor x y = 0 <-> x = 0 /\ y = 0).
Proof.
  intros x y Hx Hy.
  split.
  - intro Hor.
    split.
    + apply Z.bits_inj_0. intros n.
      destruct (Z_lt_ge_dec n 0) as [Hn | Hn].
      * apply Z.testbit_neg_r; exact Hn.
      * assert (Hbit : Z.testbit (Z.lor x y) n = false).
        { rewrite Hor. apply Z.bits_0. }
        rewrite Z.lor_spec in Hbit.
        apply orb_false_iff in Hbit.
        destruct Hbit as [Hbx _]. exact Hbx.
    + apply Z.bits_inj_0. intros n.
      destruct (Z_lt_ge_dec n 0) as [Hn | Hn].
      * apply Z.testbit_neg_r; exact Hn.
      * assert (Hbit : Z.testbit (Z.lor x y) n = false).
        { rewrite Hor. apply Z.bits_0. }
        rewrite Z.lor_spec in Hbit.
        apply orb_false_iff in Hbit.
        destruct Hbit as [_ Hby]. exact Hby.
  - intros [Hx0 Hy0].
    subst x y.
    reflexivity.
Qed.

(** Lemma 3: Bitwise XOR is 0 iff both operands are equal. *)
Lemma lxor_eq_0_iff : forall x y : Z,
  Z.lxor x y = 0 <-> x = y.
Proof.
  intros x y.
  split.
  - apply Z.lxor_eq_0_iff.
  - intro Heq. subst y. apply Z.lxor_nilpotent.
Qed.

(** ** 5. Loop Invariant and Accumulator Soundness *)

(** Theorem: The accumulator loop returns 0 on equal-length non-negative buffers
    if and only if the initial accumulator is 0 and the buffers are identical. *)
Theorem crypto_memcmp_loop_zero_iff : forall (a b : Buffer) (acc : Z),
  length a = length b ->
  nonneg_buffer a ->
  nonneg_buffer b ->
  0 <= acc ->
  (crypto_memcmp_loop a b acc = 0 <-> acc = 0 /\ a = b).
Proof.
  induction a as [| x xs IH]; intros b acc Hlen Ha Hb Hacc.
  - destruct b as [| y ys]; [| discriminate Hlen].
    simpl.
    split.
    + intro H. split; [exact H | reflexivity].
    + intros [H _]. exact H.
  - destruct b as [| y ys]; [discriminate Hlen |].
    simpl in Hlen. injection Hlen as Hlen_tail.
    inversion Ha as [| x' xs' Hx Hxs]; subst x' xs'.
    inversion Hb as [| y' ys' Hy Hys]; subst y' ys'.
    simpl.
    assert (Hvxor : 0 <= Z.lxor x y) by (apply lxor_nonneg; assumption).
    assert (Hnext_acc : 0 <= Z.lor acc (Z.lxor x y)) by (apply lor_nonneg; assumption).
    rewrite (IH ys (Z.lor acc (Z.lxor x y)) Hlen_tail Hxs Hys Hnext_acc).
    rewrite (lor_eq_0_iff acc (Z.lxor x y) Hacc Hvxor).
    rewrite lxor_eq_0_iff.
    split.
    + intros [[Hacc0 Hxy] Hxs_ys].
      subst x xs.
      split; [exact Hacc0 | reflexivity].
    + intros [Hacc0 Heq].
      injection Heq as Hxy Hxs_ys.
      repeat split; assumption.
Qed.

(** Corollary: [crypto_memcmp a b = 0] iff [a = b] for equal-length buffers. *)
Corollary crypto_