# Formal Verification Report: WebAuthn Public Key COSE Algorithm Identifier Matching in Chromium

**Target Component:** `device/fido/fido_constants.cc`, `third_party/blink/renderer/modules/credentialmanagement/credentials_container.cc`  
**Specifications:** W3C WebAuthn Level 3, RFC 9053 (COSE Algorithms), RFC 8812 (CBOR Object Signing and Encryption Registrations for WebAuthn)  
**Formal Theory Target:** `BlinkWebAuthnCOSEAlgorithmSemantics.v`  
**Mathematical Invariants:** $\text{COSE\_ES256} = -7$, $\text{COSE\_RS256} = -257$, $\text{COSE\_EDDSA} = -8$

---

## 1. Normative Specification Requirements

### 1.1 W3C WebAuthn Level 3 & Credential Management Requirements
In the W3C Web Authentication (WebAuthn) Level 3 specification, cryptographic algorithms used for generating credential key pairs and signing assertion challenges are identified using CBOR Object Signing and Encryption (COSE) Algorithm Identifiers (`COSEAlgorithmIdentifier`, defined as a `long` in WebIDL).

Under **§ 5.3 Parameters for Credential Generation (`PublicKeyCredentialParameters`)**:
1. The Relying Party (RP) supplies a sequence of `PublicKeyCredentialParameters` in `PublicKeyCredentialCreationOptions.pubKeyCredParams`.
2. Each parameter structure contains:
   - `type`: Must be set to `"public-key"`. Any dictionary entry with an unrecognized `type` is ignored during parameter filtering by the User Agent.
   - `alg`: A `COSEAlgorithmIdentifier` specifying the cryptographic signature algorithm with which the newly generated credential will be used.
3. During `navigator.credentials.create()` (**§ 5.1.3 Create a New Credential**), if `pubKeyCredParams` is non-empty, the User Agent filters the sequence to retain only entries with `type == "public-key"`, preserving the RP's preference order. If `pubKeyCredParams` is initially empty, the User Agent defaults to inserting `[-7 (ES256), -257 (RS256)]`.

### 1.2 IETF RFC 9053 § 2.1 & RFC 8812 § 2 Normative Registrations
The integer mappings for `COSEAlgorithmIdentifier` are governed by the IANA COSE Algorithms registry, formally defined in RFC 9053 and RFC 8812:

| Algorithm Name | Description | COSE Value ($\mathbb{Z}$) | Specification |
| :--- | :--- | :---: | :--- |
| **ES256** | ECDSA w/ SHA-256 (typically over curve P-256 / secp256r1) | $-7$ | RFC 9053 § 2.1 |
| **EdDSA** | Edwards-Curve Digital Signature Algorithm (e.g., Ed25519) | $-8$ | RFC 9053 § 2.2 |
| **RS256** | RSASSA-PKCS1-v1_5 using SHA-256 | $-257$ | RFC 8812 § 2 |

**Security Requirement:** The User Agent and FIDO Authenticator MUST strictly match the signed 32-bit integer (`int32_t`) representations of these identifiers without implicit unsigned casting, integer truncation, or identifier collision. An authenticator MUST NOT generate a key pair for an algorithm identifier not present in the filtered `pubKeyCredParams` list negotiated by the client.

---

## 2. Chromium & Blink Implementation Analysis

### 2.1 `device/fido/fido_constants.h` and `device/fido/fido_constants.cc`
In Chromium's FIDO device layer, COSE algorithm identifiers are strongly typed using a scoped enumeration backed by `int32_t`:

```cpp
// device/fido/fido_constants.h
enum class CoseAlgorithmIdentifier : int32_t {
  kEs256 = -7,
  kEdDSA = -8,
  kRs256 = -257,
  // Additional secondary algorithms omitted for core invariant scope
};
```

In `device/fido/fido_constants.cc` and associated CTAP request serializers (`device/fido/ctap_make_credential_request.cc`), Chromium defines the default fallback and supported algorithm lists used when negotiating with authenticators or constructing CBOR `makeCredential` payloads:

```cpp
// Representative structure in device/fido/
constexpr std::array<CoseAlgorithmIdentifier, 3> kSupportedCoseAlgorithms = {
    CoseAlgorithmIdentifier::kEs256,
    CoseAlgorithmIdentifier::kEdDSA,
    CoseAlgorithmIdentifier::kRs256,
};
```

### 2.2 Blink Credential Management Integration
When a Relying Party invokes `navigator.credentials.create({ publicKey })`, Blink's `credentials_container.cc` and `type_converters.cc` (`third_party/blink/renderer/modules/credentialmanagement/`) execute the following pipeline:

1. **WebIDL Binding Extraction:** Extracts `pubKeyCredParams` where `alg` is bound as an `int32_t` (`long` in WebIDL).
2. **Type Filtering:** Iterates over `pubKeyCredParams`. If `param->type() != "public-key"`, the parameter is discarded.
3. **Default Injection:** If the raw `pubKeyCredParams` array from the RP has length 0, Blink populates two default entries: `kEs256 (-7)` and `kRs256 (-257)`.
4. **Mojo IPC Marshaling:** The filtered `Vector<mojom::blink::PublicKeyCredentialParametersPtr>` is transmitted across the Mojo boundary to the browser process (`content/browser/webauth/authenticator_common_impl.cc`), which translates them into `device::PublicKeyCredentialParams::CredentialInfo` structs containing the `int32_t` algorithm code.
5. **Authenticator Negotiation:** The FIDO discovery/authenticator layer checks whether the target authenticator (e.g., internal platform authenticator or CTAP2 security key) supports any of the requested `int32_t` identifiers by exact integer equality.

### 2.3 Implementation Invariants
- **Invariant I1 (Identifier Disjointness):** `kEs256` ($-7$), `kEdDSA` ($-8$), and `kRs256` ($-257$) are pairwise distinct integers in $\mathbb{Z}$.
- **Invariant I2 (Bijective Translation):** The mapping between Blink/FIDO's strongly-typed `CoseAlgorithmIdentifier` enumeration and the wire-format CBOR negative integers $\{-7, -8, -257\}$ is a total bijection on the supported domain.
- **Invariant I3 (Sound Negotiation):** Any algorithm selected by the FIDO layer during `MakeCredential` is guaranteed to be both (a) requested by the RP (or defaulted per spec) with `type == "public-key"`, and (b) natively supported by the authenticator.
- **Invariant I4 (Preference Preservation):** The negotiation algorithm selects the first algorithm in the RP's priority list that is supported by the authenticator.

---

## 3. Formal Specification in Rocq / Coq

The following self-contained Rocq (Coq) module formalizes the COSE algorithm constants, the CBOR integer decoding/encoding parser, Blink's `PublicKeyCredentialParameters` filtering, and the FIDO authenticator selection semantics.

### 3.1 `BlinkWebAuthnCOSEAlgorithmSemantics.v` (Definitions)

```coq
(** * BlinkWebAuthnCOSEAlgorithmSemantics.v
    Formalization of WebAuthn COSE Algorithm Identifier Matching
    Target: Chromium device/fido/fido_constants.cc & Blink Credential Management
    Specifications: W3C WebAuthn Level 3, RFC 9053 §2.1, RFC 8812 §2 *)

From Coq Require Import ZArith.
From Coq Require Import List.
From Coq Require Import Bool.
From Coq Require Import Lia.
Import ListNotations.

Open Scope Z_scope.

(** ** 1. Normative Mathematical Constants (RFC 9053 §2.1 & RFC 8812) *)

Definition COSE_ES256 : Z := -7.
Definition COSE_EDDSA : Z := -8.
Definition COSE_RS256 : Z := -257.

(** ** 2. Chromium FIDO Strongly-Typed Enumeration (device/fido/fido_constants.h) *)

Inductive CoseAlgorithm : Type :=
  | Alg_ES256 : CoseAlgorithm
  | Alg_EDDSA : CoseAlgorithm
  | Alg_RS256 : CoseAlgorithm.

(** Decidable equality for CoseAlgorithm *)
Definition CoseAlgorithm_eqb (a1 a2 : CoseAlgorithm) : bool :=
  match a1, a2 with
  | Alg_ES256, Alg_ES256 => true
  | Alg_EDDSA, Alg_EDDSA => true
  | Alg_RS256, Alg_RS256 => true
  | _, _ => false
  end.

(** Serialization from internal Chromium enum to wire-format int32_t / Z *)
Definition encode_cose_alg (alg : CoseAlgorithm) : Z :=
  match alg with
  | Alg_ES256 => COSE_ES256
  | Alg_EDDSA => COSE_EDDSA
  | Alg_RS256 => COSE_RS256
  end.

(** Parsing from wire-format int32_t / Z to internal Chromium enum *)
Definition decode_cose_alg (z : Z) : option CoseAlgorithm :=
  if Z.eqb z COSE_ES256 then Some Alg_ES256
  else if Z.eqb z COSE_EDDSA then Some Alg_EDDSA
  else if Z.eqb z COSE_RS256 then Some Alg_RS256
  else None.

(** Predicate for supported wire-format COSE algorithm identifiers *)
Definition is_supported_cose_id (z : Z) : bool :=
  match decode_cose_alg z with
  | Some _ => true
  | None => false
  end.

(** ** 3. Blink PublicKeyCredentialParameters Filtering Semantics *)

Inductive CredentialType : Type :=
  | CredType_PublicKey : CredentialType
  | CredType_Unknown   : nat -> CredentialType.

Definition cred_type_eqb (t1 t2 : CredentialType) : bool :=
  match t1, t2 with
  | CredType_PublicKey, CredType_PublicKey => true
  | CredType_Unknown n1, CredType_Unknown n2 => Nat.eqb n1 n2
  | _, _ => false
  end.

Record PublicKeyCredentialParameters : Type := mkCredParam {
  param_type : CredentialType;
  param_alg  : Z
}.

(** Default parameters injected when pubKeyCredParams is empty (WebAuthn §5.1.3) *)
Definition default_cred_params : list PublicKeyCredentialParameters :=
  [ mkCredParam CredType_PublicKey COSE_ES256;
    mkCredParam CredType_PublicKey COSE_RS256 ].

(** Filter retaining only "public-key" types and extracting their COSE integers *)
Fixpoint filter_public_key_algs (params : list PublicKeyCredentialParameters) : list Z :=
  match params with
  | [] => []
  | p :: rest =>
      if cred_type_eqb (param_type p) CredType_PublicKey
      then (param_alg p) :: filter_public_key_algs rest
      else filter_public_key_algs rest
  end.

(** Blink's normalization of RP pubKeyCredParams *)
Definition normalize_rp_params (params : list PublicKeyCredentialParameters) : list Z :=
  match params with
  | [] => filter_public_key_algs default_cred_params
  | _  => filter_public_key_algs params
  end.

(** ** 4. FIDO Authenticator Algorithm Negotiation Semantics *)

(** Authenticator capability list represented as supported CoseAlgorithms *)
Definition authenticator_supports_alg (supported : list CoseAlgorithm) (alg : CoseAlgorithm) : bool :=
  existsb (CoseAlgorithm_eqb alg) supported.

(** Authenticator checks if a wire integer z matches a supported CoseAlgorithm *)
Definition authenticator_matches_wire_id (supported : list CoseAlgorithm) (z : Z) : option CoseAlgorithm :=
  match decode_cose_alg z with
  | Some alg =>
      if authenticator_supports_alg supported alg
      then Some alg
      else None
  | None => None
  end.

(** Negotiation selects the first RP-requested algorithm supported by the authenticator *)
Fixpoint negotiate_cose_alg (supported : list CoseAlgorithm) (rp_algs : list Z) : option CoseAlgorithm :=
  match rp_algs with
  | [] => None
  | z :: rest =>
      match authenticator_matches_wire_id supported z with
      | Some alg => Some alg
      | None => negotiate_cose_alg supported rest
      end
  end.
```

---

## 4. Concrete Theorems and Complete Proofs

Below is the complete verification suite for `BlinkWebAuthnCOSEAlgorithmSemantics.v`. Every theorem is proven using standard library tactics (`lia`, `destruct`, `simpl`, `induction`) with **zero `Admitted` or `axiom` statements**.

```coq
(** * Formal Proofs for BlinkWebAuthnCOSEAlgorithmSemantics.v *)

(** ** Theorem 1: Normative Mathematical Values & Pairwise Disjointness *)
Theorem cose_constants_exact_and_distinct :
  COSE_ES256 = -7 /\
  COSE_RS256 = -257 /\
  COSE_EDDSA = -8 /\
  COSE_ES256 <> COSE_RS256 /\
  COSE_ES256 <> COSE_EDDSA /\
  COSE_RS256 <> COSE_EDDSA.
Proof.
  unfold COSE_ES256, COSE_RS256, COSE_EDDSA.
  repeat split; lia.
Qed.

(** ** Theorem 2: Boolean Equality Reflection for CoseAlgorithm *)
Lemma CoseAlgorithm_eqb_refl : forall (a : CoseAlgorithm),
  CoseAlgorithm_eqb a a = true.
Proof.
  destruct a; reflexivity.
Qed.

Lemma CoseAlgorithm_eqb_eq : forall (a1 a2 : CoseAlgorithm),
  CoseAlgorithm_eqb a1 a2 = true <-> a1 = a2.
Proof.
  destruct a1, a2; simpl; split; intro H; try reflexivity; try discriminate.
Qed.

(** ** Theorem 3: Decode-Encode Left Inverse (Injectivity of Serialization) *)
Theorem decode_encode_id : forall (alg : CoseAlgorithm),
  decode_cose_alg (encode_cose_alg alg) = Some alg.
Proof.
  destruct alg; simpl; reflexivity.
Qed.

Theorem encode_cose_