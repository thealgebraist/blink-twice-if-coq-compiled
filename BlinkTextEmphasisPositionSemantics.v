Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Text Emphasis Mark Position Semantics *)
(** CSS Text Decoration 3 §3.2: emphasis mark vertical offset *)

Definition compute_emphasis_mark_y (baseline mark_height : Z) (is_over : bool) : Z :=
  if is_over then baseline - Z.max 0 mark_height
  else baseline + Z.max 0 mark_height.

Theorem emphasis_over_shifts_above_baseline : forall base h,
  0 <= h ->
  compute_emphasis_mark_y base h true <= base.
Proof.
  intros base h Hh.
  unfold compute_emphasis_mark_y; lia.
Qed.

Theorem emphasis_under_shifts_below_baseline : forall base h,
  0 <= h ->
  base <= compute_emphasis_mark_y base h false.
Proof.
  intros base h Hh.
  unfold compute_emphasis_mark_y; lia.
Qed.
