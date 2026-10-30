Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Grid Masonry Running Height Semantics *)
(** CSS Grid Layout 3 / Masonry §4: track running height update *)

Definition update_running_height (min_running_h item_h : Z) : Z :=
  min_running_h + item_h.

Theorem running_height_monotonic : forall min_h item_h,
  item_h >= 0 ->
  update_running_height min_h item_h >= min_h.
Proof.
  intros min_h item_h Hge.
  unfold update_running_height.
  lia.
Qed.
