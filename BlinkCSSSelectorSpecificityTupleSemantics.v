Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Selector Specificity Tuple Packing Semantics *)
(** CSS Selectors 4 §16: (A, B, C) specificity packed integer total order *)

Definition pack_specificity (id_count class_count type_count : Z) : Z :=
  id_count * 65536 + class_count * 256 + type_count.

Theorem specificity_zero :
  pack_specificity 0 0 0 = 0.
Proof.
  unfold pack_specificity; reflexivity.
Qed.

Theorem id_dominates_class : forall c t,
  0 <= c < 256 ->
  0 <= t < 256 ->
  pack_specificity 0 c t < pack_specificity 1 0 0.
Proof.
  intros c t Hc Ht.
  unfold pack_specificity; lia.
Qed.
