From Stdlib Require Import ZArith Lia.
Open Scope Z_scope.

(* CSS 2.1 §10.8.1 Inline-Block Baseline with Overflow != Visible *)
Inductive OverflowMode :=
  | OF_Visible
  | OF_Hidden
  | OF_Scroll
  | OF_Auto.

Definition compute_inline_block_baseline (mode : OverflowMode) (line_box_baseline : option Z) (margin_box_bottom : Z) : Z :=
  match mode with
  | OF_Visible =>
      match line_box_baseline with
      | Some b => b
      | None => margin_box_bottom
      end
  | _ => margin_box_bottom
  end.

Theorem non_visible_overflow_uses_margin_box_bottom : forall mode lbb mbb,
  mode <> OF_Visible ->
  compute_inline_block_baseline mode lbb mbb = mbb.
Proof.
  intros mode lbb mbb Hneq.
  unfold compute_inline_block_baseline.
  destruct mode; [contradiction Hneq; reflexivity | reflexivity | reflexivity | reflexivity].
Qed.
