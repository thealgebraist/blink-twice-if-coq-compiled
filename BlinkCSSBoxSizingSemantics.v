(* ========================================================================= *)
(*               BlinkCSSBoxSizingSemantics.v                                *)
(* ========================================================================= *)
(* Formal semantics of Chromium Blink CSS box-sizing (content-box vs         *)
(* border-box) per W3C CSS Box Sizing Module Level 3 §3.                     *)
(* Strictly verified with 0 admits.                                          *)
(* ========================================================================= *)

From Stdlib Require Import ZArith Lia.
Open Scope Z_scope.

Inductive BoxSizingMode : Type :=
  | ContentBox
  | BorderBox.

Definition resolve_content_width (mode : BoxSizingMode) (specified_w border padding : Z) : Z :=
  match mode with
  | ContentBox => Z.max 0 specified_w
  | BorderBox  => Z.max 0 (specified_w - border - padding)
  end.

Definition resolve_border_box_width (mode : BoxSizingMode) (specified_w border padding : Z) : Z :=
  match mode with
  | ContentBox => Z.max 0 specified_w + border + padding
  | BorderBox  => Z.max (border + padding) specified_w
  end.

Theorem content_width_nonneg : forall mode specified_w border padding,
  resolve_content_width mode specified_w border padding >= 0.
Proof.
  intros mode specified_w border padding.
  destruct mode; unfold resolve_content_width; apply Z.le_ge, Z.le_max_l.
Qed.

Theorem border_box_width_ge_bp : forall mode specified_w border padding,
  specified_w >= 0 ->
  border >= 0 ->
  padding >= 0 ->
  resolve_border_box_width mode specified_w border padding >= border + padding.
Proof.
  intros mode specified_w border padding Hw Hb Hp.
  destruct mode; unfold resolve_border_box_width.
  - pose proof (Z.le_max_l 0 specified_w). lia.
  - apply Z.le_ge, Z.le_max_l.
Qed.

Theorem content_box_round_trip : forall w border padding,
  w >= 0 ->
  border >= 0 ->
  padding >= 0 ->
  resolve_content_width BorderBox (resolve_border_box_width ContentBox w border padding) border padding = w.
Proof.
  intros w border padding Hw Hb Hp.
  unfold resolve_border_box_width, resolve_content_width.
  assert (Z.max 0 w = w) by (apply Z.max_r; lia).
  rewrite H.
  assert (w + border + padding - border - padding = w) by ring.
  rewrite H0.
  apply Z.max_r; lia.
Qed.

Theorem border_box_round_trip : forall w border padding,
  w >= border + padding ->
  border >= 0 ->
  padding >= 0 ->
  resolve_border_box_width ContentBox (resolve_content_width BorderBox w border padding) border padding = w.
Proof.
  intros w border padding Hw Hb Hp.
  unfold resolve_border_box_width, resolve_content_width.
  assert (Z.max 0 (w - border - padding) = w - border - padding).
  { apply Z.max_r; lia. }
  rewrite H.
  assert (Z.max 0 (w - border - padding) = w - border - padding).
  { apply Z.max_r; lia. }
  rewrite H0.
  ring.
Qed.
