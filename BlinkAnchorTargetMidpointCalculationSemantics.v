Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Anchor Target Midpoint Calculation Semantics *)
(** CSS Anchor Positioning §3: target midpoint derivation *)

Definition compute_anchor_midpoint (start end_pos : Z) : Z :=
  (start + end_pos) / 2.

Theorem anchor_midpoint_bounded : forall s e,
  s <= e ->
  s <= compute_anchor_midpoint s e <= e.
Proof.
  intros s e H.
  unfold compute_anchor_midpoint.
  split.
  - apply Z.div_le_lower_bound; lia.
  - apply Z.div_le_upper_bound; lia.
Qed.
