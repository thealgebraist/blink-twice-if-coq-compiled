# Formal Verification of WebCrypto Wrapping Key Usage Enforcement in Chromium Blink

## 1. Normative Specification: W3C Web Cryptography API §14.3.11

In the W3C Web Cryptography API, the `SubtleCrypto.wrapKey()` method encapsulates a cryptographic key (`key`) using a designated wrapping key (`wrappingKey`), exporting the target key in a specified format and subsequently encrypting or key-wrapping the exported material.

According to **§ 14.3.11 (`wrapKey` method)** of the W3C Web Cryptography API specification, the operation must enforce strict key usage access control on `wrappingKey` before executing any key export or cryptographic transformation. Specifically:

1. **Step 1–7**: Parameter normalization, algorithm parsing (` normalizedAlgorithm`), and format validation (`format`).
2. **Step 8 (Key Usage Validation)**:
   > *"If the `[[usages]]` internal slot of `wrappingKey` does not contain an entry that is `"wrapKey"`, then return a Promise rejected with an `InvalidAccessError`."*
3. **Step 9–14**: Validation of algorithm match, extractability of `key` (`[[extractable]]` must be `true`), exportation of `key`, and execution of the underlying `wrapKey` or `encrypt` sub-operation.

### Security Invariant
The normative requirement guarantees separation of cryptographic domains. A key provisioned exclusively for data encryption (`"encrypt"`) cannot be co-opted to wrap and exfiltrate extractable `CryptoKey` objects unless explicitly granted the `"wrapKey"` usage capability within its `[[usages]]` bitmask.

---

## 2. Chromium Blink Implementation Analysis

In Chromium's Blink rendering engine, the entry point for `window.crypto.subtle.wrapKey` is implemented in `third_party/blink/renderer/modules/crypto/subtle_crypto.cc`, interacting with `CryptoKey` (`third_party/blink/renderer/modules/crypto/crypto_key.cc`) and the platform abstraction layer (`third_party/blink/public/platform/web_crypto_key.h`).

### 2.1 Bitmask Representation of Key Usages
In `web_crypto_key.h`, key usages are represented as a bitmask over a 16-bit/32-bit unsigned integer type (`WebCryptoKeyUsageMask`):

```cpp
enum WebCryptoKeyUsage {
  kWebCryptoKeyUsageEncrypt = 1 << 0,    // 0x01 (1)
  kWebCryptoKeyUsageDecrypt = 1 << 1,    // 0x02 (2)
  kWebCryptoKeyUsageSign = 1 << 2,       // 0x04 (4)
  kWebCryptoKeyUsageVerify = 1 << 3,     // 0x08 (8)
  kWebCryptoKeyUsageDeriveKey = 1 << 4,  // 0x10 (16)
  kWebCryptoKeyUsageDeriveBits = 1 << 5, // 0x20 (32)
  kWebCryptoKeyUsageWrapKey = 1 << 6,    // 0x40 (64)
  kWebCryptoKeyUsageUnwrapKey = 1 << 7,  // 0x80 (128)
  kWebCryptoKeyUsageLast = kWebCryptoKeyUsageUnwrapKey
};
typedef unsigned WebCryptoKeyUsageMask;
```

### 2.2 Enforcement in `subtle_crypto.cc`
Within `SubtleCrypto::wrapKey`, Blink validates the wrapping key's capabilities prior to dispatching the asynchronous task to the WebCrypto worker pool (which interfaces with BoringSSL):

```cpp
ScriptPromise SubtleCrypto::wrapKey(
    ScriptState* script_state,
    const String& raw_format,
    CryptoKey* key,
    CryptoKey* wrapping_key,
    const V8AlgorithmIdentifier* wrap_algorithm_identifier,
    ExceptionState& exception_state) {
  // ... [Format and Algorithm Normalization] ...

  // W3C WebCrypto §14.3.11 Step 8:
  if (!wrapping_key->CanBeUsedForAlgorithm(normalized_wrap_algorithm,
                                           kWebCryptoKeyUsageWrapKey,
                                           result)) {
    return promise;
  }

  // ... [Extractability Check & Worker Dispatch] ...
}
```

And inside `CryptoKey::CanBeUsedForAlgorithm`:

```cpp
bool CryptoKey::CanBeUsedForAlgorithm(const WebCryptoAlgorithm& algorithm,
                                      WebCryptoKeyUsage usage,
                                      CryptoResult* result) const {
  if (!(key_.Usages() & usage)) {
    result->CompleteWithError(kWebCryptoErrorTypeInvalidAccess,
                              "key.usages does not permit this operation");
    return false;
  }
  // ... [Algorithm ID matching] ...
  return true;
}
```

### 2.3 Implementation Invariants
1. **Bitwise Disjointness**: Each `WebCryptoKeyUsage` enumerator is a distinct power of two: $\forall i \in \{0..7\}, \text{Usage}_i = 2^i$. Specifically, `kWebCryptoKeyUsageWrapKey` $= 2^6 = 64$.
2. **Exact Bitmask Intersection**: The C++ expression `(key_.Usages() & usage) != 0` evaluates to `true` if and only if the 6th bit (0-indexed) of `key_.Usages()` is set to `1`.
3. **Fail-Closed Rejection**: If `(key_.Usages() & kWebCryptoKeyUsageWrapKey) == 0`, execution halts immediately via `CompleteWithError(kWebCryptoErrorTypeInvalidAccess, ...)`, preventing any invocation of BoringSSL's `EVP_CipherInit_ex` or `AES_wrap_key`.

---

## 3. Formal Specification in Rocq (Coq)

We formalize the bitmask semantics, the `CryptoKey` state, the `wrapKey` access control predicate, and the correspondence between the high-level set-membership specification and the low-level bitwise implementation in `BlinkWebCryptoWrappingKeyUsageSemantics.v`.

```coq
(** * BlinkWebCryptoWrappingKeyUsageSemantics.v
    Formal verification of W3C Web Cryptography API §14.3.11 wrappingKey usage
    enforcement in Chromium Blink (subtle_crypto.cc). *)

From Coq Require Import Bool.Bool.
From Coq Require Import ZArith.ZArith.
From Coq Require Import Lists.List.
From Coq Require Import Lia.
Import ListNotations.

Open Scope Z_scope.

(** ** 1. WebCrypto Key Usage Bitmask Definitions *)

Definition WebCryptoKeyUsageMask := Z.

Definition USAGE_ENCRYPT     : Z := 1.   (* 1 << 0 = 2^0 *)
Definition USAGE_DECRYPT     : Z := 2.   (* 1 << 1 = 2^1 *)
Definition USAGE_SIGN        : Z := 4.   (* 1 << 2 = 2^2 *)
Definition USAGE_VERIFY      : Z := 8.   (* 1 << 3 = 2^3 *)
Definition USAGE_DERIVE_KEY  : Z := 16.  (* 1 << 4 = 2^4 *)
Definition USAGE_DERIVE_BITS : Z := 32.  (* 1 << 5 = 2^5 *)
Definition USAGE_WRAP_KEY    : Z := 64.  (* 1 << 6 = 2^6 *)
Definition USAGE_UNWRAP_KEY  : Z := 128. (* 1 << 7 = 2^7 *)

Definition MAX_USAGE_MASK    : Z := 255. (* (1 << 8) - 1 *)

(** Predicate defining a valid usage mask in Blink *)
Definition valid_usage_mask (mask : WebCryptoKeyUsageMask) : Prop :=
  0 <= mask <= MAX_USAGE_MASK.

(** ** 2. Low-Level Bitwise Implementation Semantics (crypto_key.cc) *)

(** Corresponds to: `(key_.Usages() & usage) != 0` *)
Definition has_key_usage (key_usages : WebCryptoKeyUsageMask) (usage : Z) : bool :=
  negb (Z.eqb (Z.land key_usages usage) 0).

(** Wrapping key permission check in `SubtleCrypto::wrapKey` *)
Definition can_wrap (key_usages : WebCryptoKeyUsageMask) : bool :=
  has_key_usage key_usages USAGE_WRAP_KEY.

(** ** 3. High-Level Abstract Specification (W3C WebCrypto §14.3.11) *)

Inductive KeyUsage : Type :=
  | Encrypt
  | Decrypt
  | Sign
  | Verify
  | DeriveKey
  | DeriveBits
  | WrapKey
  | UnwrapKey.

Definition usage_to_bit (u : KeyUsage) : Z :=
  match u with
  | Encrypt    => 0
  | Decrypt    => 1
  | Sign       => 2
  | Verify     => 3
  | DeriveKey  => 4
  | DeriveBits => 5
  | WrapKey    => 6
  | UnwrapKey  => 7
  end.

Definition usage_to_mask (u : KeyUsage) : Z :=
  Z.shiftl 1 (usage_to_bit u).

(** W3C specification checks if bit 6 is set in the usages representation *)
Definition spec_contains_wrap_key (key_usages : WebCryptoKeyUsageMask) : bool :=
  Z.testbit key_usages (usage_to_bit WrapKey).

(** ** 4. Execution Model of SubtleCrypto::wrapKey Step 8 *)

Inductive WebCryptoError : Type :=
  | InvalidAccessError
  | NotSupportedError
  | OperationError.

Inductive WrapKeyCheckResult : Type :=
  | WrapAllowed
  | WrapRejected (err : WebCryptoError).

Definition check_wrapping_key_usage (wrapping_key_usages : WebCryptoKeyUsageMask)
  : WrapKeyCheckResult :=
  if can_wrap wrapping_key_usages then
    WrapAllowed
  else
    WrapRejected InvalidAccessError.
```

---

## 4. Formal Theorems and Complete Proofs

Below are the complete, self-contained, admitted-free Rocq proofs establishing the exact mathematical and security properties of `can_wrap` and `has_key_usage`.

```coq
(** * Formal Proofs for BlinkWebCryptoWrappingKeyUsageSemantics *)

(** Theorem 1: Fundamental definitional unfolding property.
    Proves the target mathematical property:
    can_wrap(key_usages) = has_key_usage(key_usages, USAGE_WRAP_KEY). *)
Theorem can_wrap_def :
  forall (key_usages : WebCryptoKeyUsageMask),
    can_wrap key_usages = has_key_usage key_usages USAGE_WRAP_KEY.
Proof.
  intros key_usages.
  unfold can_wrap.
  reflexivity.
Qed.

(** Lemma: USAGE_WRAP_KEY is exactly 2^6 (1 << 6). *)
Lemma usage_wrap_key_is_pow2 :
  USAGE_WRAP_KEY = 2 ^ 6 /\ usage_to_mask WrapKey = USAGE_WRAP_KEY.
Proof.
  unfold USAGE_WRAP_KEY, usage_to_mask, usage_to_bit.
  simpl.
  split; reflexivity.
Qed.

(** Lemma: For any integer x, (x & 2^6) is either 0 or 64, and is non-zero
    if and only if bit 6 of x is true. *)
Lemma land_pow2_testbit_6 :
  forall (x : Z),
    negb (Z.eqb (Z.land x 64) 0) = Z.testbit x 6.
Proof.
  intros x.
  change 64 with (2 ^ 6).
  rewrite <- Z.shiftl_1_l.
  (* Notice that Z.land x (1 << 6) has only bit 6 possibly set *)
  destruct (Z.testbit x 6) eqn:Hbit.
  - (* Case: bit 6 of x is 1 *)
    assert (Hneq : Z.land x (Z.shiftl 1 6) <> 0).
    {
      intro Heq.
      assert (Htb : Z.testbit (Z.land x (Z.shiftl 1 6)) 6 = Z.testbit 0 6).
      { rewrite Heq. reflexivity. }
      rewrite Z.land_spec in Htb.
      rewrite Z.shiftl_spec in Htb by lia.
      replace (6 - 6) with 0 in Htb by lia.
      simpl in Htb.
      rewrite Hbit in Htb.
      simpl in Htb.
      discriminate Htb.
    }
    apply Z.eqb_neq in Hneq.
    rewrite Hneq.
    simpl.
    reflexivity.
  - (* Case: bit 6 of x is 0 *)
    assert (Heq : Z.land x (Z.shiftl 1 6) = 0).
    {
      apply Z.bits_inj.
      intros n.
      rewrite Z.bits_0.
      destruct (Z.lt_ge_cases n 0) as [Hneg | Hnonneg].
      + apply Z.testbit_neg_r. exact Hneg.
      + rewrite Z.land_spec.
        destruct (Z.eq_dec n 6) as [Heq6 | Hneq6].
        * subst n. rewrite Hbit. simpl. reflexivity.
        * rewrite Z.shiftl_spec by exact Hnonneg.
          assert (Hbit1 : Z.testbit 1 (n - 6) = false).
          {
            destruct (Z.lt_ge_cases (n - 6) 0) as [Hlt | Hge].
            - apply Z.testbit_neg_r. exact Hlt.
            - assert (Hgt : n - 6 > 0) by lia.
               change 1 with (Z.ones 1).
              rewrite Z.ones_spec_high by lia.
              reflexivity.
          }
          rewrite Hbit1.
          rewrite andb_false_r.
          reflexivity.
    }
    apply Z.eqb_eq in Heq.
    rewrite Heq.
    simpl.
    reflexivity.
Qed.

(** Theorem 2: Equivalence between Blink's C++ bitwise check (`can_wrap`)
    and W3C's abstract bit-membership specification (`spec_contains_wrap_key`). *)
Theorem blink_impl_matches_w3c_spec :
  forall (key_usages : WebCryptoKeyUsageMask),
    can_wrap key_usages = spec_contains_wrap_key key_usages.
Proof.
  intros key_usages.
  unfold can_wrap, has_key_usage, USAGE_WRAP_KEY, spec_contains_wrap_key, usage_to_bit.
  apply land_pow2_testbit_6