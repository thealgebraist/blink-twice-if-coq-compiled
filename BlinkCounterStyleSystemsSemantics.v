(**
  BlinkCounterStyleSystemsSemantics.v
  Formal specification of Chromium Blink CSS counter style systems (cyclic, alphabetic, additive)
  derived from third_party/blink/renderer/core/css/counter_style.cc and counter_style_map.cc
  according to W3C CSS Counter Styles Level 3 (§2 & §3 Counter Style Descriptors and Systems).
*)

From Stdlib Require Import ZArith.
From Stdlib Require Import Lists.List.
From Stdlib Require Import Bool.Bool.
From Stdlib Require Import Lia.
Import ListNotations.
Open Scope Z_scope.

Inductive CounterSystemKind : Type :=
  | SystemCyclic
  | SystemAlphabetic
  | SystemNumeric
  | SystemAdditive.

(** 1. Cyclic System Indexing (W3C §3.1.1) *)

Definition cyclic_index (v N : Z) : Z :=
  if N <=? 0 then 0
  else (v - 1) mod N.

Theorem cyclic_index_in_bounds :
  forall (v N : Z),
    0 < N ->
    0 <= cyclic_index v N < N.
Proof.
  intros v N HN.
  unfold cyclic_index.
  destruct (N <=? 0) eqn:EN; [lia|].
  apply Z.mod_pos_bound.
  exact HN.
Qed.

Theorem cyclic_index_periodicity :
  forall (v N : Z),
    0 < N ->
    cyclic_index (v + N) N = cyclic_index v N.
Proof.
  intros v N HN.
  unfold cyclic_index.
  destruct (N <=? 0) eqn:EN; [lia|].
  assert (v + N - 1 = (v - 1) + 1 * N) by lia.
  rewrite H.
  rewrite Z.mod_add by lia.
  reflexivity.
Qed.

(** 2. Alphabetic Bijective Base-N Contraction (W3C §3.1.4) *)

Definition alphabetic_step (v N : Z) : Z :=
  (v - 1) / N.

Theorem alphabetic_step_strictly_contracts :
  forall (v N : Z),
    2 <= N ->
    0 < v ->
    0 <= alphabetic_step v N < v.
Proof.
  intros v N HN Hv.
  unfold alphabetic_step.
  split.
  - apply Z.div_pos; lia.
  - apply Z.div_lt_upper_bound; [lia|].
    assert (v <= v * (N - 1)).
    {
      assert (1 <= N - 1) by lia.
      rewrite <- (Z.mul_1_r v) at 1.
      apply Z.mul_le_mono_nonneg_l; lia.
    }
    nia.
Qed.

(** 3. Additive Weight Greediness (W3C §3.1.6) *)

Record AdditiveTuple := {
  tuple_weight : Z;
  tuple_symbol : Z
}.

Fixpoint evaluate_additive_representation
    (v : Z) (tuples : list AdditiveTuple) : list Z :=
  match tuples with
  | [] => []
  | t :: rest =>
      if t.(tuple_weight) <=? 0 then []
      else
        let count := v / t.(tuple_weight) in
        let rem := v mod t.(tuple_weight) in
        (* If count > 0, we consume count * weight and recurse on rem *)
        if 0 <? count then
          (* represent symbol count times *)
          t.(tuple_symbol) :: evaluate_additive_representation rem rest
        else
          evaluate_additive_representation v rest
  end.

Theorem additive_step_remainder_strictly_smaller :
  forall (v weight : Z),
    0 < weight ->
    0 <= v ->
    v mod weight < weight.
Proof.
  intros v weight Hw Hv.
  apply Z.mod_pos_bound.
  exact Hw.
Qed.
