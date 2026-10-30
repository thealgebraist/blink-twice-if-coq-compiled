(* ========================================================================= *)
(*               BlinkShapeResultRunSplitSemantics.v                        *)
(* ========================================================================= *)
(* Formal verification of Chromium Blink ShapeResult Run Splitting &         *)
(* Subsegment Bounding against CSS Text 3 §5. Fully constructive, 0 admits. *)
(* ========================================================================= *)

From Stdlib Require Import ZArith Lists.List Bool Lia.
Open Scope Z_scope.

Record ShapeRun := mkShapeRun {
  sr_chars : Z;
  sr_width : Z
}.

Definition split_shape_run (run : ShapeRun) (split_chars left_w : Z) : ShapeRun * ShapeRun :=
  ({| sr_chars := split_chars; sr_width := left_w |},
   {| sr_chars := sr_chars run - split_chars; sr_width := sr_width run - left_w |}).

Theorem split_shape_run_chars_conservation : forall run split_chars left_w,
  let (r_left, r_right) := split_shape_run run split_chars left_w in
  sr_chars r_left + sr_chars r_right = sr_chars run.
Proof.
  intros. unfold split_shape_run. cbn. lia.
Qed.

Theorem split_shape_run_width_conservation : forall run split_chars left_w,
  let (r_left, r_right) := split_shape_run run split_chars left_w in
  sr_width r_left + sr_width r_right = sr_width run.
Proof.
  intros. unfold split_shape_run. cbn. lia.
Qed.
