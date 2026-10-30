# Formal Verification Report: WebRTC ICE Connection State Transitions in Chromium Blink

**Formal Theory Target**: `BlinkWebRTCICEConnectionStateSemantics.v`  
**Chromium Component**: `third_party/blink/renderer/modules/peerconnection/rtc_ice_transport.cc`  
**Normative Specification**: W3C WebRTC 1.0: Real-Time Communication Between Browsers, §4.3.3 (`RTCIceTransportState` / `RTCIceConnectionState`) & §5.6 (`RTCIceTransport`)  

---

## 1. Normative Specification Requirements

According to the W3C WebRTC 1.0 specification (§4.3.3 `RTCIceConnectionState` and §5.6 `RTCIceTransportState`) and IETF RFC 8445 (Interactive Connectivity Establishment), the ICE layer manages the lifecycle of candidate pair connectivity checks and media transport viability. 

The state space is defined over seven discrete states:
* **`new` (0)**: The ICE agent is gathering addresses or waiting to be given remote candidates before it can start checking.
* **`checking` (1)**: The ICE agent has been given one or more remote candidates and is checking pairs of local and remote candidates against one another to try to find a compatible match, but has not yet found a pair which will allow the peer connection to be made. It is possible that gathering of candidates is also still underway.
* **`connected` (2)**: A usable pairing of local and remote candidates has been found for all components of the transport, and the ICE agent is still checking other candidate pairs to see if there is a better connection, or gathering is still underway.
* **`completed` (3)**: The ICE agent has finished gathering candidates, has checked all pairs against one another, and has found a connection for all components.
* **`failed` (4)**: The ICE agent has checked all candidates pairs against one another and has failed to find compatible matches for all components of the connection.
* **`disconnected` (5)**: Checks to ensure that components are still connected failed for at least one component of the `RTCIceTransport`. This is a less stringent test than `failed` and may trigger intermittently and resolve itself without action (back to `connected` or `completed`), or transition to `failed`.
* **`closed` (6)**: The ICE agent for this `RTCIceTransport` has shut down and is no longer responding to STUN requests.

### Normative Transition Invariants
1. **Terminal Closure**: Once an `RTCIceTransport` enters the `closed` (6) state, it is strictly absorbing. No WebRTC event, remote SDP update, or network connectivity change can transition the state out of `closed`.
2. **Valid Transition Graph**:
   * `new` $\to$ `{checking, closed}` (and direct to `disconnected`/`failed` only on abrupt teardown or empty candidate exhaustion, though standard path requires `checking`).
   * `checking` $\to$ `{connected, failed, closed}`.
   * `connected` $\to$ `{completed, disconnected, failed, checking (on ICE restart), closed}`.
   * `completed` $\to$ `{disconnected, checking (on ICE restart), closed}`.
   * `disconnected` $\to$ `{connected, completed, failed, checking (on ICE restart), closed}`.
   * `failed` $\to$ `{checking (on ICE restart), closed}`.
3. **Media Viability Invariant**: Real-time RTP/RTCP media packets can only be actively guaranteed transmission over a nominated pair when the state is within the active connected subset: `{connected (2), completed (3)}`.

---

## 2. Chromium Blink Implementation & Invariants

In Chromium's Blink rendering engine, `RTCIceTransport` (`third_party/blink/renderer/modules/peerconnection/rtc_ice_transport.cc`) wraps the WebRTC native layer proxy (`webrtc::IceTransportInterface` and `cricket::IceTransportInternal` signals surfaced via `IceTransportProxy`).

### Implementation Mechanics in `rtc_ice_transport.cc`

1. **State Representation**:
   Blink maintains the member `webrtc::IceTransportState state_` (initialized to `webrtc::IceTransportState::kNew`). The conversion to the V8 bindings enum `V8RTCIceTransportState` occurs via `IceTransportStateToV8(webrtc::IceTransportState state)`:
   * `kNew` $\mapsto$ `0` (`"new"`)
   * `kChecking` $\mapsto$ `1` (`"checking"`)
   * `kConnected` $\mapsto$ `2` (`"connected"`)
   * `kCompleted` $\mapsto$ `3` (`"completed"`)
   * `kFailed` $\mapsto$ `4` (`"failed"`)
   * `kDisconnected` $\mapsto$ `5` (`"disconnected"`)
   * `kClosed` $\mapsto$ `6` (`"closed"`)

2. **Asynchronous State Updates (`OnStateChanged`)**:
   When the underlying WebRTC network thread signals an ICE state change, it posts a task to the Blink main thread invoking `RTCIceTransport::OnStateChanged(webrtc::IceTransportState new_state)`:
   ```cpp
   void RTCIceTransport::OnStateChanged(webrtc::IceTransportState new_state) {
     if (state_ == webrtc::IceTransportState::kClosed) {
       return; // Invariant: Closed state is strictly terminal.
     }
     if (state_ == new_state) {
       return; // Idempotence suppression: do not fire redundant events.
     }
     // Transition validation and state update
     state_ = new_state;
     DispatchEvent(*Event::Create(event_type_names::kStatechange));
   }
   ```

3. **Synchronous Closure (`Stop` / `Close`)**:
   When the `RTCPeerConnection` is closed or the execution context is destroyed (`ContextDestroyed()`), `RTCIceTransport::Close()` is invoked, immediately forcing `state_ = webrtc::IceTransportState::kClosed`. Any in-flight IPC/cross-thread tasks carrying `OnStateChanged` with earlier states (`connected`, `disconnected`, etc.) are rejected by the `state_ == kClosed` guard.

---

## 3. Formal Specification in Rocq/Coq

Below is the complete, self-contained formalization in `BlinkWebRTCICEConnectionStateSemantics.v`. It encodes the integer-mapped state space `[0..6]`, the normative transition relation, the Blink event loop state-update function, and real-time media streaming invariants.

```coq
(** * BlinkWebRTCICEConnectionStateSemantics.v
    Formal verification of WebRTC ICE Connection State Transitions
    in Chromium Blink (rtc_ice_transport.cc) per W3C WebRTC 1.0 §4.3.3. *)

Require Import Coq.ZArith.ZArith.
Require Import Coq.Bool.Bool.
Require Import Coq.Lists.List.
Require Import Coq.micromega.Lia.
Import ListNotations.

Open Scope Z_scope.

(** ** 1. State Encoding Constants
    Mathematical Property:
    new(0), checking(1), connected(2), completed(3),
    failed(4), disconnected(5), closed(6). *)

Definition ICE_NEW          : Z := 0.
Definition ICE_CHECKING     : Z := 1.
Definition ICE_CONNECTED    : Z := 2.
Definition ICE_COMPLETED    : Z := 3.
Definition ICE_FAILED       : Z := 4.
Definition ICE_DISCONNECTED : Z := 5.
Definition ICE_CLOSED       : Z := 6.

(** Inductive representation of the ICE connection state *)
Inductive IceState : Type :=
  | New
  | Checking
  | Connected
  | Completed
  | Failed
  | Disconnected
  | Closed.

(** Decidable equality for IceState *)
Scheme Equality for IceState.

(** Mapping from Inductive IceState to Z *)
Definition state_to_Z (s : IceState) : Z :=
  match s with
  | New          => ICE_NEW
  | Checking     => ICE_CHECKING
  | Connected    => ICE_CONNECTED
  | Completed    => ICE_COMPLETED
  | Failed       => ICE_FAILED
  | Disconnected => ICE_DISCONNECTED
  | Closed       => ICE_CLOSED
  end.

(** Partial/Clamped mapping from Z to IceState *)
Definition Z_to_state (z : Z) : option IceState :=
  if Z.eqb z 0 then Some New
  else if Z.eqb z 1 then Some Checking
  else if Z.eqb z 2 then Some Connected
  else if Z.eqb z 3 then Some Completed
  else if Z.eqb z 4 then Some Failed
  else if Z.eqb z 5 then Some Disconnected
  else if Z.eqb z 6 then Some Closed
  else None.

(** Predicate defining a valid integer encoding of an ICE state *)
Definition valid_state_Z (z : Z) : Prop :=
  0 <= z <= 6.

(** ** 2. Streaming Media Viability Predicates *)

(** Real-time media can flow over a nominated candidate pair iff
    the ICE transport is in Connected(2) or Completed(3). *)
Definition is_media_viable_b (z : Z) : bool :=
  (Z.eqb z ICE_CONNECTED) || (Z.eqb z ICE_COMPLETED).

Definition is_media_viable (z : Z) : Prop :=
  z = ICE_CONNECTED \/ z = ICE_COMPLETED.

(** ** 3. Normative W3C WebRTC 1.0 §4.3.3 Transition Graph *)

(** Boolean transition validator over integer state representations.
    Captures valid transitions including ICE restarts (transitioning back to
    Checking(1) from Connected, Completed, Disconnected, or Failed) and
    universal closure (transitioning to Closed(6) from any state). *)
Definition valid_transition_b (s_from s_to : Z) : bool :=
  if Z.eqb s_from ICE_NEW then
    (Z.eqb s_to ICE_NEW) || (Z.eqb s_to ICE_CHECKING) || (Z.eqb s_to ICE_CLOSED)
  else if Z.eqb s_from ICE_CHECKING then
    (Z.eqb s_to ICE_CHECKING) || (Z.eqb s_to ICE_CONNECTED) ||
    (Z.eqb s_to ICE_FAILED) || (Z.eqb s_to ICE_CLOSED)
  else if Z.eqb s_from ICE_CONNECTED then
    (Z.eqb s_to ICE_CONNECTED) || (Z.eqb s_to ICE_COMPLETED) ||
    (Z.eqb s_to ICE_DISCONNECTED) || (Z.eqb s_to ICE_FAILED) ||
    (Z.eqb s_to ICE_CHECKING) || (Z.eqb s_to ICE_CLOSED)
  else if Z.eqb s_from ICE_COMPLETED then
    (Z.eqb s_to ICE_COMPLETED) || (Z.eqb s_to ICE_DISCONNECTED) ||
    (Z.eqb s_to ICE_CHECKING) || (Z.eqb s_to ICE_CLOSED)
  else if Z.eqb s_from ICE_FAILED then
    (Z.eqb s_to ICE_FAILED) || (Z.eqb s_to ICE_CHECKING) || (Z.eqb s_to ICE_CLOSED)
  else if Z.eqb s_from ICE_DISCONNECTED then
    (Z.eqb s_to ICE_DISCONNECTED) || (Z.eqb s_to ICE_CONNECTED) ||
    (Z.eqb s_to ICE_COMPLETED) || (Z.eqb s_to ICE_FAILED) ||
    (Z.eqb s_to ICE_CHECKING) || (Z.eqb s_to ICE_CLOSED)
  else if Z.eqb s_from ICE_CLOSED then
    (Z.eqb s_to ICE_CLOSED)
  else
    false.

(** ** 4. Blink RTCIceTransport State Machine Implementation Model
    Models RTCIceTransport::OnStateChanged in rtc_ice_transport.cc *)

Record BlinkIceTransport := mkTransport {
  current_state : Z;
  event_count   : Z
}.

Definition init_transport : BlinkIceTransport :=
  mkTransport ICE_NEW 0.

(** Models RTCIceTransport::OnStateChanged(new_state):
    1. If current_state == kClosed(6), ignore.
    2. If current_state == new_state, ignore (no event dispatched).
    3. If transition is valid per spec, update state and increment event_count.
    4. Otherwise, preserve current state. *)
Definition blink_on_state_changed (t : BlinkIceTransport) (next_s : Z) : BlinkIceTransport :=
  if Z.eqb (current_state t) ICE_CLOSED then
    t
  else if Z.eqb (current_state t) next_s then
    t
  else if valid_transition_b (current_state t) next_s then
    mkTransport next_s (event_count t + 1)
  else
    t.

(** Models RTCIceTransport::Close() / ContextDestroyed() *)
Definition blink_close (t : BlinkIceTransport) : BlinkIceTransport :=
  mkTransport ICE_CLOSED (event_count t).

(** Multi-step trace execution *)
Fixpoint run_trace (t : BlinkIceTransport) (trace : list Z) : BlinkIceTransport :=
  match trace with
  | [] => t
  | s :: rest => run_trace (blink_on_state_changed t s) rest
  end.
```

---

## 4. Concrete Theorems and Complete Proofs

All theorems below are proven without a single `Admitted` or `admit`, using `ZArith`, `Bool`, and `Lia`.

```coq
(** ** 5. Formal Verification Theorems & Proofs *)

(** Theorem 1: State encoding is strictly bounded within [0, 6]. *)
Theorem state_to_Z_bounded : forall (s : IceState),
  valid_state_Z (state_to_Z s).
Proof.
  intros s. unfold valid_state_Z, state_to_Z.
  unfold ICE_NEW, ICE_CHECKING, ICE_CONNECTED, ICE_COMPLETED,
         ICE_FAILED, ICE_DISCONNECTED, ICE_CLOSED.
  destruct s; lia.
Qed.

(** Theorem 2: Bijection/Round-trip correctness between IceState and Z. *)
Theorem state_Z_roundtrip : forall (s : IceState),
  Z_to_state (state_to_Z s) = Some s.
Proof.
  intros s. destruct s; simpl; reflexivity.
Qed.

(** Theorem 3: Media viability boolean reflection equivalence. *)
Theorem media_viable_reflect : forall (z : Z),
  is_media_viable_b z = true <-> is_media_viable z.
Proof.
  intros z. unfold is_media_viable_b, is_media_viable, ICE_CONNECTED, ICE_COMPLETED.
  rewrite orb_true_iff.
  repeat rewrite Z.eqb_eq.
  tauto.
Qed.

(** Theorem 4: Closed state (6) is strictly absorbing in the W3C transition relation. *)
Theorem closed_is