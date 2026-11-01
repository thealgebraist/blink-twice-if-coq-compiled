(* Formalization generated via HM Hybrid Architecture *)
(* De-imperativized SSA AST + Robinson MGU Row Typing + WP Assertion Mining + Dale Miller Presburger LIA *)
Require Import ZArith.
Require Import Bool.
Require Import Lia.
Open Scope Z_scope.

Record TableCollapsedBorder := mkTableCollapsedBorder {
  tablecollapsedborder_style1 : Z;
  tablecollapsedborder_width1 : Z;
  tablecollapsedborder_style2 : Z;
  tablecollapsedborder_width2 : Z
}.

Definition collapsed_border_width (s1 : Z) (w1 : Z) (s2 : Z) (w2 : Z) : Z :=
  if (s1 =? 9) || (s2 =? 9) then 0 else if s1 =? 0 then w2 else if s2 =? 0 then w1 else Z.max w1 w2.

Theorem collapsed_border_hidden_zeros_and_visible_max :
  forall (s1 w1 s2 w2 : Z), collapsed_border_width 9 w1 s2 w2 = 0 /\ (1 <= s1 <= 8 -> 1 <= s2 <= 8 -> collapsed_border_width s1 w1 s2 w2 = Z.max w1 w2).
Proof.
  intros s1 w1 s2 w2. unfold collapsed_border_width. split.
  - reflexivity.
  - intros Hs1 Hs2.
    assert (E19 : (s1 =? 9) = false) by (apply Z.eqb_neq; lia).
    assert (E29 : (s2 =? 9) = false) by (apply Z.eqb_neq; lia).
    assert (E10 : (s1 =? 0) = false) by (apply Z.eqb_neq; lia).
    assert (E20 : (s2 =? 0) = false) by (apply Z.eqb_neq; lia).
    rewrite E19, E29, E10, E20. reflexivity.
Qed.
