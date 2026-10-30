(******************************************************************************)
(* Synthesized by Blink2Coq: Blink Shadow Visual Outsets Formalization       *)
(******************************************************************************)

Require Import ZArith.
Require Import Bool.
Require Import Lia.
Open Scope Z_scope.

Record Outsets := mkOutsets {
  out_top : Z;
  out_right : Z;
  out_bottom : Z;
  out_left : Z
}.

Definition compute_shadow_outset_1d (spread blur offset : Z) (is_positive_edge : bool) : Z :=
  let extent := spread + blur in
  let delta := if is_positive_edge then extent + offset else extent - offset in
  Z.max 0 delta.

Definition shadow_outsets (style : Z) (spread blur off_x off_y : Z) : Outsets :=
  if style =? 1 then
    mkOutsets 0 0 0 0
  else
    mkOutsets
      (compute_shadow_outset_1d spread blur off_y false)
      (compute_shadow_outset_1d spread blur off_x true)
      (compute_shadow_outset_1d spread blur off_y true)
      (compute_shadow_outset_1d spread blur off_x false).

Definition union_outsets (o1 o2 : Outsets) : Outsets :=
  mkOutsets
    (Z.max (out_top o1) (out_top o2))
    (Z.max (out_right o1) (out_right o2))
    (Z.max (out_bottom o1) (out_bottom o2))
    (Z.max (out_left o1) (out_left o2)).

Theorem shadow_inset_zero_expansion :
  forall (spread blur off_x off_y : Z),
    shadow_outsets 1 spread blur off_x off_y = mkOutsets 0 0 0 0.
Proof.
  intros. unfold shadow_outsets. simpl. reflexivity.
Qed.

Theorem union_outsets_idem :
  forall (o : Outsets),
    union_outsets o o = o.
Proof.
  intros [t r b l].
  unfold union_outsets. simpl.
  rewrite !Z.max_id.
  reflexivity.
Qed.

Theorem union_outsets_comm :
  forall (o1 o2 : Outsets),
    union_outsets o1 o2 = union_outsets o2 o1.
Proof.
  intros [t1 r1 b1 l1] [t2 r2 b2 l2].
  unfold union_outsets. simpl.
  rewrite !(Z.max_comm t1 t2).
  rewrite !(Z.max_comm r1 r2).
  rewrite !(Z.max_comm b1 b2).
  rewrite !(Z.max_comm l1 l2).
  reflexivity.
Qed.

Theorem compute_shadow_outset_1d_nonneg :
  forall (spread blur offset : Z) (is_pos : bool),
    0 <= compute_shadow_outset_1d spread blur offset is_pos.
Proof.
  intros. unfold compute_shadow_outset_1d.
  apply Z.le_max_l.
Qed.
