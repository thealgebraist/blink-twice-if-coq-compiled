# Formal Verification Research Report: Screen Wake Lock API `WakeLockSentinel` Release Idempotence

**Agent ID:** 669  
**Specialization:** Web Platform File System, Streams, Shape Detection, and Platform Totality in Chromium Blink  
**Target Source:** `third_party/blink/renderer/modules/wake_lock/wake_lock_sentinel.cc`  
**Specification:** W3C Screen Wake Lock API §4 (`WakeLockSentinel` Interface)  
**Formal Theory Target:** `BlinkScreenWakeLockSentinelSemantics.v`  
**Mathematical Property:** $\forall s \in \text{State}, \text{release}(s).\text{released} = \text{true} \land \text{release}(\text{release}(s)) = \text{release}(s)$

---

## 1. Exact Normative W3C/WHATWG Specification Requirements

In the W3C Screen Wake Lock API specification, Section 4 defines the `WakeLockSentinel` interface, which represents an active wake lock handle acquired by a document.

### 1.1 Internal State and Attributes
A `WakeLockSentinel` object has an associated **`[[Released]]`** internal slot, which is a boolean initialized to `false` upon creation. The WebIDL interface exposes this slot via the readonly attribute:
* **`released`** (of type `boolean`, readonly): The `released` getter steps are to return `this.[[Released]]`.

### 1.2 The `release()` Method
When the `release()` method is invoked on a `WakeLockSentinel` instance, the specification mandates the following exact normative algorithm:
1. If `this.[[Released]]` is `false`, then run the **release a wake lock** algorithm with *document* set to `this`'s relevant settings object's responsible document, *lock* set to `this`, and *type* set to `this.[[Type]]`.
2. Return **a promise resolved with** `undefined`.

### 1.3 The "Release a Wake Lock" Algorithm
To **release a wake lock** for a given *document*, *lock*, and *type*:
1. If *document*'s `[[ActiveLocks]][type]` does not contain *lock*, abort these steps.
2. Remove *lock* from *document*'s `[[ActiveLocks]][type]`.
3. If *document*'s `[[ActiveLocks]][type]` is empty, then communicate to the underlying platform to release the system wake lock of *type*.
4. Set *lock*'s `[[Released]]` to `true`.
5. Fire an event named `"release"` at *lock*.

**Idempotence Requirement:** Because step 1 of `release()` guards the execution of "release a wake lock" on `this.[[Released]] == false`, and step 4 of "release a wake lock" transitions `this.[[Released]]` to `true` monotonically (no step in the specification ever sets `[[Released]]` back to `false`), subsequent calls to `release()` must act as pure no-ops on the state, merely returning a newly resolved promise with `undefined` without firing duplicate `"release"` events or mutating the active locks set.

---

## 2. Blink Implementation Details and Invariants

In Chromium's Blink rendering engine, the `WakeLockSentinel` interface is implemented in `third_party/blink/renderer/modules/wake_lock/wake_lock_sentinel.cc` and its corresponding header `wake_lock_sentinel.h`.

### 2.1 State Representation in Blink
In `WakeLockSentinel`, the specification's `[[Released]]` boolean slot and its association with the manager (`[[ActiveLocks]]`) are represented via a raw/Member pointer to the owning `WakeLockManager` and an explicit boolean flag:

```cpp
// third_party/blink/renderer/modules/wake_lock/wake_lock_sentinel.h
Member<WakeLockManager> manager_;
bool released_ = false;
```

### 2.2 Implementation of `release()` and `DoRelease()`
The C++ implementation splits the WebIDL entry point `release()` from the internal state transition `DoRelease()`:

```cpp
// third_party/blink/renderer/modules/wake_lock/wake_lock_sentinel.cc

ScriptPromise<IDLUndefined> WakeLockSentinel::release(ScriptState* script_state) {
  // Normative Step 1: If [[Released]] is false, run "release a wake lock".
  // Normative Step 2: Return a promise resolved with undefined.
  DoRelease();
  return ToResolvedUndefinedPromise(script_state);
}

bool WakeLockSentinel::released() const {
  return released_;
}

void WakeLockSentinel::DoRelease() {
  // Guard ensuring idempotence:
  if (released_)
    return;

  released_ = true;

  // Notify manager to remove from [[ActiveLocks]]
  if (manager_) {
    manager_->UnregisterSentinel(this);
    manager_.Clear();
  }

  // Normative Step 5 of "release a wake lock":
  // Only dispatch event if the execution context is still valid.
  if (GetExecutionContext() && !GetExecutionContext()->IsContextDestroyed()) {
    DispatchEvent(*Event::Create(event_type_names::kRelease));
  }
}
```

### 2.3 Blink Platform Invariants
1. **Pointer Clearing & Unregistration Coupling:** `manager_` is non-null if and only if `released_ == false` (prior to context destruction or garbage collection). Upon the first execution of `DoRelease()`, `manager_->UnregisterSentinel(this)` is called exactly once, and `manager_` is immediately cleared (`manager_ = nullptr`).
2. **Monotonicity of `released_`:** `released_` is initialized to `false` in the constructor and is only ever mutated in `DoRelease()`, where it is set to `true`.
3. **Event Dispatch Bound:** Because `DispatchEvent` is reachable only after passing the `if (released_) return;` guard and setting `released_ = true;`, the total number of `"release"` events dispatched over the lifetime of a `WakeLockSentinel` is bounded by $1$ ($\text{events\_fired} \le 1$).
4. **Synchronous State Transition:** Unlike asynchronous hardware operations, `DoRelease()` transitions `released_` to `true` synchronously before returning the resolved promise.

---

## 3. Formal Specification Definitions in Rocq/Coq

We model the state space of `WakeLockSentinel`, its interaction with `WakeLockManager`, and the execution context lifecycle in Rocq (Coq).

* **Sentinel State (`SentinelState`):** Captures the boolean `released_` field, whether `manager_` is currently attached (`has_manager`), whether the execution context is alive (`context_alive`), the cumulative count of `"release"` events dispatched (`events_dispatched`), and the number of times `UnregisterSentinel` was invoked (`unregister_calls`).
* **Transition Functions:** `do_release` models `WakeLockSentinel::DoRelease()`, and `release_method` models `WakeLockSentinel::release(ScriptState*)`.

---

## 4. Concrete Theorems and Complete Rocq/Coq Proofs

The following self-contained Rocq file (`BlinkScreenWakeLockSentinelSemantics.v`) formalizes the Blink implementation and proves release post-conditions, strict state idempotence, side-effect bounds, and bisimulation with the W3C specification.

```coq
(** * BlinkScreenWakeLockSentinelSemantics.v
    Formal Verification of Chromium Blink WakeLockSentinel::release() Idempotence
    Source: third_party/blink/renderer/modules/wake_lock/wake_lock_sentinel.cc
    Specification: W3C Screen Wake Lock API §4
*)

Require Import Coq.Bool.Bool.
Require Import Coq.ZArith.ZArith.
Require Import Coq.Lists.List.
Require Import Coq.micromega.Lia.
Import ListNotations.

Open Scope Z_scope.

(** ** 1. Data Types and State Space *)

Inductive WakeLockType : Type :=
  | ScreenLock.

Inductive PromiseState : Type :=
  | ResolvedUndefined.

(** Represents the state of a Blink WakeLockSentinel instance and its observable side-effects. *)
Record SentinelState : Type := mkSentinelState {
  released : bool;
  has_manager : bool;
  context_alive : bool;
  lock_type : WakeLockType;
  events_dispatched : Z;
  unregister_calls : Z
}.

(** Initial state of a newly constructed WakeLockSentinel in Blink *)
Definition init_sentinel (ctx_alive : bool) (t : WakeLockType) : SentinelState :=
  mkSentinelState false true ctx_alive t 0 0.

(** Well-formedness invariant of the Blink C++ implementation:
    1. If released is true, manager_ must have been cleared (has_manager = false).
    2. Event count and unregister calls are non-negative and bounded by 1.
    3. If released is false, no events or unregistrations have occurred yet. *)
Definition blink_invariant (s : SentinelState) : Prop :=
  (s.(released) = true -> s.(has_manager) = false) /\
  (0 <= s.(events_dispatched) <= 1) /\
  (0 <= s.(unregister_calls) <= 1) /\
  (s.(released) = false -> s.(events_dispatched) = 0 /\ s.(unregister_calls) = 0).

(** ** 2. Blink Implementation Semantics (wake_lock_sentinel.cc) *)

(** Models `void WakeLockSentinel::DoRelease()` *)
Definition do_release (s : SentinelState) : SentinelState :=
  if s.(released) then
    s
  else
    let new_unreg :=
      if s.(has_manager) then s.(unregister_calls) + 1 else s.(unregister_calls) in
    let new_events :=
      if s.(context_alive) then s.(events_dispatched) + 1 else s.(events_dispatched) in
    mkSentinelState
      true          (* released_ = true *)
      false         (* manager_.Clear() *)
      s.(context_alive)
      s.(lock_type)
      new_events
      new_unreg.

(** Models `ScriptPromise<IDLUndefined> WakeLockSentinel::release(ScriptState*)` *)
Definition release_method (s : SentinelState) : (SentinelState * PromiseState) :=
  (do_release s, ResolvedUndefined).

(** Models multiple sequential calls to `DoRelease()` *)
Fixpoint do_release_n (n : nat) (s : SentinelState) : SentinelState :=
  match n with
  | O => s
  | S n' => do_release (do_release_n n' s)
  end.

(** ** 3. Core Verification Theorems *)

(** Theorem 1: Calling DoRelease always sets `released` to `true`. *)
Theorem do_release_sets_released :
  forall (s : SentinelState),
    (do_release s).(released) = true.
Proof.
  intros s.
  unfold do_release.
  destruct (released s) eqn:Hrel.
  - exact Hrel.
  - reflexivity.
Qed.

(** Theorem 2: Fundamental Idempotence of DoRelease:
    release(release(state)) = release(state) *)
Theorem do_release_idempotent :
  forall (s : SentinelState),
    do_release (do_release s) = do_release s.
Proof.
  intros s.
  unfold do_release at 1.
  rewrite do_release_sets_released.
  reflexivity.
Qed.

(** Theorem 3: Idempotence of the WebIDL `release()` method returning a Promise. *)
Theorem release_method_idempotent :
  forall (s : SentinelState),
    let (s1, p1) := release_method s in
    let (s2, p2) := release_method s1 in
    s2 = s1 /\ p2 = p1 /\ s1.(released) = true.
Proof.
  intros s.
  unfold release_method.
  repeat split.
  - apply do_release_idempotent.
  - apply do_release_sets_released.
Qed.

(** Theorem 4: Generalized N-step Idempotence for any n >= 1. *)
Theorem do_release_n_idempotent :
  forall (n : nat) (s : SentinelState),
    (n >= 1)%nat ->
    do_release_n n s = do_release s.
Proof.
  induction n as [| n' IH]; intros s Hge.
  - lia.
  - destruct n' as [| n''].
    + simpl. reflexivity.
    + simpl. rewrite IH by lia.
      apply do_release_idempotent.
Qed.

(** Theorem 5: Monotonicity of the `released` flag. *)
Theorem do_release_monotonic :
  forall (s : SentinelState),
    s.(released) = true ->
    do_release s = s.
Proof.
  intros s Hrel.
  unfold do_release.
  rewrite Hrel.
  reflexivity.
Qed.

(** Theorem 6: `DoRelease` always clears the manager pointer (`manager_.Clear()`). *)
Theorem do_release_clears_manager :
  forall (s : SentinelState),
    blink_invariant s ->
    (do_release s).(has_manager) = false.
Proof.
  intros s [Hmgr _].
  unfold do_release.
  destruct (released s) eqn:Hrel.
  - apply Hmgr. exact Hrel.
  - reflexivity.
Qed.

(** Theorem 7: Initialization establishes the Blink platform invariant. *)
Theorem init_establishes_invariant :
  forall (ctx_alive : bool) (t : WakeLockType),
    blink_invariant (init_sentinel ctx_alive t).
Proof.
  intros ctx_alive t.
  unfold blink_invariant, init_sentinel.
  simpl.
  repeat split; try lia; intros H; discriminate H.
Qed.

(** Theorem 8: `DoRelease` preserves the Blink platform invariant, proving that
    at most 1 "release" event is ever dispatched and `UnregisterSentinel` is
    called at most once across arbitrary invocations. *)
Theorem do_release_preserves_invariant :
  forall (s : SentinelState),
    blink_invariant s ->
    blink_invariant (do_release s).
Proof.
  intros s [Hmgr [Hev [Hunreg Hfalse]]].
  unfold do_release.
  destruct (released s) eqn:Hrel.
  - (* Case: Already released *)
    unfold blink_invariant.
    repeat split; try lia; auto.
  - (* Case: Not yet released *)
    destruct (Hfalse eq_refl) as [Hev0 Hunreg0].
    unfold blink_invariant.
    simpl.
    repeat split.
    + intros _. reflexivity.
    + destruct (context_alive s); lia.
    + destruct (context_alive s); lia.
    + destruct (has_manager s); lia.
    + destruct (has_manager s); lia.
    + intros Hcontra. discriminate Hcontra.
    + intros Hcontra. discriminate Hcontra.
Qed.

(** Theorem 9: Across any sequence of `n`