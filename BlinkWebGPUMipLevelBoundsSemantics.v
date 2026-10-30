Require Import ZArith.
Require Import Lia.
Require Import Bool.
Open Scope Z_scope.

(** * Blink WebGPU Mip Level Bounds Semantics *)
(** WebGPU §7.2: mip level within [0, max_mip_levels) *)

Definition is_valid_mip_level (lvl max_lvl : Z) : bool :=
  (0 <=? lvl) && (lvl <? max_lvl).

Theorem mip_level_sound : forall l max_l,
  is_valid_mip_level l max_l = true <-> (0 <= l /\ l < max_l).
Proof.
  intros l max_l.
  unfold is_valid_mip_level.
  rewrite andb_true_iff, Z.leb_le, Z.ltb_lt.
  tauto.
Qed.
