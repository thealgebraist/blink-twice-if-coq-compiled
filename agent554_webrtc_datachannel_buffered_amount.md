# Formal Verification of WebRTC `RTCDataChannel` Buffered Amount Monotonicity in Chromium Blink

**Formal Theory Target**: `BlinkWebRTCDataChannelBufferedAmountSemantics.v`  
**Chromium Subsystem**: `third_party/blink/renderer/modules/peerconnection/rtc_data_channel.cc`  
**Normative Specification**: W3C WebRTC 1.0: Real-Time Communication Between Browsers, Section 6.2 (`RTCDataChannel`)  
**Mathematical Property**: $\text{drain\_bytes}(b, s) = \max(0, b - s)$; Non-negative and monotonically non-increasing across network transmission ticks.

---

## 1. Normative W3C & IETF Specification Requirements

In WebRTC 1.0 (§6.2), the `RTCDataChannel` interface represents a bi-directional peer-to-peer data transport channel running over SCTP/DTLS/ICE (as standardized in IETF RFC 8831 and RFC 8832). A critical flow-control attribute exposed to JavaScript execution contexts is `bufferedAmount`.

### 1.1 W3C WebRTC 1.0 §6.2 Normative Constraints

According to W3C WebRTC 1.0 §6.2 (`RTCDataChannel` Interface):

1. **Attribute Definition (`bufferedAmount`)**:
   > The `bufferedAmount` attribute MUST return the number of bytes of application data (UTF-8 text and binary data) that have been queued using `send()` but that, as of the last time the event loop reached step 1, have not yet been transmitted to the network.
   * **Type Requirement**: `unsigned long` (in WebIDL, representing an integer in the range $[0, 2^{32}-1]$, or internally tracked as a non-negative 64-bit integer prior to IDL clamping/wrapping).

2. **Monotonicity under Transmission**:
   When the underlying SCTP transport (managed on the WebRTC network thread) successfully transmits queued chunks of data over the network, it dispatches an asynchronous notification to the Blink main thread (or worker thread) executing the JavaScript event loop.
   > When the underlying data transport drains queued bytes, the user agent MUST decrease `bufferedAmount` by the number of bytes transmitted. If the channel is closed, `bufferedAmount` continues to reflect the number of bytes queued but not yet sent, or decreases as the transport drains prior to teardown.

3. **Non-Negativity Invariant**:
   Because `bufferedAmount` represents a physical count of queued octets and is typed as `unsigned long`, it is strictly bounded below by $0$:
   $$\forall t \in \text{Time}, \quad \text{bufferedAmount}(t) \ge 0$$

4. **Threshold Signaling (`bufferedAmountLowThreshold`)**:
   Whenever `bufferedAmount` decreases from a value strictly greater than `bufferedAmountLowThreshold` to a value less than or equal to `bufferedAmountLowThreshold`, the User Agent MUST queue a task to fire an event named `bufferedamountlow` at the `RTCDataChannel` object.

---

## 2. Chromium Blink Implementation Analysis

In Chromium's multi-threaded architecture, the underlying libwebrtc (`webrtc::DataChannelInterface`) runs on the WebRTC signaling/network threads, while the DOM wrapper (`blink::RTCDataChannel`) lives on the Blink main thread (or dedicated worker thread).

### 2.1 State Representation in `rtc_data_channel.cc`

In `third_party/blink/renderer/modules/peerconnection/rtc_data_channel.cc` (and its header `rtc_data_channel.h`), Blink maintains a local shadow counter `buffered_amount_` to avoid synchronous cross-thread blocking calls to libwebrtc whenever JavaScript reads `channel.bufferedAmount` or calls `channel.send()`.

* **Enqueueing (`send`)**: When `RTCDataChannel::send(...)` is invoked on the Blink thread, `buffered_amount_` is synchronously incremented by the byte length of the payload (e.g., `String` UTF-8 bytes, `Blob` size, or `ArrayBufferView` byteLength).
* **Draining (`OnBufferedAmountChange`)**: As libwebrtc's SCTP transport drains the send buffer, `RTCDataChannel::Observer::OnBufferedAmountChange(uint64_t sent_data_size)` is invoked and posted back to the Blink thread onto `RTCDataChannel::OnBufferedAmountChange(uint64_t sent_data_size)`.

### 2.2 The Drain Invariant & Defensive Clamping

In `RTCDataChannel::OnBufferedAmountChange(uint64_t sent_data_size)`:

```cpp
void RTCDataChannel::OnBufferedAmountChange(uint64_t sent_data_size) {
  DCHECK_CALLED_ON_VALID_THREAD(thread_checker_);
  uint64_t previous_amount = buffered_amount_;
  
  // Defensive clamping / assertion against underflow:
  // In release builds or edge-case race conditions during channel closure/reset,
  // buffered_amount_ must never underflow below 0.
  if ( buffered_amount_ >= sent_data_size ) {
    buffered_amount_ -= sent_data_size;
  } else {
    buffered_amount_ = 0;
  }

  if (previous_amount > buffered_amount_low_threshold_ &&
      buffered_amount_ <= buffered_amount_low_threshold_) {
    ScheduleDispatchEvent(Event::Create(event_type_names::kBufferedamountlow));
  }
}
```

### 2.3 Architectural Invariants

1. **Zero Underflow Resistance**: Even if out-of-order teardown signals or accounting discrepancies between UTF-8 re-encoding and SCTP chunking report `sent_data_size > buffered_amount_`, the transition function $\text{drain\_bytes}(b, s) = \max(0, b - s)$ guarantees that unsigned integer wrap-around (which would result in a catastrophic $\approx 2^{64}-1$ or $2^{32}-1$ buffer size report) cannot occur.
2. **Pure Drain Monotonicity**: In any execution step where only network draining occurs (no concurrent synchronous `send()` call interleaving within the atomic handler execution), the state transition $b' = \text{drain\_bytes}(b, s)$ satisfies $0 \le b' \le b$.
3. **Multi-Step Trace Monotonicity**: Over any sequence of drain events $[s_1, s_2, \dots, s_n]$ between JavaScript `send()` invocations, the sequence of buffered amounts $b_0, b_1, \dots, b_n$ is monotonically non-increasing and bounded within $[0, b_0]$.
4. **Threshold Crossing Soundness**: The `bufferedamountlow` event predicate $(b_{\text{prev}} > T) \land (b_{\text{next}} \le T)$ can fire at most once per pure drain sequence without an intervening `send()` operation.

---

## 3. Formal Specification in Rocq / Coq

We model the `RTCDataChannel` buffer state and transition semantics in Rocq (Coq) over the integer domain $\mathbb{Z}$ (`ZArith`). Using $\mathbb{Z}$ rather than `nat` (where $0 - k = 0$ by total truncation) ensures our proofs genuinely validate the arithmetic clamping logic $\max(0, b - s)$ rather than relying on `nat` underflow artifacts.

### 3.1 Formal Definitions

* **`Z` Domain**: Represents 64-bit integer quantities in Blink (`int64_t` / `uint64_t` lifted to unbounded signed integers to explicitly expose potential underflow before clamping).
* **`drain_bytes (buffered sent : Z) : Z`**: The core state transition function `Z.max 0 (buffered - sent)`.
* **`drain_trace (buffered : Z) (sents : list Z) : Z`**: Left-fold of `drain_bytes` over a sequence of network transmission callbacks `OnBufferedAmountChange`.
* **`should_fire_low_event (prev next threshold : Z) : bool`**: Models the boolean condition triggering `event_type_names::kBufferedamountlow`.

---

## 4. Rocq / Coq Formal Theory (`BlinkWebRTCDataChannelBufferedAmountSemantics.v`)

Below is the complete, self-contained, and admitted-free Rocq formalization and verification suite.

```coq
(** * BlinkWebRTCDataChannelBufferedAmountSemantics.v
    Formal verification of WebRTC RTCDataChannel bufferedAmount
    non-negative decreasing monotonicity in Chromium Blink.

    Source: third_party/blink/renderer/modules/peerconnection/rtc_data_channel.cc
    Spec:   W3C WebRTC 1.0 Section 6.2 (RTCDataChannel)
*)

Require Import Coq.ZArith.ZArith.
Require Import Coq.Lists.List.
Require Import Coq.Bool.Bool.
Require Import Coq.micromega.Lia.

Import ListNotations.
Open Scope Z_scope.

Section DataChannelBufferedAmount.

  (** ** 1. Core State & Transition Definitions *)

  (** [drain_bytes buffered sent] models the state update inside
      [RTCDataChannel::OnBufferedAmountChange(uint64_t sent_data_size)].
      Mathematically: drain_bytes(b, s) = max(0, b - s). *)
  Definition drain_bytes (buffered sent : Z) : Z :=
    Z.max 0 (buffered - sent).

  (** [enqueue_bytes buffered payload] models [RTCDataChannel::send(...)]. *)
  Definition enqueue_bytes (buffered payload : Z) : Z :=
    if payload >=? 0 then buffered + payload else buffered.

  (** [drain_trace buffered sents] models a sequence of network drain events
      occurring between JavaScript send() invocations. *)
  Fixpoint drain_trace (buffered : Z) (sents : list Z) : Z :=
    match sents with
    | [] => buffered
    | s :: rest => drain_trace (drain_bytes buffered s) rest
    end.

  (** [should_fire_low_event prev next threshold] models the condition for
      scheduling [event_type_names::kBufferedamountlow]:
      (previous_amount > threshold && buffered_amount_ <= threshold). *)
  Definition should_fire_low_event (prev next threshold : Z) : bool :=
    (prev >? threshold) && (next <=? threshold).

  (** Validity predicate for a list of sent byte counts (all non-negative). *)
  Definition valid_sent_list (sents : list Z) : Prop :=
    Forall (fun s => s >= 0) sents.

  (** ** 2. Fundamental Single-Step Invariants *)

  (** Theorem 1: Non-negativity of [drain_bytes].
      Regardless of the input values of [buffered] and [sent], the resulting
      bufferedAmount is always >= 0. This proves total absence of underflow. *)
  Theorem drain_bytes_nonneg :
    forall (buffered sent : Z),
      0 <= drain_bytes buffered sent.
  Proof.
    intros buffered sent.
    unfold drain_bytes.
    lia.
  Qed.

  (** Theorem 2: Monotonicity (Non-increasing property) of [drain_bytes].
      Given a valid non-negative initial buffer (0 <= buffered) and a valid
      non-negative transmitted byte count (0 <= sent), draining never increases
      the buffered amount. *)
  Theorem drain_bytes_monotonic_non_increasing :
    forall (buffered sent : Z),
      0 <= buffered ->
      0 <= sent ->
      drain_bytes buffered sent <= buffered.
  Proof.
    intros buffered sent Hbuf Hsent.
    unfold drain_bytes.
    lia.
  Qed.

  (** Theorem 3: Combined Boundedness of a Single Drain Step.
      0 <= drain_bytes(buffered, sent) <= buffered. *)
  Theorem drain_bytes_bounded :
    forall (buffered sent : Z),
      0 <= buffered ->
      0 <= sent ->
      0 <= drain_bytes buffered sent <= buffered.
  Proof.
    intros buffered sent Hbuf Hsent.
    split.
    - apply drain_bytes_nonneg.
    - apply drain_bytes_monotonic_non_increasing; assumption.
  Qed.

  (** Theorem 4: Exact Subtraction within Normal Operating Bounds.
      When sent <= buffered, drain_bytes performs exact arithmetic subtraction. *)
  Theorem drain_bytes_exact_when_sufficient :
    forall (buffered sent : Z),
      0 <= sent <= buffered ->
      drain_bytes buffered sent = buffered - sent.
  Proof.
    intros buffered sent Hbounds.
    unfold drain_bytes.
    lia.
  Qed.

  (** Theorem 5: Saturation at Zero on Over-Drain.
      If sent >= buffered, the buffer saturates cleanly at 0. *)
  Theorem drain_bytes_saturates_at_zero :
    forall (buffered sent : Z),
      buffered <= sent ->
      drain_bytes buffered sent = 0.
  Proof.
    intros buffered sent Hle.
    unfold drain_bytes.
    lia.
  Qed.

  (** Theorem 6: Zero Identity.
      Draining 0 bytes from a non-negative buffer leaves it unchanged. *)
  Theorem drain_bytes_zero_sent :
    forall (buffered : Z),
      0 <= buffered ->
      drain_bytes buffered 0 = buffered.
  Proof.
    intros buffered Hbuf.
    unfold drain_bytes.
    lia.
  Qed.

  (** Theorem 7: Zero Absorbing State.
      Once the buffer reaches 0, any further valid drain keeps it at 0. *)
  Theorem drain_bytes_zero_buffer :
    forall (sent : Z),
      0 <= sent ->
      drain_bytes 0 sent = 0.
  Proof.
    intros sent Hsent.
    unfold drain_bytes.
    lia.
  Qed.

  (** ** 3. Algebraic Composition & Order Sensitivity *)

  (** Theorem 8: Sequential Drain Composition (Homomorphism under Non-Negative Sums).
      Draining [s1] then [s2] is identical to draining [s1 + s2] in a single tick,
      provided both [s1] and [s2] are non-negative. *)
  Theorem drain_bytes_sequential_composition :
    forall (buffered s1 s2 : Z),
      0 <= s1 ->
      0 <= s2 ->
      drain_bytes (drain_bytes buffered s1) s2 = drain_bytes buffered (s1 + s2).
  Proof.
    intros buffered s1 s2 Hs1 Hs2.
    unfold drain_bytes.
    lia.
  Qed.

  (** Theorem 9: Antitonicity in the [sent] Argument.
      More bytes transmitted results in a smaller or equal remaining buffer. *)
  Theorem drain_bytes_antitone_sent :
    forall (buffered s1 s2 : Z),
      s1 <= s2 ->
      drain_bytes buffered s2 <= drain_bytes buffered s1.
  Proof.
    intros buffered s1 s2 Hle.
    unfold drain_bytes.
    lia.
  Qed.

  (** Theorem 10: Monotonicity in the [buffered] Argument.
      A larger initial buffer results in a larger or equal remaining buffer
      for the same number of transmitted