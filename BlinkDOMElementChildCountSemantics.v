Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink childElementCount Bounds Semantics *)
(** DOM Standard §4.2: childElementCount bounded by total childNodes *)

Definition clamp_child_element_count (cnt total_nodes : Z) : Z :=
  Z.max 0 (Z.min total_nodes cnt).

Theorem child_element_count_bounded : forall c tot,
  0 <= tot ->
  0 <= clamp_child_element_count c tot <= tot.
Proof.
  intros c tot Htot.
  unfold clamp_child_element_count; lia.
Qed.
