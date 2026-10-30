From Stdlib Require Import ZArith Lists.List Bool Lia.
Open Scope Z_scope.

Definition resolve_aspect_block_size (inline_size ratio_num ratio_den : Z) : Z :=
  if ratio_num <=? 0 then 0
  else (inline_size * ratio_den) / ratio_num.

Theorem resolve_aspect_block_size_nonneg : forall inline_size ratio_num ratio_den,
  inline_size >= 0 ->
  ratio_num > 0 ->
  ratio_den >= 0 ->
  resolve_aspect_block_size inline_size ratio_num ratio_den >= 0.
Proof.
  intros inline_size ratio_num ratio_den Hw Hnum Hden.
  unfold resolve_aspect_block_size.
  assert (E: (ratio_num <=? 0) = false) by (apply Z.leb_gt; lia).
  rewrite E.
  assert (Hprod: 0 <= inline_size * ratio_den) by nia.
  assert (Hdiv: 0 <= (inline_size * ratio_den) / ratio_num).
  { apply Z.div_pos; lia. }
  lia.
Qed.

Theorem resolve_aspect_block_size_scaled_exact : forall inline_size ratio_num ratio_den,
  ratio_num > 0 ->
  ratio_den >= 0 ->
  (inline_size * ratio_den) mod ratio_num = 0 ->
  resolve_aspect_block_size inline_size ratio_num ratio_den * ratio_num =
  inline_size * ratio_den.
Proof.
  intros inline_size ratio_num ratio_den Hnum Hden Hmod.
  unfold resolve_aspect_block_size.
  assert (E: (ratio_num <=? 0) = false) by (apply Z.leb_gt; lia).
  rewrite E.
  apply (Z.div_exact (inline_size * ratio_den) ratio_num ltac:(lia)) in Hmod.
  rewrite Z.mul_comm.
  rewrite <- Hmod.
  reflexivity.
Qed.
