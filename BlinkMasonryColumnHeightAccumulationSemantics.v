Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Masonry Column Height Accumulation Semantics *)
(** CSS Grid 3 (Masonry) §2: monotonic column height growth under insertion *)

Definition accumulate_masonry_column (cur_h item_h gap : Z) : Z :=
  cur_h + item_h + gap.

Theorem masonry_height_monotonic : forall h item gap,
  0 <= item ->
  0 <= gap ->
  h <= accumulate_masonry_column h item gap.
Proof.
  intros h item gap Hitem Hgap.
  unfold accumulate_masonry_column; lia.
Qed.
