Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Block Margin Strut Negative Cancellation Semantics *)
(** CSS 2.1 §8.3.1: positive and negative margin collapsing *)

Definition collapse_margins (pos neg : Z) : Z :=
  pos + neg.

Theorem collapsed_margin_bounds : forall pos neg,
  pos >= 0 ->
  neg <= 0 ->
  neg <= collapse_margins pos neg <= pos.
Proof.
  intros pos neg Hpos Hneg.
  unfold collapse_margins.
  lia.
Qed.
