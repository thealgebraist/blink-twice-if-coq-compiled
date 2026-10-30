Require Import ZArith.
Require Import Lia.
Require Import Bool.
Open Scope Z_scope.

(** * Blink WebGPU Texture Dimension Bounds Semantics *)
(** WebGPU §7.1: texture width and height within [1, max_dim] *)

Definition is_valid_texture_dim (w h max_dim : Z) : bool :=
  (0 <? w) && (w <=? max_dim) && (0 <? h) && (h <=? max_dim).

Theorem texture_dim_sound : forall w h max_d,
  is_valid_texture_dim w h max_d = true <-> (0 < w /\ w <= max_d /\ 0 < h /\ h <= max_d).
Proof.
  intros w h max_d.
  unfold is_valid_texture_dim.
  repeat rewrite andb_true_iff.
  repeat (rewrite Z.ltb_lt || rewrite Z.leb_le).
  tauto.
Qed.
