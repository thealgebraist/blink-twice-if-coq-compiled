# Formal Verification Report: `PaymentRequest` Active Exclusivity Semantics
**Agent**: 638 (Web Payments, Autofill & Form Normalization)  
**Target Source**: `third_party/blink/renderer/modules/payments/payment_request.cc`  
**Specification**: W3C Payment Request API §5.2 (`show()` method)  
**Formal Theory Target**: `BlinkPaymentRequestActiveExclusivitySemantics.v`  
**Mathematical Property**: $\forall s \in \text{State}, \text{reachable}(s) \implies \text{active\_count}(s) \le 1$

---

## 1. Normative W3C Payment Request Specification Requirements

In the W3C Payment Request API specification, each `PaymentRequest` instance possesses an internal state machine (`[[state]]`) with values in `{"created", "interactive", "closed"}`. Furthermore, the User Agent (UA) maintains a global/browsing-context-level boolean flag **payment-relevant browsing context's payment request is showing**.

### 1.1. The `show()` Method (§5.2)
When `PaymentRequest.prototype.show(detailsPromise)` is invoked on a `request` object:
1. **State Precondition**: If `request.[[state]]` is not `"created"`, reject the returned promise with an `"InvalidStateError"` `DOMException`.
2. **Global Exclusivity Check**: If the **payment-relevant browsing context's payment request is showing** boolean is `true`:
   - Set `request.[[state]]` to `"closed"`.
   - Return a promise rejected with an `"AbortError"` `DOMException` (preventing concurrent payment sheets from spoofing or overlapping user consent UI).
3. **State Transition**:
   - Set `request.[[state]]` to `"interactive"`.
   - Set the **payment-relevant browsing context's payment request is showing** boolean to `true`.

### 1.2. The `abort()` Method (§5.3) & Resolution Lifecycle
When an interactive request settles (via user cancellation, `abort()` fulfillment, or payment response settlement/rejection):
1. `request.[[state]]` transitions from `"interactive"` to `"closed"`.
2. The **payment-relevant browsing context's payment request is showing** boolean is reset to `false`.

**Normative Invariant**: At any instant during the execution of the event loop, the cardinality of `PaymentRequest` instances where `[[state]] == "interactive"` within the same payment-relevant browsing context (or top-level WebContents in Chromium) is bounded above by $1$.

---

## 2. Blink Implementation Details and Invariants

In Chromium's Blink rendering engine (`third_party/blink/renderer/modules/payments/payment_request.cc` and `payment_request.h`), the W3C state machine and exclusivity invariants are enforced jointly by renderer-side state checks and Mojo IPC synchronization with the browser process (`components/payments/content/payment_request_ state/display_manager`).

### 2.1. Renderer State Representation (`payment_request.h`)
Blink defines the internal lifecycle state enumeration:
```cpp
enum State {
  kCreated,
  kInteractive,
  kClosed
};
State state_ = kCreated;
```
And tracks pending promises:
- `Member<ScriptPromiseResolver<PaymentResponse>> accept_resolver_;`
- `Member<ScriptPromiseResolver<IDLUndefined>> abort_resolver_;`

### 2.2. `PaymentRequest::show()` Execution (`payment_request.cc`)
In `PaymentRequest::show()`:
1. **Local State Verification**:
   ```cpp
   if (state_ != kCreated) {
     exception_state.ThrowDOMException(DOMExceptionCode::kInvalidStateError,
                                       "Already called show() once");
     return EmptyPromise();
   }
   ```
2. **Browser/Frame Context & User Activation**:
   Blink checks `DomWindow()` validity and user activation (`LocalFrame::ConsumeTransientUserActivation`). If activation is missing and isn't bypassed by `has_enrolled_instrument`, it rejects and transitions `state_ = kClosed`.
3. **Transition to `kInteractive` & Mojo Dispatch**:
   ```cpp
   state_ = kInteractive;
   accept_resolver_ = MakeGarbageCollected<ScriptPromiseResolver<PaymentResponse>>(script_state);
   payment_provider_->Show(is_user_gesture, wait_for_updated_details);
   ```
4. **Exclusivity Enforcement (`PaymentRequestDisplayManager` & `OnError`)**:
   In Chromium's architecture, if another `PaymentRequest` is already showing in the same `WebContents` or frame tree, the browser-side `PaymentRequestDisplayManager::TryShow()` rejects the handle creation, or the renderer/browser lock immediately rejects `show()` with ` PaymentErrorReason::ALREADY_SHOWING` (`kAlreadyShowing`), invoking `OnError()` which calls `ClearResolversAndCloseMojoConnection()`, transitioning `state_ = kClosed` and rejecting `accept_resolver_` with `DOMExceptionCode::kAbortError`.
   Synchronously within a single page context / renderer model, the `showing` lock prevents more than one request from remaining in `kInteractive`.

### 2.3. Teardown & `ClearResolversAndCloseMojoConnection()`
Every terminal pathway (`OnComplete()`, `OnAbort(true)`, `OnError()`, `ContextDestroyed()`) funnels through:
```cpp
void PaymentRequest::ClearResolversAndCloseMojoConnection() {
  state_ = kClosed;
  accept_resolver_.Clear();
  abort_resolver_.Clear();
  ...
}
```
This guarantees monotonic progression: `kCreated` $\to$ `kInteractive` $\to$ `kClosed` (or directly `kCreated` $\to$ `kClosed` on immediate `show()` rejection), and ensures the active lock is released upon leaving `kInteractive`.

---

## 3. Formal Specification & Verification in Rocq/Coq

Below is the self-contained, admitted-free Rocq/Coq formalization (`BlinkPaymentRequestActiveExclusivitySemantics.v`) modeling the `PaymentRequest` state machine, the browsing context exclusivity lock, all lifecycle transitions (`Create`, `Show`, `Abort`, `Settle`, `Error`), and proving the core invariant `active_count(s) <= 1`.

```coq
(** * BlinkPaymentRequestActiveExclusivitySemantics.v
    Formal verification of W3C Payment Request API §5.2 & Chromium Blink
    third_party/blink/renderer/modules/payments/payment_request.cc
    Property: active_count(state) <= 1
*)

From Coq Require Import Bool.Bool.
From Coq Require Import Arith.PeanoNat.
From Coq Require Import Lists.List.
From Coq Require Import micromega.Lia.
Import ListNotations.

Section PaymentRequestExclusivity.

  (** ** 1. Core Types and State Machine Definitions *)

  (** Unique identifier for a PaymentRequest instance *)
  Definition RequestId := nat.

  (** W3C PaymentRequest [[state]] / Blink PaymentRequest::State *)
  Inductive PRState : Type :=
  | Created : PRState
  | Interactive : PRState
  | Closed : PRState.

  Scheme Equality for PRState.

  (** Record representing an individual PaymentRequest instance in Blink *)
  Record PaymentRequestInstance : Type := mkPR {
    pr_id : RequestId;
    pr_state : PRState;
    pr_updating : bool (* [[updating]] flag for PaymentRequestUpdateEvent *)
  }.

  (** Global/Browsing-Context state modeling WebContents / Frame context *)
  Record SystemState : Type := mkSysState {
    requests : list PaymentRequestInstance;
    is_showing : bool; (** W3C: "payment request is showing" boolean *)
    next_id : RequestId
  }.

  (** Initial empty browsing context state *)
  Definition init_state : SystemState := {|
    requests := [];
    is_showing := false;
    next_id := 0
  |}.

  (** Predicate testing if a single PaymentRequest is active (kInteractive) *)
  Definition is_active (pr : PaymentRequestInstance) : bool :=
    match pr.(pr_state) with
    | Interactive => true
    | _ => false
    end.

  (** Count the number of active PaymentRequests in a list *)
  Fixpoint count_active_list (l : list PaymentRequestInstance) : nat :=
    match l with
    | [] => 0
    | pr :: tl => (if is_active pr then 1 else 0) + count_active_list tl
    end.

  (** Top-level active_count metric on SystemState *)
  Definition active_count (s : SystemState) : nat :=
    count_active_list s.(requests).

  (** ** 2. Operations (Blink payment_request.cc Methods) *)

  (** Lookup a request by ID *)
  Fixpoint find_request (id : RequestId) (l : list PaymentRequestInstance)
    : option PaymentRequestInstance :=
    match l with
    | [] => None
    | pr :: tl => if Nat.eqb pr.(pr_id) id then Some pr else find_request id tl
    end.

  (** Update a specific request in the list by ID *)
  Fixpoint update_request (id : RequestId) (new_state : PRState) (new_upd : bool)
                          (l : list PaymentRequestInstance) : list PaymentRequestInstance :=
    match l with
    | [] => []
    | pr :: tl =>
        if Nat.eqb pr.(pr_id) id then
          {| pr_id := pr.(pr_id); pr_state := new_state; pr_updating := new_upd |} :: tl
        else
          pr :: update_request id new_state new_upd tl
    end.

  (** 2.1. PaymentRequest::Create() -> new PaymentRequest() *)
  Definition op_create (s : SystemState) : SystemState :=
    let new_pr := {| pr_id := s.(next_id); pr_state := Created; pr_updating := false |} in
    {| requests := new_pr :: s.(requests);
       is_showing := s.(is_showing);
       next_id := S s.(next_id) |}.

  (** 2.2. PaymentRequest::show() (§5.2)
      - If state != Created, reject with InvalidStateError (no state change).
      - If is_showing == true, transition request to Closed and reject with AbortError.
      - Otherwise, transition request to Interactive and set is_showing := true. *)
  Definition op_show (id : RequestId) (s : SystemState) : SystemState :=
    match find_request id s.(requests) with
    | None => s
    | Some pr =>
        match pr.(pr_state) with
        | Created =>
            if s.(is_showing) then
              (* Exclusivity violation prevented: transition to Closed, is_showing remains true *)
              {| requests := update_request id Closed false s.(requests);
                 is_showing := s.(is_showing);
                 next_id := s.(next_id) |}
            else
              (* Exclusivity granted: transition to Interactive, set is_showing := true *)
              {| requests := update_request id Interactive false s.(requests);
                 is_showing := true;
                 next_id := s.(next_id) |}
        | _ => s (* InvalidStateError: state unchanged *)
        end
    end.

  (** 2.3. PaymentRequest::ClearResolversAndCloseMojoConnection()
      Triggered by OnAbort(true), OnComplete(), OnError(), or user cancellation.
      - If request is Interactive, transitions to Closed and resets is_showing := false. *)
  Definition op_close_interactive (id : RequestId) (s : SystemState) : SystemState :=
    match find_request id s.(requests) with
    | None => s
    | Some pr =>
        match pr.(pr_state) with
        | Interactive =>
            {| requests := update_request id Closed false s.(requests);
               is_showing := false;
               next_id := s.(next_id) |}
        | _ => s
        end
    end.

  (** 2.4. PaymentRequest::OnUpdatePaymentDetails()
      Updates the [[updating]] flag while remaining in Interactive state. *)
  Definition op_set_updating (id : RequestId) (upd : bool) (s : SystemState) : SystemState :=
    match find_request id s.(requests) with
    | None => s
    | Some pr =>
        match pr.(pr_state) with
        | Interactive =>
            if Bool.eqb pr.(pr_updating) false then
              {| requests := update_request id Interactive upd s.(requests);
                 is_showing := s.(is_showing);
                 next_id := s.(next_id) |}
            else s
        | _ => s
        end
    end.

  (** ** 3. Transition System and Reachability *)

  Inductive Action : Type :=
  | ActCreate : Action
  | ActShow (id : RequestId) : Action
  | ActClose (id : RequestId) : Action
  | ActSetUpdating (id : RequestId) (upd : bool) : Action.

  Definition step (a : Action) (s : SystemState) : SystemState :=
    match a with
    | ActCreate => op_create s
    | ActShow id => op_show id s
    | ActClose id => op_close_interactive id s
    | ActSetUpdating id upd => op_set_updating id upd s
    end.

  Inductive Reachable : SystemState -> Prop :=
  | ReachInit : Reachable init_state
  | ReachStep : forall s a, Reachable s -> Reachable (step a s).

  (** ** 4. Inductive Invariants and Auxiliary Lemmas *)

  (** Predicate: All request IDs in the list are strictly less than bound *)
  Fixpoint ids_below (bound : nat) (l : list PaymentRequestInstance) : Prop :=
    match l with
    | [] => True
    | pr :: tl => pr.(pr_id) < bound /\ ids_below bound tl
    end.

  (** Predicate: Request IDs in the list are pairwise distinct *)
  Fixpoint unique_ids (l : list PaymentRequestInstance) : Prop :=
    match l with
    | [] => True
    | pr :: tl => ids_below pr.(pr_id) tl /\ unique_ids tl
    end.

  (** Lemma: If all IDs in l are below bound, and id >= bound, find_request returns None *)
  Lemma find_request_above_bound : forall l bound id,
    ids_below bound l ->
    bound <= id ->
    find_request id l = None.
  Proof.
    induction l as [| pr tl IH]; intros bound id Hbelow Hle.
    - simpl. reflexivity.
    - simpl in *. destruct Hbelow as [Hlt Htl].
      destruct (Nat.eqb (pr_id pr) id) eqn:Heq.
      + apply Nat.eqb_eq in Heq. lia.
      + eapply IH; eauto.
  Qed.

  (** Lemma: Updating a non-existent ID leaves the list unchanged *)
  Lemma update_request_not_