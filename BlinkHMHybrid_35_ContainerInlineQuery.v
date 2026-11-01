(* Formalization generated via HM Hybrid Architecture *)
(* De-imperativized SSA AST + Robinson MGU Row Typing + WP Assertion Mining + Dale Miller Presburger LIA *)
Require Import ZArith.
Require Import Bool.
Require Import Lia.
Open Scope Z_scope.

Record ContainerInlineQuery := mkContainerInlineQuery {
  containerinlinequery_container_inline_w : Z;
  containerinlinequery_min_w : Z;
  containerinlinequery_max_w : Z
}.

Definition eval_container_inline_range (avail_w : Z) (min_w : Z) (max_w : Z) : bool :=
  (min_w <=? avail_w) && (avail_w <=? max_w).

Theorem container_inline_range_implies_consistent_bounds :
  forall (avail_w min_w max_w : Z), eval_container_inline_range avail_w min_w max_w = true -> min_w <= avail_w /\ avail_w <= max_w /\ min_w <= max_w.
Proof.
  intros avail_w min_w max_w H.
  unfold eval_container_inline_range in H.
  apply andb_true_iff in H as [H1 H2].
  apply Z.leb_le in H1. apply Z.leb_le in H2. lia.
Qed.
