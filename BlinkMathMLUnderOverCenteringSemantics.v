Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink MathML UnderOver Horizontal Centering Semantics *)
(** MathML Core §3.5: script centered over base *)

Definition compute_underover_centering_offset (base_width script_width : Z) : Z :=
  (base_width - script_width) / 2.

Theorem centering_symmetric_for_equal_widths : forall w,
  compute_underover_centering_offset w w = 0.
Proof.
  intros w.
  unfold compute_underover_centering_offset.
  assert (w - w = 0) by lia.
  rewrite H; reflexivity.
Qed.
