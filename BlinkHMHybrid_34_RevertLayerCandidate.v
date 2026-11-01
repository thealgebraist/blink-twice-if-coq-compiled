(* Formalization generated via HM Hybrid Architecture *)
(* De-imperativized SSA AST + Robinson MGU Row Typing + WP Assertion Mining + Dale Miller Presburger LIA *)
Require Import ZArith.
Require Import Bool.
Require Import Lia.
Open Scope Z_scope.

Record RevertLayerCandidate := mkRevertLayerCandidate {
  revertlayercandidate_cur_origin : Z;
  revertlayercandidate_cur_layer : Z;
  revertlayercandidate_cand_origin : Z;
  revertlayercandidate_cand_layer : Z
}.

Definition revert_layer_accepts (cur_origin : Z) (cur_layer : Z) (cand_origin : Z) (cand_layer : Z) : bool :=
  (cand_origin <? cur_origin) || ((cand_origin =? cur_origin) && (cand_layer <? cur_layer)).

Theorem revert_layer_rejects_same_or_later_layer :
  forall (orig cur_layer cand_layer : Z), cur_layer <= cand_layer -> revert_layer_accepts orig cur_layer orig cand_layer = false.
Proof.
  intros orig cur_layer cand_layer Hle.
  unfold revert_layer_accepts.
  rewrite Z.ltb_irrefl, Z.eqb_refl. simpl.
  apply Z.ltb_ge. lia.
Qed.
