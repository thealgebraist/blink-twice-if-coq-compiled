Require Import ZArith.
Require Import Bool.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Grid Implicit Track Creation Semantics *)
(** CSS Grid Layout 1 §7.5: implicit grid line clamping *)

Definition clamp_grid_line (line max_lines : Z) : Z :=
  if line <=? 1 then 1
  else if max_lines <? line then max_lines
  else line.

Theorem clamp_grid_line_sound : forall line max_lines,
  max_lines >= 1 ->
  1 <= clamp_grid_line line max_lines <= max_lines.
Proof.
  intros line max_lines Hmax.
  unfold clamp_grid_line.
  destruct (line <=? 1) eqn:E1.
  - lia.
  - apply Z.leb_gt in E1.
    destruct (max_lines <? line) eqn:E2.
    + lia.
    + apply Z.ltb_ge in E2.
      lia.
Qed.
