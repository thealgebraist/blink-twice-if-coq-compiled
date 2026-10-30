# Formal Verification Report: WebSocket Client Frame Masking XOR Symmetry in Chromium

**Target Theory**: `BlinkWebSocketFrameMaskingXORSymmetrySemantics.v`  
**Chromium Subsystem**: `net/websockets/websocket_frame.cc`  
**Normative Specification**: IETF RFC 6455 §5.3 (Client-to-Server Masking)  
**Mathematical Foundation**: Involutivity of bitwise exclusive-OR over integer rings ($\mathbb{Z}$) and byte streams ($\text{List } \mathbb{Z}$)

---

## 1. Normative Specification Analysis (RFC 6455 §5.3)

To prevent cache poisoning attacks against intermediary proxies (e.g., transparent HTTP proxies misinterpreting attacker-controlled WebSocket payload bytes as valid HTTP `GET` requests targeting cached resources), RFC 6455 mandates cryptographic-grade frame masking for all client-to-server transmissions.

### 1.1 Normative Algorithmic Requirements
According to **RFC 6455 Section 5.3**:
1. **Masking Key Generation**: A client MUST mask all frames that it sends to the server. The masking key is a 32-bit value chosen at random by the client, derived from a strong source of entropy.
2. **Byte-Level Transformation**: Let the masking key be represented as a 4-byte sequence $K = [k_0, k_1, k_2, k_3]$. For a payload of length $N$, the $i$-th octet of the transformed data ($\text{transformed-octet}_i$) is the XOR of the $i$-th octet of the original data ($\text{original-octet}_i$) with the $(i \bmod 4)$-th octet of the masking key:
   $$\text{transformed-octet}_i = \text{original-octet}_i \oplus k_{i \bmod 4}$$
3. **Symmetry & Unmasking**: Because bitwise XOR ($\oplus$) forms an abelian group of exponent 2 over $GF(2^8)$, the exact same algorithm and key offset state machine MUST be applied to unmask the frame payload upon receipt or across chunked stream boundaries:
   $$\text{original-octet}_i = \text{transformed-octet}_i \oplus k_{i \bmod 4}$$

---

## 2. Chromium Implementation & Invariants (`net/websockets/websocket_frame.cc`)

In Chromium's network stack (interfacing with Blink's `WebSocketChannelImpl` and Mojo data pipes), WebSocket frame masking is implemented in `net/websockets/websocket_frame.cc` via the `MaskWebSocketFramePayload` function.

### 2.1 C++ Implementation Mechanics
```cpp
// Simplified representation of net/websockets/websocket_frame.cc
void MaskWebSocketFramePayload(const WebSocketMaskingKey& masking_key,
                               uint64_t frame_offset,
                               char* const data,
                               int data_size) {
  static constexpr size_t kMaskingKeyLength = WebSocketFrameHeader::kMaskingKeyLength; // 4
  
  // Word-level SIMD / size_t optimization path omitted for clarity; 
  // algebraically equivalent to the byte-by-byte loop:
  for (int i = 0; i < data_size; ++i) {
    const size_t key_index = (frame_offset + i) % kMaskingKeyLength;
    data[i] ^= masking_key.key[key_index];
  }
}
```

### 2.2 Engine Invariants
1. **In-Place Involution Invariant**: Calling `MaskWebSocketFramePayload(key, offset, buf, len)` twice consecutively on the same memory buffer `buf` with identical `key` and `offset` restores `buf` to its exact initial bit pattern.
2. **Stream Chunking & Offset Homomorphism**: WebSocket payloads arriving over Blink `ReadableStream` or Mojo `DataPipe` are often fragmented into arbitrary chunks. Masking a contiguous buffer $B_1 \mathbin{\Vert} B_2$ at `frame_offset` $\delta$ must produce the exact same byte sequence as masking $B_1$ at offset $\delta$ and masking $B_2$ at offset $\delta + |B_1|$.
3. **Byte-Boundary Preservation ($0 \le b < 256$)**: If the input buffer consists of valid octets ($\forall b \in B, 0 \le b < 256$) and the masking key consists of valid octets, the masked output strictly remains within $[0, 256)$ without signedness overflow corruption.

---

## 3. Formal Specification & Verification in Rocq/Coq

Below is the complete, self-contained, and admitted-free Rocq (Coq) formalization (`BlinkWebSocketFrameMaskingXORSymmetrySemantics.v`). It models byte-level and stream-level WebSocket frame masking, proves the fundamental XOR involution properties, verifies stream chunking homomorphisms, and establishes unsigned octet boundary preservation.

```coq
(** * BlinkWebSocketFrameMaskingXORSymmetrySemantics.v
    Formal Verification of RFC 6455 §5.3 & Chromium net/websockets/websocket_frame.cc
    Masking Involution, Stream Chunking Homomorphism, and Octet Invariants. *)

From Coq Require Import ZArith.
From Coq Require Import List.
From Coq Require Import Lia.
From Coq Require Import Bool.
Import ListNotations.

Open Scope Z_scope.

(* ========================================================================== *)
(* 1. Formal Specification Definitions (Types, Functions, Predicates)         *)
(* ========================================================================== *)

(** A Byte is modeled as an integer in Z. 
    Well-formed octets satisfy the predicate [is_octet b := 0 <= b < 256]. *)
Definition Byte := Z.

Definition is_octet (b : Byte) : Prop :=
  0 <= b < 256.

(** RFC 6455 §5.3 specifies a 32-bit (4-byte) masking key. *)
Record WebSocketMaskingKey : Type := mkMaskingKey {
  k0 : Byte;
  k1 : Byte;
  k2 : Byte;
  k3 : Byte
}.

(** Well-formedness predicate for a 4-byte WebSocketMaskingKey. *)
Definition wf_masking_key (k : WebSocketMaskingKey) : Prop :=
  is_octet (k0 k) /\ is_octet (k1 k) /\ is_octet (k2 k) /\ is_octet (k3 k).

(** Select the masking key byte at a given stream offset modulo 4.
    Corresponds to: masking_key.key[(frame_offset + i) % 4] *)
Definition key_byte_at (k : WebSocketMaskingKey) (offset : Z) : Byte :=
  let idx := Z.modulo offset 4 in
  if Z.eqb idx 0 then k0 k
  else if Z.eqb idx 1 then k1 k
  else if Z.eqb idx 2 then k2 k
  else k3 k.

(** Byte-level masking operation: bitwise XOR. *)
Definition mask_byte (b : Byte) (k_byte : Byte) : Byte :=
  Z.lxor b k_byte.

(** Stream/Buffer-level payload masking corresponding to 
    net::MaskWebSocketFramePayload in net/websockets/websocket_frame.cc. *)
Fixpoint mask_payload (k : WebSocketMaskingKey) (offset : Z) (payload : list Byte) : list Byte :=
  match payload with
  | [] => []
  | b :: rest =>
      (mask_byte b (key_byte_at k offset)) :: (mask_payload k (offset + 1) rest)
  end.

(* ========================================================================== *)
(* 2. Fundamental Algebraic Lemmas (Bitwise XOR & Modulo Arithmetic)          *)
(* ========================================================================== *)

(** Theorem 1: Mathematical Property Target
    Bitwise XOR masking of a single byte is an involution: (b ^ k) ^ k = b. *)
Theorem mask_byte_involution : forall (b k : Byte),
  Z.lxor (Z.lxor b k) k = b.
Proof.
  intros b k.
  rewrite Z.lxor_assoc.
  rewrite Z.lxor_nilpotent.
  rewrite Z.lxor_0_r.
  reflexivity.
Qed.

(** Corollary in terms of [mask_byte]. *)
Lemma mask_byte_sym : forall (b k : Byte),
  mask_byte (mask_byte b k) k = b.
Proof.
  intros b k.
  unfold mask_byte.
  apply mask_byte_involution.
Qed.

(** Key lookup is periodic with period 4. *)
Lemma key_byte_at_periodic : forall (k : WebSocketMaskingKey) (offset : Z),
  key_byte_at k (offset + 4) = key_byte_at k offset.
Proof.
  intros k offset.
  unfold key_byte_at.
  replace (offset + 4) with (offset + 1 * 4) by lia.
  rewrite Z.mod_add by lia.
  reflexivity.
Qed.

(* ========================================================================== *)
(* 3. Concrete Theorems on Frame Payload Streams                              *)
(* ========================================================================== *)

(** Theorem 2: Frame Payload Masking Involution
    Applying [mask_payload] twice with the same key and starting frame_offset
    restores the exact original payload stream. *)
Theorem mask_payload_involution : forall (k : WebSocketMaskingKey) ( payload : list Byte) (offset : Z),
  mask_payload k offset (mask_payload k offset payload) = payload.
Proof.
  intros k payload.
  induction payload as [| b rest IH]; intros offset.
  - (* Base case: empty payload *)
    simpl. reflexivity.
  - (* Inductive step: b :: rest *)
    simpl.
    rewrite mask_byte_sym.
    rewrite IH.
    reflexivity.
Qed.

(** Theorem 3: Length Preservation Invariant
    Masking a WebSocket payload buffer strictly preserves its byte length. *)
Theorem mask_payload_length : forall (k : WebSocketMaskingKey) (payload : list Byte) (offset : Z),
  length (mask_payload k offset payload) = length payload.
Proof.
  intros k payload.
  induction payload as [| b rest IH]; intros offset.
  - simpl. reflexivity.
  - simpl. f_equal. apply IH.
Qed.

(** Theorem 4: Stream Chunking & Offset Homomorphism
    Masking a concatenated stream (p1 ++ p2) at [offset] is identical to
    masking [p1] at [offset] and concatenating it with [p2] masked at
    [offset + Z.of_nat (length p1)].
    This proves correctness of Chromium's incremental frame masking across
    fragmented Mojo data pipes and network buffers. *)
Theorem mask_payload_app_homomorphism :
  forall (k : WebSocketMaskingKey) (p1 p2 : list Byte) (offset : Z),
    mask_payload k offset (p1 ++ p2) =
    (mask_payload k offset p1) ++ (mask_payload k (offset + Z.of_nat (length p1)) p2).
Proof.
  intros k p1.
  induction p1 as [| b rest IH]; intros p2 offset.
  - (* Base case: p1 = [] *)
    simpl.
    replace (offset + 0) with offset by lia.
    reflexivity.
  - (* Inductive step: p1 = b :: rest *)
    simpl length.
    rewrite Nat2Z.inj_succ.
    simpl app.
    simpl mask_payload.
    f_equal.
    rewrite IH.
    f_equal.
    f_equal.
    lia.
Qed.

(** Theorem 5: Indexing Commutativity (Random-Access Masking Invariant)
    For any valid byte index [n] within the payload, the [n]-th byte of the
    masked payload equals the [n]-th byte of the unmasked payload XORed with
    the key at [offset + Z.of_nat n]. *)
Theorem mask_payload_nth :
  forall (k : WebSocketMaskingKey) (payload : list Byte) (offset : Z) (n : nat) (d : Byte),
    (n < length payload)%nat ->
    nth n (mask_payload k offset payload) d =
    mask_byte (nth n payload d) (key_byte_at k (offset + Z.of_nat n)).
Proof.
  intros k payload.
  induction payload as [| b rest IH]; intros offset n d Hlen.
  - (* Base case: empty list contradicts n < 0 *)
    simpl in Hlen. lia.
  - (* Inductive step *)
    destruct n as [| n'].
    + (* n = 0 *)
      simpl.
      replace (offset + 0) with offset by lia.
      reflexivity.
    + (* n = S n' *)
      simpl in Hlen.
      assert (Hlen' : (n' < length rest)%nat) by lia.
      simpl nth.
      rewrite IH with (d := d) by exact Hlen'.
      f_equal.
      f_equal.
      rewrite Nat2Z.inj_succ.
      lia.
Qed.

(* ========================================================================== *)
(* 4. Octet Boundary & Non-Negativity Preservation                            *)
(* ========================================================================== *)

(** Helper Lemma: key_byte_at preserves the [is_octet] invariant. *)
Lemma key_byte_at_is_octet : forall (k : WebSocketMaskingKey) (offset : Z),
  wf_masking_key k ->
  is_octet (key_byte_at k offset).
Proof.
  intros k offset [H0 [H1 [H2 H3]]].
  unfold key_byte_at.
  destruct (Z.eqb (offset mod 4) 0); [exact H0 |].
  destruct (Z.eqb (offset mod 4) 1); [exact H1 |].
  destruct (Z.eqb (offset mod 4) 2); [exact H2 |].
  exact H3.
Qed.

(** Helper Lemma: Bitwise XOR of two octets [0, 256) remains an octet [0, 256). *)
Lemma mask_byte_is_octet : forall (b k_byte : Byte),
  is_octet b ->
  is_octet k_byte ->
  is_octet (mask_byte b k_byte).
Proof.
  intros b k_byte [Hb_lo Hb_hi] [Hk_lo Hk_hi].
  unfold is_octet, mask_byte.
  split.
  - (* Non-negativity: 0 <= Z.lxor b k_byte *)
    apply Z.lxor_nonneg.
    split; lia.
  - (* Upper bound: Z.lxor b k_byte < 256 (i.e. 2^8) *)
    destruct (