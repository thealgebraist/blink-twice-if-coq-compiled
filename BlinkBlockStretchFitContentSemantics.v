Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Block Stretch vs Fit-Content Sizing Semantics *)
(** CSS Box Sizing 3 §5.1: fit-content sizing formula *)

Definition fit_content_size (avail min_c max_c : Z) : Z :=
  Z.max min_c (Z.min avail max_c).

Theorem fit_content_bounds : forall avail min_c max_c,
  min_c <= max_c ->
  min_c <= fit_content_size avail min_c max_c.
Proof.
  intros avail min_c max_c Hle.
  unfold fit_content_size.
  apply Z.le_max_l.
Qed.
