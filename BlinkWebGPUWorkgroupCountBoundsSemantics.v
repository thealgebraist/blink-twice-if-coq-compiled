Require Import ZArith.
Require Import Lia.
Require Import Bool.
Open Scope Z_scope.

(** * Blink WebGPU Workgroup Count Bounds Semantics *)
(** WebGPU §11.1: compute workgroup count bounded by limits *)

Definition is_valid_workgroups (x y z max_wg : Z) : bool :=
  (0 <? x) && (x <=? max_wg) &&
  (0 <? y) && (y <=? max_wg) &&
  (0 <? z) && (z <=? max_wg).

Theorem workgroups_valid_sound : forall x y z max_wg,
  is_valid_workgroups x y z max_wg = true <->
  (0 < x /\ x <= max_wg /\ 0 < y /\ y <= max_wg /\ 0 < z /\ z <= max_wg).
Proof.
  intros x y z max_wg.
  unfold is_valid_workgroups.
  repeat rewrite andb_true_iff.
  repeat (rewrite Z.ltb_lt || rewrite Z.leb_le).
  tauto.
Qed.
