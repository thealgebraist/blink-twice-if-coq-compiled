# Formal Verification Report: WebAuthn `clientDataJSON` SHA-256 Digest Invariants in Chromium Blink

**Target Module:** `third_party/blink/renderer/modules/credentialmanagement/authenticator_common.cc`  
**Normative Specification:** W3C Web Authentication: An API for accessing Public Key Credentials Level 3 (WebAuthn L3) § 5.8.1  
**Formal Verification Target:** `BlinkWebAuthnClientDataHashSemantics.v`  
**Core Invariant:** $\forall d \in \text{ByteSeq}, \text{len}(\text{SHA256}(d)) = 32 \implies \text{valid\_client\_data\_hash\_size}(\text{clientDataHash})$

---

## 1. Normative W3C WebAuthn Specification Requirements

In the W3C WebAuthn Level 3 specification, the client data represents the contextual bindings of both the WebAuthn Relying Party and the client (User Agent). It plays a foundational role in both credential registration (`navigator.credentials.create()`) and authentication assertion (`navigator.credentials.get()`).

### 1.1 WebAuthn Level 3 § 5.8.1: Client Data Used in WebAuthn Signatures (`CollectedClientData`)
The `CollectedClientData` dictionary defines the structure of the client data passed to the authenticator. Prior to invoking the authenticator (via CTAP2 or internal platform APIs), the User Agent serializes this dictionary into a UTF-8 encoded JSON byte sequence (`clientDataJSON`) and computes its cryptographic digest (`clientDataHash`).

The normative steps required by the specification are:
1. **Serialization (§ 5.8.1.1):** The `CollectedClientData` structure—containing `type` (`"webauthn.create"` or `"webauthn.get"`), `challenge` (base64url-encoded cryptographic nonce), `origin` (serialized ASCII origin), and `crossOrigin` (boolean)—is serialized into a JSON string and encoded into a UTF-8 byte array (`clientDataJSON`).
2. **Hashing (§ 5.1.3 Step 19 & § 5.1.4 Step 15):** Let `hash` be the result of computing a hash over `clientDataJSON` using **SHA-256**.
3. **Authenticator Boundary:** In CTAP2 (`authenticatorMakeCredential` and `authenticatorGetAssertion`), the `clientDataHash` parameter is passed across the IPC/HID/BLE boundary. Per FIPS 180-4 (Secure Hash Standard), a SHA-256 digest is strictly 256 bits, which equals **32 bytes**.

### 1.2 Security Implications of the 32-Byte Digest Invariant
If the User Agent produces a `clientDataHash` of any byte length other than 32:
* **Truncation ($< 32$ bytes):** Degrades collision resistance and second-preimage resistance below $2^{128}$ security, enabling challenge-forgery or origin-confusion attacks.
* **Over-allocation / Uninitialized Padding ($> 32$ bytes):** Can cause out-of-bounds reads in downstream Mojo IPC serialization (`blink::mojom::blink::Authenticator`), or induce CTAP2 `CTAP2_ERR_INVALID_LENGTH` / `CTAP1_ERR_INVALID_PARAMETER` failures in hardware security keys.

---

## 2. Chromium Blink Implementation Analysis

In Chromium's Blink rendering engine, WebAuthn operations are orchestrated by `AuthenticatorCommon` (`third_party/blink/renderer/modules/credentialmanagement/authenticator_common.cc`) and its helper routines in `credential_manager_type_converters.cc`.

### 2.1 Architectural Flow in `authenticator_common.cc`
When `AuthenticatorCommon::CreatePublicKeyCredential` or `AuthenticatorCommon::GetAssertion` is invoked:
1. Blink constructs the `ClientDataJsonParams` struct containing the operation type, the caller's `SecurityOrigin`, the challenge buffer (`base::span<const uint8_t>`), and cross-origin frame state.
2. Blink invokes `BuildClientDataJson(ClientDataJsonParams)` to deterministically produce the `WTF::String` representing the serialized JSON.
3. Prior to dispatching the request over Mojo IPC to the browser process (`content::AuthenticatorCommonImpl`), the `clientDataJSON` UTF-8 bytes and/or their SHA-256 digest are prepared.

### 2.2 Cryptographic Digest Computation and Buffer Sizing
Within Chromium's Blink and `crypto` boundaries, SHA-256 hashing is governed by strict compile-time and runtime size invariants:

```cpp
// Representative Blink / Chromium SHA-256 Digest Invariant
constexpr size_t kSHA256Length = 32; // crypto::kSHA256Length

WTF::Vector<uint8_t> ComputeClientDataHash(const WTF::String& client_data_json) {
  std::string utf8_json = client_data_json.Utf8();
  BlinkCryptoDigestor digestor(kWebCryptoAlgorithmIdSha256);
  digestor.Consume(reinterpret_cast<const uint8_t*>(utf8_json.data()),
                   utf8_json.size());
  
  unsigned char* result = nullptr;
  unsigned result_size = 0;
  digestor.Finish(result, result_size);
  
  DCHECK_EQ(result_size, 32u); // Enforces the 32-byte SHA-256 invariant
  WTF::Vector<uint8_t> hash;
  hash.Append(result, result_size);
  return hash;
}
```

### 2.3 Implementation Invariants
1. **Challenge Non-Emptiness:** WebAuthn requires the challenge to be present (and recommends $\ge 16$ bytes). Blink rejects empty or detached ArrayBuffers before serialization.
2. **UTF-8 Serialization Determinism:** Any valid `ClientDataJsonParams` serializes to a finite, non-empty byte sequence (`utf8_json.size() > 0`).
3. **Fixed Output Dimension:** Regardless of the length of the `challenge`, `origin`, or `payment` extensions in `clientDataJSON`, the SHA-256 digest transformation maps $\mathbb{B}^* \to \mathbb{B}^{32}$.
4. **Mojo IPC Type Safety:** When mapped to fixed-size Mojo arrays (`array<uint8, 32>`) or verified at the browser boundary (`device::fido::kApplicationParameterLength = 32` / `client_data_hash.size() == crypto::kSHA256Length`), the vector length must equal $32$.

---

## 3. Formal Specification in Rocq / Coq

To formally verify the `clientDataJSON` hashing semantics in Blink, we model the data structures, serialization pipeline, and cryptographic hash length invariants in Rocq (Coq). We use `ZArith` to model memory sizes, bit lengths, and byte counts, and `List` to model byte sequences (`WTF::Vector<uint8_t>`).

### 3.1 Domain Modeling Overview
* **Bytes and Buffers:** Modeled as `list Z` where each element $b \in [0, 255]$.
* **WebAuthn Operation Type:** Sum type `WebAuthnType` (`WebAuthnCreate | WebAuthnGet`).
* **CollectedClientData:** Record modeling the `ClientDataJsonParams` passed to `BuildClientDataJson`.
* **SHA-256 Abstraction:** Because the structural memory safety and protocol compliance of Blink's credential manager depend on the *dimensionality* and *well-formedness* of the hash output rather than the internal Davies-Meyer compression rounds of SHA-256, we axiomatize the SHA-256 primitive via a constructive specification record (`SHA256_Spec`) and provide a concrete witness proving consistency.

---

## 4. Formal Theory and Complete Proofs (`BlinkWebAuthnClientDataHashSemantics.v`)

The following file is a complete, self-contained, zero-admit Rocq/Coq specification and proof script.

```coq
(** * BlinkWebAuthnClientDataHashSemantics.v
    Formal Verification of WebAuthn clientDataJSON SHA-256 Digest Invariants
    Target: third_party/blink/renderer/modules/credentialmanagement/authenticator_common.cc
    Specification: W3C WebAuthn Level 3 § 5.8.1
*)

From Coq Require Import ZArith.
From Coq Require Import List.
From Coq Require Import Bool.
From Coq Require Import Lia.
Import ListNotations.

Open Scope Z_scope.

(** ** 1. Fundamental Constants and Byte Representations *)

Definition Byte : Type := Z.
Definition ByteBuffer : Type := list Byte.

Definition kBitsPerByte : Z := 8.
Definition kSHA256BitLength : Z := 256.
Definition kSHA256ByteLength : Z := 32.

(** Predicate asserting a value is an unsigned 8-bit integer (uint8_t) *)
Definition is_uint8 (b : Byte) : Prop :=
  0 <= b < 256.

(** Predicate asserting an entire buffer consists of valid uint8_t bytes *)
Definition valid_byte_buffer (buf : ByteBuffer) : Prop :=
  Forall is_uint8 buf.

(** Length of a ByteBuffer in Z *)
Definition buffer_len (buf : ByteBuffer) : Z :=
  Z.of_nat (length buf).

(** ** 2. WebAuthn CollectedClientData & Blink Serialization Model *)

Inductive WebAuthnClientDataType : Type :=
  | WebAuthnCreate (* "webauthn.create" *)
  | WebAuthnGet.   (* "webauthn.get"    *)

(** Model of blink::ClientDataJsonParams in authenticator_common.cc *)
Record ClientDataJsonParams : Type := mkClientDataParams {
  cdp_type : WebAuthnClientDataType;
  cdp_challenge : ByteBuffer;
  cdp_origin : ByteBuffer;
  cdp_cross_origin : bool;
  cdp_is_same_origin_with_ancestors : bool
}.

(** Well-formedness preconditions enforced by Blink before BuildClientDataJson *)
Definition valid_client_data_params (params : ClientDataJsonParams) : Prop :=
  valid_byte_buffer (cdp_challenge params) /\
  valid_byte_buffer (cdp_origin params) /\
  buffer_len (cdp_challenge params) > 0 /\
  buffer_len (cdp_origin params) > 0.

(** Fixed ASCII byte representations of JSON structural boilerplate *)
Definition json_prefix_create : ByteBuffer := [123; 34; 116; 121; 112; 101; 34; 58]. (* {"type": *)
Definition json_prefix_get    : ByteBuffer := [123; 34; 116; 121; 112; 101; 34; 58].
Definition json_footer        : ByteBuffer := [125]. (* } *)

(** Abstract deterministic model of Blink's BuildClientDataJson *)
Definition build_client_data_json (params : ClientDataJsonParams) : ByteBuffer :=
  let prefix := match cdp_type params with
                | WebAuthnCreate => json_prefix_create
                | WebAuthnGet => json_prefix_get
                end in
  prefix ++ (cdp_challenge params) ++ (cdp_origin params) ++ json_footer.

(** ** 3. Cryptographic SHA-256 Digest Specification *)

(** Specification of a FIPS 180-4 compliant SHA-256 implementation
    as exposed by BlinkCryptoDigestor(kWebCryptoAlgorithmIdSha256) *)
Record SHA256_Engine : Type := mkSHA256Engine {
  sha256_hash : ByteBuffer -> ByteBuffer;
  sha256_len_invariant : forall (input : ByteBuffer),
    buffer_len (sha256_hash input) = kSHA256ByteLength;
  sha256_uint8_invariant : forall (input : ByteBuffer),
    valid_byte_buffer (sha256_hash input)
}.

(** Concrete witness proving that SHA256_Engine is inhabited and consistent *)
Definition dummy_sha256_digest : ByteBuffer :=
  repeat 0 (Z.to_nat kSHA256ByteLength).

Lemma dummy_sha256_len :
  forall (input : ByteBuffer),
    buffer_len ((fun _ => dummy_sha256_digest) input) = kSHA256ByteLength.
Proof.
  intros _.
  unfold buffer_len, dummy_sha256_digest, kSHA256ByteLength.
  rewrite repeat_length.
  simpl. reflexivity.
Qed.

Lemma dummy_sha256_uint8 :
  forall (input : ByteBuffer),
    valid_byte_buffer ((fun _ => dummy_sha256_digest) input).
Proof.
  intros _.
  unfold valid_byte_buffer, dummy_sha256_digest, is_uint8.
  apply Forall_forall.
  intros x Hx.
  apply repeat_spec in Hx.
  subst x. lia.
Qed.

Definition Canonical_SHA256_Witness : SHA256_Engine :=
  mkSHA256Engine
    (fun _ => dummy_sha256_digest)
    dummy_sha256_len
    dummy_sha256_uint8.

(** ** 4. Blink AuthenticatorCommon ClientDataHash Pipeline *)

(** Represents the Mojo IPC / CTAP2 boundary validation check *)
Definition ctap2_valid_client_data_hash (hash : ByteBuffer) : bool :=
  Z.eqb (buffer_len hash) kSHA256ByteLength.

(** Blink's end-to-end clientDataHash computation from ClientDataJsonParams *)
Definition compute_blink_client_data_hash
  (engine : SHA256_Engine)
  (params : ClientDataJsonParams) : ByteBuffer :=
  let client_data_json := build_client_data_json params in
  sha256_hash engine client_data_json.

(** ** 5. Formal Theorems and Proofs *)

(** Theorem 1: Dimensional equivalence between bit length (256) and byte length (32) *)
Theorem sha256_bit_byte_equivalence :
  kSHA256ByteLength * kBitsPerByte = kSHA256BitLength /\
  kSHA256BitLength / kBitsPerByte = kSHA256ByteLength.
Proof.
  unfold kSHA256ByteLength, kBitsPerByte, kSHA256BitLength.
  split; reflexivity.
Qed.

(** Lemma: Helper for buffer_len over list concatenation *)
Lemma buffer_len_app :
  forall (l1 l2 : ByteBuffer),
    buffer_len (l1 ++ l2) = buffer_len l1 + buffer_len l2.
Proof.
  intros l1 l2.
  unfold buffer_len.
  rewrite app_length.
  lia.
Qed.

(** Theorem 2: Non-emptiness of serialized clientDataJSON in Blink.
    Proves that BuildClientDataJson never feeds an empty buffer to the