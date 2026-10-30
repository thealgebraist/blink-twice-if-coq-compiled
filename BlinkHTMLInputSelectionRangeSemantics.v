Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Text Control Selection Bounds Semantics *)
(** HTML Standard §4.10.5: selectionStart/End clamped within [0, length] *)

Definition clamp_selection_range (start end_pos len : Z) : (Z * Z) :=
  (Z.max 0 (Z.min len start), Z.max 0 (Z.min len end_pos)).

Theorem selection_range_bounded : forall s e l,
  0 <= l ->
  0 <= fst (clamp_selection_range s e l) <= l /\
  0 <= snd (clamp_selection_range s e l) <= l.
Proof.
  intros s e l Hl.
  unfold clamp_selection_range; simpl; lia.
Qed.
