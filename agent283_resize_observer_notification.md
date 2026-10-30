### Audit Report: Agent 283
**Target:** Chromium Blink `ResizeObserver` Notification Semantics (`third_party/blink/renderer/core/resize_observer/`) vs. W3C Resize Observer 1 Specification §3 (ResizeObservation & Notification Model).

---

### 1. Change Condition Analysis

In the W3C Resize Observer 1 Specification (§3.2 `ResizeObservation`), an observation is determined to have an active change via the `hasActiveObservations` step, which compares the current observed box size against the last reported size (`lastReportedSizes`). 

In Chromium Blink (`ResizeObservation::ObservationSizeOutOfSync`), this check is implemented by comparing the newly computed `LayoutSize` (or ` LogicalSize` depending on the observed box model) against `observation_size_`.

The discrete boolean condition governing whether a dimension update triggers a notification is formally captured by:
$$\text{has\_changed}(w_{\text{old}}, h_{\text{old}}, w_{\text{new}}, h_{\text{new}}) \equiv (w_{\text{old}} \neq_? w_{\text{new}}) \lor (h_{\text{old}} \neq_? h_{\text{new}})$$

---

### 2. Core Invariants

1. **Soundness & Completeness of Notification Firing:** A `ResizeObserverEntry` notification is populated and queued for firing in the current broadcast cycle **if and only if** at least one tracked dimension (width or height) differs from the previously recorded state.
2. **Idempotence under Stability:** If an element undergoes a style or layout recalculation that preserves its exact pixel/layout dimensions ($w_{\text{old}} = w_{\text{new}} \land h_{\text{old}} = h_{\text{new}}$), the observer remains dormant (`ObservationSizeOutOfSync() == false`).
3. **Post-Notification State Synchronization:** Immediately upon queuing a notification, the internal tracking state updates to $(w_{\text{new}}, h_{\text{new}})$, guaranteeing that subsequent passes within the same or future frames do not re-fire unless another dimensional mutation occurs.

---

### 3. Formal Verification (`BlinkResizeObserverNotificationSemantics.v`)

The following Rocq (Coq) script formalizes the Blink notification semantics and proves the required invariants with **0 admits**.

```coq
(** * BlinkResizeObserverNotificationSemantics.v
    Formal Audit by Agent 283: Chromium Blink ResizeObserver Notification
    vs W3C Resize Observer 1 Specification §3. *)

From Coq Require Import Arith.PeanoNat.
From Coq Require Import Bool.Bool.

Module BlinkResizeObserverNotificationSemantics.

  (** ** 1. Change Condition Definition *)

  (** Boolean inequality on natural numbers (representing discrete layout units). *)
  Definition neqb (n m : nat) : bool :=
    negb (Nat.eqb n m).

  Infix "!=?" := neqb (at level 70, no associativity).

  (** The core change detection predicate used in Blink's
      [ResizeObservation::ObservationSizeOutOfSync]. *)
  Definition has_changed (old_w old_h new_w new_h : nat) : bool :=
    (old_w !=? new_w) || (old_h !=? new_h).

  (** ** 2. State Machine & Notification Model *)

  Record ObservationState := mkState {
    last_w : nat;
    last_h : nat
  }.

  Inductive NotificationResult :=
  | Fired (updated_state : ObservationState) (reported_w reported_h : nat)
  | Suppressed (unchanged_state : ObservationState).

  (** Models a single evaluation pass of the ResizeObserver step. *)
  Definition evaluate_observation (st : ObservationState) (new_w new_h : nat) : NotificationResult :=
    if has_changed (last_w st) (last_h st) new_w new_h then
      Fired (mkState new_w new_h) new_w new_h
    else
      Suppressed st.

  (** Helper predicate: did the evaluation result in a notification firing? *)
  Definition is_fired (res : NotificationResult) : bool :=
    match res with
    | Fired _ _ _ => true
    | Suppressed _ => false
    end.

  (** ** 3. Auxiliary Lemmas *)

  Lemma neqb_spec : forall n m : nat,
    (n !=? m) = true <-> n <> m.
  Proof.
    intros n m. unfold neqb.
    rewrite negb_true_iff.
    rewrite Nat.eqb_neq.
    reflexivity.
  Qed.

  Lemma neqb_false_spec : forall n m : nat,
    (n !=? m) = false <-> n = m.
  Proof.
    intros n m. unfold neqb.
    rewrite negb_false_iff.
    rewrite Nat.eqb_eq.
    reflexivity.
  Qed.

  (** ** 4. Main Invariant Theorems *)

  (** Theorem 1: Soundness and Completeness of [has_changed].
      [has_changed] evaluates to true if and only if at least one dimension changes. *)
  Theorem has_changed_iff_dimension_changed :
    forall old_w old_h new_w new_h : nat,
      has_changed old_w old_h new_w new_h = true <->
      (old_w <> new_w \/ old_h <> new_h).
  Proof.
    intros old_w old_h new_w new_h.
    unfold has_changed.
    rewrite orb_true_iff.
    rewrite neqb_spec, neqb_spec.
    reflexivity.
  Qed.

  (** Theorem 2: Silence under Dimensional Stability.
      [has_changed] evaluates to false if and only if both dimensions remain identical. *)
  Theorem has_changed_false_iff_unchanged :
    forall old_w old_h new_w new_h : nat,
      has_changed old_w old_h new_w new_h = false <->
      (old_w = new_w /\ old_h = new_h).
  Proof.
    intros old_w old_h new_w new_h.
    unfold has_changed.
    rewrite orb_false_iff.
    rewrite neqb_false_spec, neqb_false_spec.
    reflexivity.
  Qed.

  (** Theorem 3: Primary Audit Invariant.
      A notification is fired if and only if at least one dimension changes. *)
  Theorem notification_fired_iff_changed :
    forall (st : ObservationState) (new_w new_h : nat),
      is_fired (evaluate_observation st new_w new_h) = true <->
      (last_w st <> new_w \/ last_h st <> new_h).
  Proof.
    intros st new_w new_h.
    unfold evaluate_observation, is_fired.
    destruct (has_changed (last_w st) (last_h st) new_w new_h) eqn:Hchg.
    - split; intros _.
      + apply has_changed_iff_dimension_changed. exact Hchg.
      + reflexivity.
    - split; intros H.
      + discriminate H.
      + apply has_changed_iff_dimension_changed in H.
        rewrite H in Hchg. discriminate Hchg.
  Qed.

  (** Theorem 4: Post-Notification Synchronization Idempotence.
      Once an observation is evaluated against (new_w, new_h), an immediate
      subsequent evaluation with the same (new_w, new_h) is guaranteed to be suppressed. *)
  Theorem post_notification_quiescence :
    forall (st : ObservationState) (new_w new_h : nat),
      let st' := match evaluate_observation st new_w new_h with
                 | Fired u _ _ => u
                 | Suppressed u => u
                 end in
      is_fired (evaluate_observation st' new_w new_h) = false.
  Proof.
    intros st new_w new_h st'.
    unfold st', evaluate_observation.
    destruct (has_changed (last_w st) (last_h st) new_w new_h) eqn:Hchg.
    - simpl. unfold has_changed, neqb.
      rewrite Nat.eqb_refl, Nat.eqb_refl.
      simpl. reflexivity.
    - apply has_changed_false_iff_unchanged in Hchg.
      destruct Hchg as [Hw Hh].
      unfold has_changed, neqb.
      rewrite Hw, Hh.
      rewrite Nat.eqb_refl, Nat.eqb_refl.
      simpl. reflexivity.
  Qed.

End BlinkResizeObserverNotificationSemantics.
```