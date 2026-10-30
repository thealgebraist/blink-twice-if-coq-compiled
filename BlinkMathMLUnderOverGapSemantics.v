Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink MathML UnderOver Vertical Gap Semantics *)
(** MathML Core §3.5: vertical gap clearance *)

Definition resolve_underover_vertical_gap (gap min_gap : Z) : Z :=
  Z.max (Z.max 0 min_gap) gap.

Theorem underover_gap_bounded_below : forall g min_g,
  0 <= min_g ->
  min_g <= resolve_underover_vertical_gap g min_g.
Proof.
  intros g min_g Hmin.
  unfold resolve_underover_vertical_gap; lia.
Qed.
