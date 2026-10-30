# Formal Verification Report: W3C Payment Request `complete()` Terminal State Transition

**Agent ID:** 631 (Web Payments, Autofill & Form Normalization)  
**Chromium Source:** `third_party/blink/renderer/modules/payments/payment_response.cc`  
**Specification:** W3C Payment Request API §6.2 `PaymentResponse.complete(result)`  
**Formal Theory Target:** `BlinkPaymentResponseCompleteStatusSemantics.v`  
**Mathematical Property:** $\text{complete}(\sigma, r)$ deterministically transitions the payment state machine from $\text{Responding}$ to $\text{Closed}$, and strictly rejects any subsequent invocations ($\text{cannot complete twice}$).

---

## 1. Normative W3C Payment Request Specification Requirements

In the W3C Payment Request API specification (§6.2 `complete()` method), when the merchant calls `response.complete(result)` after receiving a `PaymentResponse` from `request.show()`, the user agent must execute an atomic state transition to finalize the payment transaction UI.

### 1.1 Internal Slots and State Model
A `PaymentRequest` instance and its associated `PaymentResponse` govern the lifecycle using internal slots:
*   `request.[[state]]`: Can be `"created"`, `"interactive"`, or `"closed"`.
*   `response.[[complete]]`: A boolean internal slot initialized to `false` when the `PaymentResponse` is constructed.
*   `request.[[updating]]`: A boolean flag indicating whether an asynchronous `PaymentRequestUpdateEvent` or `PaymentMethodChangeEvent` is currently being processed.

### 1.2 Normative Algorithm for `complete(result)`
According to W3C Payment Request API §6.2:
1. Let `response` be the `PaymentResponse` object on which the method is called.
2. Let `request` be `response.[[request]]`.
3. If `response.[[complete]]` is `true`, return a promise rejected with an `"InvalidStateError"` `DOMException`.
4. If `request.[[state]]` is not `"interactive"`, or `request.[[updating]]` is `true` (meaning the user agent is waiting for an update or retry promise to settle), return a promise rejected with an `"InvalidStateError"` `DOMException`.
5. Set `response.[[complete]]` to `true`.
6. Set `request.[[state]]` to `"closed"`.
7. Process `result` (`"success"`, `"fail"`, `"unknown"`) to close down the native payment sheet UI and resolve the returned promise with `undefined`.

For the `PaymentResponse` sub-machine, the combination of `(request.[[state]] == "interactive" && !request.[[updating]] && !response.[[complete]])` represents the **`Responding`** state. Transitioning `response.[[complete]] = true` and `request.[[state]] = "closed"` moves the system irreversibly into the **`Closed`** terminal state (unless explicitly reopened via `retry()`, which is outside the scope of `complete()`).

---

## 2. Chromium Blink Implementation & Invariants

In Chromium's Blink rendering engine, the state machine for `PaymentResponse` is orchestrated across `PaymentResponse` (`payment_response.cc`) and `PaymentRequest` (`payment_request.cc`, which implements `PaymentCompleter` and `PaymentStateResolver`).

### 2.1 Source Architecture in `payment_response.cc`
```cpp
// third_party/blink/renderer/modules/payments/payment_response.cc

ScriptPromise<IDLUndefined> PaymentResponse::complete(
    ScriptState* script_state,
    const V8PaymentComplete& result,
    ExceptionState& exception_state) {
  PaymentStateResolver::PaymentComplete converted_result =
       PaymentStateResolver::PaymentComplete::kUnknown;
  switch (result.AsEnum()) {
    case V8PaymentComplete::Enum::kUnknown:
      converted_result = PaymentStateResolver::PaymentComplete::kUnknown;
      break;
    case V8PaymentComplete::Enum::kSuccess:
      converted_result = PaymentStateResolver::PaymentComplete::kSuccess;
      break;
    case V8PaymentComplete::Enum::kFail:
      converted_result = PaymentStateResolver::PaymentComplete::kFail;
      break;
  }
  return payment_state_resolver_->Complete(script_state, converted_result,
                                           exception_state);
}
```

### 2.2 State Resolution Invariants in `PaymentStateResolver` (`PaymentRequest`)
`payment_state_resolver_` points directly to the owning `PaymentRequest` instance. Inside `PaymentRequest::Complete`:
1. **Precondition Verification**: Blink checks the internal completion and lifecycle flags:
   * If `complete_resolver_` is already non-null (a completion is already in-flight) or the state is already `kClosed` (`complete_called_` is true), Blink throws `DOMExceptionCode::kInvalidStateError` (`"Cannot call complete() twice"` or `"Invalid state"`).
   * If `retry_resolver_` is active (the response is currently retrying rather than waiting in the `Responding` state), it rejects with `kInvalidStateError`.
2. **State Mutation**:
   * Transitions the internal state from `Responding` to `Closed` (or marks `complete_resolver_` active and `is_waiting_for_merchant_validation_` false, immediately locking out further `complete()` or `retry()` calls).
   * Sends the IPC message `payment_provider_->Complete( PaymentComplete(result) )` over Mojo to the browser process.

### 2.3 Key Blink Invariants
* **Invariant 1 (Single Completion):** At most one call to `complete()` can succeed during a `Responding` lifecycle phase.
* **Invariant 2 (Terminal Absorbing State):** Once `complete()` transitions the state to `Closed`, the state machine is absorbed into `Closed` with respect to `complete()`. No choice of `PaymentComplete` enum (`kSuccess`, `kFail`, `kUnknown`) can keep the state in `Responding`.
* **Invariant 3 (Monotonic Completion Counter):** The number of successful completions in any execution trace of `complete()` calls without intervening `retry()` calls is bounded above by $1$.

---

## 3. Formal Specification in Rocq / Coq

Below is the self-contained formalization of `BlinkPaymentResponseCompleteStatusSemantics.v`. It models the `PaymentResponse` state machine, the `PaymentComplete` result enumeration, DOM exceptions, state transitions, and multi-step execution traces.

```coq
(** * BlinkPaymentResponseCompleteStatusSemantics.v
    Formal verification of W3C Payment Request API §6.2 PaymentResponse.complete()
    and Chromium Blink third_party/blink/renderer/modules/payments/payment_response.cc *)

From Coq Require Import Bool.Bool.
From Coq Require Import Arith.Arith.
From Coq Require Import ZArith.ZArith.
From Coq Require Import Lists.List.
From Coq Require Import micromega.Lia.
Import ListNotations.

Open Scope Z_scope.

(** ** 1. Data Types and State Model *)

(** W3C PaymentComplete enum (§6.3) / Blink PaymentStateResolver::PaymentComplete *)
Inductive PaymentCompleteResult : Type :=
  | CompleteSuccess : PaymentCompleteResult
  | CompleteFail    : PaymentCompleteResult
  | CompleteUnknown : PaymentCompleteResult.

(** Lifecycle state of PaymentResponse / PaymentStateResolver *)
Inductive ResponseLifecycleState : Type :=
  | StateCreated    : ResponseLifecycleState
  | StateResponding : ResponseLifecycleState
  | StateRetrying   : ResponseLifecycleState
  | StateClosed     : ResponseLifecycleState.

(** Equality decider for ResponseLifecycleState *)
Definition state_eqb (s1 s2 : ResponseLifecycleState) : bool :=
  match s1, s2 with
  | StateCreated, StateCreated       => true
  | StateResponding, StateResponding => true
  | StateRetrying, StateRetrying     => true
  | StateClosed, StateClosed         => true
  | _, _                             => false
  end.

Lemma state_eqb_eq : forall s1 s2 : ResponseLifecycleState,
  state_eqb s1 s2 = true <-> s1 = s2.
Proof.
  destruct s1, s2; simpl; split; intros H; try reflexivity; try discriminate.
Qed.

(** Exception codes modeled after Blink DOMExceptionCode *)
Inductive ExceptionCode : Type :=
  | InvalidStateError : ExceptionCode.

(** Outcome of a Promise-returning Blink IDL method *)
Inductive PromiseOutcome (T : Type) : Type :=
  | PromiseResolved : T -> PromiseOutcome T
  | PromiseRejected : ExceptionCode -> PromiseOutcome T.

Arguments PromiseResolved {T} _.
Arguments PromiseRejected {T} _.

(** Complete state of the PaymentResponse & owning PaymentStateResolver *)
Record PaymentResponseState : Type := mkPaymentResponseState {
   lifecycle_state : ResponseLifecycleState;
   complete_called : bool;
   mojo_complete_sent : Z; (* Counts Mojo IPC Complete() invocations *)
   last_result : option PaymentCompleteResult
}.

(** Initial state when PaymentResponse is constructed upon PaymentRequest.show() resolution *)
Definition init_responding_state : PaymentResponseState := {|
  lifecycle_state := StateResponding;
  complete_called := false;
  mojo_complete_sent := 0;
  last_result := None
|}.

(** Well-formedness invariant of the Blink PaymentResponse state *)
Definition wf_response_state (st : PaymentResponseState) : Prop :=
  (st.(complete_called) = true -> st.(lifecycle_state) = StateClosed) /\
  (st.(lifecycle_state) = StateResponding -> st.(complete_called) = false) /\
  (st.(mojo_complete_sent) = 0 \/ st.(mojo_complete_sent) = 1) /\
  (st.(mojo_complete_sent) = 1 <-> st.(complete_called) = true).

(** ** 2. Transition Semantics of PaymentResponse::complete(result) *)

(** Pure transition function representing Blink's PaymentResponse::complete
    delegating to PaymentRequest::Complete *)
Definition blink_payment_response_complete
  (st : PaymentResponseState)
  (res : PaymentCompleteResult)
  : PaymentResponseState * PromiseOutcome unit :=
  if st.(complete_called) then
    (st, PromiseRejected InvalidStateError)
  else
    match st.(lifecycle_state) with
    | StateResponding =>
        let st' := {|
          lifecycle_state := StateClosed;
          complete_called := true;
          mojo_complete_sent := st.(mojo_complete_sent) + 1;
          last_result := Some res
        |} in
        (st', PromiseResolved tt)
    | _ =>
        (st, PromiseRejected InvalidStateError)
    end.

(** Multi-step execution of a sequence of complete() calls *)
Fixpoint exec_complete_trace
  (st : PaymentResponseState)
  (calls : list PaymentCompleteResult)
  : PaymentResponseState * list (PromiseOutcome unit) :=
  match calls with
  | [] => (st, [])
  | r :: rest =>
      let (st', out) := blink_payment_response_complete st r in
      let (st_final, outs) := exec_complete_trace st' rest in
      (st_final, out :: outs)
  end.

(** Predicate checking if a PromiseOutcome is resolved *)
Definition is_resolved {T : Type} (o : PromiseOutcome T) : bool :=
  match o with
  | PromiseResolved _ => true
  | PromiseRejected _ => false
  end.

(** Count how many outcomes in a trace succeeded (resolved) *)
Fixpoint count_resolved (outs : list (PromiseOutcome unit)) : Z :=
  match outs with
  | [] => 0
  | o :: rest => (if is_resolved o then 1 else 0) + count_resolved rest
  end.
```

---

## 4. Concrete Theorems and Complete Mechanized Proofs

We now state and prove the core correctness theorems establishing that:
1. `complete(state, res)` transitions from `Responding` to `Closed`.
2. `complete()` cannot succeed twice (a second call is guaranteed to reject with `InvalidStateError` and leave the state unchanged).
3. The well-formedness invariant `wf_response_state` is preserved across arbitrary transition sequences.
4. For any arbitrary trace of $N$ `complete()` calls starting from a well-formed state, the number of resolved promises is at most $1$, and the Mojo IPC channel receives at most $1$ `Complete` message.

```coq
(** ** 3. Formal Verification Theorems & Proofs *)

(** Theorem 1: Initial Responding state satisfies the well-formedness invariant. *)
Theorem init_responding_state_wf :
  wf_response_state init_responding_state.
Proof.
  unfold wf_response_state, init_responding_state; simpl.
  repeat split; intros H; try discriminate; try reflexivity; lia.
Qed.

(** Theorem 2: Calling complete() from a well-formed Responding state transitions
    deterministically to Closed, marks complete_called = true, and resolves the promise. *)
Theorem complete_transitions_responding_to_closed :
  forall (st : PaymentResponseState) (res : PaymentCompleteResult),
    wf_response_state st ->
    st.(lifecycle_state) = StateResponding ->
    exists st',
      blink_payment_response_complete st res = (st', PromiseResolved tt) /\
      st'.(lifecycle_state) = StateClosed /\
      st'.(complete_called) = true /\
      st'.(last_result) = Some res /\
      st'.(mojo_complete_sent) = 1.
Proof.
  intros st res Hwf Hresp.
  destruct Hwf as [Hcc_closed [Hresp_cc [Hmojo_bound Hmojo_iff]]].
  pose proof (Hresp_cc Hresp) as Hcc_false.
  unfold blink_payment_response_complete.
  rewrite Hcc_false.
  rewrite Hresp.
  eexists.
  repeat split; simpl.
  assert (st.(mojo_complete_sent) = 0) as Hmojo0.
  { destruct Hmojo_bound as [H0 | H1].
    - exact H0.
    - apply Hmojo_iff in H1. congruence. }
  lia.
Qed.

(** Theorem 3: Calling complete() when already in StateClosed rejects with
    InvalidStateError and does not mutate state. *)
Theorem complete_in_closed_rejects_unchanged :
  forall (st : PaymentResponseState) (res : PaymentCompleteResult),
    st.(lifecycle_state) = StateClosed ->
    blink_payment_response_complete st res = (st, PromiseRejected InvalidStateError).
Proof.
  intros st res Hclosed.
  unfold blink_payment_response_complete.
  destruct (st.(complete_called)); [reflexivity |].
  rewrite Hclosed.
  reflexivity.
Qed.

(** Theorem 4: Cannot complete twice — any two consecutive calls to complete()
    from ANY state result in the second call being rejected with InvalidStateError
    and preserving the state produced by the first call. *)
Theorem cannot_complete_twice :
  forall (st st1 st2 : PaymentResponseState)
         (r1 r2 : PaymentCompleteResult)
         (out1 out2 : PromiseOutcome