(* Formalization generated via HM Hybrid Architecture *)
(* De-imperativized SSA AST + Robinson MGU Row Typing + WP Assertion Mining + Dale Miller Presburger LIA *)
Require Import ZArith.
Require Import Bool.
Require Import Lia.
Open Scope Z_scope.

Record BaselineOffset := mkBaselineOffset {
  baselineoffset_font_ascent : Z;
  baselineoffset_box_ascent : Z
}.

Definition align_vertical (mode : Z) (box_h : Z) (line_h : Z) (baseline : Z) : Z :=
  if mode =? 0 then baseline else if mode =? 1 then (line_h - box_h) / 2 else if mode =? 2 then line_h - box_h else 0.

Theorem align_vertical_bottom_ge_top :
  forall (box_h line_h baseline : Z), box_h <= line_h -> 0 <= align_vertical 2 box_h line_h baseline.
Proof.
  intros box_h line_h baseline Hle. unfold align_vertical. simpl. lia.
Qed.
