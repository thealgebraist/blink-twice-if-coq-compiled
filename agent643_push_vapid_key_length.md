# Formal Verification Report: Push API VAPID `applicationServerKey` 65-Byte Uncompressed P-256 Length Semantics

**Agent Designation:** Formal Verification Agent 643  
**Specialization:** Web Push, Notifications, Badging & Background Sync (Chromium Blink)  
**Target Artifact:** `BlinkPushVAPIDKeyLengthSemantics.v`  
**Chromium Source Under Analysis:** `third_party/blink/renderer/modules/push_messaging/push_manager.cc`  
**Specification Targets:** W3C Push API §7.2 (`PushSubscriptionOptionsInit`), RFC 8292 §2 & §3 (VAPID), SEC 1 v2.0 §2.3.3  

---

## 1. Normative Specification Requirements

### 1.1 W3C Push API & RFC 8292 (VAPID)
Under the W3C Push API specification (§7.2, `PushSubscriptionOptions` and `PushManager.subscribe()`), a Web Application may supply an `applicationServerKey` inside `PushSubscriptionOptionsInit` to restrict a push subscription to a specific application server using the Voluntary Application Server Identification (VAPID) protocol defined in **RFC 8292**.

1. **Cryptographic Curve Requirement (RFC 8292 §2):**
   Application servers MUST generate an Elliptic Curve Digital Signature Algorithm (ECDSA) key pair on the NIST P-256 curve (`secp256r1`, prime256v1) in accordance with FIPS 186-4.
2. **Public Key Encoding Requirement (RFC 8292 §3.2 & §4.2, W3C Push API §7.2):**
   When passed to `PushManager.subscribe({ applicationServerKey })` (either as a `BufferSource` or base64url-decoded `DOMString`), the public key MUST be encoded in the **uncompressed point form** defined in **SEC 1: Elliptic Curve Cryptography, Section 2.3.3** ( Elliptic-Curve-Point-to-Octet-String Conversion).
3. **Exact Octet Length Derivation:**
   For the NIST P-256 curve over the finite field $\mathbb{F}_p$ where $p = 2^{256} - 2^{224} + 2^{192} + 2^{96} - 1$:
   - The field element bit length is $256\text{ bits}$, giving an octet length $m = \lceil \log_2(p) / 8 \rceil = 32\text{ octets}$.
   - An uncompressed point $P = (x_P, y_P)$ is serialized as:
     $$\text{OctetString} = \text{0x04} \mathbin{\Vert} X \mathbin{\Vert} Y$$
     where $\text{0x04}$ is the single-octet uncompressed form indicator, $X$ is the 32-octet big-endian representation of $x_P$, and $Y$ is the 32-octet big-endian representation of $y_P$.
   - Total length: $1 + 32 + 32 = 65\text{ octets (bytes)}$.
4. **Normative Error Handling (W3C Push API `subscribe()` Steps):**
   If the `applicationServerKey` provided is not a valid P-256 public key in uncompressed form (or is neither a valid 65-byte uncompressed P-256 key nor a legacy sender ID where supported), the User Agent MUST reject the promise with an `InvalidAccessError` `DOMException` before dispatching IPC requests to the background push service.

---

## 2. Chromium Blink Implementation & Invariants

### 2.1 Source Analysis: `third_party/blink/renderer/modules/push_messaging/push_manager.cc`
In Chromium Blink, `PushManager::subscribe` converts the incoming `PushSubscriptionOptionsInit*` dictionary into a `PushSubscriptionOptions*` Blink object via `PushSubscriptionOptions::FromOptionsInit`.

Key constants and validation logic across `push_manager.cc` and `push_subscription_options.cc`:

```cpp
// Maximum/Exact length for NIST P-256 uncompressed public key (0x04 || X || Y)
constexpr size_t kMaxApplicationServerKeyLength = 65; // And exact P-256 check: == 65
constexpr uint8_t kUncompressedPointPrefix = 0x04;
```

When validating the `applicationServerKey`:
1. **Input Normalization:** If `applicationServerKey` is a `DOMString`, Blink decodes it using Base64URL decoding (`Base64UnpaddedURLDecode`). If it is an `ArrayBuffer` or `ArrayBufferView`, Blink extracts the raw byte span `(uint8_t*, size_t)`.
2. **VAPID Key Identification & Length Invariant:**
   Blink checks whether the input represents a NIST P-256 uncompressed public key:
   ```cpp
   const bool is_vapid = (input_length == 65 && input[0] == 0x04);
   ```
   Specifically, for strict VAPID `applicationServerKey` length semantics:
   $$\text{is\_valid\_vapid\_key\_len}(\text{len}) \iff (\text{len} = 65)$$
3. **Rejection Invariant:**
   If a byte buffer (or decoded string intended as a VAPID key) fails the length predicate $\text{len} = 65$ (or fails `InvalidAccessError` validation criteria), `exception_state.ThrowDOMException(DOMExceptionCode::kInvalidAccessError, ...)` is invoked synchronously, preventing malformed keys from crossing the Mojo IPC boundary (`mojom::blink::PushMessaging`) into the browser process or corrupting Service Worker registration state.

---

## 3. Formal Specification in Rocq/Coq

Below is the complete, self-contained formalization of `BlinkPushVAPIDKeyLengthSemantics.v`. It models SEC 1 P-256 coordinate geometry lengths, Blink's boolean and propositional length validators, byte-list encodings, and the state-machine preservation of background Service Worker push registrations.

```coq
(** * BlinkPushVAPIDKeyLengthSemantics.v
    Formal Verification of Web Push API VAPID applicationServerKey
    65-byte Uncompressed P-256 Length Semantics in Chromium Blink.

    Source: third_party/blink/renderer/modules/push_messaging/push_manager.cc
    Specification: RFC 8292 §3 / W3C Push API §7.2
*)

From Coq Require Import ZArith.
From Coq Require Import Lia.
From Coq Require Import Bool.
From Coq Require Import List.
Import ListNotations.

Open Scope Z_scope.

(** ** 1. Cryptographic & Protocol Constants (RFC 8292 & SEC 1 §2.3.3) *)

(** NIST P-256 field element bit length *)
Definition P256_FIELD_BITS : Z := 256.

(** Bits per octet *)
Definition BITS_PER_BYTE : Z := 8.

(** NIST P-256 coordinate octet length: 256 / 8 = 32 bytes *)
Definition P256_COORD_LEN : Z := P256_FIELD_BITS / BITS_PER_BYTE.

(** SEC 1 §2.3.3 uncompressed point indicator prefix length (0x04 takes 1 byte) *)
Definition SEC1_UNCOMPRESSED_PREFIX_LEN : Z := 1.

(** SEC 1 §2.3.3 uncompressed point indicator byte value *)
Definition SEC1_UNCOMPRESSED_FORM_TAG : Z := 4. (* 0x04 *)

(** Exact required length of a VAPID applicationServerKey in bytes:
    1 (prefix) + 32 (X coordinate) + 32 (Y coordinate) = 65 bytes *)
Definition VAPID_KEY_EXACT_LEN : Z :=
  SEC1_UNCOMPRESSED_PREFIX_LEN + P256_COORD_LEN + P256_COORD_LEN.

(** ** 2. Mathematical Property Definitions *)

(** Core executable boolean predicate from target specification:
    is_valid_vapid_key_len(len) = (len == 65) *)
Definition is_valid_vapid_key_len (len : Z) : bool :=
  Z.eqb len 65.

(** Propositional counterpart of the VAPID key length requirement *)
Definition ValidVAPIDKeyLenProp (len : Z) : Prop :=
  len = 65.

(** Full uncompressed P-256 header + length validation over a raw byte list *)
Definition is_valid_vapid_key_bytes (bytes : list Z) : bool :=
  match bytes with
  | prefix :: _ =>
      andb (Z.eqb prefix SEC1_UNCOMPRESSED_FORM_TAG)
           (is_valid_vapid_key_len (Z.of_nat (length bytes)))
  | [] => false
  end.

(** ** 3. Blink PushManager Subscribe Validation & Background State Machine *)

(** DOMException codes relevant to PushManager.subscribe *)
Inductive BlinkDOMException : Type :=
  | InvalidAccessError
  | InvalidStateError
  | NotAllowedError.

(** Result of PushManager::subscribe option validation in Blink *)
Inductive ValidationResult : Type :=
  | ValidationSuccess (validated_key : list Z)
  | ValidationFailure (err : BlinkDOMException).

(** Blink validation function modeling PushSubscriptionOptions::FromOptionsInit *)
Definition blink_validate_vapid_key (raw_key : list Z) : ValidationResult :=
  if is_valid_vapid_key_bytes raw_key then
    ValidationSuccess raw_key
  else
    ValidationFailure InvalidAccessError.

(** Background Push Service state: holds active valid subscriptions *)
Record BackgroundPushState : Type := mkBackgroundPushState {
  active_subscriptions : list (list Z)
}.

(** Invariant on BackgroundPushState: every registered subscription key
    has a valid 65-byte VAPID key length and uncompressed tag *)
Definition BackgroundStateInvariant (st : BackgroundPushState) : Prop :=
  forall key, In key (active_subscriptions st) ->
    is_valid_vapid_key_len (Z.of_nat (length key)) = true /\
    Z.of_nat (length key) = 65.

(** State transition when PushManager::subscribe is invoked *)
Definition blink_push_subscribe_step
  (st : BackgroundPushState)
  (candidate_key : list Z) : BackgroundPushState * ValidationResult :=
  match blink_validate_vapid_key candidate_key with
  | ValidationSuccess k =>
      (mkBackgroundPushState (k :: active_subscriptions st), ValidationSuccess k)
  | ValidationFailure e =>
      (st, ValidationFailure e)
  end.

(** ** 4. Concrete Theorems and Complete Proofs *)

(** Theorem 1: The SEC 1 structural derivation of P-256 uncompressed key length
    equals exactly 65 bytes. *)
Theorem sec1_p256_uncompressed_len_is_65 :
  VAPID_KEY_EXACT_LEN = 65.
Proof.
  unfold VAPID_KEY_EXACT_LEN, SEC1_UNCOMPRESSED_PREFIX_LEN,
         P256_COORD_LEN, P256_FIELD_BITS, BITS_PER_BYTE.
  reflexivity.
Qed.

(** Theorem 2: Exact reflection between the boolean validator
    is_valid_vapid_key_len and the propositional equality len = 65. *)
Theorem is_valid_vapid_key_len_iff :
  forall (len : Z),
    is_valid_vapid_key_len len = true <-> ValidVAPIDKeyLenProp len.
Proof.
  intros len.
  unfold is_valid_vapid_key_len, ValidVAPIDKeyLenProp.
  rewrite Z.eqb_eq.
  tauto.
Qed.

(** Theorem 3: Soundness and completeness of rejection when length != 65. *)
Theorem is_valid_vapid_key_len_false_iff :
  forall (len : Z),
    is_valid_vapid_key_len len = false <-> len <> 65.
Proof.
  intros len.
  unfold is_valid_vapid_key_len.
  rewrite Z.eqb_neq.
  tauto.
Qed.

(** Theorem 4: Decidability of VAPID key length validity. *)
Theorem valid_vapid_key_len_decidable :
  forall (len : Z),
    {ValidVAPIDKeyLenProp len} + {~ ValidVAPIDKeyLenProp len}.
Proof.
  intros len.
  unfold ValidVAPIDKeyLenProp.
  destruct (Z.eq_dec len 65) as [Heq | Hneq].
  - left. exact Heq.
  - right. exact Hneq.
Qed.

(** Theorem 5: Strict boundary exclusion — any length strictly less than 65
    (e.g., 0-byte empty buffer, 32-byte raw X coordinate, 33-byte compressed
    SEC 1 point, or 64-byte raw X||Y without 0x04 prefix) is rejected. *)
Theorem reject_underlength_vapid_keys :
  forall (len : Z),
    len < 65 -> is_valid_vapid_key_len len = false.
Proof.
  intros len Hlt.
  apply is_valid_vapid_key_len_false_iff.
  lia.
Qed.

(** Theorem 6: Explicit rejection of common malformed cryptographic key lengths
    (0-byte empty, 33-byte compressed P-256, 64-byte unprefixed P-256,
     97-byte P-384 uncompressed). *)
Theorem reject_common_malformed_key_lengths :
  is_valid_vapid_key_len 0 = false /\
  is_valid_vapid_key_len 33 = false /\
  is_valid_vapid_key_len 64 = false /\
  is_valid_vapid_key_len 97 = false /\
  is_valid_vapid_key_len 65 = true.
Proof.
  repeat split; reflexivity.
Qed.

(** Theorem 7: Strict boundary exclusion — any length strictly greater than 65
    is rejected. *)
Theorem reject_overlength_vapid_keys :
  forall (len : Z),
    len > 65 -> is_valid_vapid_key_len len = false.
Proof.
  intros len Hgt.
  apply is_valid_vapid_key_len_false_iff.
  lia.
Qed.

(** Theorem 8: Decomposition of a valid 65-byte VAPID key into its
    1-byte 0x04 prefix and 64-byte (X || Y) coordinate payload. *)
Theorem valid_vapid_key_bytes_decomposition :
  forall (bytes : list Z),
    is_valid_