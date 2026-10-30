Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Page Margin Box Available Space Semantics *)
(** CSS Paged Media 3 §4: content available space *)

Definition compute_page_available_space (page_dim margin_start margin_end : Z) : Z :=
  Z.max 0 (page_dim - (Z.max 0 margin_start + Z.max 0 margin_end)).

Theorem available_space_nonneg : forall dim ms me,
  0 <= compute_page_available_space dim ms me.
Proof.
  intros dim ms me.
  unfold compute_page_available_space.
  lia.
Qed.

Theorem available_space_bounded_by_page_dim : forall dim ms me,
  0 <= dim ->
  compute_page_available_space dim ms me <= dim.
Proof.
  intros dim ms me Hdim.
  unfold compute_page_available_space.
  lia.
Qed.
