Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Table Auto-Layout Column Width Floor Semantics *)
(** CSS 2.1 §17.5.2: auto table layout column width floor *)

Definition auto_column_width (min_content max_content avail_share : Z) : Z :=
  Z.max min_content (Z.min max_content avail_share).

Theorem auto_col_width_ge_min_content : forall min_c max_c avail,
  min_c <= max_c ->
  min_c <= auto_column_width min_c max_c avail.
Proof.
  intros min_c max_c avail Hle.
  unfold auto_column_width.
  apply Z.le_max_l.
Qed.
