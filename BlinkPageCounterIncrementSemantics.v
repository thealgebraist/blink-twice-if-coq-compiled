Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Page Counter Monotonic Increment Semantics *)
(** CSS Paged Media 3 §5: strictly monotonic counter advancement *)

Definition increment_page_counter (current_page : Z) : Z :=
  current_page + 1.

Theorem page_counter_strictly_monotonic : forall p,
  p < increment_page_counter p.
Proof.
  intros p.
  unfold increment_page_counter; lia.
Qed.
