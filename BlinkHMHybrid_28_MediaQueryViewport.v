(* Formalization generated via HM Hybrid Architecture *)
(* De-imperativized SSA AST + Robinson MGU Row Typing + WP Assertion Mining + Dale Miller Presburger LIA *)
Require Import ZArith.
Require Import Bool.
Require Import Lia.
Open Scope Z_scope.

Record MediaQueryViewport := mkMediaQueryViewport {
  mediaqueryviewport_vp_width : Z;
  mediaqueryviewport_min_width : Z;
  mediaqueryviewport_max_width : Z
}.

Definition eval_media_min_max (vp_w : Z) (min_w : Z) (max_w : Z) : bool :=
  (min_w <=? vp_w) && (vp_w <=? max_w).

Theorem eval_media_empty_interval_false :
  forall (vp_w min_w max_w : Z), max_w < min_w -> eval_media_min_max vp_w min_w max_w = false.
Proof.
  intros vp_w min_w max_w Hgt.
  unfold eval_media_min_max.
  apply andb_false_iff.
  destruct (min_w <=? vp_w) eqn:E1.
  - apply Z.leb_le in E1. right. apply Z.leb_gt. lia.
  - left. reflexivity.
Qed.
