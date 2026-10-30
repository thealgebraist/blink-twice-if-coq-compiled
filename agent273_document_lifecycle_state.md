### Agent 273 Audit Report: Chromium Blink Document Lifecycle vs. HTML Standard §7.13

**Target Component**: `third_party/blink/renderer/core/dom/document_lifecycle.h`  
**Specification Reference**: WHATWG HTML Standard §7.13 (*Event loop: Update the rendering*)  
**Verification Artifact**: `BlinkDocumentLifecycleStateSemantics.v`  

---

### 1. State Mapping & Architecture Analysis

HTML Standard §7.13 defines the rendering update phase of the event loop as a deterministic sequence of macro-steps (recalculating styles, updating layout/geometry, evaluating media queries, running resize/intersection observers, and painting/compositing). 

Chromium's Blink engine reifies this pipeline as a deterministic finite state machine managed by `blink::DocumentLifecycle`. To prevent re-entrancy bugs and layout thrashing during a render frame, Blink enforces strict state-transition invariants via runtime `DCHECK` assertions in `DocumentLifecycle::CanAdvanceTo` and `DocumentLifecycle::CanRewindTo`.

#### State Enumeration Mapping
For the formal verification subset, the lifecycle phases are mapped to an ordered discrete domain $\Sigma = \{0 \dots 7\}$:

| Index | Identifier | Blink `LifecycleState` Equivalent | HTML §7.13 Semantic Correspondence |
| :--- | :--- | :--- | :--- |
| `0` | `Unstyled` | `kVisualUpdatePending` / `kUninitialized` | Pre-render frame / dirty DOM awaiting style recalc. |
| `1` | `InStyleRecalc` | `kInStyleRecalc` | Active execution of CSS cascade and computed style resolution. |
| `2` | `StyleClean` | `kStyleClean` | Style trees synchronized; DOM mutations here invalidate back to `0`. |
| `3` | `InPerformLayout` | `kInPerformLayout` | Active execution of LayoutNG box tree generation & geometry calculation. |
| `4` | `LayoutClean` | `kLayoutClean` | Geometry finalized; queries like `offsetWidth` resolve without synchronous reflow. |
| `5` | `InCompositing` | `kInCompositingInputsUpdate` / `kCompositingClean` | Layerization, property tree building, and scroll/overlap analysis. |
| `6` | `InPaint` | `kInPrePaint` / `kInPaint` | Recording display lists (`cc::DisplayItemList`) and paint artifacts. |
| `7` | `PaintClean` | `kPaintClean` | Frame emission complete; ready for commit to Compositor Thread (`cc`). |

---

### 2. Core Invariants

1. **Strict Forward Frame Advancement (`AdvanceStep`)**: 
   During the forward execution of "Update the rendering" (specifically within `LocalFrameView::RunStyleAndLayoutLifecyclePhases` and `RunPaintLifecyclePhase`), state transitions must be strictly monotonic and sequential ($s \to s+1$). Transient processing states (`InStyleRecalc`, `InPerformLayout`, `InCompositing`, `InPaint`) cannot be skipped, nor can the machine remain stationary during an active transition.
2. **Intermediate Milestone Realization (No Phase Jumping)**:
   A document cannot reach `PaintClean` (7) from a dirty state ($\le 3$) during a render pass without explicitly passing through and establishing the `LayoutClean` (4) state. This guarantees that `cc` never rasterizes display lists backed by uncomputed or stale box geometry.

---

### 3. Formal Verification (`BlinkDocumentLifecycleStateSemantics.v`)

The following file is a complete, self-contained Rocq/Coq 8.18+ formalization. It uses standard library `Arith` and `Lia` tactics, requiring **0 `Admitted` or `Axiom` declarations**.

```coq
(** * BlinkDocumentLifecycleStateSemantics.v
    Formal verification of Chromium Blink DocumentLifecycle state transitions
    audited against WHATWG HTML Standard §7.13 (Update the rendering).
    Author: Agent 273
*)

From Coq Require Import Arith.PeanoNat.
From Coq Require Import Lists.List.
From Coq Require Import micromega.Lia.
Import ListNotations.

(** ** 1. Lifecycle State Definitions *)

Inductive LifecycleState : Type :=
  | Unstyled        (* 0 *)
  | InStyleRecalc   (* 1 *)
  | StyleClean      (* 2 *)
  | InPerformLayout (* 3 *)
  | LayoutClean     (* 4 *)
  | InCompositing   (* 5 *)
  | InPaint         (* 6 *)
  | PaintClean.     (* 7 *)

(** Mapping from LifecycleState to discrete numeric phase IDs. *)
Definition state_id (s : LifecycleState) : nat :=
  match s with
  | Unstyled        => 0
  | InStyleRecalc   => 1
  | StyleClean      => 2
  | InPerformLayout => 3
  | LayoutClean     => 4
  | InCompositing   => 5
  | InPaint         => 6
  | PaintClean      => 7
  end.

(** Decidable equality for LifecycleState. *)
Lemma state_eq_dec : forall (s1 s2 : LifecycleState), {s1 = s2} + {s1 <> s2}.
Proof.
  decide equality.
Defined.

(** Injectivity of state_id mapping. *)
Lemma state_id_inj : forall s1 s2, state_id s1 = state_id s2 -> s1 = s2.
Proof.
  destruct s1, s2; simpl; intro H; try reflexivity; discriminate H.
Qed.

(** Boundedness of state_id. *)
Lemma state_id_bound : forall s, state_id s <= 7.
Proof.
  destruct s; simpl; lia.
Qed.

(** ** 2. Transition Semantics *)

(** Single-step forward advancement during a render frame update.
    Models Blink's strict forward phase progression in LocalFrameView. *)
Inductive AdvanceStep : LifecycleState -> LifecycleState -> Prop :=
  | Step_ToInStyleRecalc   : AdvanceStep Unstyled InStyleRecalc
  | Step_ToStyleClean      : AdvanceStep InStyleRecalc StyleClean
  | Step_ToInPerformLayout : AdvanceStep StyleClean InPerformLayout
  | Step_ToLayoutClean     : AdvanceStep InPerformLayout LayoutClean
  | Step_ToInCompositing   : AdvanceStep LayoutClean InCompositing
  | Step_ToInPaint         : AdvanceStep InCompositing InPaint
  | Step_ToPaintClean      : AdvanceStep InPaint PaintClean.

(** State rewind transitions (invalidation outside of active rendering steps).
    Included for architectural completeness of DocumentLifecycle::CanRewindTo. *)
Inductive RewindStep : LifecycleState -> LifecycleState -> Prop :=
  | Rewind_StyleToUnstyled  : RewindStep StyleClean Unstyled
  | Rewind_LayoutToStyle    : RewindStep LayoutClean StyleClean
  | Rewind_LayoutToUnstyled : RewindStep LayoutClean Unstyled
  | Rewind_PaintToLayout    : RewindStep PaintClean LayoutClean
  | Rewind_PaintToStyle     : RewindStep PaintClean StyleClean
  | Rewind_PaintToUnstyled  : RewindStep PaintClean Unstyled.

(** Validexecution trace during a forward render frame pass.
    A trace is a non-empty list of states where each adjacent pair
    satisfies AdvanceStep. *)
Inductive ValidRenderTrace : list LifecycleState -> Prop :=
  | Trace_Single : forall s,
      ValidRenderTrace [s]
  | Trace_Step : forall s1 s2 rest,
      AdvanceStep s1 s2 ->
      ValidRenderTrace (s2 :: rest) ->
      ValidRenderTrace (s1 :: s2 :: rest).

(** Multi-step reflexive-transitive closure of AdvanceStep. *)
Inductive AdvanceStar : LifecycleState -> LifecycleState -> Prop :=
  | Star_Refl : forall s, AdvanceStar s s
  | Star_Step : forall s1 s2 s3,
      AdvanceStep s1 s2 ->
      AdvanceStar s2 s3 ->
      AdvanceStar s1 s3.

(** Multi-step strict (non-empty) transitive closure of AdvanceStep. *)
Inductive AdvancePlus : LifecycleState -> LifecycleState -> Prop :=
  | Plus_Single : forall s1 s2,
      AdvanceStep s1 s2 ->
      AdvancePlus s1 s2
  | Plus_Step : forall s1 s2 s3,
      AdvanceStep s1 s2 ->
      AdvancePlus s2 s3 ->
      AdvancePlus s1 s3.

(** ** 3. Proof of Invariant 1: Strict Monotonic Advancement *)

(** Theorem: Every single forward render step increments the state ID by exactly 1. *)
Theorem advance_step_exact_increment : forall s1 s2,
  AdvanceStep s1 s2 -> state_id s2 = S (state_id s1).
Proof.
  intros s1 s2 Hstep.
  inversion Hstep; simpl; reflexivity.
Qed.

(** Corollary: Every single forward render step strictly increases the state ID. *)
Theorem advance_step_strictly_monotonic : forall s1 s2,
  AdvanceStep s1 s2 -> state_id s1 < state_id s2.
Proof.
  intros s1 s2 Hstep.
  apply advance_step_exact_increment in Hstep.
  lia.
Qed.

(** Theorem: Any non-empty sequence of forward transitions strictly advances the phase. *)
Theorem advance_plus_strictly_monotonic : forall s1 s2,
  AdvancePlus s1 s2 -> state_id s1 < state_id s2.
Proof.
  intros s1 s2 Hplus.
  induction Hplus as [s1 s2 Hstep | s1 s2 s3 Hstep Hplus IH].
  - apply advance_step_strictly_monotonic; assumption.
  - apply advance_step_strictly_monotonic in Hstep.
    lia.
Qed.

(** Theorem: Reflexive-transitive forward transitions never decrease the state ID. *)
Theorem advance_star_monotonic : forall s1 s2,
  AdvanceStar s1 s2 -> state_id s1 <= state_id s2.
Proof.
  intros s1 s2 Hstar.
  induction Hstar as [s | s1 s2 s3 Hstep Hstar IH].
  - lia.
  - apply advance_step_strictly_monotonic in Hstep.
    lia.
Qed.

(** Theorem: Acyclicity of the render frame advancement pipeline. *)
Theorem advance_no_cycles : forall s,
  ~ AdvancePlus s s.
Proof.
  intros s Hcycle.
  apply advance_plus_strictly_monotonic in Hcycle.
  lia.
Qed.

(** ** 4. Proof of Invariant 2: Mandatory LayoutClean Milestone *)

(** Helper: Exact characterization of states by their numeric ID. *)
Lemma state_id_4_is_LayoutClean : forall s,
  state_id s = 4 -> s = LayoutClean.
Proof.
  intros s H.
  destruct s; simpl in H; try discriminate H; reflexivity.
Qed.

(** Discrete Intermediate Value Theorem for ValidRenderTrace:
    If a valid render trace starts at state [s_start] and ends at [s_end],
    then for any state [s_mid] whose ID lies between [s_start] and [s_end],
    [s_mid] must be present in the trace. *)
Lemma trace_intermediate_value : forall trace s_start s_end,
  ValidRenderTrace trace ->
  hd_error trace = Some s_start ->
  last trace s_start = s_end ->
  forall s_mid,
    state_id s_start <= state_id s_mid ->
    state_id s_mid <= state_id s_end ->
    In s_mid trace.
Proof.
  intros trace s_start s_end Htrace.
  revert s_start s_end.
  induction Htrace as [s | s1 s2 rest Hstep Htrace IH]; intros s_start s_end Hhd Hlast s_mid Hge Hle.
  - (* Base case: single element trace [s] *)
    simpl in Hhd. injection Hhd as Heq1. subst s_start.
    simpl in Hlast. subst s_end.
    assert (Hid : state_id s = state_id s_mid) by lia.
    apply state_id_inj in Hid. subst s_mid.
    simpl. left. reflexivity.
  - (* Inductive step: s1 :: s2 :: rest *)
    simpl in Hhd. injection Hhd as Heq1. subst s_start.
    assert (Hinc : state_id s2 = S (state_id s1)).
    { apply advance_step_exact_increment; assumption. }
    destruct (Nat.eq_dec (state_id s1) (state_id s_mid)) as [Heq_id | Hneq_id].
    + (* s_mid is the current head s1 *)
      apply state_id_inj in Heq_id. subst s_mid.
      simpl. left. reflexivity.
    + (* s_mid must lie in the tail (s2 :: rest) *)
      simpl. right.
      assert (Hlast_sub : last (s2 :: rest) s2 = s_end).
      { simpl in Hlast. destruct rest; simpl in *; assumption. }
      apply (IH s2 s_end eq_refl Hlast_sub s_mid).
      * lia.
      * assumption.
Qed.

(** Theorem: Cannot jump to PaintClean without passing LayoutClean.
    Any valid forward render trace starting from a pre-layout-clean state
    (Unstyled, InStyleRecalc, StyleClean, or InPerformLayout) that reaches
    PaintClean MUST contain LayoutClean as an intermediate state. *)
Theorem cannot_reach_PaintClean_without_LayoutClean : forall trace s_init,
  ValidRenderTrace trace ->
  hd_error trace = Some s_init ->
  last trace s_init = PaintClean ->
  state_id s_init <= state_id LayoutClean ->
  In LayoutClean trace.
Proof.
  intros trace s_init Htrace Hhd Hlast Hinit_le.
  apply (trace_intermediate_value trace s_init PaintClean Htrace Hhd Hlast LayoutClean).
  - exact Hinit_le.
  - simpl. lia.
Qed.

(** Alternative relational formulation of Invariant 2 over AdvanceStar:
    Any multi-step transition from a state with ID <= 4 to PaintClean
    factors through LayoutClean. *)
Theorem advance_star_factors_through_LayoutClean : forall s_init,
  state_id s_init <= state_id LayoutClean ->
  AdvanceStar s_init PaintClean ->
  AdvanceStar s_init LayoutClean /\ AdvanceStar LayoutClean PaintClean.
Proof.
  intros s_init Hle Hstar.
  remember PaintClean as s_target eqn:Heq_target.
  induction Hstar as [s | s1 s2 s3 Hstep Hstar IH].
  - (* Reflexive case: s = PaintClean, contradicts state_id s <= 4 *)
    subst s. simpl in Hle. lia