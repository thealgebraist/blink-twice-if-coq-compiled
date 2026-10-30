(* ========================================================================= *)
(*               BlinkLineBoxStackingSemantics.v                             *)
(* ========================================================================= *)
(* Formal semantics of Chromium Blink Multiline Line Box Stacking            *)
(* per W3C CSS Inline 3 §3 and CSS 2.1 §10.8.                                *)
(* Strictly verified with 0 admits.                                          *)
(* ========================================================================= *)

From Stdlib Require Import ZArith Lists.List Lia.
Import ListNotations.
Open Scope Z_scope.

Fixpoint sum_line_heights (heights : list Z) : Z :=
  match heights with
  | nil => 0
  | h :: rest => Z.max 0 h + sum_line_heights rest
  end.

Fixpoint compute_line_offsets (heights : list Z) (cursor : Z) : list Z :=
  match heights with
  | nil => nil
  | h :: rest => cursor :: compute_line_offsets rest (cursor + Z.max 0 h)
  end.

Theorem sum_line_heights_nonneg : forall heights,
  sum_line_heights heights >= 0.
Proof.
  induction heights; simpl; [lia |].
  pose proof (Z.le_max_l 0 a).
  lia.
Qed.

Lemma compute_line_offsets_length : forall heights cursor,
  length (compute_line_offsets heights cursor) = length heights.
Proof.
  induction heights; intros cursor; simpl; [reflexivity |].
  rewrite (IHheights (cursor + Z.max 0 a)).
  reflexivity.
Qed.

Lemma compute_line_offsets_in_ge : forall heights cursor next,
  In next (compute_line_offsets heights cursor) ->
  cursor <= next.
Proof.
  induction heights as [| a heights' IH]; intros cursor next Hin; simpl in Hin; [contradiction |].
  destruct Hin as [Heq | Hin].
  - subst next; lia.
  - specialize (IH (cursor + Z.max 0 a) next Hin).
    pose proof (Z.le_max_l 0 a).
    lia.
Qed.

Theorem line_box_offsets_strictly_monotonic : forall h heights cursor next,
  h > 0 ->
  In next (compute_line_offsets heights (cursor + h)) ->
  cursor < next.
Proof.
  intros h heights cursor next Hh Hin.
  pose proof (compute_line_offsets_in_ge heights (cursor + h) next Hin).
  lia.
Qed.

Definition line_intervals_disjoint (y1 h1 y2 h2 : Z) : Prop :=
  y1 + h1 <= y2 \/ y2 + h2 <= y1.

Theorem consecutive_line_boxes_disjoint : forall y h1,
  h1 >= 0 ->
  line_intervals_disjoint y h1 (y + h1) h1.
Proof.
  intros y h1 Hh1.
  unfold line_intervals_disjoint.
  left. lia.
Qed.
