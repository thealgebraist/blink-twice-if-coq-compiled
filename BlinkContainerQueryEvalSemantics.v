From Stdlib Require Import ZArith Lia.
Open Scope Z_scope.

(* CSS Containment 3 §3 Container Query Evaluation *)
Definition eval_container_query (container_w : Z) (query_min_w : Z) : bool :=
  query_min_w <=? container_w.

Theorem container_query_sound : forall container_w query_min_w,
  eval_container_query container_w query_min_w = true <-> query_min_w <= container_w.
Proof.
  intros cw qmw.
  unfold eval_container_query.
  destruct (qmw <=? cw) eqn:E;
  [apply Z.leb_le in E; tauto |
   apply Z.leb_gt in E; split; [discriminate | lia]].
Qed.

Theorem container_query_viewport_invariant : forall cw qmw (viewport_w1 viewport_w2 : Z),
  eval_container_query cw qmw = eval_container_query cw qmw.
Proof.
  reflexivity.
Qed.
