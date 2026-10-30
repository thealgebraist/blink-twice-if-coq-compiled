# Formal Verification of Chromium Blink WebCrypto ECDSA Named Curve Validation

**Target Component:** `third_party/blink/renderer/modules/crypto/ec_key_gen_params.cc` (and normalization pipeline in `normalize_algorithm.cc`)  
**Specification:** W3C Web Cryptography API § 24.2 (ECDSA)  
**Formal Theory:** `BlinkWebCryptoECDSACurveSpecSemantics.v`  
**Core Invariant:** $\text{is\_valid\_curve}(c) \equiv (c = 256) \lor (c = 384) \lor (c = 521)$

---

## 1. Normative W3C Web Cryptography API Specification Requirements

Within the W3C Web Cryptography API specification, Section 24 defines the **ECDSA** algorithm, and Section 24.2 specifies the registration, parameter structures, and operational semantics for elliptic curve key generation and import operations.

### 1.1 WebIDL Dictionary Definitions (§ 24.3 & § 13)
Key generation and import operations for ECDSA rely on the `EcKeyGenParams` and `EcKeyImportParams` dictionaries, which specify the underlying elliptic curve via a `NamedCurve` DOMString:

```webidl
typedef DOMString NamedCurve;

dictionary EcKeyGenParams : Algorithm {
  required NamedCurve namedCurve;
};
```

### 1.2 Normative Curve Validation (§ 24.2.4 & § 24.2.5)
During the `generateKey` and `importKey` operations, the normalized algorithm parameters must satisfy strict domain constraints before any cryptographic primitives in the underlying library (BoringSSL) are invoked:

1. **String Normalization:** The `namedCurve` member of `normalizedAlgorithm` is evaluated against the registered NIST prime curves.
2. **Domain Restriction:** The specification strictly mandates:
   > *"If the `namedCurve` member of `normalizedAlgorithm` is `"P-256"`, `"P-384"` or `"P-521"`, perform the curve-specific generation steps... Otherwise, throw a `NotSupportedError`."*
3. **Cryptographic Group Parameters:**
   * `"P-256"` maps to NIST P-256 (`secp256r1`, prime order $n$ of bit-length 256).
   * `"P-384"` maps to NIST P-384 (`secp384r1`, prime order $n$ of bit-length 384).
   * `"P-521"` maps to NIST P-521 (`secp521r1`, prime order $n$ of bit-length 521).

Any curve identifier outside the set $\{"\text{P-256}", "\text{P-384}", "\text{P-521}"\}$—including brainpool curves, secp256k1, or Edwards curves (which belong to the Ed25519/Ed448 specifications rather than § 24 ECDSA)—must be rejected deterministically at the Blink boundary.

---

## 2. Blink Implementation Details and Invariants

In Chromium, the translation from V8 JavaScript objects to Blink internal representations and subsequently to BoringSSL `EC_GROUP` structures occurs across the Blink `modules/crypto` and `platform/exported` boundaries.

### 2.1 Architecture and Normalization Pipeline
The validation of `EcKeyGenParams` is enforced during algorithm normalization (`third_party/blink/renderer/modules/crypto/normalize_algorithm.cc` and `ec_key_gen_params.cc`), translating the WebIDL `EcKeyGenParams` into `blink::WebCryptoEcKeyGenParams`:

```cpp
// Conceptual representation of Blink's Curve Parsing & Parameter Instantiation
bool ParseNamedCurve(const String& curve_name, WebCryptoNamedCurve& curve) {
  if (curve_name == "P-256") {
    curve = kWebCryptoNamedCurveP256;
    return true;
  }
  if (curve_name == "P-384") {
    curve = kWebCryptoNamedCurveP384;
    return true;
  }
  if (curve_name == "P-521") {
    curve = kWebCryptoNamedCurveP521;
    return true;
  }
  return false;
}
```

### 2.2 Structural Invariants in `WebCryptoEcKeyGenParams`
1. **Closed Enum Representation:** Blink maps valid strings into a strongly-typed enumeration `blink::WebCryptoNamedCurve` (`public/platform/web_crypto_algorithm_params.h`):
   * `kWebCryptoNamedCurveP256` (Bit size: $256$)
   * `kWebCryptoNamedCurveP384` (Bit size: $384$)
   * `kWebCryptoNamedCurveP521` (Bit size: $521$)
2. **Total Rejection of Unrecognized Curves:** If `ParseNamedCurve` returns `false`, Blink immediately halts parameter construction and synthesizes a `DOMException` of type `NotSupportedError`, preventing uninitialized or out-of-bounds enum values from reaching `components/webcrypto/algorithms/ecdsa.cc` (which interfaces with BoringSSL's `EC_GROUP_new_by_curve_name`).
3. **BoringSSL NID Mapping:** Downstream in `components/webcrypto/algorithms/ec.cc`, the validated `WebCryptoNamedCurve` maps bijectively to BoringSSL NIDs:
   * $256 \leftrightarrow \text{NID\_X9\_62\_prime256v1}$
   * $384 \leftrightarrow \text{NID\_secp384r1}$
   * $521 \leftrightarrow \text{NID\_secp521r1}$

---

## 3. Formal Specification in Rocq / Coq

We model the curve validation semantics in Rocq (Coq) within the module `BlinkWebCryptoECDSACurveSpecSemantics.v`. Curves are represented by their canonical field bit-lengths $c \in \mathbb{Z}$, and the boolean validation gate is defined by:

$$\text{is\_valid\_curve}(c) = (c =? 256) \lor (c =? 384) \lor (c =? 521)$$

Below is the complete, self-contained formalization and proof script.

```coq
(** * BlinkWebCryptoECDSACurveSpecSemantics.v
    Formal Verification of W3C Web Cryptography API §24.2 ECDSA Curve Validation
    Target: third_party/blink/renderer/modules/crypto/ec_key_gen_params.cc *)

From Coq Require Import ZArith.
From Coq Require Import Bool.
From Coq Require Import Lia.
From Coq Require Import List.
Import ListNotations.

Open Scope Z_scope.
Open Scope bool_scope.

(** ** 1. Formal Domain Definitions *)

(** A curve identifier at the semantic boundary is represented by its bit-length in Z. *)
Definition CurveBitLength := Z.

(** Strongly-typed inductive representation corresponding to blink::WebCryptoNamedCurve *)
Inductive WebCryptoNamedCurve : Type :=
  | kWebCryptoNamedCurveP256 : WebCryptoNamedCurve
  | kWebCryptoNamedCurveP384 : WebCryptoNamedCurve
  | kWebCryptoNamedCurveP521 : WebCryptoNamedCurve.

(** WebCrypto Exception States per W3C §24.2 *)
Inductive WebCryptoError : Type :=
  | NotSupportedError : WebCryptoError.

(** Result Monad for Blink Algorithm Normalization *)
Inductive NormalizationResult (A : Type) : Type :=
  | Success : A -> NormalizationResult A
  | Failure : WebCryptoError -> NormalizationResult A.

Arguments Success {A} _.
Arguments Failure {A} _.

(** ** 2. Executable Specification & Predicate Definitions *)

(** Decidable boolean checker: is_valid_curve(c) = (c =? 256) || (c =? 384) || (c =? 521) *)
Definition is_valid_curve (c : CurveBitLength) : bool :=
  (c =? 256) || (c =? 384) || (c =? 521).

(** Propositional specification of W3C §24.2 valid ECDSA named curves *)
Definition Spec_ValidCurve (c : CurveBitLength) : Prop :=
  c = 256 \/ c = 384 \/ c = 521.

(** Canonical mapping from Blink enum back to prime field bit-length *)
Definition curve_to_bits (curve : WebCryptoNamedCurve) : CurveBitLength :=
  match curve with
  | kWebCryptoNamedCurveP256 => 256
  | kWebCryptoNamedCurveP384 => 384
  | kWebCryptoNamedCurveP521 => 521
  end.

(** Blink ec_key_gen_params / normalize_algorithm parser model *)
Definition parse_named_curve (c : CurveBitLength) : NormalizationResult WebCryptoNamedCurve :=
  if c =? 256 then Success kWebCryptoNamedCurveP256
  else if c =? 384 then Success kWebCryptoNamedCurveP384
  else if c =? 521 then Success kWebCryptoNamedCurveP521
  else Failure NotSupportedError.

(** Cryptographic security bound: NIST curves must provide at least 128-bit classic security
    (requiring field bit-length >= 256) and bounded by 521 bits. *)
Definition SecurityBound (c : CurveBitLength) : Prop :=
  256 <= c <= 521.
```

---

## 4. Concrete Theorems and Complete Rocq/Coq Proofs

We now prove the reflection equivalence, parser soundness/completeness, bijective round-trip correctness, and cryptographic security bounds using `ZArith`, `Bool`, and `Lia` with **zero admitted lemmas**.

```coq
(** ** 3. Formal Theorems and Proofs *)

(** Theorem 1: Boolean Reflection Equivalence
    Proves that the executable boolean gate `is_valid_curve` is sound and complete
    with respect to the propositional W3C specification `Spec_ValidCurve`. *)
Theorem is_valid_curve_iff_spec : forall (c : CurveBitLength),
  is_valid_curve c = true <-> Spec_ValidCurve c.
Proof.
  intros c.
  unfold is_valid_curve, Spec_ValidCurve.
  rewrite !orb_true_iff.
  rewrite !Z.eqb_eq.
  tauto.
Qed.

(** Corollary 1.1: Rejection Reflection
    Proves that `is_valid_curve c = false` if and only if `c` is not in {256, 384, 521}. *)
Theorem is_valid_curve_false_iff : forall (c : CurveBitLength),
  is_valid_curve c = false <-> (c <> 256 /\ c <> 384 /\ c <> 521).
Proof.
  intros c.
  unfold is_valid_curve.
  rewrite !orb_false_iff.
  rewrite !Z.eqb_neq.
  tauto.
Qed.

(** Theorem 2: Cryptographic Field Bit-Length Security Bounds
    Every valid curve accepted by the validator strictly satisfies 256 <= c <= 521,
    guaranteeing at least 128-bit elliptic curve discrete logarithm security (ECDLP). *)
Theorem valid_curve_security_bounds : forall (c : CurveBitLength),
  is_valid_curve c = true -> SecurityBound c.
Proof.
  intros c Hvalid.
  apply is_valid_curve_iff_spec in Hvalid.
  unfold SecurityBound, Spec_ValidCurve in *.
  lia.
Qed.

(** Theorem 3: Non-Malleability / Disjointness of Curve Classes
    Even numbers other than 256 and 384, and odd numbers other than 521 (such as 255 for Curve25519),
    are strictly rejected. Specifically, P-521 is the unique odd-bit-length curve accepted. *)
Theorem odd_valid_curve_is_521 : forall (c : CurveBitLength),
  is_valid_curve c = true -> Z.odd c = true -> c = 521.
Proof.
  intros c Hvalid Hodd.
  apply is_valid_curve_iff_spec in Hvalid.
  unfold Spec_ValidCurve in Hvalid.
  destruct Hvalid as [H256 | [H384 | H521]].
  - subst c. simpl in Hodd. discriminate Hodd.
  - subst c. simpl in Hodd. discriminate Hodd.
  - exact H521.
Qed.

(** Theorem 4: Rejection of Curve25519 / Secp224r1 / Secp192r1
    Explicitly proves that legacy NIST curves (P-192, P-224) and non-NIST curves (255)
    are rejected by the ECDSA validator. *)
Theorem legacy_and_non_nist_rejected :
  is_valid_curve 192 = false /\
  is_valid_curve 224 = false /\
  is_valid_curve 255 = false.
Proof.
  unfold is_valid_curve.
  simpl.
  repeat split; reflexivity.
Qed.

(** Theorem 5: Parser Soundness
    If Blink's `parse_named_curve` succeeds and yields a `WebCryptoNamedCurve`,
    then the input bit-length `c` must satisfy `is_valid_curve c = true` and match `curve_to_bits`. *)
Theorem parse_named_curve_sound : forall (c : CurveBitLength) (curve : WebCryptoNamedCurve),
  parse_named_curve c = Success curve ->
  is_valid_curve c = true /\ curve_to_bits curve = c.
Proof.
  intros c curve Hparse.
  unfold parse_named_curve in Hparse.
  destruct (c =? 256) eqn:E256.
  - inversion Hparse; subst; clear Hparse.
    apply Z.eqb_eq in E256; subst c.
    split; reflexivity.
  - destruct (c =? 384) eqn:E384.
    + inversion Hparse; subst; clear Hparse.
      apply Z.eqb_eq in E384; subst c.
      split; reflexivity.
    + destruct (c =? 521) eqn:E521.
      * inversion Hparse; subst; clear Hparse.
        apply Z.eqb_eq in E521; subst c.
        split; reflexivity.
      * discriminate Hparse.
Qed.

(** Theorem 6: Parser Completeness and Error Determinism
    `parse_named_curve` returns `Failure NotSupportedError` if and only if
    `is_valid_curve c = false`. *)
Theorem parse_named