Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Display Item List Sequential Ordering Semantics *)
(** CSS 2.1 App E §E.2: display item list index strict progression *)

Definition next_display_item_index (idx : Z) : Z :=
  idx + 1.

Theorem display_item_iteration_strictly_monotonic : forall idx,
  idx < next_display_item_index idx.
Proof.
  intros idx.
  unfold next_display_item_index; lia.
Qed.
