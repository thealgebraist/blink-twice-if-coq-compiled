Require Import ZArith.
Require Import Lia.
Require Import Bool.
Open Scope Z_scope.

(** * Blink Container Query Range Matching Semantics *)
(** CSS Containment 3 §2: container query range satisfaction *)

Definition eval_container_range (cw min_w max_w : Z) : bool :=
  andb (min_w <=? cw) (cw <=? max_w).

Theorem container_in_range : forall c min_w max_w,
  min_w <= c ->
  c <= max_w ->
  eval_container_range c min_w max_w = true.
Proof.
  intros c min_w max_w Hmin Hmax.
  unfold eval_container_range.
  apply andb_true_iff; split; apply Z.leb_le; assumption.
Qed.
