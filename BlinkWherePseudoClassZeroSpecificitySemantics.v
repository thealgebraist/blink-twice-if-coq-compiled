From Stdlib Require Import ZArith Lia.
Open Scope Z_scope.

(* CSS Selectors 4 §4.3 :where() Pseudo-Class Zero Specificity *)
Definition where_specificity : Z * Z * Z :=
  (0, 0, 0).

Theorem where_specificity_is_zero :
  where_specificity = (0, 0, 0).
Proof.
  reflexivity.
Qed.

Theorem arbitrary_specificity_ge_where : forall a b c,
  a >= 0 ->
  b >= 0 ->
  c >= 0 ->
  let '(w_a, w_b, w_c) := where_specificity in
  a >= w_a /\ b >= w_b /\ c >= w_c.
Proof.
  intros a b c Ha Hb Hc.
  unfold where_specificity. lia.
Qed.
