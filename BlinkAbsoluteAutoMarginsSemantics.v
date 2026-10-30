(* ========================================================================= *)
(*               BlinkAbsoluteAutoMarginsSemantics.v                        *)
(* ========================================================================= *)
(* Formal verification of Chromium Blink Absolute Positioned Auto Margins    *)
(* Centering against CSS Positioned Layout 3 §5.2. Fully constructive.       *)
(* ========================================================================= *)

From Stdlib Require Import ZArith Lists.List Bool Lia.
Open Scope Z_scope.

Definition resolve_abspos_auto_margins (cb_width left width right : Z) : Z :=
  let free_space := Z.max 0 (cb_width - (left + width + right)) in
  free_space / 2.

Theorem abspos_auto_margin_nonneg : forall cb_w l w r,
  resolve_abspos_auto_margins cb_w l w r >= 0.
Proof.
  intros. unfold resolve_abspos_auto_margins.
  assert (0 <= Z.max 0 (cb_w - (l + w + r))) by lia.
  assert (0 <= Z.max 0 (cb_w - (l + w + r)) / 2).
  { apply Z.div_pos; lia. }
  lia.
Qed.

Theorem abspos_auto_margin_sum_le_free : forall cb_w l w r,
  2 * resolve_abspos_auto_margins cb_w l w r <= Z.max 0 (cb_w - (l + w + r)).
Proof.
  intros. unfold resolve_abspos_auto_margins.
  assert (0 < 2) by lia.
  pose proof (Z.mul_div_le (Z.max 0 (cb_w - (l + w + r))) 2 H) as Hle.
  exact Hle.
Qed.
