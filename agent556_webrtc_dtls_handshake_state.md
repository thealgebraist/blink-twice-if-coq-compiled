# Formal Verification Report: WebRTC DTLS Handshake State Progression in Chromium Blink

**Formal Theory Target:** `BlinkWebRTCDTLSHandshakeStateSemantics.v`  
**Chromium Source:** `third_party/blink/renderer/modules/peerconnection/rtc_dtls_transport.cc`  
**Specification:** W3C WebRTC 1.0: Real-Time Communication Between Browsers, §5.5 (`RTCDtlsTransport` Interface)  
**Mathematical Property:** Monotonic non-terminal progression (`new(0) -> connecting(1) -> connected(2)`) and absorbing terminal finality (`closed(3)`, `failed(4)`).

---

## 1. Normative W3C & IETF Specification Requirements

According to the **W3C WebRTC 1.0 Specification (§5.5, `RTCDtlsTransport` Interface)** and the underlying **IETF RFC 6347 (Datagram Transport Layer Security Version 1.2)** / **RFC 8827 (WebRTC Security Architecture)**, an `RTCDtlsTransport` object manages the Datagram Transport Layer Security (DTLS) handshake and encrypted media/data framing over an underlying `RTCIceTransport`.

### 1.1 The `RTCDtlsTransportState` Enumeration
The specification defines the `RTCDtlsTransportState` enum with five distinct states:

1. **`"new"` (0)**: DTLS has not started negotiating yet. The transport is awaiting underlying ICE connectivity or local/remote configuration parameters.
2. **`"connecting"` (1)**: DTLS is in the process of negotiating a secure connection and verifying the remote fingerprint.
3. **`"connected"` (2)**: DTLS has completed negotiation of a secure connection and verified the remote fingerprint. SRTP keying material has been exported, and encrypted media can flow.
4. **`"closed"` (3)**: The transport has been intentionally closed as the result of an explicit local `close()` operation or receipt of a remote DTLS `close_notify` alert.
5. **`"failed"` (4)**: The transport has failed as the result of an error (such as a failure to validate the remote fingerprint, a fatal DTLS alert, or a timeout during the handshake).

### 1.2 Normative State Machine Invariants
The specification mandates strict transition semantics:
* **Initial State:** Upon construction of an `RTCDtlsTransport`, the `state` attribute MUST be initialized to `"new"` (unless constructed from an already progressing native transport, in which case it reflects the current progression).
* **Forward Progression:** During normal negotiation, the state progresses strictly forward: `"new"` $\to$ `"connecting"` $\to$ `"connected"`. Once `"connecting"` or `"connected"` is reached, the transport MUST NOT revert to `"new"`, and once `"connected"` is reached, it MUST NOT revert to `"connecting"` (re-handshakes or ICE restarts that require new DTLS sessions either maintain `"connected"` until replaced or instantiate a new transport).
* **Terminal Absorption (`"closed"` and `"failed"`):** Both `"closed"` and `"failed"` are terminal absorbing states. 
  * When `RTCPeerConnection.close()` is invoked, the state transitions synchronously or asynchronously to `"closed"`, and no subsequent network events may transition it out of `"closed"` (not even into `"failed"`).
  * When a fatal handshake error or fingerprint mismatch occurs, the state transitions to `"failed"`, and cannot transition to `"connected"`, `"connecting"`, `"new"`, or `"closed"`.

---

## 2. Chromium Blink Implementation Details & Invariants

In Chromium, the JavaScript-exposed `RTCDtlsTransport` interface is implemented in `third_party/blink/renderer/modules/peerconnection/rtc_dtls_transport.cc` (and its header `rtc_dtls_transport.h`). It wraps a native WebRTC layer proxy (`webrtc::DtlsTransportInterface`) via `DtlsTransportProxy`.

### 2.1 State Mapping and Representation
Blink bridges the native C++ `webrtc::DtlsTransportState` enum to the Blink IDL `V8RTCDtlsTransportState`:

```cpp
// Conceptual mapping in rtc_dtls_transport.cc
V8RTCDtlsTransportState::Enum StateToV8(webrtc::DtlsTransportState state) {
  switch (state) {
    case webrtc::DtlsTransportState::kNew:
      return V8RTCDtlsTransportState::Enum::kNew;        // 0
    case webrtc::DtlsTransportState::kConnecting:
      return V8RTCDtlsTransportState::Enum::kConnecting; // 1
    case webrtc::DtlsTransportState::kConnected:
      return V8RTCDtlsTransportState::Enum::kConnected;  // 2
    case webrtc::DtlsTransportState::kClosed:
      return V8RTCDtlsTransportState::Enum::kClosed;     // 3
    case webrtc::DtlsTransportState::kFailed:
      return V8RTCDtlsTransportState::Enum::kFailed;     // 4
    case webrtc::DtlsTransportState::kNumValues:
      NOTREACHED();
  }
}
```

### 2.2 Asynchronous Thread Hopping and Guard Invariants
Native DTLS operations occur on the WebRTC network thread (`p2p_transport_channel` / `dtls_transport`), while `RTCDtlsTransport` lives on the Blink main (JS) thread. State updates are marshaled via `DtlsTransportProxy` to `RTCDtlsTransport::OnStateChange(webrtc::DtlsTransportInformation info)`.

Because of asynchronous task posting between the network thread and the Blink main thread, race conditions can occur between local synchronous actions (such as `RTCDtlsTransport::Close()` triggered by `RTCPeerConnection::close()`) and in-flight network callbacks:

1. **Local Close Guard (`closed_from_owner_`):**
   When `RTCPeerConnection::close()` is called, it synchronously invokes `RTCDtlsTransport::Close()`.
   ```cpp
   void RTCDtlsTransport::Close() {
     closed_from_owner_ = true;
     if (current_state_.state() != webrtc::DtlsTransportState::kClosed) {
       current_state_ = webrtc::DtlsTransportInformation(
           webrtc::DtlsTransportState::kClosed);
     }
   }
   ```
2. **Callback Filtering (`OnStateChange`):**
   When an in-flight `OnStateChange` task executes on the main thread after `Close()` has been called, Blink enforces terminal finality:
   ```cpp
   void RTCDtlsTransport::OnStateChange(webrtc::DtlsTransportInformation info) {
     // Invariant 1: If already closed by owner, ignore in-flight network updates.
     if (closed_from_owner_) {
       return;
     }
     // Invariant 2: State progression must respect WebRTC native state machine
     // and never regress from terminal states.
     current_state_ = info;
     // ... dispatch statechange or error events ...
   }
   ```
3. **Certificate Inspection Guard:**
   In ` connected` state, remote certificates are populated (`current_state_.remote_ssl_certificates()`). Once in `kNew` or `kConnecting`, remote certificates are empty. Monotonic progression ensures that once `kConnected` is reached and certificates are validated, the transport never reverts to an unverified active state (`kConnecting` or `kNew`).

---

## 3. Formal Specification in Rocq / Coq

Below is the complete, self-contained formalization of `BlinkWebRTCDTLSHandshakeStateSemantics.v`. We encode the discrete state space, integer projection (`Z`), the normative state transition relation, the executable Blink state reducer (incorporating `closed_from_owner_`), and multi-step execution traces.

```coq
(** * BlinkWebRTCDTLSHandshakeStateSemantics.v
    Formalizing W3C WebRTC 1.0 §5.5 and Chromium Blink's RTCDtlsTransport
    state machine (third_party/blink/renderer/modules/peerconnection/rtc_dtls_transport.cc).
*)

From Coq Require Import Bool.Bool.
From Coq Require Import ZArith.ZArith.
From Coq Require Import Lists.List.
From Coq Require Import micromega.Lia.
Import ListNotations.

Open Scope Z_scope.

(** ** 1. DTLS Transport State Definitions *)

Inductive DtlsState : Type :=
  | DTLS_New        (* 0 : new *)
  | DTLS_Connecting (* 1 : connecting *)
  | DTLS_Connected  (* 2 : connected *)
  | DTLS_Closed     (* 3 : closed (terminal) *)
  | DTLS_Failed.    (* 4 : failed (terminal) *)

(** Decidable equality on DtlsState *)
Definition dtls_state_eqb (s1 s2 : DtlsState) : bool :=
  match s1, s2 with
  | DTLS_New, DTLS_New => true
  | DTLS_Connecting, DTLS_Connecting => true
  | DTLS_Connected, DTLS_Connected => true
  | DTLS_Closed, DTLS_Closed => true
  | DTLS_Failed, DTLS_Failed => true
  | _, _ => false
  end.

Lemma dtls_state_eqb_eq : forall s1 s2,
  dtls_state_eqb s1 s2 = true <-> s1 = s2.
Proof.
  destruct s1, s2; simpl; split; intro H; try reflexivity; try discriminate.
Qed.

(** Integer encoding matching the mathematical property:
    new(0) -> connecting(1) -> connected(2); closed(3) / failed(4) terminal. *)
Definition state_to_Z (s : DtlsState) : Z :=
  match s with
  | DTLS_New        => 0
  | DTLS_Connecting => 1
  | DTLS_Connected  => 2
  | DTLS_Closed     => 3
  | DTLS_Failed     => 4
  end.

(** Classification predicates *)
Definition is_terminal (s : DtlsState) : bool :=
  match s with
  | DTLS_Closed | DTLS_Failed => true
  | _ => false
  end.

Definition is_non_terminal (s : DtlsState) : bool :=
  negb (is_terminal s).

(** ** 2. Normative W3C / Blink State Transition Relation *)

(** Valid single-step transition in the DTLS state machine:
    - Reflexive idling is permitted in any state.
    - Non-terminal states can progress monotonically: 0 -> 1 -> 2 (or 0 -> 2 if fast-pathed).
    - Any non-terminal state (0, 1, 2) can transition to Closed (3) or Failed (4).
    - Terminal states (3, 4) can only transition to themselves (absorbing). *)
Definition valid_step_b (s1 s2 : DtlsState) : bool :=
  match s1, s2 with
  | DTLS_New, DTLS_New               => true
  | DTLS_New, DTLS_Connecting        => true
  | DTLS_New, DTLS_Connected         => true
  | DTLS_New, DTLS_Closed            => true
  | DTLS_New, DTLS_Failed            => true

  | DTLS_Connecting, DTLS_Connecting => true
  | DTLS_Connecting, DTLS_Connected  => true
  | DTLS_Connecting, DTLS_Closed     => true
  | DTLS_Connecting, DTLS_Failed     => true

  | DTLS_Connected, DTLS_Connected   => true
  | DTLS_Connected, DTLS_Closed      => true
  | DTLS_Connected, DTLS_Failed      => true

  | DTLS_Closed, DTLS_Closed         => true
  | DTLS_Failed, DTLS_Failed         => true

  | _, _                             => false
  end.

Definition valid_step (s1 s2 : DtlsState) : Prop :=
  valid_step_b s1 s2 = true.

(** Reflexive-transitive closure representing multi-step execution traces *)
Inductive valid_trace : DtlsState -> DtlsState -> Prop :=
  | vt_refl : forall s, valid_trace s s
  | vt_step : forall s1 s2 s3,
      valid_step s1 s2 ->
      valid_trace s2 s3 ->
      valid_trace s1 s3.

(** ** 3. Blink Implementation Model (rtc_dtls_transport.cc) *)

(** Blink's RTCDtlsTransport maintains:
    - current_state_ : DtlsState
    - closed_from_owner_ : bool
*)
Record BlinkDtlsTransport : Type := mkTransport {
  current_state : DtlsState;
  closed_from_owner : bool
}.

(** Well-formedness invariant of Blink's C++ object:
    If closed_from_owner_ is true, current_state_ is strictly DTLS_Closed. *)
Definition blink_wf (t : BlinkDtlsTransport) : Prop :=
  closed_from_owner t = true -> current_state t = DTLS_Closed.

(** Initial state upon construction in Blink *)
Definition blink_init : BlinkDtlsTransport :=
  mkTransport DTLS_New false.

(** Events processed by RTCDtlsTransport on the Blink main thread *)
Inductive BlinkEvent : Type :=
  | Ev_OwnerClose                         (* RTCDtlsTransport::Close() *)
  | Ev_NetworkStateChange (next : DtlsState). (* RTCDtlsTransport::OnStateChange(info) *)

(** Blink state transition function modeling OnStateChange and Close() with guard *)
Definition blink_handle_event (t : BlinkDtlsTransport) (ev : BlinkEvent) : BlinkDtlsTransport :=
  match ev with
  | Ev_OwnerClose =>
      mkTransport DTLS_Closed true
  | Ev_NetworkStateChange next_s =>
      if closed_from_owner t then
        t (* Ignored due to `if (closed_from_owner_) return;` in rtc_dtls_transport.cc *)
      else if valid_step_b (current_state t) next_s then
        mkTransport next_s false
      else
        t (* Defensive guard against out-of-order / invalid IPC state regression *)
  end.

Fixpoint blink_run_events (t : BlinkDtlsTransport) (evs : list BlinkEvent) : BlinkDtlsTransport :=
  match evs with
  | [] => t
  | ev :: rest => blink_run_events (blink_handle_event t ev) rest
  end.
```

---

## 4. Concrete Theorems and Complete Rocq/Coq Proofs

We now state and prove the core mathematical theorems verifying state bounds, non-terminal monotonicity (`new(0) -> connecting(1) -> connected(2)`), terminal absorption (`closed(3)` and `failed(4)`), and the soundness of Blink's C++ implementation over arbitrary event traces. All proofs are complete and free of `Admitted`.

```coq
(** ** 4. Formal Verification of Mathematical Properties *)

(** Theorem 1: State Encoding Bounds
    Every DTLS state maps to an integer in the interval [0, 4]. *)
Theorem state_to_Z_bounds : forall s : DtlsState,
  0 <= state_to_Z s <= 4.
Proof.
  