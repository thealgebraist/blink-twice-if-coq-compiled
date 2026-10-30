Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink HarfBuzz Cluster Formation Semantics *)
(** HarfBuzz Cluster Architecture: cluster monotonicity in LTR *)

Record HarfBuzzCluster := {
  hb_cluster_index : Z;
  hb_glyph_id : Z
}.

Definition cluster_index_monotonic_step (c1 c2 : HarfBuzzCluster) : Prop :=
  hb_cluster_index c1 <= hb_cluster_index c2.

Theorem cluster_step_transitive : forall c1 c2 c3,
  cluster_index_monotonic_step c1 c2 ->
  cluster_index_monotonic_step c2 c3 ->
  cluster_index_monotonic_step c1 c3.
Proof.
  intros c1 c2 c3 H1 H2.
  unfold cluster_index_monotonic_step in *.
  lia.
Qed.
