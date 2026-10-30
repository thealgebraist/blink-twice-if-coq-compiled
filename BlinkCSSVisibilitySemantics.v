(* ========================================================================= *)
(*               BlinkCSSVisibilitySemantics.v                               *)
(* ========================================================================= *)
(* Formal semantics of Chromium Blink CSS Visibility (visible, hidden,       *)
(* collapse) per W3C CSS 2.1 §11.2 & §17.5.5.                                *)
(* Strictly verified with 0 admits.                                          *)
(* ========================================================================= *)

From Stdlib Require Import ZArith Lia.
Open Scope Z_scope.

Inductive VisibilityMode : Type :=
  | VisVisible
  | VisHidden
  | VisCollapse.

Definition block_layout_height (v : VisibilityMode) (h : Z) : Z :=
  Z.max 0 h.

Theorem hidden_preserves_layout_height : forall h,
  block_layout_height VisHidden h = block_layout_height VisVisible h.
Proof.
  intros. reflexivity.
Qed.

Definition table_row_layout_height (v : VisibilityMode) (h : Z) : Z :=
  match v with
  | VisCollapse => 0
  | _           => Z.max 0 h
  end.

Theorem collapse_zeros_row_height : forall h,
  table_row_layout_height VisCollapse h = 0.
Proof.
  intros. reflexivity.
Qed.

Theorem visible_row_height_matches_block : forall h,
  table_row_layout_height VisVisible h = block_layout_height VisVisible h.
Proof.
  intros. reflexivity.
Qed.

Theorem table_row_height_nonneg : forall v h,
  table_row_layout_height v h >= 0.
Proof.
  intros v h. destruct v; simpl; [apply Z.le_ge, Z.le_max_l | apply Z.le_ge, Z.le_max_l | lia].
Qed.
