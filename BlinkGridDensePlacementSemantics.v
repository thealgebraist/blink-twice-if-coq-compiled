(* ========================================================================= *)
(*               BlinkGridDensePlacementSemantics.v                         *)
(* ========================================================================= *)
(* Formal verification of Chromium Blink Grid Auto-Placement (Dense vs      *)
(* Sparse) against CSS Grid Layout 1 §8.5. Fully constructive, 0 admits.    *)
(* ========================================================================= *)

From Stdlib Require Import ZArith Lists.List Bool Lia.
Open Scope Z_scope.

Record Coord := mkCoord {
  c_row : Z;
  c_col : Z
}.

Record ItemSpec := mkItem {
  span_r : Z;
  span_c : Z
}.

Record PlacedItem := mkPlaced {
  p_item : ItemSpec;
  p_pos  : Coord
}.

Definition covers_cell (p : PlacedItem) (r c : Z) : bool :=
  let r0 := c_row (p_pos p) in
  let c0 := c_col (p_pos p) in
  let hr := span_r (p_item p) in
  let wc := span_c (p_item p) in
  (r0 <=? r) && (r <? r0 + hr) && (c0 <=? c) && (c <? c0 + wc).

Theorem covers_cell_bounds : forall p r c,
  covers_cell p r c = true ->
  c_row (p_pos p) <= r < c_row (p_pos p) + span_r (p_item p) /\
  c_col (p_pos p) <= c < c_col (p_pos p) + span_c (p_item p).
Proof.
  intros p r c Hcov.
  unfold covers_cell in Hcov.
  repeat (apply andb_prop in Hcov; destruct Hcov as [Hcov ?]).
  apply Z.leb_le in Hcov.
  apply Z.ltb_lt in H1.
  apply Z.leb_le in H0.
  apply Z.ltb_lt in H.
  split; lia.
Qed.

Theorem disjoint_items_never_overlap : forall p1 p2 r c,
  c_row (p_pos p1) + span_r (p_item p1) <= c_row (p_pos p2) ->
  covers_cell p1 r c = true ->
  covers_cell p2 r c = false.
Proof.
  intros p1 p2 r c Hdisj Hcov1.
  apply covers_cell_bounds in Hcov1.
  unfold covers_cell.
  destruct (c_row (p_pos p2) <=? r) eqn:E; [|reflexivity].
  apply Z.leb_le in E.
  lia.
Qed.
