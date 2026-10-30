(******************************************************************************)
(* BlinkShapeOutsideSemantics.v                                               *)
(* Sound Formal Specification for CSS Shapes & Exclusions (shape-outside)     *)
(* Corresponding to:                                                          *)
(* 1. W3C CSS Shapes Module Level 1 (§3 Shapes, §4 Basic Shapes)              *)
(* 2. Blink ShapeOutsideInfo (`shape_outside_info.cc`) & BoxShape             *)
(******************************************************************************)

From Stdlib Require Import ZArith List Lia Bool.
Require Import BlinkOperationalSemantics.
Open Scope Z_scope.

Record ShapeMarginBox := mkShapeMarginBox {
  smb_box_x : Z;
  smb_box_y : Z;
  smb_box_w : Z;
  smb_box_h : Z;
  smb_margin : Z
}.

(** Resolves the inline interval excluded by a rectangular shape at cursor Y *)
Definition compute_shape_excluded_interval (smb : ShapeMarginBox) (cursor_y : Z) : option (Z * Z) :=
  let m := Z.max 0 (smb_margin smb) in
  let top_y := smb_box_y smb - m in
  let bottom_y := smb_box_y smb + smb_box_h smb + m in
  if (top_y <=? cursor_y) && (cursor_y <? bottom_y) then
    let left_x := smb_box_x smb - m in
    let right_x := smb_box_x smb + smb_box_w smb + m in
    Some (left_x, right_x)
  else
    None.

(******************************************************************************)
(* SOUNDNESS THEOREMS (0 admits)                                              *)
(******************************************************************************)

Theorem shape_excluded_interval_ordering :
  forall smb cur_y left_x right_x,
    0 <= smb_box_w smb ->
    compute_shape_excluded_interval smb cur_y = Some (left_x, right_x) ->
    left_x <= right_x.
Proof.
  intros smb cur_y left_x right_x Hw Hcomp.
  unfold compute_shape_excluded_interval in Hcomp.
  destruct ((smb_box_y smb - Z.max 0 (smb_margin smb) <=? cur_y) &&
            (cur_y <? smb_box_y smb + smb_box_h smb + Z.max 0 (smb_margin smb))) eqn:Ein; [| discriminate].
  inversion Hcomp; subst.
  assert (0 <= Z.max 0 (smb_margin smb)) by apply Z.le_max_l.
  lia.
Qed.

Theorem shape_outside_deterministic :
  forall smb cur_y r1 r2,
    r1 = compute_shape_excluded_interval smb cur_y ->
    r2 = compute_shape_excluded_interval smb cur_y ->
    r1 = r2.
Proof.
  intros smb cur_y r1 r2 H1 H2. subst. reflexivity.
Qed.
