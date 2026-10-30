(* Blink2Coq HTML/CSS Synthesis for SubgridAlgorithm *)
(* Source: renderer/core/layout/grid/subgrid_algorithm.cc *)

From Stdlib Require Import ZArith Lia. Open Scope Z_scope.
Definition subgrid_track_count (parent_span : Z) : Z := Z.max 0 parent_span.
Theorem subgrid_track_count_nonneg : forall span,
  0 <= subgrid_track_count span.
Proof. intros. unfold subgrid_track_count. apply Z.le_max_l. Qed.
