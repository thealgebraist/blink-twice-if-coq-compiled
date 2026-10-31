(* Formalization generated via HM Hybrid Architecture *)
(* De-imperativized SSA AST + Robinson MGU Row Typing + WP Assertion Mining + Dale Miller Presburger LIA *)
Require Import ZArith.
Require Import Bool.
Require Import Lia.
Open Scope Z_scope.

Record NGInlineItem := mkNGInlineItem {
  nginlineitem_start_offset : Z;
  nginlineitem_end_offset : Z;
  nginlineitem_item_type : Z
}.

Definition item_length (s : Z) (e : Z) : Z :=
  e - s.

Theorem item_length_nonneg :
  forall (s e : Z), s <= e -> 0 <= item_length s e.
Proof.
  intros s e Hle. unfold item_length. lia.
Qed.
