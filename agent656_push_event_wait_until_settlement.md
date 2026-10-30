# Formal Verification Report: PushEvent `waitUntil` Promise Lifecycle Extension and Settlement in Chromium Blink

**Agent ID:** 656  
**Specialization:** Web Push, Notifications, Badging & Background Sync  
**Chromium Source Target:** `third_party/blink/renderer/modules/service_worker/extendable_event.cc`  
**Specification Target:** W3C Service Workers §4.3 (`ExtendableEvent.waitUntil`), W3C Push API §6.2 (`PushEvent`)  
**Formal Theory Target:** `BlinkPushEventWaitUntilSettlementSemantics.v`  

---

## 1. Exact Normative W3C Specification Requirements

The lifecycle of a `PushEvent` (as well as `NotificationEvent`, `SyncEvent`, and `PeriodicSyncEvent`) is governed by the `ExtendableEvent` interface defined in the W3C Service Workers specification, which serves as the foundational execution substrate for Web Push, Notifications, and Background Sync.

### 1.1 Service Workers §4.3 (`ExtendableEvent`)
An `ExtendableEvent` object has an associated:
* **`extend lifetime promises`**: A list of promises (initially empty).
* **`pending promises count`**: An integer (initially `0`).
* **`timed out flag`**: Initially unset.

When the `waitUntil(f)` method is invoked on an `ExtendableEvent` $E$ with promise $f$:
1. **Validity Guard:** If $E$ is not *Trusted* or if all the following conditions are false:
   * $E$'s `timed out flag` is unset; and
   * Either $E$'s `dispatch flag` is set, or $E$'s `pending promises count` is greater than `0`;
   then throw an `"InvalidStateError"` `DOMException`.
2. **Promise Registration:** Append $f$ to $E$'s `extend lifetime promises`.
3. **Counter Increment:** Increment $E$'s `pending promises count` by `1`:
   $$\text{extend\_lifetime}(\text{pending}, 1) = \text{pending} + 1$$
4. **Settlement Microtask:** Upon fulfillment or rejection of $f$, queue a microtask to run the following steps:
   * Decrement $E$'s `pending promises count` by `1` (clamped at zero in defensive implementations):
     $$\text{settle}(\text{pending}) = \max(0, \text{pending} - 1)$$
   * If $E$'s `pending promises count` is `0`, then obtain the registration and check if the worker's lifecycle state can transition or if the event handling completion callback should be invoked in the browser process.

### 1.2 W3C Push API §6.2 (Firing the `push` Event)
When the user agent receives a push message from the push service:
1. It starts the Service Worker (if not already running) and dispatches a `PushEvent` (which inherits from `ExtendableEvent`).
2. The Service Worker stays alive to process background notifications (`showNotification`) and badge updates (`navigator.setAppBadge`) for as long as `pending promises count > 0` or `dispatch flag == true`.
3. If a promise passed to `waitUntil` rejects, the user agent may enforce default notification fallback policies (e.g., showing a generic user-visible notification if `userVisibleOnly` was true and no notification was shown).

---

## 2. Blink Implementation Details & Invariants

In Chromium Blink, `PushEvent` inherits from `ExtendableEvent` (`third_party/blink/renderer/modules/push_messaging/push_event.h`). The core lifecycle extension logic resides in:
* `third_party/blink/renderer/modules/service_worker/extendable_event.cc`
* `third_party/blink/renderer/modules/service_worker/wait_until_observer.cc`

### 2.1 Architecture of `ExtendableEvent` and `WaitUntilObserver`
Blink separates the DOM event object (`ExtendableEvent`) from the lifecycle state machine (`WaitUntilObserver`). When a `PushEvent` is created in `ServiceWorkerGlobalScope::DispatchPushEvent`, a `WaitUntilObserver` is instantiated with `WaitUntilObserver::kPush` and attached to the `PushEvent`.

```cpp
// third_party/blink/renderer/modules/service_worker/extendable_event.cc
void ExtendableEvent::waitUntil(ScriptState* script_state,
                                ScriptPromiseUntyped script_promise,
                                ExceptionState& exception_state) {
  if (!isTrusted()) {
    exception_state.ThrowDOMException(
        DOMExceptionCode::kInvalidStateError,
        "Cannot call waitUntil() on an untrusted event.");
    return;
  }
  if (!observer_)
    return;
  observer_->WaitUntil(script_state, script_promise, exception_state);
}
```

### 2.2 State Machine Invariants in `WaitUntilObserver`
Inside `WaitUntilObserver` (`wait_until_observer.cc`), the pending promise count is tracked via `num_pending_promises_` (or an equivalent internal reference counter combining synchronous event dispatch depth and asynchronous promises):

1. **Dispatch Entry (`WillDispatchEvent`):**
   Before dispatching the `PushEvent` to JS, `WaitUntilObserver::WillDispatchEvent()` sets the dispatch state to active and increments the internal pending activity counter so premature settlement cannot occur during synchronous execution.
2. **Calling `WaitUntil` (`WaitUntilObserver::WaitUntil`):**
   * Checks `IsDispatchingEvent() || num_pending_promises_ > 0` and `!has_timed_out_`. If violated, throws `DOMExceptionCode::kInvalidStateError`.
   * Calls `IncrementPendingPromiseCount()` ($\text{pending} \leftarrow \text{pending} + 1$).
   * Attaches `ThenCallable` fulfillment (`OnPromiseFulfilled`) and rejection (`OnPromiseRejected`) handlers to the V8 promise.
3. **Promise Settlement (`OnPromiseFulfilled` / `OnPromiseRejected`):**
   * If rejected, records `event_dispatch_failed_ = true` (used by `ServiceWorkerGlobalScope` to fail the `PushEvent` callback to the browser process).
   * Calls `DecrementPendingPromiseCount()` ($\text{pending} \leftarrow \max(0, \text{pending} - 1)$).
   * When both synchronous dispatch has completed and `num_pending_promises_ == 0`, invokes `ReportAllPromisesSettled()` which triggers the Mojo completion callback (`DidHandlePushEvent`) back to the browser process (`ServiceWorkerVersion`).

---

## 3. Formal Specification Definitions in Rocq/Coq

Below is the complete, self-contained formalization of the `ExtendableEvent` / `PushEvent` `waitUntil` lifecycle and settlement semantics in Rocq/Coq (`BlinkPushEventWaitUntilSettlementSemantics.v`).

```coq
(** * BlinkPushEventWaitUntilSettlementSemantics.v
    Formal verification of W3C Service Worker §4.3 & Push API §6.2
    ExtendableEvent.waitUntil promise lifecycle extension and settlement
    in Chromium Blink (extendable_event.cc / wait_until_observer.cc). *)

From Coq Require Import ZArith.
From Coq Require Import Lia.
From Coq Require Import Bool.
From Coq Require Import List.
Import ListNotations.

Open Scope Z_scope.

(** ** 1. Mathematical Primitives *)

(** Spec §4.3: Increment pending promises count by delta (typically 1). *)
Definition extend_lifetime (pending : Z) (delta : Z) : Z :=
  pending + delta.

(** Spec §4.3: Decrement pending promises count by 1, clamped at 0. *)
Definition settle (pending : Z) : Z :=
  Z.max 0 (pending - 1).

(** Multi-step settlement of n promises. *)
Fixpoint settle_n (pending : Z) (n : nat) : Z :=
  match n with
  | O => pending
  | S n' => settle (settle_n pending n')
  end.

(** ** 2. PushEvent & WaitUntilObserver State Representation *)

Inductive PromiseOutcome : Type :=
  | Fulfilled : PromiseOutcome
  | Rejected  : PromiseOutcome.

Record ExtendableEventState : Type := mkEventState {
  is_trusted        : bool;
  is_dispatching    : bool;
  has_timed_out     : bool;
  pending_promises  : Z;
  dispatch_failed   : bool
}.

(** Initial state when PushEvent is constructed and WillDispatchEvent() runs. *)
Definition init_push_event_state (trusted : bool) : ExtendableEventState :=
  mkEventState trusted true false 0 false.

(** ** 3. Normative Guards and State Transitions *)

(** W3C Service Worker §4.3 step 1 & WaitUntilObserver::WaitUntil guard:
    Event must be trusted, not timed out, and either currently dispatching
    or keeping the worker alive via at least one pending promise. *)
Definition can_wait_until (st : ExtendableEventState) : bool :=
  is_trusted st &&
  negb (has_timed_out st) &&
  (is_dispatching st || (pending_promises st >? 0)).

(** Predicate characterizing whether the Service Worker must be kept alive
    for background Push processing. *)
Definition is_worker_kept_alive (st : ExtendableEventState) : bool :=
  negb (has_timed_out st) &&
  (is_dispatching st || (pending_promises st >? 0)).

(** Predicate indicating that the PushEvent has finished all processing
    and DidHandlePushEvent Mojo callback can be invoked. *)
Definition is_event_settled (st : ExtendableEventState) : bool :=
  negb (is_dispatching st) && (pending_promises st =? 0).

(** Transition: ExtendableEvent::waitUntil(script_state, promise, exception_state) *)
Definition step_wait_until (st : ExtendableEventState) : option ExtendableEventState :=
  if can_wait_until st then
    Some (mkEventState
            (is_trusted st)
            (is_dispatching st)
            (has_timed_out st)
            (extend_lifetime (pending_promises st) 1)
            (dispatch_failed st))
  else
    None. (* Throws InvalidStateError DOMException *)

(** Transition: WaitUntilObserver::DidDispatchEvent (synchronous JS handler exits) *)
Definition step_did_dispatch (st : ExtendableEventState) : ExtendableEventState :=
  mkEventState
    (is_trusted st)
    false
    (has_timed_out st)
    (pending_promises st)
    (dispatch_failed st).

(** Transition: WaitUntilObserver::OnPromiseFulfilled / OnPromiseRejected *)
Definition step_settle_promise (st : ExtendableEventState) (outcome : PromiseOutcome)
  : ExtendableEventState :=
  let failed := match outcome with
                | Fulfilled => dispatch_failed st
                | Rejected  => true
                end in
  mkEventState
    (is_trusted st)
    (is_dispatching st)
    (has_timed_out st)
    (settle (pending_promises st))
    failed.

(** Transition: ServiceWorker timeout expiration *)
Definition step_timeout (st : ExtendableEventState) : ExtendableEventState :=
  mkEventState
    (is_trusted st)
    (is_dispatching st)
    true
    (pending_promises st)
    true.

(** ** 4. Trace Semantics for Background Push Processing *)

Inductive EventAction : Type :=
  | ActWaitUntil     : EventAction
  | ActDidDispatch   : EventAction
  | ActSettlePromise : PromiseOutcome -> EventAction
  | ActTimeout       : EventAction.

Definition step_action (st : ExtendableEventState) (act : EventAction)
  : ExtendableEventState :=
  match act with
  | ActWaitUntil =>
      match step_wait_until st with
      | Some st' => st'
      | None     => st (* Exception thrown; state remains unchanged *)
      end
  | ActDidDispatch         => step_did_dispatch st
  | ActSettlePromise outc  => step_settle_promise st outc
  | ActTimeout             => step_timeout st
  end.

Fixpoint run_trace (st : ExtendableEventState) (trace : list EventAction)
  : ExtendableEventState :=
  match trace with
  | []          => st
  | act :: rest => run_trace (step_action st act) rest
  end.

(** Structural invariant of WaitUntilObserver: pending_promises is never negative. *)
Definition valid_pending_invariant (st : ExtendableEventState) : Prop :=
  0 <= pending_promises st.
```

---

## 4. Concrete Theorems and Complete Rocq/Coq Proofs

The following theorems verify the exact mathematical properties of `extend_lifetime` and `settle`, the state machine invariants of `WaitUntilObserver`, the lifecycle extension guarantees during asynchronous promise chaining, and exact termination conditions. All proofs are complete with zero `Admitted` statements.

```coq
(** ** 5. Formal Theorems & Proofs *)

(** Theorem 1: Non-negativity preservation of extend_lifetime and settle. *)
Theorem extend_and_settle_nonneg :
  forall (pending : Z),
    0 <= pending ->
    0 <= extend_lifetime pending 1 /\ 0 <= settle pending.
Proof.
  intros pending Hnonneg.
  unfold extend_lifetime, settle.
  split; lia.
Qed.

(** Theorem 2: Exact cancellation of a single waitUntil extension followed by settlement. *)
Theorem extend_then_settle_identity :
  forall (pending : Z),
    0 <= pending ->
    settle (extend_lifetime pending 1) = pending.
Proof.
  intros pending Hnonneg.
  unfold extend_lifetime, settle.
  lia.
Qed.

(** Theorem 3: Underflow safety at zero (clamping property). *)
Theorem settle_zero_idempotent :
  settle 0 = 0.
Proof.
  unfold settle.
  lia.
Qed.

(** Theorem 4: Exact algebraic characterization of n settlements. *)
Theorem settle_n_exact :
  forall (n : nat) (pending : Z),
    0 <= pending ->
    settle_n pending n = Z.max 0 (pending - Z.of_nat n).
Proof.
  induction n as [| n' IH]; intros pending Hnonneg.
  - simpl. lia.
  - simpl. rewrite IH by assumption.
    unfold settle.
    lia.
Qed.

(** Theorem 5: N extensions followed by N settlements restores the exact count. *)
Theorem extend_n_settle_n_cancel :
  forall (n : nat) (pending : Z),
    0 <= pending ->
    settle_n (pending + Z.of_nat n) n = pending.
Proof.
  intros n pending Hnonneg.
  rewrite settle_n_exact by lia.
  lia.
Qed.

(** Theorem 6: Chained waitUntil inside an existing waitUntil promise callback
    succeeds even after synchronous event dispatch has completed (is_dispatching = false). *)
Theorem async_chained_wait_until_succeeds :
