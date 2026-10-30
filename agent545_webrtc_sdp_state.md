# Formal Verification of the Chromium Blink WebRTC SDP Offer/Answer Signaling State Machine

**Topic:** WebRTC SDP Offer/Answer Signaling State Machine  
**Chromium Source:** `third_party/blink/renderer/modules/peerconnection/rtc_peer_connection.cc`  
**Specification:** W3C WebRTC 1.0: Real-Time Communication Between Browsers (§4.3.1, §4.4.1.6) & IETF RFC 8829 (JSEP §3.2)  
**Formal Theory Target:** `BlinkWebRTCSignalingStateSemantics.v`  
**Mathematical Property:** Signaling states: `stable(0)`, `have-local-offer(1)`, `have-remote-offer(2)`, `closed(3)`; `closed` is strictly terminal and absorbing.

---

## 1. Exact Normative W3C & IETF Specification Requirements

The WebRTC Session Description Protocol (SDP) Offer/Answer state machine governs the negotiation of media capabilities, network transports (ICE), and cryptographic keys (DTLS) between two peers. The normative state transition semantics are jointly defined by the W3C WebRTC 1.0 specification and IETF RFC 8829 (JavaScript Session Establishment Protocol - JSEP).

### 1.1 W3C WebRTC 1.0 (§4.3.1 `RTCSignalingState` Enum & §4.4.1.6 Signaling State)
Per W3C WebRTC 1.0 §4.3.1, the `RTCSignalingState` enum defines the progression of the SDP offer/answer negotiation. For the core uncompressed offer/answer cycle (excluding provisional answers `pranswer` which behave as transient sub-states of offer states), the primary state space $\mathcal{S}$ consists of:

1. **`"stable"` (`0`)**: There is no offer/answer exchange in progress. This is both the initial state of a newly instantiated `RTCPeerConnection` and the quiescent state reached after a successful `answer` application or `rollback`.
2. **`"have-local-offer"` (`1`)**: A local description of type `"offer"` has been successfully applied via `setLocalDescription()`. The peer is awaiting a remote `"answer"` (or a local/remote `"rollback"`).
3. **`"have-remote-offer"` (`2`)**: A remote description of type `"offer"` has been successfully applied via `setRemoteDescription()`. The peer is awaiting the generation and application of a local `"answer"` (or `"rollback"`).
4. **`"closed"` (`3`)**: The `RTCPeerConnection` has been terminated via `close()`. All underlying media transports, RTP senders/receivers, and SCTP data channels are torn down.

### 1.2 IETF RFC 8829 (JSEP §3.2) & W3C §4.4.1.5 Transition Rules
The normative state transition function $\delta: \mathcal{S} \times \Sigma \to \mathcal{S} \cup \{\bot\}$ (where $\Sigma$ is the alphabet of signaling operations and $\bot$ represents an `InvalidModificationError` or `InvalidStateError` exception) enforces the following exact rules:

* **Rule 1 (Connection Initialization):** Upon construction of `RTCPeerConnection`, the `[[SignalingState]]` internal slot is initialized to `"stable"`.
* **Rule 2 (Local Offer Application):** Invoking `setLocalDescription(offer)` is valid if and only if `[[SignalingState]]` $\in \{\text{"stable"}, \text{"have-local-offer"}\}$. It transitions the state to `"have-local-offer"` (supporting both initial offers and repeated re-offers before an answer arrives).
* **Rule 3 (Remote Answer Application):** Invoking `setRemoteDescription(answer)` is valid if and only if `[[SignalingState]]` $= \text{"have-local-offer"}$. It transitions the state to `"stable"`.
* **Rule 4 (Remote Offer Application):** Invoking `setRemoteDescription(offer)` is valid if and only if `[[SignalingState]]` $\in \{\text{"stable"}, \text{"have-remote-offer"}\}$. It transitions the state to `"have-remote-offer"`.
* **Rule 5 (Local Answer Application):** Invoking `setLocalDescription(answer)` is valid if and only if `[[SignalingState]]` $= \text{"have-remote-offer"}$. It transitions the state to `"stable"`.
* **Rule 6 ( Glare Resolution / Rollback):** Invoking `setLocalDescription(rollback)` from `"have-local-offer"` or `setRemoteDescription(rollback)` from `"have-remote-offer"` reverts the state to `"stable"`. Rollback from `"stable"` is invalid (`InvalidModificationError`).
* **Rule 7 (Terminal Closure):** Invoking `close()` from *any* state unconditionally transitions `[[SignalingState]]` to `"closed"`. Furthermore, per W3C WebRTC 1.0 §4.4.1.6, before any asynchronous signaling operation (`setLocalDescription`, `setRemoteDescription`, `createOffer`, `createAnswer`, `addIceCandidate`) executes or resolves on the main thread, if `[[IsClosed]]` is `true` (i.e., `[[SignalingState]]` $= \text{"closed"}$), the operation must immediately abort with an `InvalidStateError`. Thus, `"closed"` is a **strictly absorbing terminal state**.

---

## 2. Blink Implementation Details and Invariants

In Chromium's Blink rendering engine, the JavaScript-facing WebRTC state machine is implemented in `third_party/blink/renderer/modules/peerconnection/rtc_peer_connection.cc` and its accompanying header `rtc_peer_connection.h`. Blink acts as an asynchronous synchronization boundary over the underlying WebRTC native C++ library (`third_party/webrtc/pc/sdp_offer_answer.cc`).

### 2.1 State Representation and Internal Slots
In `RTCPeerConnection`, the signaling state is tracked via the member variable:
```cpp
webrtc::PeerConnectionInterface::SignalingState signaling_state_;
bool is_closed_;
```
While `webrtc::PeerConnectionInterface::SignalingState` enumerates `kStable`, `kHaveLocalOffer`, `kHaveLocalPrAnswer`, `kHaveRemoteOffer`, `kHaveRemotePrAnswer`, and `kClosed`, Blink maps these directly to the V8 IDL enum `V8RTCSignalingState` via `BlinkSignalingState()`.

### 2.2 Asynchronous IPC/Thread Synchronization and the `ChangeSignalingState` Guard
Because WebRTC SDP parsing and media transport configuration occur on the WebRTC Signaling Thread and Network/Worker Threads, while Blink executes on the Renderer Main Thread, state updates arrive via asynchronous callbacks (`RTCPeerConnectionHandlerClient::DidChangeSessionDescriptions` and `DidChangeSignalingState`).

To prevent thread-crossing race conditions from resurrecting a closed connection, `rtc_peer_connection.cc` enforces strict guards:

1. **`ThrowExceptionIfSignalingStateClosed(signaling_state_, exception_state)`**:
   Every public IDL method (`setLocalDescription`, `setRemoteDescription`, `createOffer`, `createAnswer`) begins with an explicit check against `signaling_state_ == webrtc::PeerConnectionInterface::SignalingState::kClosed`. If true, it synchronously throws a `DOMExceptionCode::kInvalidStateError` and returns a rejected `ScriptPromise`.

2. **`RTCPeerConnection::close()`**:
   ```cpp
   void RTCPeerConnection::close() {
     if (signaling_state_ == webrtc::PeerConnectionInterface::SignalingState::kClosed)
       return;
     CloseInternal();
   }
   ```
   `CloseInternal()` immediately sets `signaling_state_ = webrtc::PeerConnectionInterface::SignalingState::kClosed;`, sets `is_closed_ = true;`, stops the `peer_handler_`, and suppresses any further `signalingstatechange` events.

3. **`RTCPeerConnection::ChangeSignalingState(SignalingState signaling_state)`**:
   ```cpp
   void RTCPeerConnection::ChangeSignalingState(
       webrtc::PeerConnectionInterface::SignalingState signaling_state) {
     if (signaling_state_ != webrtc::PeerConnectionInterface::SignalingState::kClosed &&
         signaling_state_ != signaling_state) {
       signaling_state_ = signaling_state;
       ScheduleDispatchEvent(Event::Create(event_type_names::kSignalingstatechange));
     }
   }
   ```
   **Crucial Invariant:** Notice the guard `if (signaling_state_ != ...::kClosed)`. Even if an in-flight asynchronous task from the WebRTC signaling thread posts a callback to the Blink main thread attempting to transition the state to `kStable` or `kHaveRemoteOffer` *after* JS has called `close()`, Blink's `ChangeSignalingState` explicitly drops the transition.

### 2.3 System Invariants in `rtc_peer_connection.cc`
From the C++ implementation, we extract four core mathematical invariants to be formally verified:
* **Invariant I1 (State Domain Bounds):** At all execution points, the encoded integer representation $s$ of `signaling_state_` satisfies $0 \le s \le 3$.
* **Invariant I2 (Terminal Absorption of `closed`):** Once `signaling_state_ == 3` (`kClosed`), for all possible sequences of local/remote SDP operations or delayed thread callbacks $w \in \Sigma^*$, the resulting state remains $3$.
* **Invariant I3 (Bipartite Offer Polarity Exclusivity):** A connection cannot simultaneously hold an unacknowledged local offer and an unacknowledged remote offer. Attempting to apply a remote offer while in `have-local-offer` ($1$) without an intervening rollback is rejected (Glare condition), and vice versa.
* **Invariant I4 (Quiescent Convergence):** Any valid offer ($0 \to 1$ or $0 \to 2$) followed immediately by its complementary answer or matching rollback deterministically restores the state to `stable` ($0$).

---

## 3. Formal Specification Definitions in Rocq/Coq

Below is the self-contained formalization of `BlinkWebRTCSignalingStateSemantics.v`. We encode both the strongly-typed algebraic state machine and its exact integer representation $s \in \mathbb{Z}$ (`0`, `1`, `2`, `3`) as specified in the target mathematical property.

```coq
(** * BlinkWebRTCSignalingStateSemantics.v
    Formal Verification of Chromium Blink's WebRTC SDP Offer/Answer State Machine
    Source: third_party/blink/renderer/modules/peerconnection/rtc_peer_connection.cc
    Spec: W3C WebRTC 1.0 §4.3.1, §4.4.1.6 & IETF RFC 8829 (JSEP §3.2)
*)

From Coq Require Import ZArith.
From Coq Require Import Lia.
From Coq Require Import Bool.
From Coq Require Import List.
Import ListNotations.

Open Scope Z_scope.

(** ** 1. Integer State Constants and Algebraic Types *)

Definition STATE_STABLE : Z := 0.
Definition STATE_HAVE_LOCAL_OFFER : Z := 1.
Definition STATE_HAVE_REMOTE_OFFER : Z := 2.
Definition STATE_CLOSED : Z := 3.

(** Inductive representation of the W3C RTCSignalingState enum *)
Inductive SignalingState : Type :=
  | Stable          (* 0: stable *)
  | HaveLocalOffer  (* 1: have-local-offer *)
  | HaveRemoteOffer (* 2: have-remote-offer *)
  | Closed.         (* 3: closed *)

(** Bijective mapping between algebraic SignalingState and Z encoding *)
Definition state_to_Z (s : SignalingState) : Z :=
  match s with
  | Stable          => STATE_STABLE
  | HaveLocalOffer  => STATE_HAVE_LOCAL_OFFER
  | HaveRemoteOffer => STATE_HAVE_REMOTE_OFFER
  | Closed          => STATE_CLOSED
  end.

Definition Z_to_state (z : Z) : option SignalingState :=
  if Z.eqb z 0 then Some Stable
  else if Z.eqb z 1 then Some HaveLocalOffer
  else if Z.eqb z 2 then Some HaveRemoteOffer
  else if Z.eqb z 3 then Some Closed
  else None.

(** Valid integer state predicate *)
Definition is_valid_state_Z (z : Z) : Prop :=
  0 <= z <= 3.

Definition is_valid_state_Z_b (z : Z) : bool :=
  (0 <=? z) && (z <=? 3).

(** ** 2. Signaling Actions (SDP Offer/Answer & Lifecycle Operations) *)

Inductive SignalingAction : Type :=
  | ActSetLocalOffer      (* setLocalDescription({type: 'offer'}) *)
  | ActSetLocalAnswer     (* setLocalDescription({type: 'answer'}) *)
  | ActSetLocalRollback   (* setLocalDescription({type: 'rollback'}) *)
  | ActSetRemoteOffer     (* setRemoteDescription({type: 'offer'}) *)
  | ActSetRemoteAnswer    (* setRemoteDescription({type: 'answer'}) *)
  | ActSetRemoteRollback  (* setRemoteDescription({type: 'rollback'}) *)
  | ActClose              (* close() / CloseInternal() *)
  | ActAsyncCallback (target : Z). (* ChangeSignalingState(target) from WebRTC thread *)

(** ** 3. Normative & Blink State Transition Semantics *)

(** Total integer-level transition function modeling Blink's exact behavior.
    If an invalid SDP operation is attempted (e.g., glare or invalid state),
    Blink throws DOMException (InvalidStateError / InvalidModificationError)
    and the internal state remains unchanged. *)
Definition step_Z (s : Z) (a : SignalingAction) : Z :=
  if Z.eqb s STATE_CLOSED then
    STATE_CLOSED (* Invariant: ThrowExceptionIfSignalingStateClosed & ChangeSignalingState guard *)
  else
    match a with
    | ActClose =>
        STATE_CLOSED
    | ActSetLocalOffer =>
        if (Z.eqb s STATE_STABLE) || (Z.eqb s STATE_HAVE_LOCAL_OFFER)
        then STATE_HAVE_LOCAL_OFFER
        else s
    | ActSetRemoteAnswer =>
        if Z.eqb s STATE_HAVE_LOCAL_OFFER
        then STATE_STABLE
        else s
    | ActSetLocalRollback =>
        if Z.eqb s STATE_HAVE_LOCAL_OFFER
        then STATE_STABLE
        else s
    | ActSetRemoteOffer =>
        if (Z.eqb s STATE_STABLE) || (Z.eqb s STATE_HAVE_REMOTE_OFFER)
        then STATE_HAVE_REMOTE_OFFER
        else s
    | ActSetLocalAnswer =>
        if Z.eqb s STATE_HAVE_REMOTE_OFFER
        then STATE_STABLE
        else s
    | ActSetRemoteRollback =>
        if Z.eqb s STATE_HAVE_REMOTE_OFFER
        then STATE_STABLE
        else s
    | ActAsyncCallback target =>
        (* Blink's ChangeSignalingState only accepts valid non-closed states
           when current state != kClosed *)
        if (0 <=? target) && (target <=? 3)
        then target
        else s
    end.

(** Boolean predicate checking whether an SDP action succeeds without