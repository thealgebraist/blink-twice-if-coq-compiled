From Stdlib Require Import ZArith Lia.
Open Scope Z_scope.

(* Media Queries 4 §2 Media Query Range Feature Evaluation *)
Definition eval_width_range (min_w max_w v_w : Z) : bool :=
  andb (min_w <=? v_w) (v_w <=? max_w).

Theorem width_range_eval_sound : forall min_w max_w v_w,
  eval_width_range min_w max_w v_w = true <-> (min_w <= v_w /\ v_w <= max_w).
Proof.
  intros min_w max_w v_w.
  unfold eval_width_range.
  destruct (min_w <=? v_w) eqn:E1;
  destruct (v_w <=? max_w) eqn:E2; cbn;
  [apply Z.leb_le in E1; apply Z.leb_le in E2; tauto |
   apply Z.leb_le in E1; apply Z.leb_gt in E2; split; [discriminate | intros [H1 H2]; lia] |
   apply Z.leb_gt in E1; apply Z.leb_le in E2; split; [discriminate | intros [H1 H2]; lia] |
   apply Z.leb_gt in E1; apply Z.leb_gt in E2; split; [discriminate | intros [H1 H2]; lia]].
Qed.
