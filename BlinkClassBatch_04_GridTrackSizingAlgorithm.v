(* Blink2Coq Synthesis for GridTrackSizingAlgorithm *)
(* Source: third_party/blink/renderer/core/layout/grid/grid_track_sizing_algorithm.cc *)

Require Import ZArith Lia. Open Scope Z_scope.
Definition resolve_grid_minmax (avail min_t max_t : Z) : Z :=
  if avail <? min_t then min_t else if max_t <? avail then max_t else avail.
Theorem grid_minmax_bounded : forall avail min_t max_t,
  min_t <= max_t -> min_t <= resolve_grid_minmax avail min_t max_t <= max_t.
Proof.
  intros av mi ma Hle. unfold resolve_grid_minmax.
  destruct (av <? mi) eqn:E1; [apply Z.ltb_lt in E1; lia | apply Z.ltb_ge in E1].
  destruct (ma <? av) eqn:E2; [apply Z.ltb_lt in E2; lia | apply Z.ltb_ge in E2; lia].
Qed.
