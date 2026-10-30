# Formal Verification Report: WebRTC `RTCRtpSender` Encodings Priority Total Ordering

## 1. Normative Specification Requirements

The relative allocation of bandwidth and network QoS markings (such as Differentiated Services Code Point / DSCP) for media streams in WebRTC is governed by the `RTCPriorityType` enumeration applied to individual `RTCRtpEncodingParameters` dictionaries within an `RTCRtpSender`.

### 1.1 W3C WebRTC 1.0 Specification (§5.2.2)
In the W3C Recommendation *WebRTC 1.0: Real-Time Communication Between Browsers* (§5.2.2 `RTCRtpEncodingParameters` Dictionary) and its normative extension *WebRTC Priority Control API* (§4.1 `RTCPriorityType` Enum), priority is defined over four discrete levels:

```webidl
enum RTCPriorityType {
  "very-low",
  "low",
  "medium",
  "high"
};

dictionary RTCRtpEncodingParameters : RTCRtpCodingParameters {
  boolean active = true;
  RTCPriorityType priority = "low";
  RTCPriorityType networkPriority;
  // ...
};
```

### 1.2 IETF RFC 8835 (Transports for WebRTC) & RFC 8837 (DSCP)
Normative congestion control and scheduling requirements in IETF RFC 8835 (§4.1, §4.2) and RFC 8837 mandate that the media engine's packet pacer and congestion controller allocate available link capacity across active RTP streams according to a strict total ordering of their relative priorities:

$$\text{very-low} < \text{low} < \text{medium} < \text{high}$$

Specifically:
1. **Default Assignment**: When initializing an `RTCRtpEncodingParameters` dictionary without an explicit `priority` member, the user agent MUST initialize `priority` to `"low"`. If `networkPriority` is unset, it defaults to the value of `priority`.
2. **Total Order**: Any two priority configurations $p_1, p_2 \in \text{RTCPriorityType}$ must be comparable under a strict total order ($<$) or non-strict total order ($\le$), establishing a well-founded finite lattice with bottom element `"very-low"` and top element `"high"`.
3. **Monotonicity of Relative Bitrate Allocation**: Under congestion, if encoding $E_1$ and encoding $E_2$ share a transport congestion window (via BUNDLE) and have equal target bitrates, if $\text{priority}(E_1) \le \text{priority}(E_2)$, the congestion controller's weighted bitrate allocation weight $W$ must satisfy $W(E_1) \le W(E_2)$.

---

## 2. Chromium Blink Implementation Analysis

In Chromium's Blink rendering engine, the translation between the V8 JavaScript bindings for WebIDL `RTCPriorityType` and the native WebRTC C++ media engine (`webrtc::RtpEncodingParameters` and `webrtc::Priority`) is implemented in `third_party/blink/renderer/modules/peerconnection/rtc_rtp_sender.cc`.

### 2.1 Translation Layer and Data Representation
In `rtc_rtp_sender.cc`, Blink converts between `V8RTCPriorityType::Enum` (generated from `rtc_priority_type.idl`) and `webrtc::Priority` (defined in `third_party/webrtc/api/priority.h`):

```cpp
// third_party/webrtc/api/priority.h
namespace webrtc {
enum class Priority {
  kVeryLow = 0,
  kLow = 1,
  kMedium = 2,
  kHigh = 3,
};
}  // namespace webrtc
```

In `third_party/blink/renderer/modules/peerconnection/rtc_rtp_sender.cc`, the bidirectional conversion functions `PriorityFromEnum` and `PriorityToEnum` enforce the isomorphic mapping:

```cpp
webrtc::Priority PriorityFromEnum(V8RTCPriorityType::Enum priority) {
  switch (priority) {
    case V8RTCPriorityType::Enum::kVeryLow:
      return webrtc::Priority::kVeryLow;
    case V8RTCPriorityType::Enum::kLow:
      return webrtc::Priority::kLow;
    case V8RTCPriorityType::Enum::kMedium:
      return webrtc::Priority::kMedium;
    case V8RTCPriorityType::Enum::kHigh:
      return webrtc::Priority::kHigh;
  }
  NOTREACHED();
}

V8RTCPriorityType::Enum PriorityToEnum(webrtc::Priority priority) {
  switch (priority) {
    case webrtc::Priority::kVeryLow:
      return V8RTCPriorityType::Enum::kVeryLow;
    case webrtc::Priority::kLow:
      return V8RTCPriorityType::Enum::kLow;
    case webrtc::Priority::kMedium:
      return V8RTCPriorityType::Enum::kMedium;
    case webrtc::Priority::kHigh:
      return V8RTCPriorityType::Enum::kHigh;
  }
  NOTREACHED();
}
```

Furthermore, within `ToRtpEncodingParameters(ExecutionContext*, const RTCRtpEncodingParameters*, ...)`, Blink translates the WebIDL dictionary into `webrtc::RtpEncodingParameters`:
- `encoding->priority()` (guaranteed present with default `"low"` by Blink IDL bindings) is mapped to `webrtc_encoding.bitrate_priority` (a `double` weight: `0.5`, `1.0`, `2.0`, `4.0` corresponding to `kVeryLow`..`kHigh`) and `webrtc_encoding.network_priority` (`webrtc::Priority`).
- In `RTCRtpSender::setParameters`, Blink verifies read-only envelope invariants while permitting dynamic mutation of `priority` and `networkPriority` across negotiation cycles without triggering an `InvalidModificationError`.

### 2.2 Implementation Invariants
1. **Rank Bijection**: The mapping $\text{rank} : \text{RTCPriorityType} \to \{0, 1, 2, 3\} \subset \mathbb{Z}$ defined by $\text{kVeryLow} \mapsto 0$, $\text{kLow} \mapsto 1$, $\text{kMedium} \mapsto 2$, $\text{kHigh} \mapsto 3$ is a bijection onto the integer interval $[0, 3]$.
2. **Round-Trip Identity**: `PriorityToEnum(PriorityFromEnum(p)) == p` and `PriorityFromEnum(PriorityToEnum(w)) == w` hold unconditionally for all valid enum variants, preventing state drift during `getParameters()` $\to$ `setParameters()` cycles.
3. **Strict Ordering Isomorphism**: The C++ relational operators `<` and `<=` on `webrtc::Priority` underlying integral values induce a strict total order and bounded lattice over `RTCPriorityType`.
4. **Bitrate Weight Monotonicity**: The conversion from `webrtc::Priority` to pacing/allocation weights (scaled by integer factors $1, 2, 4, 8$ in integer arithmetic or $0.5, 1.0, 2.0, 4.0$ in floating-point) is strictly increasing with respect to the priority rank.

---

## 3. Formal Specification in Rocq/Coq

Below is the formal specification module `BlinkWebRTCRTPSenderPriorityOrderSemantics.v`. It models the WebIDL/Blink priority types, rank mappings, total ordering predicates, lattice operators (`min`/`max`), bitrate weight mappings, and `RTCRtpEncodingParameters` update transitions.

```coq
(** * BlinkWebRTCRTPSenderPriorityOrderSemantics.v
    Formal verification of WebRTC RTCRtpSender encodings priority total ordering
    Source: third_party/blink/renderer/modules/peerconnection/rtc_rtp_sender.cc
    Spec: W3C WebRTC 1.0 §5.2.2 & WebRTC Priority Control API *)

From Coq Require Import Bool.Bool.
From Coq Require Import ZArith.ZArith.
From Coq Require Import Micega.Lia.
From Coq Require Import Lists.List.
Import ListNotations.

Open Scope Z_scope.

(** ** 1. WebIDL and Blink Priority Types *)

(** Models V8RTCPriorityType::Enum and webrtc::Priority *)
Inductive RTCPriorityType : Type :=
  | PriorityVeryLow : RTCPriorityType
  | PriorityLow     : RTCPriorityType
  | PriorityMedium  : RTCPriorityType
  | PriorityHigh    : RTCPriorityType.

(** Default priority mandated by WebRTC 1.0 §5.2.2 *)
Definition default_priority : RTCPriorityType := PriorityLow.

(** Integer rank mapping: very-low(0) < low(1) < medium(2) < high(3) *)
Definition priority_rank (p : RTCPriorityType) : Z :=
  match p with
  | PriorityVeryLow => 0
  | PriorityLow     => 1
  | PriorityMedium  => 2
  | PriorityHigh    => 3
  end.

(** Inverse mapping from integer rank (clamped to valid range [0, 3]) *)
Definition rank_to_priority (z : Z) : option RTCPriorityType :=
  if Z.eqb z 0 then Some PriorityVeryLow
  else if Z.eqb z 1 then Some PriorityLow
  else if Z.eqb z 2 then Some PriorityMedium
  else if Z.eqb z 3 then Some PriorityHigh
  else None.

(** Scaled integer bitrate priority weight (2x base weight in webrtc: 1, 2, 4, 8)
    Corresponds to webrtc::kDefaultBitratePriority * {0.5, 1.0, 2.0, 4.0} *)
Definition priority_bitrate_weight (p : RTCPriorityType) : Z :=
  match p with
  | PriorityVeryLow => 1
  | PriorityLow     => 2
  | PriorityMedium  => 4
  | PriorityHigh    => 8
  end.

(** ** 2. Decidable Equality and Ordering Relations *)

Definition priority_eqb (p1 p2 : RTCPriorityType) : bool :=
  Z.eqb (priority_rank p1) (priority_rank p2).

Definition priority_ltb (p1 p2 : RTCPriorityType) : bool :=
  Z.ltb (priority_rank p1) (priority_rank p2).

Definition priority_leb (p1 p2 : RTCPriorityType) : bool :=
  Z.leb (priority_rank p1) (priority_rank p2).

(** Propositional ordering predicates *)
Definition priority_lt (p1 p2 : RTCPriorityType) : Prop :=
  priority_rank p1 < priority_rank p2.

Definition priority_le (p1 p2 : RTCPriorityType) : Prop :=
  priority_rank p1 <= priority_rank p2.

(** Lattice operations: join (max) and meet (min) *)
Definition priority_max (p1 p2 : RTCPriorityType) : RTCPriorityType :=
  if priority_leb p1 p2 then p2 else p1.

Definition priority_min (p1 p2 : RTCPriorityType) : RTCPriorityType :=
  if priority_leb p1 p2 then p1 else p2.

(** ** 3. RTCRtpEncodingParameters Model and State Transitions *)

Record RTCRtpEncodingParameters : Type := mkEncoding {
  enc_ssrc             : option Z;
  enc_rid              : Z;
  enc_active           : bool;
  enc_priority         : RTCPriorityType;
  enc_network_priority : RTCPriorityType;
  enc_max_bitrate_bps  : option Z
}.

(** WebIDL dictionary initialization with default priority = "low"
    and networkPriority defaulting to priority *)
Definition init_encoding (rid : Z) (opt_prio opt_net_prio : option RTCPriorityType)
  : RTCRtpEncodingParameters :=
  let p := match opt_prio with
           | Some val => val
           | None => default_priority
           end in
  let np := match opt_net_prio with
            | Some val => val
            | None => p
            end in
  mkEncoding None rid true p np None.

(** Read-only envelope validation during RTCRtpSender::setParameters
    (RFC 8829 / WebRTC 1.0 §5.2): rid cannot be modified, while priority
    and networkPriority are freely mutable across all 4 levels. *)
Definition valid_encoding_update (before after : RTCRtpEncodingParameters) : bool :=
  Z.eqb (enc_rid before) (enc_rid after) &&
  match enc_ssrc before, enc_ssrc after with
  | Some s1, Some s2 => Z.eqb s1 s2
  | None, None => true
  | _, _ => false
  end.

(** Helper: Update priority of an encoding in setParameters *)
Definition update_encoding_priority
  (enc : RTCRtpEncodingParameters)
  (new_prio new_net_prio : RTCPriorityType) : RTCRtpEncodingParameters :=
  mkEncoding
    (enc_ssrc enc)
    (enc_rid enc)
    (enc_active enc)
    new_prio
    new_net_prio
    (enc_max_bitrate_bps enc).
```

---

## 4. Concrete Theorems and Complete Proofs

The following Rocq/Coq proof script establishes the algebraic, order-theoretic, and state-machine invariants of `RTCRtpSender` encoding priorities. All proofs are complete and free of `Admitted` or axioms.

```coq
(** ** 4. Formal Verification Theorems and Proofs *)

(** Theorem 1: Explicit rank chain invariant
    very-low(0) < low(1) < medium(2) < high(3) *)
Theorem priority_rank_chain :
  priority_rank PriorityVeryLow < priority_rank PriorityLow /\
  priority_rank PriorityLow < priority_rank PriorityMedium /\
  priority_rank PriorityMedium < priority_rank PriorityHigh.
Proof.
  simpl. lia.
Qed.

(** Theorem 2: Priority rank is strictly bounded in [0, 3] *)
Theorem priority_rank_bounds : forall (p : RTCPriorityType),
  0 <= priority_rank p <= 3.
Proof.
  intros p. destruct p; simpl; lia.
Qed.

(** Theorem 3: priority_rank is injective (Bijection Part 1) *)
Theorem priority_rank_injective : forall (p1 p2 : RTCPriorityType),
  priority_rank p1 = priority_rank p2 -> p1 = p2.
Proof.
  intros p1 p2 H.
  destruct p1, p2; simpl in H; try reflexivity; discriminate H.
Qed.

(** Theorem 4: Round-trip inversion between priority_rank and rank_to_priority
    Models PriorityToEnum(PriorityFromEnum(p)) == p in rtc_rtp_sender.