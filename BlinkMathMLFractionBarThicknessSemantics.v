Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink MathML Fraction Bar Thickness Semantics *)
(** MathML Core §3.3.2: fraction bar thickness >= 1 *)

Definition resolve_fraction_bar_thickness (raw_rule_thickness : Z) : Z :=
  Z.max 1 raw_rule_thickness.

Theorem fraction_bar_thickness_strictly_positive : forall raw,
  0 < resolve_fraction_bar_thickness raw.
Proof.
  intros raw.
  unfold resolve_fraction_bar_thickness.
  lia.
Qed.
