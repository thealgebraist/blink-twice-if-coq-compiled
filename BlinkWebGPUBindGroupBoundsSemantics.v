Require Import ZArith.
Require Import Lia.
Require Import Bool.
Open Scope Z_scope.

(** * Blink WebGPU Bind Group Bounds Semantics *)
(** WebGPU §8.2: bind group index in bounds [0, max_groups) *)

Definition is_valid_bind_group_index (idx max_groups : Z) : bool :=
  (0 <=? idx) && (idx <? max_groups).

Theorem bind_group_index_sound : forall idx max_g,
  is_valid_bind_group_index idx max_g = true <-> (0 <= idx /\ idx < max_g).
Proof.
  intros idx max_g.
  unfold is_valid_bind_group_index.
  rewrite andb_true_iff, Z.leb_le, Z.ltb_lt.
  tauto.
Qed.
