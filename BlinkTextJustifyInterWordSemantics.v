(* ========================================================================= *)
(*               BlinkTextJustifyInterWordSemantics.v                       *)
(* ========================================================================= *)
(* Formal verification of Chromium Blink Text Justification Inter-Word Space *)
(* Distribution against CSS Text 3 §7.3.3. Fully constructive, 0 admits.     *)
(* ========================================================================= *)

From Stdlib Require Import ZArith Lists.List Bool Lia.
Open Scope Z_scope.

Definition compute_inter_word_space (avail_w line_w space_count : Z) : Z :=
  let free_space := Z.max 0 (avail_w - line_w) in
  if space_count <=? 0 then 0
  else free_space / space_count.

Theorem inter_word_space_nonneg : forall avail_w line_w space_count,
  compute_inter_word_space avail_w line_w space_count >= 0.
Proof.
  intros. unfold compute_inter_word_space.
  destruct (space_count <=? 0) eqn:E; [lia |].
  apply Z.leb_gt in E.
  assert (0 <= Z.max 0 (avail_w - line_w)) by lia.
  assert (0 <= Z.max 0 (avail_w - line_w) / space_count).
  { apply Z.div_pos; lia. }
  lia.
Qed.

Theorem inter_word_space_bounded : forall avail_w line_w space_count,
  space_count > 0 ->
  space_count * compute_inter_word_space avail_w line_w space_count <=
  Z.max 0 (avail_w - line_w).
Proof.
  intros avail_w line_w space_count Hc.
  unfold compute_inter_word_space.
  assert (E: (space_count <=? 0) = false) by (apply Z.leb_gt; lia).
  rewrite E.
  assert (0 < space_count) by lia.
  pose proof (Z.mul_div_le (Z.max 0 (avail_w - line_w)) space_count H) as Hle.
  exact Hle.
Qed.
