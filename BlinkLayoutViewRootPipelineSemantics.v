From Stdlib Require Import ZArith Lia.
Open Scope Z_scope.

(* CSS 2.1 §10.1 & CSS Box Model 3 LayoutView Root Master Pipeline *)
Record ViewportBounds := {
  vb_width : Z;
  vb_height : Z
}.

Definition is_point_within_viewport (vb : ViewportBounds) (x y : Z) : bool :=
  andb (andb (0 <=? x) (x <=? vb_width vb))
       (andb (0 <=? y) (y <=? vb_height vb)).

Theorem origin_is_within_viewport : forall vb,
  vb_width vb >= 0 ->
  vb_height vb >= 0 ->
  is_point_within_viewport vb 0 0 = true.
Proof.
  intros vb Hw Hh.
  unfold is_point_within_viewport; cbn.
  destruct (0 <=? vb_width vb) eqn:Ew;
  destruct (0 <=? vb_height vb) eqn:Eh; cbn;
  [reflexivity |
   apply Z.leb_gt in Eh; lia |
   apply Z.leb_gt in Ew; lia |
   apply Z.leb_gt in Ew; lia].
Qed.
