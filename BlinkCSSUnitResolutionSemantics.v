(* ========================================================================= *)
(*               BlinkCSSUnitResolutionSemantics.v                           *)
(* ========================================================================= *)
(* Formal semantics of Chromium Blink CSS Value Units & Font-Size Relative   *)
(* Resolution per W3C CSS Values and Units Module Level 4 §5.                *)
(* Strictly verified with 0 admits.                                          *)
(* ========================================================================= *)

From Stdlib Require Import ZArith Lists.List Bool.Bool Lia.
Open Scope Z_scope.

Definition kFixedPointDenominator : Z := 64.

Inductive CSSLengthUnit :=
  | UnitPx (v : Z)
  | UnitEm (tenths : Z)
  | UnitRem (tenths : Z)
  | UnitPercent (pct : Z).

Definition resolve_length_unit
  (unit : CSSLengthUnit)
  (element_font_size : Z)
  (root_font_size : Z)
  (reference_size : Z) : Z :=
  match unit with
  | UnitPx v => v * kFixedPointDenominator
  | UnitEm tenths => (tenths * element_font_size * kFixedPointDenominator) / 10
  | UnitRem tenths => (tenths * root_font_size * kFixedPointDenominator) / 10
  | UnitPercent pct => (pct * reference_size) / 100
  end.

Theorem resolve_px_exact : forall v f_elem f_root ref,
  resolve_length_unit (UnitPx v) f_elem f_root ref = v * 64.
Proof.
  intros. reflexivity.
Qed.

Theorem resolve_zero_is_zero : forall f_elem f_root ref,
  resolve_length_unit (UnitPx 0) f_elem f_root ref = 0 /\
  resolve_length_unit (UnitEm 0) f_elem f_root ref = 0 /\
  resolve_length_unit (UnitRem 0) f_elem f_root ref = 0 /\
  resolve_length_unit (UnitPercent 0) f_elem f_root ref = 0.
Proof.
  intros.
  unfold resolve_length_unit.
  repeat split; reflexivity.
Qed.

Theorem resolve_nonneg : forall u f_elem f_root ref,
  f_elem >= 0 ->
  f_root >= 0 ->
  ref >= 0 ->
  match u with
  | UnitPx v => v >= 0
  | UnitEm tenths => tenths >= 0
  | UnitRem tenths => tenths >= 0
  | UnitPercent pct => pct >= 0
  end ->
  resolve_length_unit u f_elem f_root ref >= 0.
Proof.
  intros u f_elem f_root ref Hfe Hfr Href Hu.
  destruct u as [v | tenths | tenths | pct]; cbn in *; unfold resolve_length_unit, kFixedPointDenominator.
  - lia.
  - apply Z.le_ge. apply Z.div_pos; [nia | lia].
  - apply Z.le_ge. apply Z.div_pos; [nia | lia].
  - apply Z.le_ge. apply Z.div_pos; [nia | lia].
Qed.

Theorem resolve_em_monotonic_in_font_size : forall tenths f1 f2 f_root ref,
  tenths >= 0 ->
  0 <= f1 <= f2 ->
  resolve_length_unit (UnitEm tenths) f1 f_root ref <=
  resolve_length_unit (UnitEm tenths) f2 f_root ref.
Proof.
  intros tenths f1 f2 f_root ref Ht [Hf1_pos Hf12].
  unfold resolve_length_unit, kFixedPointDenominator.
  apply Z.div_le_mono; [lia |].
  nia.
Qed.
