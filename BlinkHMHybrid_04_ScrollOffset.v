(* Formalization generated via HM Hybrid Architecture *)
(* De-imperativized SSA AST + Robinson MGU Row Typing + WP Assertion Mining + Dale Miller Presburger LIA *)
Require Import ZArith.
Require Import Bool.
Require Import Lia.
Open Scope Z_scope.

Record ScrollOffset := mkScrollOffset {
  scrolloffset_x : Z;
  scrolloffset_y : Z
}.

Definition clamp_scroll_x (x : Z) (max_x : Z) : Z :=
  if x <? 0 then 0 else if max_x <? x then max_x else x.

Theorem clamp_scroll_x_bounded :
  forall (x max_x : Z), 0 <= max_x -> 0 <= clamp_scroll_x x max_x <= max_x.
Proof.
  intros x max_x Hmax.
  unfold clamp_scroll_x.
  destruct (x <? 0) eqn:Ex; [apply Z.ltb_lt in Ex; lia |].
  apply Z.ltb_ge in Ex.
  destruct (max_x <? x) eqn:Em; [apply Z.ltb_lt in Em; lia |].
  apply Z.ltb_ge in Em. lia.
Qed.
