(* ========================================================================= *)
(*               BlinkClearanceComputationSemantics.v                        *)
(* ========================================================================= *)
(* Formal semantics of Chromium Blink CSS Clearance Computation               *)
(* per W3C CSS 2.1 §9.5.2.                                                   *)
(* Strictly verified with 0 admits.                                          *)
(* ========================================================================= *)

From Stdlib Require Import ZArith Lia.
Open Scope Z_scope.

Definition compute_clearance (float_bottom : Z) (block_y : Z) (margin_top : Z) : Z :=
  Z.max 0 (float_bottom - (block_y + margin_top)).

Definition cleared_block_y (float_bottom : Z) (block_y : Z) (margin_top : Z) : Z :=
  block_y + margin_top + compute_clearance float_bottom block_y margin_top.

Theorem clearance_nonneg : forall fb by_pos mt,
  compute_clearance fb by_pos mt >= 0.
Proof.
  intros. unfold compute_clearance.
  apply Z.le_ge, Z.le_max_l.
Qed.

Theorem cleared_block_past_float : forall fb by_pos mt,
  cleared_block_y fb by_pos mt >= fb.
Proof.
  intros fb by_pos mt.
  unfold cleared_block_y, compute_clearance.
  pose proof (Z.le_max_r 0 (fb - (by_pos + mt))).
  lia.
Qed.

Theorem cleared_block_past_original : forall fb by_pos mt,
  cleared_block_y fb by_pos mt >= by_pos + mt.
Proof.
  intros fb by_pos mt.
  unfold cleared_block_y, compute_clearance.
  pose proof (Z.le_max_l 0 (fb - (by_pos + mt))).
  lia.
Qed.

Theorem cleared_block_closed_form : forall fb by_pos mt,
  cleared_block_y fb by_pos mt = Z.max (by_pos + mt) fb.
Proof.
  intros fb by_pos mt.
  unfold cleared_block_y, compute_clearance.
  destruct (Z.max_spec 0 (fb - (by_pos + mt))) as [[_ Hmax] | [_ Hmax]];
  rewrite Hmax; lia.
Qed.
