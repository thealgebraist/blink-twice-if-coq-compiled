# Formal Verification Report: WebAuthn Attestation Statement Format Validation in Chromium (`device/fido/attestation_statement_formats.cc`)

**Formal Theory Target:** `BlinkWebAuthnAttestationFormatSemantics.v`  
**Specification Target:** W3C WebAuthn Level 3, Section 8 ("Defined Attestation Statement Formats")  
**Implementation Target:** Chromium `device/fido/attestation_statement_formats.cc` & `device/fido/attestation_object.cc`  
**Mathematical Domain:** Discrete Integer Encoding & Structural Predicate Verification ($\mathbb{Z}$ / `ZArith`)

---

## 1. Normative W3C WebAuthn Level 3 Specification Requirements

In the Web Authentication (WebAuthn) Level 3 specification, an **Attestation Object** is returned by an authenticator during the `navigator.credentials.create()` ceremony (specifically within the `AuthenticatorMakeCredential` operation). The attestation object is CBOR-encoded and contains three mandatory fields: `authData` (authenticator data), `fmt` (attestation statement format identifier), and `attStmt` (the attestation statement structure).

Section 8 of the W3C WebAuthn Level 3 specification normatively defines the structural and cryptographic syntax for registered attestation statement formats. In the context of a user agent (client platform) like Chromium, attestation statement format validation occurs primarily during:
1. **CBOR Parsing and Structural Validation:** Ensuring the `attStmt` map delivered by a roaming or platform authenticator adheres to the syntactic constraints of its declared `fmt` before passing the response to the Relying Party (RP) or evaluating it for enterprise/client-side attestation policies.
2. **Privacy / Anonymization Transformations ("None" Attestation Replacement):** If the RP requests `"none"` attestation (or the user decays attestation permission via the browser UI), the client must strip the authenticator's native attestation statement and replace `fmt` with `"none"` and `attStmt` with an empty CBOR map `{}` ( unless enterprise policy dictates otherwise).

The normative structural requirements for the five core formats analyzed in this report are:

### 1.1 None Attestation Statement Format (`fmt = "none"`, Code `0`)
* **Normative Reference:** WebAuthn Level 3 §8.7
* **Purpose:** Used when the authenticator does not provide attestation, or when the client replaces the authenticator's attestation to protect user privacy.
* **Syntax Requirements:** The `attStmt` MUST be an empty CBOR map (`{}`). Presence of `alg`, `sig`, `x5c`, or any other keys constitutes a malformed `"none"` attestation statement.

### 1.2 Packed Attestation Statement Format (`fmt = "packed"`, Code `1`)
* **Normative Reference:** WebAuthn Level 3 §8.2
* **Purpose:** A compact, WebAuthn-optimized format usable for both full X.509 certificate chains (`x5c`) and self-attestation.
* **Syntax Requirements:** 
  * `alg` (COSEAlgorithmIdentifier): REQUIRED integer identifying the cryptographic algorithm used to generate the signature.
  * `sig` (byte string): REQUIRED non-empty byte string containing the cryptographic signature over `authenticatorData || clientDataHash`.
  * `x5c` (array of byte strings): OPTIONAL. If present, contains `attestnCert` and its certificate chain (Full Attestation). If absent, the statement represents Self-Attestation.

### 1.3 FIDO U2F Attestation Statement Format (`fmt = "fido-u2f"`, Code `2`)
* **Normative Reference:** WebAuthn Level 3 §8.6
* **Purpose:** Backward compatibility with legacy CTAP1 / FIDO U2F security keys.
* **Syntax Requirements:**
  * `sig` (byte string): REQUIRED non-empty ANS.1 DER-encoded ECDSA signature.
  * `x5c` (array of byte strings): REQUIRED array containing *exactly one* element (`|x5c| == 1`), which is the `attCert`. Unlike `"packed"`, `"fido-u2f"` forbids certificate chains of length $>1$ and explicitly omits the `alg` field from `attStmt` (implicitly fixed to `ES256` / `-7`).
  * **Cryptographic Key Constraint:** The credential public key MUST be an elliptic curve key over the NIST P-256 curve (`alg = -7`).

### 1.4 TPM Attestation Statement Format (`fmt = "tpm"`, Code `3`)
* **Normative Reference:** WebAuthn Level 3 §8.3
* **Purpose:** Hardware attestation utilizing a Trusted Platform Module (TPM 2.0).
* **Syntax Requirements:**
  * `ver` (text string): REQUIRED version string, which MUST be exact string `"2.0"`.
  * `alg` (COSEAlgorithmIdentifier): REQUIRED integer specifying the signature algorithm.
  * `sig` (byte string): REQUIRED non-empty signature byte string.
  * `x5c` (array of byte strings): REQUIRED (in standard X.509 AIK mode; ECDAA is deprecated/removed in WebAuthn L3) non-empty array of certificates where the first element is the AIK certificate.
  * `certInfo` (byte string): REQUIRED non-empty `TPMS_ATTEST` structure.
  * `pubArea` (byte string): REQUIRED non-empty `TPMT_PUBLIC` structure.

### 1.5 Android Key Attestation Statement Format (`fmt = "android-key"`, Code `4`)
* **Normative Reference:** WebAuthn Level 3 §8.4
* **Purpose:** Platform authenticators backed by Android hardware-backed Keystore.
* **Syntax Requirements:**
  * `alg` (COSEAlgorithmIdentifier): REQUIRED integer.
  * `sig` (byte string): REQUIRED non-empty signature byte string.
  * `x5c` (array of byte strings): REQUIRED non-empty certificate chain (`|x5c| >= 1`) rooted in the Android Hardware Attestation Root.

---

## 2. Chromium Implementation Details and Invariants (`device/fido/`)

In Chromium's architecture, Blink (`third_party/blink/renderer/modules/credentialmanagement/`) delegates WebAuthn operations over Mojo IPC (`blink::mojom::Authenticator`) to the browser process (`content/browser/webauth/`), which interfaces with the FIDO device layer in `device/fido/`.

The parsing, representation, and structural validation of attestation statements are implemented in `device/fido/attestation_statement_formats.cc`, `device/fido/attestation_statement.h`, and `device/fido/attestation_object.cc`.

### 2.1 Class Hierarchy and Representation
Chromium models attestation statements via the base class `device::AttestationStatement`, which stores the format string `format_` and exposes virtual structural predicates:
* `NoneAttestationStatement`: Represents `fmt = "none"`.
* `PackedAttestationStatement`: Represents `fmt = "packed"`.
* `FidoAttestationStatement`: Represents `fmt = "fido-u2f"`.
* `TpmAttestationStatement` / `OpaqueAttestationStatement`: Represents `"tpm"`, `"android-key"`, etc.

### 2.2 Core Chromium Validation Invariants
During `AttestationObject::Parse()` and `FidoAttestationStatement::CreateFromU2fRegisterResponse()`, Chromium enforces strict invariants before passing the serialized CBOR object back to Blink:

1. **Invariant 1 (Strict Empty Map for None):** When `NoneAttestationStatement` is instantiated or when `AttestationObject::EraseAttestationStatement()` executes (to satisfy privacy stripping), the `attStmt` map is guaranteed to contain 0 keys. Any incoming `"none"` statement with residual keys (`sig`, `x5c`, etc.) is rejected by CBOR map validation.
2. **Invariant 2 (U2F Single-Certificate and Implicit Algorithm Invariant):** In `FidoAttestationStatement::CreateFromCBORMap()`, Chromium extracts `"sig"` and `"x5c"`. It explicitly checks `x5c.size() == 1` and `!sig.empty()`. Furthermore, it checks that no extraneous keys exist and enforces that the associated `AttestedCredentialData` uses `kCoseEs256` (`-7`).
3. **Invariant 3 (Self-Attestation Confined to Packed):** Chromium's `AttestationStatement::IsSelfAttestation()` returns `true` if and only if the format is `"packed"` and `x5c` is empty. All other formats with `fmt != "none"` (`"fido-u2f"`, `"tpm"`, `"android-key"`) strictly require `x5c.size() >= 1`.
4. **Invariant 4 (TPM Structural Completeness):** For `"tpm"`, the `ver` field must equal `"2.0"`, and both `certInfo` (`TPMS_ATTEST`) and `pubArea` (`TPMT_PUBLIC`) must be present and non-empty alongside `alg`, `sig`, and `x5c`.
5. **Invariant 5 (Idempotent Privacy Erasure):** Calling `EraseAttestationStatement()` on any valid `AttestationObject` transforms its format to `"none"` (`0`) and zeroes out all attestation statement fields (`alg`, `sig`, `x5c`, `certInfo`, `pubArea`, `ver`), yielding a state that is provably valid under the `"none"` format rules and guaranteed not to leak X.509 certificate chains (`x5c_count == 0`).

---

## 3. Formal Specification in Rocq / Coq (`BlinkWebAuthnAttestationFormatSemantics.v`)

Below is the complete, self-contained, and mechanically verified Rocq/Coq formalization of Chromium's WebAuthn attestation statement format validation semantics. It uses integer-encoded format identifiers (`0` through `4`) as specified in the target mathematical property and verifies the structural, cryptographic, and privacy invariants using `ZArith`, `Lia`, and `Bool`.

```coq
(** * BlinkWebAuthnAttestationFormatSemantics.v
    Formal Verification of W3C WebAuthn Level 3 §8 Attestation Statement Format
    Validation in Chromium (device/fido/attestation_statement_formats.cc).

    Mathematical Encoding of Attestation Statement Formats:
      - FMT_NONE        = 0 ("none")
      - FMT_PACKED      = 1 ("packed")
      - FMT_FIDO_U2F    = 2 ("fido-u2f")
      - FMT_TPM         = 3 ("tpm")
      - FMT_ANDROID_KEY = 4 ("android-key")
*)

From Coq Require Import ZArith.
From Coq Require Import Bool.
From Coq Require Import Lia.

Open Scope Z_scope.

(** ** 1. Format Identifier Constants *)

Definition FMT_NONE        : Z := 0.
Definition FMT_PACKED      : Z := 1.
Definition FMT_FIDO_U2F    : Z := 2.
Definition FMT_TPM         : Z := 3.
Definition FMT_ANDROID_KEY : Z := 4.

(** COSE Algorithm Identifier for ES256 (ECDSA w/ SHA-256 over P-256) *)
Definition COSE_ALG_ES256  : Z := -7.

(** Predicate defining whether an integer represents a recognized WebAuthn format code *)
Definition is_known_format (fmt : Z) : Prop :=
  0 <= fmt <= 4.

Definition is_known_format_b (fmt : Z) : bool :=
  (0 <=? fmt) && (fmt <=? 4).

(** ** 2. Abstract Syntax of an Attestation Statement Map (CBOR) *)

(** Represents the parsed state of an Attestation Object's [fmt] and [attStmt] map
    alongside the credential public key's COSE algorithm in [authData]. *)
Record AttestationStatement := mkAttStmt {
  fmt            : Z;     (** Format identifier: 0..4 *)
  has_alg        : bool;  (** True iff 'alg' key is present in attStmt *)
  alg_id         : Z;     (** Value of 'alg' in attStmt (if present) *)
  cred_alg_id    : Z;     (** COSE algorithm of the credentialPublicKey in authData *)
  sig_len        : Z;     (** Byte length of 'sig' field (0 if absent/empty) *)
  x5c_count      : Z;     (** Number of X.509 certificates in 'x5c' (0 if absent) *)
  tpm_ver_is_2_0 : bool;  (** True iff 'ver' is present and equals "2.0" *)
  cert_info_len  : Z;     (** Byte length of TPM 'certInfo' (0 if absent) *)
  pub_area_len   : Z      (** Byte length of TPM 'pubArea' (0 if absent) *)
}.

(** Well-formedness of raw length/count fields (non-negative sizes) *)
Definition wf_lengths (s : AttestationStatement) : Prop :=
  s.(sig_len) >= 0 /\
  s.(x5c_count) >= 0 /\
  s.(cert_info_len) >= 0 /\
  s.(pub_area_len) >= 0.

(** ** 3. Format-Specific Validation Predicates (WebAuthn L3 §8 & Chromium device/fido) *)

(** §8.7 None Attestation Statement Format:
    [attStmt] MUST be an empty CBOR map {}. *)
Definition valid_none (s : AttestationStatement) : bool :=
  (s.(fmt) =? FMT_NONE) &&
  negb s.(has_alg) &&
  (s.(sig_len) =? 0) &&
  (s.(x5c_count) =? 0) &&
  negb s.(tpm_ver_is_2_0) &&
  (s.(cert_info_len) =? 0) &&
  (s.(pub_area_len) =? 0).

(** §8.2 Packed Attestation Statement Format:
    Requires 'alg' and non-empty 'sig'. 'x5c' is optional (>= 0).
    If 'x5c' is absent (0), it is Self-Attestation, requiring alg_id == cred_alg_id.
    No TPM-specific fields may be present. *)
Definition valid_packed (s : AttestationStatement) : bool :=
  (s.(fmt) =? FMT_PACKED) &&
  s.(has_alg) &&
  (s.(sig_len) >? 0) &&
  (s.(x5c_count) >=? 0) &&
  (if s.(x5c_count) =? 0 then (s.(alg_id) =? s.(cred_alg_id)) else true) &&
  negb s.(tpm_ver_is_2_0) &&
  (s.(cert_info_len) =? 0) &&
  (s.(pub_area_len) =? 0).

(** §8.6 FIDO U2F Attestation Statement Format:
    'alg' is NOT present in attStmt (implicitly ES256).
    Requires non-empty 'sig', EXACTLY 1 certificate in 'x5c' (x5c_count == 1),
    and the credential public key algorithm MUST be COSE_ALG_ES256 (-7). *)
Definition valid_fido_u2f (s : AttestationStatement) : bool :=
  (s.(fmt