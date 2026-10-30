# Formal Verification Report: WebRTC RTP Packet Sequence Number 16-bit Modular Wrap-Around

**Target Theory**: `BlinkWebRTCRTPSequenceWrapSemantics.v`  
**Chromium Component**: `third_party/webrtc/modules/rtp_rtcp/source/rtp_packet_received.cc` (and base `rtp_packet.cc`)  
**Normative Specification**: IETF RFC 3550 §5.1 (RTP: A Transport Protocol for Real-Time Applications)  
**Mathematical Property**: $\text{next\_seq}(s) = (s + 1) \bmod 65536 \land 0 \le \text{next\_seq}(s) \le 65535$

---

## 1. Normative Specification Requirements

In WebRTC (governed jointly by W3C WebRTC 1.0 and IETF RTCWeb specifications), media transport relies on the Real-time Transport Protocol (RTP) defined in **IETF RFC 3550**. 

According to **RFC 3550 §5.1 (RTP Fixed Header Fields)**:
> **sequence number (16 bits)**: The sequence number increments by one for each RTP data packet sent, and may be used by the receiver to detect packet loss and to restore packet sequence. The initial value of the sequence number SHOULD be random (unpredictable) to make known-plaintext attacks on encryption more difficult, even if the source itself does not encrypt according to the method in Section 9.1, because the packets may flow through a translator that does.

### Normative Invariants Derived from RFC 3550 §5.1 & Appendix A.1:
1. **Domain Bounds**: The sequence number space $\mathcal{S}$ is strictly bounded to unsigned 16-bit integers: $\mathcal{S} = [0, 2^{16}-1] = [0, 65535]$.
2. **Modular Increment**: Upon transmission of consecutive RTP packets, if packet $i$ carries sequence number $s_i \in \mathcal{S}$, packet $i+1$ MUST carry sequence number $s_{i+1} = (s_i + 1) \bmod 65536$.
3. **Wrap-Around Continuity**: Transitioning from $s_i = 65535$ (`0xFFFF`) to $s_{i+1} = 0$ (`0x0000`) is a valid, normal operational transition and must not cause arithmetic overflow traps, undefined behavior, or packet rejection at the parser level.
4. **Serial Number Arithmetic (RFC 1982)**: Ordering and distance calculations on the receiver side (jitter buffer, NACK generation, and ROC—Rollover Counter—estimation in SRTP per RFC 3711) rely on signed 16-bit modular difference where $s_b$ is considered "newer" than $s_a$ iff $0 < (s_b - s_a) \bmod 65536 < 32768$.

---

## 2. Chromium & WebRTC Implementation Analysis

In Chromium, Blink's MediaStream and `RTCPeerConnection` APIs (`third_party/blink/renderer/modules/peerconnection/`) delegate RTP packetization, parsing, and sequence tracking to the underlying `libwebrtc` engine located in `third_party/webrtc/`.

### 2.1 Packet Parsing (`rtp_packet_received.cc` & `rtp_packet.cc`)
`webrtc::RtpPacketReceived` (defined in `third_party/webrtc/modules/rtp_rtcp/source/rtp_packet_received.cc`) inherits directly from `webrtc::RtpPacket` (`rtp_packet.cc`).

When an incoming network buffer is parsed in `RtpPacket::ParseBuffer(const uint8_t* buffer, size_t size)`:
```cpp
// third_party/webrtc/modules/rtp_rtcp/source/rtp_packet.cc
sequence_number_ = ByteReader<uint16_t>::ReadBigEndian(&buffer[2]);
```
Here, `sequence_number_` is stored as an unsigned 16-bit integer (`uint16_t`). By utilizing C++ `uint16_t`:
- The type invariant $0 \le \text{sequence\_number\_} \le 65535$ is enforced by the memory representation.
- In `RtpPacket::SetSequenceNumber(uint16_t seq_no)`, the value is written into offset 2 of the RTP header via `ByteWriter<uint16_t>::WriteBigEndian(WriteAt(2), seq_no)`.

### 2.2 Sequence Unwrapping and Ordering (`rtp_packet_received.cc` Ecosystem)
While `RtpPacketReceived::SequenceNumber()` returns the raw `uint16_t` modulo $65536$, downstream consumers invoked immediately after `rtp_packet_received.cc` instantiation (such as `RtpVideoStreamReceiver2`, `UlpfecReceiver`, and `NackModule2`) rely on `webrtc::SeqNumUnwrapper<uint16_t>` (`rtc_base/numerics/sequence_number_unwrapper.h`) and `webrtc::IsNewerSequenceNumber` (`modules/include/module_common_types_public.h`):

```cpp
inline bool IsNewerSequenceNumber(uint16_t sequence_number,
                                  uint16_t prev_sequence_number) {
  // Distinguish between elements that are exactly 0x8000 apart.
  // If s1 - s2 = 0x8000, IsNewer(s1, s2) is false.
  return (sequence_number != prev_sequence_number) &&
         static_cast<uint16_t>(sequence_number - prev_sequence_number) < 0x8000u;
}
```

### 2.3 Implementation Invariants
1. **Bit-Width Safety**: In C++, unsigned integer arithmetic (`uint16_t`) is guaranteed by the standard (ISO/IEC 14882) to follow modular arithmetic modulo $2^{16}$ (`65536`), matching RFC 3550 §5.1 without risk of signed overflow Undefined Behavior (UB) when promoted and truncated properly.
2. **Bijective Wire Encoding**: Big-endian two-byte reading/writing `ByteReader<uint16_t>::ReadBigEndian` forms a bijection between byte pairs $(b_0, b_1) \in [0, 255]^2$ and $s \in [0, 65535]$ via $s = 256 \cdot b_0 + b_1$.

---

## 3. Formal Specification in Rocq/Coq

Below is the formalization of the RTP 16-bit sequence number semantics, wire encoding/decoding, modular wrap-around transitions, and half-ring serial number comparison in Rocq/Coq (`BlinkWebRTCRTPSequenceWrapSemantics.v`).

```coq
(** * BlinkWebRTCRTPSequenceWrapSemantics.v
    Formalization of RFC 3550 §5.1 RTP 16-bit Sequence Number Wrap-Around
    and Chromium WebRTC (rtp_packet_received.cc) Invariants. *)

From Coq Require Import ZArith.
From Coq Require Import Bool.
From Coq Require Import Lia.

Open Scope Z_scope.

(** ** 1. Constants and Domain Definitions *)

Definition RTP_SEQ_MODULUS : Z := 65536.
Definition RTP_SEQ_MAX     : Z := 65535.
Definition RTP_SEQ_HALF    : Z := 32768.

(** Predicate defining a valid 16-bit unsigned RTP sequence number *)
Definition valid_seq_num (s : Z) : Prop :=
  0 <= s <= RTP_SEQ_MAX.

(** Boolean decidability for valid_seq_num *)
Definition is_valid_seq_num (s : Z) : bool :=
  (0 <=? s) && (s <=? RTP_SEQ_MAX).

(** Predicate defining a valid 8-bit unsigned byte *)
Definition valid_byte (b : Z) : Prop :=
  0 <= b <= 255.

(** ** 2. Core RTP Sequence Operations (RFC 3550 §5.1) *)

(** Next sequence number transition: next_seq(s) = (s + 1) mod 65536 *)
Definition next_seq (s : Z) : Z :=
  (s + 1) mod RTP_SEQ_MODULUS.

(** N-step sequence number transition *)
Definition advance_seq (s delta : Z) : Z :=
  (s + delta) mod RTP_SEQ_MODULUS.

(** Modular distance from s_prev to s_curr in [0, 65535] *)
Definition seq_diff (s_curr s_prev : Z) : Z :=
  (s_curr - s_prev) mod RTP_SEQ_MODULUS.

(** WebRTC IsNewerSequenceNumber predicate (RFC 1982 / module_common_types_public.h) *)
Definition is_newer_seq (s_curr s_prev : Z) : bool :=
  let diff := seq_diff s_curr s_prev in
  (negb (s_curr =? s_prev)) && (diff <? RTP_SEQ_HALF).

(** ** 3. Wire Format Big-Endian Serialization (rtp_packet.cc) *)

(** ReadBigEndian(&buffer[2]) *)
Definition decode_be16 (b0 b1 : Z) : Z :=
  b0 * 256 + b1.

(** WriteBigEndian(WriteAt(2), seq_no) *)
Definition encode_be16_hi (s : Z) : Z :=
  s / 256.

Definition encode_be16_lo (s : Z) : Z :=
  s mod 256.

(** ** 4. Receiver 64-bit Sequence Number Unwrapper State *)

(** Models webrtc::SeqNumUnwrapper<uint16_t> *)
Definition unwrap_step (last_unwrapped : Z) (s_curr : Z) : Z :=
  let last_seq := last_unwrapped mod RTP_SEQ_MODULUS in
  let forward_diff := seq_diff s_curr last_seq in
  if forward_diff <? RTP_SEQ_HALF then
    last_unwrapped + forward_diff
  else
    last_unwrapped - (RTP_SEQ_MODULUS - forward_diff).
```

---

## 4. Concrete Theorems and Complete Proofs

The following Rocq/Coq script provides complete, admitted-free proofs establishing range invariants, boundary wrap-around behavior, multi-step compositionality, wire serialization bijectivity, and unwrapper monotonicity.

```coq
(** * Formal Verification Proofs *)

(** ** Theorem 1: Decidability Reflection for valid_seq_num *)
Theorem is_valid_seq_num_spec : forall s : Z,
  is_valid_seq_num s = true <-> valid_seq_num s.
Proof.
  intros s.
  unfold is_valid_seq_num, valid_seq_num, RTP_SEQ_MAX.
  rewrite andb_true_iff.
  rewrite Z.leb_le, Z.leb_le.
  reflexivity.
Qed.

(** ** Theorem 2: Primary Invariant - next_seq stays within [0, 65535] *)
Theorem next_seq_bounds : forall s : Z,
  valid_seq_num s -> valid_seq_num (next_seq s).
Proof.
  intros s Hvalid.
  unfold valid_seq_num, next_seq, RTP_SEQ_MODULUS, RTP_SEQ_MAX in *.
  pose proof (Z.mod_pos_bound (s + 1) 65536) as Hmod.
  lia.
Qed.

(** ** Theorem 3: Universal Bounds - next_seq is bounded for ANY integer input *)
Theorem next_seq_universal_bounds : forall s : Z,
  valid_seq_num (next_seq s).
Proof.
  intros s.
  unfold valid_seq_num, next_seq, RTP_SEQ_MODULUS, RTP_SEQ_MAX.
  pose proof (Z.mod_pos_bound (s + 1) 65536) as Hmod.
  lia.
Qed.

(** ** Theorem 4: Exact Wrap-Around at 16-bit Boundary (65535 -> 0) *)
Theorem next_seq_wrap_at_max :
  next_seq RTP_SEQ_MAX = 0.
Proof.
  unfold next_seq, RTP_SEQ_MAX, RTP_SEQ_MODULUS.
  reflexivity.
Qed.

(** ** Theorem 5: Linear Increment Below Boundary (s < 65535 -> s + 1) *)
Theorem next_seq_linear_below_max : forall s : Z,
  0 <= s < RTP_SEQ_MAX ->
  next_seq s = s + 1.
Proof.
  intros s Hbounds.
  unfold next_seq, RTP_SEQ_MAX, RTP_SEQ_MODULUS in *.
  apply Z.mod_small.
  lia.
Qed.

(** ** Theorem 6: Case Split Characterization of next_seq *)
Theorem next_seq_characterization : forall s : Z,
  valid_seq_num s ->
  (s < RTP_SEQ_MAX /\ next_seq s = s + 1) \/
  (s = RTP_SEQ_MAX /\ next_seq s = 0).
Proof.
  intros s Hvalid.
  unfold valid_seq_num, RTP_SEQ_MAX in Hvalid.
  destruct (Z.eq_dec s 65535) as [Heq | Hneq].
  - right. split.
    + unfold RTP_SEQ_MAX. exact Heq.
    + subst s. apply next_seq_wrap_at_max.
  - left. split.
    + unfold RTP_SEQ_MAX. lia.
    + apply next_seq_linear_below_max. unfold RTP_SEQ_MAX. lia.
Qed.

(** ** Theorem 7: Bijectivity / Invertibility of next_seq on [0, 65535] *)
Definition prev_seq (s : Z) : Z :=
  (s - 1) mod RTP_SEQ_MODULUS.

Theorem prev_next_seq_id : forall s : Z,
  valid_seq_num s ->
  prev_seq (next_seq s) = s.
Proof.
  intros s Hvalid.
  unfold prev_seq, next_seq, valid_seq_num, RTP_SEQ_MODULUS, RTP_SEQ_MAX in *.
  rewrite Zminus_mod_idemp_l.
  replace (s + 1 - 1) with s by lia.
  apply Z.mod_small.
  lia.
Qed.

(** ** Theorem 8: Multi-step Advance Compositionality *)
Theorem advance_seq_compose : forall s d1 d2 : Z,
  advance_seq (advance_seq s d1) d