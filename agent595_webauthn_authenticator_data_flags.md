# Formal Verification Report: WebAuthn `authenticatorData` Flags Bitmask Semantics in Chromium

**Target Component:** `device/fido/authenticator_data.cc` / Blink Credential Management Architecture  
**Specification:** W3C Web Authentication: An API for accessing Public Key Credentials Level 3 (WebAuthn L3) §6.1  
**Formalization Target:** `BlinkWebAuthnAuthDataFlagsSemantics.v`  

---

## 1. Normative W3C WebAuthn Specification Requirements

In the W3C WebAuthn Level 3 Specification (§6.1, *Authenticator Data*), the `authenticatorData` structure encodes contextual bindings and authenticator state asserted during a `navigator.credentials.create()` or `navigator.credentials.get()` ceremony. 

The structure begins with a 32-byte `rpIdHash`, followed immediately at byte offset 32 by a single `flags` byte (8 bits). The bit positions are ordered from least significant bit (Bit 0) to most significant bit (Bit 7):

| Bit Position | Hex Mask | Identifier | Normative Meaning |
| :--- | :--- | :--- | :--- |
| **Bit 0** | `0x01` | **UP** | **User Present**: `1` indicates the user completed a presence test (e.g., touch). |
| **Bit 1** | `0x02` | *RFU1* | Reserved for Future Use. Relying Parties MUST ignore this bit. |
| **Bit 2** | `0x04` | **UV** | **User Verified**: `1` indicates the user was verified (e.g., PIN, biometric). |
| **Bit 3** | `0x08` | **BE** | **Backup Eligibility**: `1` indicates the credential source is backup eligible (multi-device credential / passkey). `0` indicates a single-device credential. |
| **Bit 4** | `0x10` | **BS** | **Backup State**: `1` indicates the credential source is currently backed up. |
| **Bit 5** | `0x20` | *RFU2* | Reserved for Future Use. Relying Parties MUST ignore this bit. |
| **Bit 6** | `0x40` | **AT** | **Attested Credential Data**: `1` indicates the `authenticatorData` includes an `attestedCredentialData` byte array immediately following the 4-byte `signCount`. |
| **Bit 7** | `0x80` | **ED** | **Extension Data**: `1` indicates the `authenticatorData` includes CBOR-encoded `extensions` at the end of the structure. |

### Normative State & Structural Invariants

1. **Backup State Dependency Invariant (§6.1 & §6.3.3):** 
   If the Backup Eligibility (**BE**, Bit 3) flag is `0`, the Backup State (**BS**, Bit 4) flag **MUST** be `0`. A single-device credential cannot be in a backed-up state:
   $$\neg \text{BE} \implies \neg \text{BS} \quad \equiv \quad \text{BS} \implies \text{BE}$$
   In hexadecimal mask arithmetic over an 8-bit integer $f \in [0, 255]$:
   $$(f \land \mathtt{0x10} \neq 0) \implies (f \land \mathtt{0x08} \neq 0)$$

2. **Structural Presence Invariant (§6.1):**
   The presence of optional variable-length suffixes in `authenticatorData` is strictly isomorphic to the boolean states of **AT** and **ED**:
   * $\text{AT} = 1 \iff (f \land \mathtt{0x40} \neq 0) \iff \text{attestedCredentialData} \neq \bot$
   * $\text{ED} = 1 \iff (f \land \mathtt{0x80} \neq 0) \iff \text{extensions} \neq \bot$

---

## 2. Chromium Implementation & Invariants (`device/fido/authenticator_data.cc`)

While Blink (`third_party/blink/renderer/modules/credentialmanagement/`) exposes the WebIDL interfaces (`AuthenticatorResponse`, `AuthenticatorAssertionResponse`), the deserialization, serialization, and bitmask verification of `authenticatorData` occur in the Chromium FIDO device layer (`device/fido/authenticator_data.h` and `device/fido/authenticator_data.cc`) before crossing the Mojo IPC boundary or upon parsing CTAP2 responses.

### 2.1 Flag Bitmask Definitions (`device/fido/authenticator_data.h`)

Chromium defines the `Flag` enumeration matching the exact bit shifts required by WebAuthn L3 §6.1:

```cpp
enum class Flag : uint8_t {
  kTestOfUserPresence = 1u << 0,   // 0x01 (UP)
  kTestOfUserVerification = 1u << 2, // 0x04 (UV)
  kBackupEligible = 1u << 3,       // 0x08 (BE)
  kBackupState = 1u << 4,          // 0x10 (BS)
  kAttestation = 1u << 6,          // 0x40 (AT)
  kExtensionDataIncluded = 1u << 7 // 0x80 (ED)
};
```

Accessor methods in `AuthenticatorData` perform bitwise AND masks against `flags_`:

```cpp
bool obtained_user_presence() const {
  return flags_ & base::strict_cast<uint8_t>(Flag::kTestOfUserPresence);
}
bool obtained_user_verification() const {
  return flags_ & base::strict_cast<uint8_t>(Flag::kTestOfUserVerification);
}
bool backup_eligible() const {
  return flags_ & base::strict_cast<uint8_t>(Flag::kBackupEligible);
}
bool backup_state() const {
  return flags_ & base::strict_cast<uint8_t>(Flag::kBackupState);
}
bool attested_data_included() const {
  return flags_ & base::strict_cast<uint8_t>(Flag::kAttestation);
}
bool extension_data_included() const {
  return flags_ & base::strict_cast<uint8_t>(Flag::kExtensionDataIncluded);
}
```

### 2.2 Deserialization & Constructor Invariants (`device/fido/authenticator_data.cc`)

In `AuthenticatorData::DecodeAuthenticatorData(base::span<const uint8_t> auth_data)` and the `AuthenticatorData` constructor, Chromium enforces structural consistency between the bitmask and the parsed fields:

1. **Length Check:** Verifies `auth_data.size() >= kAttestedCredentialDataOffset` (32 bytes `application_parameter` + 1 byte `flags` + 4 bytes `counter` = 37 bytes).
2. **AT Flag Verification:**
   ```cpp
   const bool attested_credential_data_included =
       (flags & static_cast<uint8_t>(Flag::kAttestation)) != 0;
   ```
   If `attested_credential_data_included` is true, `ConsumeAttestedCredentialData` must succeed and populate `std::optional<AttestedCredentialData> attested_data_`. If false, `attested_data_` must be `std::nullopt`. Enforced via `CHECK_EQ((flags_ & static_cast<uint8_t>(Flag::kAttestation)) != 0, !!attested_data_)`.
3. **ED Flag Verification:**
   ```cpp
   const bool extension_data_included =
       (flags & static_cast<uint8_t>(Flag::kExtensionDataIncluded)) != 0;
   ```
   If `extension_data_included` is true, the remaining span must decode as a valid CBOR map (`extensions_->is_map()`). If false, `extensions_` must be `std::nullopt` and no trailing unparsed bytes may remain. Enforced via `CHECK_EQ((flags_ & static_cast<uint8_t>(Flag::kExtensionDataIncluded)) != 0, !!extensions_)`.
4. **Reserved Bits Tolerance:** In accordance with WebAuthn §6.1, `DecodeAuthenticatorData` does not reject payloads when RFU1 (`0x02`) or RFU2 (`0x20`) are set, ensuring forward compatibility while preserving exact bitchecks on the 6 defined flags.

---

## 3. Formal Specification in Rocq / Coq (`BlinkWebAuthnAuthDataFlagsSemantics.v`)

Below is the complete, self-contained formalization and verification in Rocq/Coq. It models the 8-bit flag space over `Z`, proves the correspondence between `Z.land` bitmasks and boolean bit extraction (`Z.testbit`), establishes flag orthogonality, verifies RFU invariance, and proves the soundness and completeness of Chromium's `AuthenticatorData` validation invariants.

```coq
(** * BlinkWebAuthnAuthDataFlagsSemantics.v
    Formal Verification of WebAuthn Level 3 §6.1 authenticatorData Flags
    and Chromium device/fido/authenticator_data.cc Bitmask Invariants. *)

From Coq Require Import ZArith.
From Coq Require Import Bool.
From Coq Require Import Lia.

Open Scope Z_scope.

Section WebAuthnFlagsSemantics.

  (** ** 1. Bit Indices and Hexadecimal Masks (WebAuthn Level 3 §6.1) *)

  Definition BIT_UP   : Z := 0.
  Definition BIT_RFU1 : Z := 1.
  Definition BIT_UV   : Z := 2.
  Definition BIT_BE   : Z := 3.
  Definition BIT_BS   : Z := 4.
  Definition BIT_RFU2 : Z := 5.
  Definition BIT_AT   : Z := 6.
  Definition BIT_ED   : Z := 7.

  (** Hexadecimal masks corresponding to [device/fido/authenticator_data.h] *)
  Definition MASK_UP   : Z := 1.   (* 0x01 = 1 << 0 *)
  Definition MASK_RFU1 : Z := 2.   (* 0x02 = 1 << 1 *)
  Definition MASK_UV   : Z := 4.   (* 0x04 = 1 << 2 *)
  Definition MASK_BE   : Z := 8.   (* 0x08 = 1 << 3 *)
  Definition MASK_BS   : Z := 16.  (* 0x10 = 1 << 4 *)
  Definition MASK_RFU2 : Z := 32.  (* 0x20 = 1 << 5 *)
  Definition MASK_AT   : Z := 64.  (* 0x40 = 1 << 6 *)
  Definition MASK_ED   : Z := 128. (* 0x80 = 1 << 7 *)

  (** Valid 8-bit unsigned integer range (uint8_t) *)
  Definition is_uint8 (flags : Z) : Prop :=
    0 <= flags < 256.

  (** ** 2. Chromium C++ Bitwise Flag Check Model
      Models `(flags_ & static_cast<uint8_t>(Flag::k...)) != 0` *)

  Definition has_flag_mask (flags mask : Z) : bool :=
    negb (Z.eqb (Z.land flags mask) 0).

  Definition flag_UP (flags : Z) : bool := has_flag_mask flags MASK_UP.
  Definition flag_UV (flags : Z) : bool := has_flag_mask flags MASK_UV.
  Definition flag_BE (flags : Z) : bool := has_flag_mask flags MASK_BE.
  Definition flag_BS (flags : Z) : bool := has_flag_mask flags MASK_BS.
  Definition flag_AT (flags : Z) : bool := has_flag_mask flags MASK_AT.
  Definition flag_ED (flags : Z) : bool := has_flag_mask flags MASK_ED.

  (** ** 3. Abstract Decoded Flags Record *)

  Record DecodedFlags : Type := mkDecodedFlags {
    up : bool;
    uv : bool;
    be : bool;
    bs : bool;
    at_flag : bool;
    ed : bool
  }.

  Definition decode_flags (flags : Z) : DecodedFlags :=
    mkDecodedFlags
      (flag_UP flags)
      (flag_UV flags)
      (flag_BE flags)
      (flag_BS flags)
      (flag_AT flags)
      (flag_ED flags).

  Definition encode_flags (d : DecodedFlags) : Z :=
    Z.lor (if up d then MASK_UP else 0)
   (Z.lor (if uv d then MASK_UV else 0)
   (Z.lor (if be d then MASK_BE else 0)
   (Z.lor (if bs d then MASK_BS else 0)
   (Z.lor (if at_flag d then MASK_AT else 0)
          (if ed d then MASK_ED else 0))))).

  (** ** 4. Normative and Structural Invariants *)

  (** WebAuthn L3 §6.1 Backup State Consistency:
      BS=1 is only valid if BE=1. *)
  Definition valid_backup_state (flags : Z) : bool :=
    implb (flag_BS flags) (flag_BE flags).

  (** Chromium [device/fido/authenticator_data.cc] Structural Check:
      `CHECK_EQ((flags_ & kAttestation) != 0, !!attested_data_)`
      `CHECK_EQ((flags_ & kExtensionDataIncluded) != 0, !!extensions_)` *)
  Definition check_structural_invariants
    (flags : Z) (has_attested_data has_extension_data : bool) : bool :=
    andb (Bool.eqb (flag_AT flags) has_attested_data)
         (Bool.eqb (flag_ED flags) has_extension_data).

  (** Combined WebAuthn L3 + Chromium Verification Predicate *)
  Definition verify_auth_data_flags
    (flags : Z) (has_attested_data has_extension_data : bool) : bool :=
    andb (valid_backup_state flags)
         (check_structural_invariants flags has_attested_data has_extension_data).

  (** ** 5. Foundational Bitmask Equivalence Theorems *)

  Lemma mask_is_pow2 :
    MASK_UP   = 2 ^ BIT_UP   /\
    MASK_RFU1 = 2 ^ BIT_RFU1 /\
    MASK_UV   = 2 ^ BIT_UV   /\
    MASK_BE   = 2 ^ BIT_BE   /\
    MASK_BS   = 2 ^ BIT_BS   /\
    MASK_RFU2 = 2 ^ BIT_RFU2 /\
    MASK_AT   = 2 ^ BIT_AT   /\
    MASK_ED   = 2 ^ BIT_ED.
  Proof.
    repeat split; reflexivity.