Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink MathML Radical Symbol Sizing Semantics *)
(** MathML Core §3.6.1: radical height coverage *)

Definition compute_radical_symbol_height (radicand_height vertical_gap rule_thickness : Z) : Z :=
  Z.max 0 radicand_height + Z.max 0 vertical_gap + Z.max 1 rule_thickness.

Theorem radical_height_covers_radicand : forall rh vg rt,
  0 <= rh ->
  rh < compute_radical_symbol_height rh vg rt.
Proof.
  intros rh vg rt Hrh.
  unfold compute_radical_symbol_height; lia.
Qed.
