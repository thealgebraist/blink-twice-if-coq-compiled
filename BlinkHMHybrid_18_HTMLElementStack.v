(* Formalization generated via HM Hybrid Architecture *)
(* De-imperativized SSA AST + Robinson MGU Row Typing + WP Assertion Mining + Dale Miller Presburger LIA *)
Require Import ZArith.
Require Import Bool.
Require Import Lia.
Open Scope Z_scope.

Record HTMLElementStack := mkHTMLElementStack {
  htmlelementstack_depth : Z;
  htmlelementstack_scope_floor : Z;
  htmlelementstack_in_p_button_scope : bool
}.

Definition pop_to_scope_floor (depth : Z) (scope_floor : Z) (pop_req : Z) : Z :=
  if depth - pop_req <? scope_floor then scope_floor else depth - pop_req.

Theorem pop_to_scope_floor_preserves_boundary :
  forall (depth scope_floor pop_req : Z), 0 <= pop_req -> scope_floor <= depth -> scope_floor <= pop_to_scope_floor depth scope_floor pop_req <= depth.
Proof.
  intros depth scope_floor pop_req Hpop Hfl.
  unfold pop_to_scope_floor.
  destruct (depth - pop_req <? scope_floor) eqn:E.
  - apply Z.ltb_lt in E. lia.
  - apply Z.ltb_ge in E. lia.
Qed.
