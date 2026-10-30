(******************************************************************************)
(* BlinkSubgridSemantics.v                                                    *)
(* Sound Formal Specification for CSS Subgrid Track Slice Resolution          *)
(* Corresponding to:                                                          *)
(* 1. W3C CSS Grid Layout Module Level 2 (§2 Subgrids, §3 Subgrid Sizing)     *)
(* 2. Blink GridLineResolver & GridSubtree                                    *)
(*    (`third_party/blink/renderer/core/layout/grid/grid_line_resolver.cc`)   *)
(******************************************************************************)

From Stdlib Require Import ZArith List Lia Bool.
Require Import BlinkOperationalSemantics.
Open Scope Z_scope.

Record SubgridSpan := mkSubgridSpan {
  sgs_parent_start : Z; (* 1-based start line in parent grid *)
  sgs_parent_end : Z    (* 1-based end line in parent grid, end > start *)
}.

Definition subgrid_track_count (span : SubgridSpan) : Z :=
  Z.max 0 (sgs_parent_end span - sgs_parent_start span).

(** Maps a subgrid's local track index (0-based) to parent track index (0-based) *)
Definition map_subgrid_track_to_parent (span : SubgridSpan) (local_idx : Z) : Z :=
  sgs_parent_start span + local_idx.

(******************************************************************************)
(* SOUNDNESS THEOREMS (0 admits)                                              *)
(******************************************************************************)

Theorem subgrid_track_count_nonneg :
  forall span,
    0 <= subgrid_track_count span.
Proof.
  intros span. unfold subgrid_track_count. apply Z.le_max_l.
Qed.

Theorem subgrid_mapping_monotonic :
  forall span idx1 idx2,
    idx1 <= idx2 ->
    map_subgrid_track_to_parent span idx1 <= map_subgrid_track_to_parent span idx2.
Proof.
  intros span idx1 idx2 Hle.
  unfold map_subgrid_track_to_parent. lia.
Qed.

Theorem subgrid_mapping_in_bounds :
  forall span idx,
    sgs_parent_start span <= sgs_parent_end span ->
    0 <= idx < subgrid_track_count span ->
    sgs_parent_start span <= map_subgrid_track_to_parent span idx < sgs_parent_end span.
Proof.
  intros span idx Hvalid [Hge Hlt].
  unfold map_subgrid_track_to_parent, subgrid_track_count in *.
  assert (sgs_parent_end span - sgs_parent_start span >= 0) by lia.
  rewrite Z.max_r in Hlt by lia.
  lia.
Qed.
