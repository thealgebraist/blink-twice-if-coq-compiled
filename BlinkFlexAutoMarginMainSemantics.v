From Stdlib Require Import ZArith Lists.List Bool Lia.
Open Scope Z_scope.

Definition flex_main_auto_margin (line_size items_size auto_count : Z) : Z :=
  let free_space := Z.max 0 (line_size - items_size) in
  if auto_count <=? 0 then 0
  else free_space / auto_count.

Theorem flex_main_auto_margin_nonneg : forall line_size items_size auto_count,
  flex_main_auto_margin line_size items_size auto_count >= 0.
Proof.
  intros. unfold flex_main_auto_margin.
  destruct (auto_count <=? 0) eqn:E; [lia |].
  apply Z.leb_gt in E.
  assert (Hpos: 0 <= Z.max 0 (line_size - items_size)) by lia.
  assert (Hdiv: 0 <= Z.max 0 (line_size - items_size) / auto_count).
  { apply Z.div_pos; lia. }
  lia.
Qed.

Theorem flex_main_auto_margin_bounded : forall line_size items_size auto_count,
  auto_count > 0 ->
  auto_count * flex_main_auto_margin line_size items_size auto_count <=
  Z.max 0 (line_size - items_size).
Proof.
  intros line_size items_size auto_count Hc.
  unfold flex_main_auto_margin.
  assert (E: (auto_count <=? 0) = false) by (apply Z.leb_gt; lia).
  rewrite E.
  assert (Hpos: 0 < auto_count) by lia.
  pose proof (Z.mul_div_le (Z.max 0 (line_size - items_size)) auto_count Hpos) as Hle.
  exact Hle.
Qed.
