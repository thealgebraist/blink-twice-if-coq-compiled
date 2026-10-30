# Formal Verification of WebAuthn Resident Key & Backup Eligibility Flag Consistency in Chromium

**Target Component:** `device/fido/authenticator_data.cc`, `device/fido/make_credential_request_handler.cc`  
**Specification:** W3C WebAuthn Level 3 (§5.1.2, §6.1, §7.1) & FIDO CTAP 2.1 (§6.1)  
**Formal Theory Target:** `BlinkWebAuthnResidentKeyFlagSemantics.v`  
**Verification Engine:** Rocq / Coq 8.18+ (`ZArith`, `Lia`, `Bool`)

---

## 1. Normative Specification Requirements

The interaction between Relying Party (RP) requirements for Client-Side Discoverable Credentials (historically termed *Resident Keys*) and Authenticator Data flags is governed by W3C WebAuthn Level 3 and FIDO2 CTAP 2.1.

### 1.1 W3C WebAuthn Level 3 (§5.1.2 `ResidentKeyRequirement` & §6.1 Authenticator Data)

In **§5.1.2 (Resident Key Requirement Enumeration)**, the Relying Party specifies its requirement via `authenticatorSelection.residentKey`:
* `"discouraged"`: The RP prefers a server-side credential, though it will accept a discoverable credential.
* `"preferred"`: The RP strongly prefers creating a client-side discoverable credential, but will accept a server-side credential if the authenticator lacks capacity or capability.
* `"required"`: The RP requires a client-side discoverable credential. If the authenticator cannot create one, the ceremony **MUST** fail with a `NotAllowedError` or `ConstraintError`.

In **§6.1 (Authenticator Data)**, the authenticator returns a byte array containing a 1-byte `flags` bitfield at offset 32 (immediately following the 32-byte `rpIdHash`):
* **Bit 0 (`UP` - User Present):** $2^0 = \text{0x01}$
* **Bit 2 (`UV` - User Verified):** $2^2 = \text{0x04}$
* **Bit 3 (`BE` - Backup Eligibility):** $2^3 = \text{0x08}$
* **Bit 4 (`BS` - Backup State):** $2^4 = \text{0x10}$
* **Bit 6 (`AT` - Attested Credential Data):** $2^6 = \text{0x40}$
* **Bit 7 (`ED` - Extension Data Included):** $2^7 = \text{0x80}$

### 1.2 Flag Invariants & Multi-Device Credentials (Passkeys)

While the `flags` byte does not contain a dedicated `RK` bit, WebAuthn Level 3 §6.1.1 and §7.1 mandate strict state invariants tying Backup Eligibility (`BE`), Backup State (`BS`), Attested Credential Data (`AT`), and Discoverability (`rk`):

1. **Backup State Dependency Invariant (§6.1):**  
   The Backup State (`BS`) bit MUST NOT be set (`1`) if the Backup Eligibility (`BE`) bit is cleared (`0`). A credential cannot be currently backed up if it is not eligible for backup:
   $$\text{BS} = 1 \implies \text{BE} = 1$$

2. **Creation Ceremony Attestation Invariant (§7.1 Step 17):**  
   During `navigator.credentials.create()`, the authenticator generates a new key pair and **MUST** set the `AT` flag (`Bit 6 = 1`) to include the attested credential data (AAGUID, Credential ID, and COSE Public Key).

3. **Resident Key / Discoverable Enforcement Invariant (CTAP 2.1 §6.1 & WebAuthn §5.4.4):**  
   When `residentKey` is `"required"`, the client platform (`device/fido`) MUST set the CTAP2 `rk` option to `true` (or reject the authenticator if `options.rk` is unsupported). Furthermore, in the modern Passkey architecture, multi-device credentials (`BE = 1`) are intrinsically client-side discoverable (`rk = true`), whereas non-discoverable credentials (`rk = false`) created under `"discouraged"` or fallback `"preferred"` cannot act as synced passkeys unless upgraded or explicitly handled by platform-specific sync providers.

4. **Client Extension Output `credProps` (`rk` reporting):**  
   Per §10.1.1 (Credential Properties Extension), the client platform reports `credProps.rk = true` if and only if the client confirmed that the authenticator created a client-side discoverable credential (either via CTAP2 `rk=true` request acceptance or platform passkey provider guarantees where `BE = 1` implies discoverability).

---

## 2. Chromium Blink & `device/fido` Implementation Analysis

In Chromium, the translation from Blink's Mojo interface (`blink::mojom::ResidentKeyRequirement`) to low-level authenticator binary framing and validation occurs across `content/browser/webauth/` and `device/fido/`.

### 2.1 Bit Extraction and Validation in `device/fido/authenticator_data.cc`

In `device/fido/authenticator_data.h` and `device/fido/authenticator_data.cc`, the `AuthenticatorData::Flag` enum defines the bitmasks:

```cpp
enum class Flag : uint8_t {
  kTestOfUserPresence = 1u << 0,     // 0x01 (UP)
  kTestOfUserVerification = 1u << 2, // 0x04 (UV)
  kBackupEligible = 1u << 3,         // 0x08 (BE)
  kBackupState = 1u << 4,            // 0x10 (BS)
  kAttestation = 1u << 6,            // 0x40 (AT)
  kExtensionDataIncluded = 1u << 7,  // 0x80 (ED)
};
```

During `AuthenticatorData::DecodeAuthenticatorData(base::span<const uint8_t> auth_data)`, Chromium extracts `flag_byte = auth_data[32]` and enforces structural invariants:
* `backup_eligible() = (flag_byte & Flag::kBackupEligible) != 0`
* `backup_state() = (flag_byte & Flag::kBackupState) != 0`
* **Structural Validation:** If `!backup_eligible() && backup_state()`, decoding fails (`std::nullopt`), preventing malformed passkey state transitions from reaching Blink.

### 2.2 Resident Key Dispatch & Consistency in `make_credential_request_handler.cc`

In `device/fido/make_credential_request_handler.cc`, Chromium evaluates `options.resident_key` (`kDiscouraged`, `kPreferred`, `kRequired`):

1. **Candidate Filtering (`CheckIfAuthenticatorSelectionCriteriaAreMet`):**  
   * If `rk_req == kRequired` and `!authenticator->Options().supports_resident_key`, the authenticator is rejected before dispatching `AuthenticatorMakeCredential`.
   * If `rk_req == kPreferred`, Chromium sets `request.resident_key_required = authenticator->Options().supports_resident_key`.
   * If `rk_req == kDiscouraged`, Chromium sets `request.resident_key_required = false`.

2. **Post-Response Verification (`HandleResponse`):**  
   Once the authenticator responds with `AuthenticatorMakeCredentialResponse`, Chromium validates:
   * `auth_data.obtained_user_presence()` (`UP == 1`).
   * `auth_data.attested_data().has_value()` (`AT == 1`).
   * `!(!auth_data.backup_eligible() && auth_data.backup_state())` (`BS -> BE`).
   * Consistency between the requested `rk_req`, the negotiated `rk_dispatched` boolean, and the resulting `BE` flag for multi-device passkey providers:
     $$\text{resident\_key\_consistent}(\text{rk\_req}, \text{rk\_cap}, \text{rk\_disp}, \text{be\_flag}, \text{bs\_flag})$$

---

## 3. Formal Specification in Rocq / Coq

Below is the complete, self-contained formalization of `BlinkWebAuthnResidentKeyFlagSemantics.v`. It models both the bit-level extraction in `device/fido/authenticator_data.cc` using `Z.testbit` and the state-machine consistency predicates in `make_credential_request_handler.cc`.

```coq
(** * BlinkWebAuthnResidentKeyFlagSemantics.v
    Formal verification of W3C WebAuthn Level 3 (§5.1.2, §6.1, §7.1)
    ResidentKeyRequirement, AuthenticatorData flags (UP, UV, BE, BS, AT, ED),
    and Chromium's device/fido/authenticator_data.cc invariants. *)

From Coq Require Import Bool.Bool.
From Coq Require Import ZArith.ZArith.
From Coq Require Import Micega.Lia.

Open Scope bool_scope.
Open Scope Z_scope.

(** ** 1. W3C WebAuthn §5.1.2 ResidentKeyRequirement Enumeration *)

Inductive ResidentKeyRequirement : Type :=
  | RK_Discouraged
  | RK_Preferred
  | RK_Required.

Scheme Equality for ResidentKeyRequirement.

(** ** 2. Authenticator Capabilities & CTAP2 Dispatch State *)

Record AuthenticatorCapabilities : Type := mkAuthCap {
  cap_supports_rk : bool;
  cap_multi_device : bool (* e.g., Synced Passkey / Cloud Keychain provider *)
}.

(** Models Chromium's NegotiateResidentKey logic in make_credential_request_handler.cc:
    - Returns Some true if CTAP2 rk=true is dispatched.
    - Returns Some false if CTAP2 rk=false is dispatched.
    - Returns None if the authenticator must be rejected (ConstraintError). *)
Definition negotiate_rk (req : ResidentKeyRequirement) (cap : AuthenticatorCapabilities) : option bool :=
  match req with
  | RK_Discouraged => Some false
  | RK_Preferred   => Some (cap_supports_rk cap)
  | RK_Required    => if cap_supports_rk cap then Some true else None
  end.

(** ** 3. Bit-Level Model of device/fido/authenticator_data.cc *)

Definition UP_BIT : Z := 0. (* 1 << 0 = 0x01 *)
Definition UV_BIT : Z := 2. (* 1 << 2 = 0x04 *)
Definition BE_BIT : Z := 3. (* 1 << 3 = 0x08 *)
Definition BS_BIT : Z := 4. (* 1 << 4 = 0x10 *)
Definition AT_BIT : Z := 6. (* 1 << 6 = 0x40 *)
Definition ED_BIT : Z := 7. (* 1 << 7 = 0x80 *)

Definition flag_up (flags_byte : Z) : bool := Z.testbit flags_byte UP_BIT.
Definition flag_uv (flags_byte : Z) : bool := Z.testbit flags_byte UV_BIT.
Definition flag_be (flags_byte : Z) : bool := Z.testbit flags_byte BE_BIT.
Definition flag_bs (flags_byte : Z) : bool := Z.testbit flags_byte BS_BIT.
Definition flag_at (flags_byte : Z) : bool := Z.testbit flags_byte AT_BIT.
Definition flag_ed (flags_byte : Z) : bool := Z.testbit flags_byte ED_BIT.

(** Bitwise masks matching AuthenticatorData::Flag in authenticator_data.h *)
Definition MASK_UP : Z := 1.   (* 0x01 *)
Definition MASK_UV : Z := 4.   (* 0x04 *)
Definition MASK_BE : Z := 8.   (* 0x08 *)
Definition MASK_BS : Z := 16.  (* 0x10 *)
Definition MASK_AT : Z := 64.  (* 0x40 *)
Definition MASK_ED : Z := 128. (* 0x80 *)

(** C++ bitwise AND check: (flags & mask) != 0 *)
Definition cpp_has_flag (flags_byte mask : Z) : bool :=
  negb (Z.eqb (Z.land flags_byte mask) 0).

(** ** 4. Mathematical Property: resident_key_consistent *)

(** Backup eligibility and state consistency per WebAuthn §6.1:
    BS=1 implies BE=1 (equivalently: !BS || BE) *)
Definition backup_flags_valid (be_flag bs_flag : bool) : bool :=
  implb bs_flag be_flag.

(** Core mathematical property: resident_key_consistent(rk_req, be_flag)
    Also parameterized over authenticator capability and actual rk allocation (`rk_allocated`),
    reflecting the full invariant enforced across WebAuthn §5.1.2, §6.1, and §10.1.1:
    1. If rk_req == RK_Required, a discoverable credential MUST be allocated (rk_allocated = true).
    2. If be_flag == true (Multi-Device Passkey / Backup Eligible), the credential in a modern
       passkey provider is discoverable (or satisfies the RP's residentKey expectation when required).
    3. Under simplified two-argument projection `resident_key_consistent(rk_req, be_flag)`
       for a Backup-Eligible Passkey Authenticator (where discoverability is tied to BE): *)
Definition resident_key_consistent (rk_req : ResidentKeyRequirement) (be_flag : bool) : bool :=
  match rk_req with
  | RK_Discouraged => true
  | RK_Preferred   => true
  | RK_Required    => be_flag
  end.

(** Full Chromium MakeCredential validation predicate combining:
    - Negotiated CTAP2 `rk` option (`rk_dispatched`)
    - Authenticator capability (`cap`)
    - AuthenticatorData flags byte (`flags_byte`) *)
Definition make_credential_auth_data_valid
  (rk_req : ResidentKeyRequirement)
  (cap : AuthenticatorCapabilities)
  (flags_byte : Z) : bool :=
  match negotiate_rk rk_req cap with
  | None => false
  | Some rk_dispatched =>
      let up := flag_up flags_byte in
      let be := flag_be flags_byte in
      let bs := flag_bs flags_byte in
      let at_flag := flag_at flags_byte in
      (* 1. User Presence (UP) and Attested Credential Data (AT) must be set on creation *)
      up && at_flag &&
      (* 2. WebAuthn §6.1 Backup State invariant: BS => BE *)
      backup_flags_valid be bs &&
      (* 3. If multi-device passkey authenticator, rk_dispatched requires BE=1 *)
      (if cap_multi_device cap then implb rk_dispatched be else true)
  end.

(** CredProps extension `rk` output calculation (WebAuthn §10.1.1): *)
Definition compute_cred_props_rk
  (rk_req