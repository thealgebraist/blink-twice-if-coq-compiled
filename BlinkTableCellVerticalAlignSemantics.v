(* ========================================================================= *)
(*               BlinkTableCellVerticalAlignSemantics.v                      *)
(* ========================================================================= *)
(* Formal semantics of Chromium Blink Table Cell Vertical Alignment per      *)
(* W3C CSS 2.1 §17.5.3 (top, middle, bottom, baseline).                     *)
(* Strictly verified with 0 admits.                                          *)
(* ========================================================================= *)

From Stdlib Require Import ZArith Lists.List Bool.Bool Lia.
Open Scope Z_scope.

Inductive VerticalAlignMode :=
  | VAlignTop
  | VAlignMiddle
  | VAlignBottom
  | VAlignBaseline (row_baseline cell_baseline : Z).

Definition compute_cell_vertical_offset (mode : VerticalAlignMode) (row_h cell_h : Z) : Z :=
  match mode with
  | VAlignTop => 0
  | VAlignMiddle => (row_h - cell_h) / 2
  | VAlignBottom => row_h - cell_h
  | VAlignBaseline rb cb => Z.max 0 (rb - cb)
  end.

Theorem cell_top_offset_zero : forall row_h cell_h,
  compute_cell_vertical_offset VAlignTop row_h cell_h = 0.
Proof.
  intros. reflexivity.
Qed.

Theorem cell_offset_nonneg : forall mode row_h cell_h,
  0 <= cell_h <= row_h ->
  compute_cell_vertical_offset mode row_h cell_h >= 0.
Proof.
  intros mode row_h cell_h [Hcell_pos Hle].
  destruct mode; cbn.
  - lia.
  - apply Z.le_ge. apply Z.div_pos; lia.
  - lia.
  - apply Z.le_ge. apply Z.le_max_l.
Qed.

Theorem cell_contained_in_row_standard : forall mode row_h cell_h,
  mode = VAlignTop \/ mode = VAlignMiddle \/ mode = VAlignBottom ->
  0 <= cell_h <= row_h ->
  compute_cell_vertical_offset mode row_h cell_h + cell_h <= row_h.
Proof.
  intros mode row_h cell_h Hmode [Hcell_pos Hle].
  destruct Hmode as [Htop | [Hmid | Hbot]].
  - subst mode. cbn. lia.
  - subst mode. cbn.
    pose proof (Z.div_le_upper_bound (row_h - cell_h) 2 (row_h - cell_h)) as Hup.
    assert ((row_h - cell_h) / 2 <= row_h - cell_h).
    { apply Hup; lia. }
    lia.
  - subst mode. cbn. lia.
Qed.

Theorem cell_middle_centering_parity : forall row_h cell_h,
  0 <= cell_h <= row_h ->
  let top_space := compute_cell_vertical_offset VAlignMiddle row_h cell_h in
  let bottom_space := row_h - (top_space + cell_h) in
  Z.abs (top_space - bottom_space) <= 1.
Proof.
  intros row_h cell_h Hle.
  cbn.
  pose proof (Z.div_mod (row_h - cell_h) 2) as Hdiv.
  assert (Htwo: 2 <> 0) by lia.
  specialize (Hdiv Htwo).
  pose proof (Z.mod_pos_bound (row_h - cell_h) 2) as Hbound.
  assert (Hpos: 0 < 2) by lia.
  specialize (Hbound Hpos).
  assert (Hrem: (row_h - cell_h) mod 2 = 0 \/ (row_h - cell_h) mod 2 = 1) by lia.
  destruct Hrem as [H0 | H1]; lia.
Qed.
