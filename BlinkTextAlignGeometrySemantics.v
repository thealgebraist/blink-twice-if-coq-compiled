(* ========================================================================= *)
(*               BlinkTextAlignGeometrySemantics.v                           *)
(* ========================================================================= *)
(* Formal semantics of Chromium Blink Text Alignment in Headers and Table     *)
(* Header Cells per W3C CSS Text Module Level 3 §7.                          *)
(* Strictly verified with 0 admits.                                          *)
(* ========================================================================= *)

From Stdlib Require Import ZArith Lists.List Bool.Bool Lia.
Open Scope Z_scope.

Inductive TextAlignMode :=
  | AlignLeft
  | AlignCenter
  | AlignRight.

Definition compute_text_align_offset (mode : TextAlignMode) (line_w content_w : Z) : Z :=
  match mode with
  | AlignLeft => 0
  | AlignCenter => (line_w - content_w) / 2
  | AlignRight => line_w - content_w
  end.

Theorem align_left_offset_zero : forall line_w content_w,
  compute_text_align_offset AlignLeft line_w content_w = 0.
Proof.
  intros. reflexivity.
Qed.

Theorem align_offset_nonneg : forall mode line_w content_w,
  0 <= content_w <= line_w ->
  compute_text_align_offset mode line_w content_w >= 0.
Proof.
  intros mode line_w content_w [Hpos Hle].
  destruct mode; cbn.
  - lia.
  - apply Z.le_ge. apply Z.div_pos; lia.
  - lia.
Qed.

Theorem align_content_fits_in_line : forall mode line_w content_w,
  0 <= content_w <= line_w ->
  compute_text_align_offset mode line_w content_w + content_w <= line_w.
Proof.
  intros mode line_w content_w [Hpos Hle].
  destruct mode; cbn.
  - lia.
  - pose proof (Z.div_le_upper_bound (line_w - content_w) 2 (line_w - content_w)) as Hup.
    assert ((line_w - content_w) / 2 <= line_w - content_w) by (apply Hup; lia).
    lia.
  - lia.
Qed.

Theorem align_center_parity : forall line_w content_w,
  0 <= content_w <= line_w ->
  let left_space := compute_text_align_offset AlignCenter line_w content_w in
  let right_space := line_w - (left_space + content_w) in
  Z.abs (left_space - right_space) <= 1.
Proof.
  intros line_w content_w Hle.
  cbn.
  pose proof (Z.div_mod (line_w - content_w) 2) as Hdiv.
  assert (Htwo: 2 <> 0) by lia.
  specialize (Hdiv Htwo).
  pose proof (Z.mod_pos_bound (line_w - content_w) 2) as Hbound.
  assert (Hpos: 0 < 2) by lia.
  specialize (Hbound Hpos).
  assert (Hrem: (line_w - content_w) mod 2 = 0 \/ (line_w - content_w) mod 2 = 1) by lia.
  destruct Hrem as [H0 | H1]; lia.
Qed.

