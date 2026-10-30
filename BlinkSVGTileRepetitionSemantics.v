Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink feTile Pattern Repetition Semantics *)
(** Filter Effects 1 §20: Modulo seamless texture repetition *)

Definition tile_coordinate (p tile_size : Z) : Z :=
  p mod tile_size.

Theorem tile_coord_in_bounds : forall p tile_size,
  0 < tile_size ->
  0 <= tile_coordinate p tile_size < tile_size.
Proof.
  intros p tile_size Hts.
  unfold tile_coordinate.
  apply Z.mod_pos_bound.
  lia.
Qed.

Theorem tile_periodic : forall p tile_size,
  0 < tile_size ->
  tile_coordinate (p + tile_size) tile_size = tile_coordinate p tile_size.
Proof.
  intros p tile_size Hts.
  unfold tile_coordinate.
  replace (p + tile_size) with (p + 1 * tile_size) by lia.
  apply Z_mod_plus_full.
Qed.
