Require Import ZArith.
Require Import Bool.
Open Scope Z_scope.

(** * Blink Flex Item Order Property Sorting Semantics *)
(** CSS Flexbox 1 §5.4: order property stable sorting *)

Definition flex_order_compare (o1 d1 o2 d2 : Z) : comparison :=
  match Z.compare o1 o2 with
  | Eq => Z.compare d1 d2
  | other => other
  end.

Theorem order_tie_preserves_dom_order : forall o d1 d2,
  flex_order_compare o d1 o d2 = Z.compare d1 d2.
Proof.
  intros o d1 d2.
  unfold flex_order_compare.
  rewrite Z.compare_refl.
  reflexivity.
Qed.
