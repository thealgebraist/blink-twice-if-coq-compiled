# Formal Verification of `CryptoKey.extractable` Immutability in Chromium Blink

**Author**: Formal Methods & Web Cryptography Research Group  
**Target Component**: `third_party/blink/renderer/modules/crypto/crypto_key.cc`  
**Normative Specification**: W3C Web Cryptography API §13.1 (`CryptoKey` Interface)  
**Formal Artifact**: `BlinkWebCryptoCryptoKeyExtractableSemantics.v`  
**Theorem Prover**: Rocq / Coq (8.18+)

---

## 1. Normative W3C Web Cryptography API Requirements

In the W3C Web Cryptography API Specification (§13.1, *The CryptoKey Interface*), cryptographic keys are represented to JavaScript execution contexts via the `CryptoKey` WebIDL interface:

```webidl
[SecureContext, Exposed=(Window,Worker)]
interface CryptoKey {
  readonly attribute KeyType type;
  readonly attribute boolean extractable;
  readonly attribute object algorithm;
  readonly attribute object usages;
};
```

### Normative Invariants (§13.1 & §13.2)
1. **Internal Slot Representation**: Every `CryptoKey` object possesses an internal slot `[[extractable]]`, which is a boolean value indicating whether the raw keying material may be exported out of the WebCrypto subsystem via `SubtleCrypto.exportKey()` or `SubtleCrypto.wrapKey()`.
2. **Read-Only Accessor Semantics**: The `extractable` getter step must return the exact value stored in the `[[extractable]]` internal slot without side effects.
3. **Strict Temporal Immutability**: Once a `CryptoKey` instance is constructed (via `generateKey`, `importKey`, `deriveKey`, or `unwrapKey`), the `[[extractable]]` internal slot is never mutated throughout the lifetime of the object. No WebCrypto operation—whether successful or failing—may transition `[[extractable]]` from `false` to `true` (privilege escalation) or from `true` to `false`.
4. **Structured Clone Preservation (§13.4)**: During structured serialization/deserialization (e.g., `postMessage`), the deserialized `CryptoKey` must initialize its `[[extractable]]` slot to the exact boolean value of the source key's `[[extractable]]` slot.

---

## 2. Chromium Blink Implementation Analysis

In Chromium, the WebIDL `CryptoKey` interface is backed by the C++ class `blink::CryptoKey` located in `third_party/blink/renderer/modules/crypto/crypto_key.h` and `crypto_key.cc`, which wraps a platform-layer `blink::WebCryptoKey` (`public/platform/web_crypto_key.h`).

### Architectural Layout in `crypto_key.cc` and `web_crypto_key.cc`

```cpp
// third_party/blink/renderer/modules/crypto/crypto_key.h
class MODULES_EXPORT CryptoKey final : public ScriptWrappable {
  DEFINE_WRAPPERTYPEINFO();
 public:
  CryptoKey(const WebCryptoKey& key) : key_(key) {}
  ~CryptoKey() override = default;

  bool extractable() const { return key_.Extractable(); }
  const WebCryptoKey& Key() const { return key_; }

 private:
  const WebCryptoKey key_;
};
```

At the platform boundary (`blink/renderer/platform/exported/web_crypto_key.cc`):

```cpp
class WebCryptoKeyPrivate : public WTF::ThreadSafeRefCounted<WebCryptoKeyPrivate> {
 public:
  WebCryptoKeyPrivate(std::unique_ptr<WebCryptoKeyHandle> handle,
                      WebCryptoKeyType type,
                      bool extractable,
                      const WebCryptoKeyAlgorithm& algorithm,
                      WebCryptoKeyUsageMask usages)
      : handle_(std::move(handle)),
        type_(type),
        extractable_(extractable),
        algorithm_(algorithm),
        usages_(usages) {}

  bool Extractable() const { return extractable_; }

 private:
  const std::unique_ptr<WebCryptoKeyHandle> handle_;
  const WebCryptoKeyType type_;
  const bool extractable_;
  const WebCryptoKeyAlgorithm algorithm_;
  const WebCryptoKeyUsageMask usages_;
};
```

### Implementation Invariants
1. **C++ `const` Qualification**: Both `CryptoKey::key_` in the Oilpan-managed `ScriptWrappable` wrapper and `WebCryptoKeyPrivate::extractable_` in the thread-safe reference-counted inner representation are declared `const`.
2. **Absence of Mutator Methods**: Neither `blink::CryptoKey` nor `blink::WebCryptoKey` nor `blink::WebCryptoKeyPrivate` exposes any setter, friend mutator, or `const_cast` pathway capable of modifying `extractable_`.
3. **BoringSSL Isolation**: The underlying BoringSSL key handle (`EVP_PKEY*` or raw symmetric bytes inside `WebCryptoKeyHandle`) is opaque to the renderer's V8 bindings; all export gatekeeping in `crypto_key.cc` (`CryptoKey::CanBeUsedForUsage` and `SubtleCrypto::exportKey`) queries `key_.Extractable()` prior to invoking the background BoringSSL worker thread.

---

## 3. Formal Specification in Rocq / Coq

Below is the complete, self-contained formalization of `BlinkWebCryptoCryptoKeyExtractableSemantics.v`. It models the Blink `CryptoKey` state space, all possible WebCrypto operations, structured cloning, and BoringSSL export gatekeeping.

```coq
(** * BlinkWebCryptoCryptoKeyExtractableSemantics.v
    Formal Verification of W3C Web Cryptography API §13.1
    Chromium Target: third_party/blink/renderer/modules/crypto/crypto_key.cc
    Property: Strict temporal and operational immutability of CryptoKey.extractable
*)

From Coq Require Import Bool.Bool.
From Coq Require Import ZArith.ZArith.
From Coq Require Import Lists.List.
From Coq Require Import Micromeega.Lia.
Import ListNotations.

Open Scope Z_scope.
Open Scope bool_scope.

(** ** 1. Cryptographic Primitives & WebIDL Types *)

Inductive KeyType : Type :=
  | Secret
  | Public
  | Private.

Inductive KeyUsage : Type :=
  | Encrypt
  | Decrypt
  | Sign
  | Verify
  | DeriveKey
  | DeriveBits
  | WrapKey
  | UnwrapKey.

Definition UsageMask := Z.

(** BoringSSL opaque handle identifier and key material representation *)
Record BoringSSLKeyHandle : Type := mkHandle {
  handle_id : Z;
  raw_key_bits : Z
}.

(** WebCryptoKeyPrivate (platform layer: web_crypto_key.cc) *)
Record WebCryptoKeyPrivate : Type := mkWebCryptoKeyPrivate {
  wck_handle : BoringSSLKeyHandle;
  wck_type : KeyType;
  wck_extractable : bool;
  wck_algorithm_id : Z;
  wck_usages : UsageMask
}.

(** blink::CryptoKey (renderer layer: crypto_key.cc) *)
Record BlinkCryptoKey : Type := mkBlinkCryptoKey {
  bck_object_id : Z;
  bck_key : WebCryptoKeyPrivate
}.

(** ** 2. Accessor Semantics (crypto_key.cc) *)

(** Corresponds to `bool WebCryptoKey::Extractable() const` *)
Definition web_crypto_key_extractable (k : WebCryptoKeyPrivate) : bool :=
  wck_extractable k.

(** Corresponds to `bool CryptoKey::extractable() const` *)
Definition blink_crypto_key_extractable (ck : BlinkCryptoKey) : bool :=
  web_crypto_key_extractable (bck_key ck).

(** ** 3. Constructor & Structured Clone Semantics *)

Definition construct_crypto_key
  (obj_id : Z)
  (h : BoringSSLKeyHandle)
  (ktype : KeyType)
  (extractable_arg : bool)
  (alg : Z)
  (usages : UsageMask) : BlinkCryptoKey :=
  mkBlinkCryptoKey obj_id
    (mkWebCryptoKeyPrivate h ktype extractable_arg alg usages).

(** Structured Clone (§13.4) creates a new Blink wrapper around identical private fields *)
Definition structured_clone_crypto_key (new_obj_id : Z) (src : BlinkCryptoKey) : BlinkCryptoKey :=
  let priv := bck_key src in
  mkBlinkCryptoKey new_obj_id
    (mkWebCryptoKeyPrivate
       (wck_handle priv)
       (wck_type priv)
       (wck_extractable priv)
       (wck_algorithm_id priv)
       (wck_usages priv)).

(** ** 4. Operational Transitions Across Key Lifetime *)

(** SubtleCrypto operations that inspect or use a CryptoKey during its lifetime *)
Inductive KeyOperation : Type :=
  | OpInspectExtractable
  | OpInspectType
  | OpInspectUsages
  | OpEncrypt (plaintext : Z)
  | OpDecrypt (ciphertext : Z)
  | OpSign (message : Z)
  | OpVerify (message : Z) (signature : Z)
  | OpExportKey
  | OpWrapKey (wrapping_key : BlinkCryptoKey)
  | OpStructuredClone (new_id : Z).

(** Result of an operation paired with the post-state of the CryptoKey *)
Inductive OpOutcome : Type :=
  | OkBool (b : bool)
  | OkData (d : Z)
  | OkCloned (cloned : BlinkCryptoKey)
  | ErrInvalidAccessError
  | ErrOperationError.

(** Export gatekeeper in SubtleCrypto::exportKey / wrapKey *)
Definition attempt_export (ck : BlinkCryptoKey) : OpOutcome :=
  if blink_crypto_key_extractable ck then
    OkData (raw_key_bits (wck_handle (bck_key ck)))
  else
    ErrInvalidAccessError.

(** Single-step operational semantics of Blink CryptoKey usage *)
Definition step_crypto_key (ck : BlinkCryptoKey) (op : KeyOperation)
  : (BlinkCryptoKey * OpOutcome) :=
  match op with
  | OpInspectExtractable => (ck, OkBool (blink_crypto_key_extractable ck))
  | OpInspectType        => (ck, OkData 0)
  | OpInspectUsages      => (ck, OkData (wck_usages (bck_key ck)))
  | OpEncrypt pt         => (ck, OkData (Z.lxor pt (raw_key_bits (wck_handle (bck_key ck)))))
  | OpDecrypt ct         => (ck, OkData (Z.lxor ct (raw_key_bits (wck_handle (bck_key ck)))))
  | OpSign msg           => (ck, OkData (Z.lxor msg (raw_key_bits (wck_handle (bck_key ck)))))
  | OpVerify _ _         => (ck, OkBool true)
  | OpExportKey          => (ck, attempt_export ck)
  | OpWrapKey _          => (ck, attempt_export ck)
  | OpStructuredClone id => (ck, OkCloned (structured_clone_crypto_key id ck))
  end.

(** Multi-step execution trace over the lifetime of a CryptoKey *)
Fixpoint exec_trace (ck : BlinkCryptoKey) (trace : list KeyOperation) : BlinkCryptoKey :=
  match trace with
  | [] => ck
  | op :: rest =>
      let (ck', _) := step_crypto_key ck op in
      exec_trace ck' rest
  end.

(** Collect all outcomes produced along an execution trace *)
Fixpoint exec_outcomes (ck : BlinkCryptoKey) (trace : list KeyOperation) : list OpOutcome :=
  match trace with
  | [] => []
  | op :: rest =>
      let (ck', out) := step_crypto_key ck op in
      out :: exec_outcomes ck' rest
  end.
```

---

## 4. Concrete Theorems and Complete Proofs

We now state and prove six core theorems establishing construction fidelity, single-step invariance, arbitrary trace immutability, structured clone preservation, non-escalation of non-extractable keys, and unconditional rejection of export attempts when `extractable = false`.

```coq
(** ** 5. Formal Theorems & Proofs *)

(** Theorem 1: Constructor Fidelity
    The `extractable()` getter on a newly constructed `blink::CryptoKey`
    returns the exact boolean passed at construction time. *)
Theorem construct_extractable_exact :
  forall (obj_id : Z) (h : BoringSSLKeyHandle) (ktype : KeyType)
         (ext : bool) (alg : Z) (usages : UsageMask),
    blink_crypto_key_extractable (construct_crypto_key obj_id h ktype ext alg usages) = ext.
Proof.
  intros obj_id h ktype ext alg usages.
  unfold construct_crypto_key, blink_crypto_key_extractable, web_crypto_key_extractable.
  simpl.
  reflexivity.
Qed.

(** Theorem 2: Single-Step Operational Immutability
    Every WebCrypto operation preserves the exact `extractable` boolean attribute. *)
Theorem step_preserves_extractable :
  forall (ck ck' : BlinkCryptoKey) (op : KeyOperation) (out : OpOutcome),
    step_crypto_key ck op = (ck', out) ->
    blink_crypto_key_extractable ck' = blink_crypto_key_extractable ck.
Proof.
  intros ck ck' op out Hstep.
  destruct op; simpl in Hstep; inversion Hstep; subst; reflexivity.
Qed.

(** Theorem 3: Lifetime Trace Immutability
    Across any finite sequence of WebCrypto operations over the lifetime of a key,
    `blink_crypto_key_extractable` is strictly invariant. *)
Theorem lifetime_extractable_immutable :
  forall (trace : list KeyOperation) (ck : BlinkCryptoKey),
    blink_crypto_key_extractable (exec_trace ck trace) = blink_crypto_key_extractable ck.
Proof.
  induction trace as [| op rest IH]; intros ck.
  - simpl. reflexivity.
  - simpl.
    destruct (step_crypto_key ck op) as [ck' out] eqn:Hstep.
    rewrite IH.
    eapply step_preserves_extractable.
    exact Hstep.
Qed.

(** Theorem 4: Structured Clone Extractable Preservation (§13.4)
    Cloning a CryptoKey across execution contexts preserves `extractable`. *)
Theorem structured_clone_preserves_extractable :
  forall (new_id : Z) (ck : BlinkCryptoKey),
    blink_crypto_key_extractable (structured_clone_crypto_key new_id ck) =
    blink_crypto_key_extractable ck.
Proof.
  intros new_id ck.
  unfold structured_clone_crypto_key, blink_crypto_key_extractable, web_crypto_key_extractable.
  simpl.
  reflexivity.
Qed.

(** Theorem 5: Impossibility of Privilege Escalation
    A key constructed with