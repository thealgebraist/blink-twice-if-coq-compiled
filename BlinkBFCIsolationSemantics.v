(* ========================================================================= *)
(*               BlinkBFCIsolationSemantics.v                                *)
(* ========================================================================= *)
(* Formal semantics of Chromium Blink Block Formatting Context (BFC)         *)
(* Isolation per W3C CSS 2.1 §9.4.1.                                         *)
(* Strictly verified with 0 admits.                                          *)
(* ========================================================================= *)

From Stdlib Require Import ZArith Lia.
Open Scope Z_scope.

Inductive DisplayMode : Type :=
  | DisplayBlock
  | DisplayInline
  | DisplayInlineBlock
  | DisplayFlowRoot.

Inductive OverflowType : Type :=
  | OverflowVis
  | OverflowHid
  | OverflowScr
  | OverflowAut.

Definition establishes_new_bfc (d : DisplayMode) (ov : OverflowType) (is_float : bool) : bool :=
  match d with
  | DisplayInlineBlock => true
  | DisplayFlowRoot    => true
  | _ =>
      if is_float then true
      else match ov with
           | OverflowVis => false
           | _           => true
           end
  end.

Theorem flow_root_establishes_bfc : forall ov fl,
  establishes_new_bfc DisplayFlowRoot ov fl = true.
Proof.
  intros. reflexivity.
Qed.

Theorem overflow_hidden_establishes_bfc : forall fl,
  establishes_new_bfc DisplayBlock OverflowHid fl = true.
Proof.
  intros fl. destruct fl; reflexivity.
Qed.

Definition bfc_root_block_size (content_h float_bottom : Z) : Z :=
  Z.max (Z.max 0 content_h) (Z.max 0 float_bottom).

Theorem bfc_root_encompasses_floats : forall content_h float_bottom,
  float_bottom >= 0 ->
  bfc_root_block_size content_h float_bottom >= float_bottom.
Proof.
  intros content_h float_bottom Hfl.
  unfold bfc_root_block_size.
  assert (Z.max 0 float_bottom = float_bottom) by (apply Z.max_r; lia).
  rewrite H.
  apply Z.le_ge, Z.le_max_r.
Qed.

Theorem bfc_root_encompasses_content : forall content_h float_bottom,
  content_h >= 0 ->
  bfc_root_block_size content_h float_bottom >= content_h.
Proof.
  intros content_h float_bottom Hc.
  unfold bfc_root_block_size.
  assert (Z.max 0 content_h = content_h) by (apply Z.max_r; lia).
  rewrite H.
  apply Z.le_ge, Z.le_max_l.
Qed.
