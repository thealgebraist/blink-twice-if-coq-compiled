From Stdlib Require Import ZArith Lia.
Open Scope Z_scope.

(* Intersection Observer 1 §3 IntersectionObserver Threshold Crossing *)
Definition has_crossed_threshold (old_ratio new_ratio threshold : Z) : bool :=
  orb (andb (old_ratio <? threshold) (threshold <=? new_ratio))
      (andb (new_ratio <? threshold) (threshold <=? old_ratio)).

Theorem stationary_does_not_cross : forall r th,
  has_crossed_threshold r r th = false.
Proof.
  intros r th.
  unfold has_crossed_threshold.
  destruct (r <? th) eqn:E1; destruct (th <=? r) eqn:E2; cbn;
  [apply Z.ltb_lt in E1; apply Z.leb_le in E2; lia |
   reflexivity |
   reflexivity |
   reflexivity].
Qed.

Theorem upward_crossing_detected : forall old_r new_r th,
  old_r < th ->
  th <= new_r ->
  has_crossed_threshold old_r new_r th = true.
Proof.
  intros old_r new_r th Hlt Hle.
  unfold has_crossed_threshold.
  apply Z.ltb_lt in Hlt; apply Z.leb_le in Hle.
  rewrite Hlt, Hle; cbn. reflexivity.
Qed.
