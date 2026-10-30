# Formal Verification of WebAuthn Signature Counter Monotonicity in Chromium

**Target Component:** `device/fido/authenticator_data.cc` & Blink Credential Management Architecture  
**Specification:** W3C WebAuthn Level 3 (§6.1 Authenticator Data, §7.2 Verifying an Authentication Assertion)  
**Formal Theory:** `BlinkWebAuthnSignCountMonotonicitySemantics.v`  
**Verification Engine:** Rocq / Coq Proof Assistant (Standard Library `ZArith`, `Lia`, `Bool`)  

---

## 1. Normative W3C WebAuthn Specification Requirements

### 1.1 Structural Definition (§6.1 Authenticator Data)
In the W3C Web Authentication (WebAuthn) Level 3 specification, the **Authenticator Data** (`authData`) structure is a byte array produced by the authenticator during both registration (`navigator.credentials.create()`) and authentication (`navigator.credentials.get()`). It encodes contextual bindings, cryptographic flags, and the signature counter:

| Field | Byte Length | Description |
| :--- | :--- | :--- |
| `rpIdHash` | 32 | SHA-256 hash of the Relying Party ID (`rp.id`) the credential is scoped to. |
| `flags` | 1 | Bitfield indicating User Presence (`UP`, bit 0), User Verification (`UV`, bit 2), Backup Eligibility (`BE`, bit 3), Backup State (`BS`, bit 4), Attested Credential Data (`AT`, bit 6), and Extension Data (`ED`, bit 7). |
| `signCount` | 4 | **32-bit unsigned big-endian integer** representing the signature counter. |
| `attestedCredentialData` | Variable | Present iff `AT` flag is set. Contains `aaguid`, `credentialId`, and `credentialPublicKey`. |
| `extensions` | Variable | Present iff `ED` flag is set. CBOR-encoded extension outputs. |

Formally, `signCount` occupies byte offsets $33..36$ (0-indexed) of the raw `authData` buffer:
$$\text{signCount} \in [0, 2^{32} - 1] \subset \mathbb{Z}$$

### 1.2 Normative Verification Rules (§7.2 Step 21)
During an authentication ceremony, the Relying Party (RP) or client platform verifying the assertion compares the newly received counter $\text{authData.signCount}$ (denoted `next`) against the stored counter value $\text{credentialRecord.signCount}$ (denoted `prev`) recorded during registration or the immediately preceding successful authentication.

Normative requirements from WebAuthn Level 3 §7.2 Step 21 state:

> 1. If either $\text{authData.signCount}$ is non-zero or $\text{credentialRecord.signCount}$ is non-zero, then run the following sub-step:
>    - If $\text{authData.signCount}$ is **greater than** $\text{credentialRecord.signCount}$:
>      - Update $\text{credentialRecord.signCount}$ to the value of $\text{authData.signCount}$.
>    - If $\text{authData.signCount}$ is **less than or equal to** $\text{credentialRecord.signCount}$:
>      - This is a signal that the authenticator may be cloned, i.e., at least two copies of the credential private key may exist and are being used in parallel. The Relying Party MUST incorporate this information into its risk scoring and/or reject the authentication ceremony.
> 2. If both $\text{authData.signCount} = 0$ and $\text{credentialRecord.signCount} = 0$:
>    - The authenticator does not implement a signature counter (e.g., multi-device credentials / synced passkeys where distributed atomic counters are infeasible). The verification succeeds without updating the counter.

Furthermore, an authenticator that initializes its counter at $0$ during registration ($\text{prev} = 0$) and increments it on the first assertion ($\text{next} > 0$) transitions seamlessly from $0$ to a strictly positive monotonic regime. Conversely, if $\text{prev} = 0$ and $\text{next} = 0$, it remains in the stateless counter regime. In both cases, $\text{prev} = 0$ is unconditionally valid with respect to any unsigned 32-bit integer $\text{next} \ge 0$.

This yields the exact boolean validity predicate over unsigned integers $\text{prev}, \text{next} \in [0, 2^{32}-1]$:
$$\text{sign\_count\_valid}(\text{prev}, \text{next}) \iff (\text{prev} = 0) \lor (\text{prev} < \text{next})$$

*(Note: A stricter variant requires $(\text{prev} = 0 \land \text{next} = 0) \lor (\text{prev} < \text{next})$. Under unsigned arithmetic $\text{next} \ge 0$, when $\text{prev} = 0$, the disjunction $\text{next} = 0 \lor 0 < \text{next}$ is tautologically equivalent to $\text{prev} = 0$.)*

---

## 2. Chromium Implementation & Invariants (`device/fido/authenticator_data.cc`)

### 2.1 Binary Deserialization and Serialization Invariants
In Chromium's FIDO module (`device/fido/authenticator_data.h` and `device/fido/authenticator_data.cc`), `AuthenticatorData` encapsulates the parsed representation of the raw `authData` byte span.

```cpp
// Conceptual representation of Chromium's device/fido/authenticator_data.h
class COMPONENT_EXPORT(DEVICE_FIDO) AuthenticatorData {
 public:
  static std::optional<AuthenticatorData> DecodeAuthenticatorData(
      base::span<const uint8_t> auth_data);

  std::vector<uint8_t> SerializeToByteArray() const;

  // Returns the 32-bit counter decoded from big-endian bytes [33..36].
  base::span<const uint8_t, kSignCounterLength> counter() const {
    return counter_;
  }
  
  uint32_t GetSignCount() const {
    return base::U32FromBigEndian(counter_);
  }

 private:
  static constexpr size_t kRpIdHashLength = 32;
  static constexpr size_t kFlagsLength = 1;
  static constexpr size_t kSignCounterLength = 4;

  std::array<uint8_t, kRpIdHashLength> application_parameter_;
  uint8_t flags_;
  std::array<uint8_t, kSignCounterLength> counter_;
  std::optional<AttestedCredentialData> attested_data_;
  std::optional<cbor::Value> extensions_;
};
```

In `AuthenticatorData::DecodeAuthenticatorData(base::span<const uint8_t> auth_data)`:
1. **Length Invariant:** Chromium enforces `auth_data.size() >= kRpIdHashLength + kFlagsLength + kSignCounterLength` ($32 + 1 + 4 = 37$ bytes). If `auth_data.size() < 37`, decoding immediately fails and returns `std::nullopt` before any counter extraction occurs.
2. **Endianness & Domain Invariant:** `counter_` is extracted from `auth_data.subspan<33, 4>()` and interpreted via `base::U32FromBigEndian` (or `base::BigEndianReader`). Because it is stored as four `uint8_t` bytes and converted to `uint32_t`, the value is structurally bounded within $[0, 2^{32}-1]$ ($0 \le \text{signCount} \le 4294967295$).
3. **Virtual & Enclave Authenticator Invariants:** In Chromium's internal authenticators (`device/fido/virtual_fido_device.cc`, `device/fido/enclave/`, and platform credential managers), the stored counter state is updated upon signature generation or assertion verification:
   - If the registration initialized `sign_count = 0` and the device simulates a non-incrementing counter, `prev == 0 && next == 0` holds.
   - If the device increments its counter, it checks for 32-bit overflow or strictly increments `state->sign_count++`, enforcing `prev < next`.
   - When verifying assertions in test harnesses, virtual authenticators, or relying party verification layers within Chromium, the transition validator checks `(prev == 0) || (prev < next)`.

### 2.2 Security Invariants Enforced by the Architecture
1. **Clone Detection Soundness:** If an attacker clones a hardware-bound token at counter state $C > 0$, both the genuine token and the clone hold state $C$. Once the genuine token authenticates (advancing the RP state to $C+1$), a subsequent authentication attempt by the clone presents $C' = C+1 \le C+1$. The predicate `sign_count_valid(C+1, C+1)` evaluates to `false`, flagging the clone.
2. **Irreversible Activation of Monotonicity:** Once a credential transitions from counter value $0$ to any positive counter value $k > 0$, it can never legally return to $0$ or remain static. Every subsequent valid transition must strictly increase the counter.
3. **Finite Horizon / Overflow Protection:** Because `signCount` is bounded by `UINT32_MAX` ($2^{32}-1$), no valid strictly increasing transition exists from $\text{prev} = 2^{32}-1$. An authenticator at maximum capacity cannot wrap around to $0$ without violating `sign_count_valid`.

---

## 3. Formal Specification in Rocq / Coq

Below is the complete, self-contained formalization of `BlinkWebAuthnSignCountMonotonicitySemantics.v`. It models the byte-level big-endian decoding in `device/fido/authenticator_data.cc`, the unsigned 32-bit domain invariants, the exact transition predicate `sign_count_valid`, and the multi-step state machine governing WebAuthn assertion verification.

```coq
(** * BlinkWebAuthnSignCountMonotonicitySemantics.v
    Formal Verification of W3C WebAuthn Level 3 §6.1 / §7.2 Signature Counter
    Monotonicity and Chromium device/fido/authenticator_data.cc Semantics. *)

From Coq Require Import ZArith.
From Coq Require Import Bool.
From Coq Require Import Lia.
From Coq Require Import List.
Import ListNotations.

Open Scope Z_scope.

(** ** 1. Architectural Constants and Domain Definitions *)

(** Maximum value of a 32-bit unsigned integer (2^32 - 1 = 4294967295). *)
Definition UINT32_MAX : Z := 4294967295.

(** Minimum valid byte length of WebAuthn AuthenticatorData:
    32 (rpIdHash) + 1 (flags) + 4 (signCount) = 37 bytes. *)
Definition AUTH_DATA_MIN_LEN : nat := 37%nat.

(** Predicate characterizing a valid unsigned 8-bit byte. *)
Definition is_uint8 (b : Z) : Prop := 0 <= b <= 255.

(** Predicate characterizing a valid unsigned 32-bit integer (uint32_t). *)
Definition is_uint32 (n : Z) : Prop := 0 <= n <= UINT32_MAX.

(** Executable boolean check for uint32 bounds. *)
Definition is_uint32_b (n : Z) : bool := (0 <=? n) && (n <=? UINT32_MAX).

(** ** 2. Big-Endian Deserialization (device/fido/authenticator_data.cc) *)

(** Decodes 4 big-endian bytes (offsets 33..36 of authData) into a 32-bit integer,
    matching Chromium's base::U32FromBigEndian(counter_). *)
Definition decode_be32 (b0 b1 b2 b3 : Z) : Z :=
  b0 * 16777216 + b1 * 65536 + b2 * 256 + b3.

(** Minimal model of parsed AuthenticatorData focusing on §6.1 fields. *)
Record AuthenticatorData := mkAuthData {
  auth_rp_id_hash : list Z;
  auth_flags : Z;
  auth_sign_count : Z
}.

(** Well-formedness invariant of a decoded AuthenticatorData instance
    as guaranteed by AuthenticatorData::DecodeAuthenticatorData. *)
Definition wf_auth_data (ad : AuthenticatorData) : Prop :=
  length (auth_rp_id_hash ad) = 32%nat /\
  is_uint8 (auth_flags ad) /\
  is_uint32 (auth_sign_count ad).

(** ** 3. WebAuthn SignCount Monotonicity Specification *)

(** Mathematical Property:
    sign_count_valid(prev, next) = (prev =? 0) || (prev <? next) *)
Definition sign_count_valid (prev next : Z) : bool :=
  (prev =? 0) || (prev <? next).

(** Strict specification variant explicitly separating the unimplemented-counter
    case (0 -> 0) from the strictly increasing case (prev < next). *)
Definition sign_count_valid_strict_spec (prev next : Z) : bool :=
  ((prev =? 0) && (next =? 0)) || (prev <? next).

(** ** 4. Credential Record State Transition Semantics *)

(** Result of verifying the signature counter during an authentication ceremony. *)
Inductive CounterVerificationResult : Type :=
  | CounterUpdated (new_count : Z)
  | CloneWarningDetected.

(** State transition function corresponding to WebAuthn Level 3 §7.2 Step 21. *)
Definition verify_and_update_sign_count (prev next : Z) : CounterVerificationResult :=
  if sign_count_valid prev next then
    CounterUpdated next
  else
    CloneWarningDetected.

(** Multi-step valid counter trace over a sequence of authentication assertions. *)
Inductive valid_counter_trace : Z -> list Z -> Prop :=
  | Trace_Nil : forall init,
      is_uint32 init ->
      valid_counter_trace init []
  | Trace_Cons : forall prev next rest,
      is_uint32 prev ->
      is_uint32 next ->
      sign_count_valid prev next = true ->
      valid_counter_trace next rest ->
      valid_counter_trace prev (next :: rest).
```

---

## 4. Concrete Theorems and Complete Admitted-Free Proofs

This section provides the complete deductive verification of our formal theory using `ZArith`, `Bool`, and `Lia`. Every theorem is proven without `admit` or `Admitted`.

```coq
(** ** 5. Formal Proofs of Correctness and Security Invariants *)

(** *** Theorem 1: Big-Endian 32-bit Decoding Soundness
    Proves that decoding any four valid uint8 bytes produces a valid uint32
    within [0, UINT32_MAX], matching device/fido/authenticator_data.cc. *)
Theorem decode_be32_is_uint32 : forall