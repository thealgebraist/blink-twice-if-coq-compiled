Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink WebGPU Buffer Size Alignment Semantics *)
(** WebGPU §6.2: buffer size aligned to 4 bytes *)

Definition align_to_4 (sz : Z) : Z :=
  ((sz + 3) / 4) * 4.

Theorem align_to_4_ge : forall sz,
  0 <= sz ->
  sz <= align_to_4 sz.
Proof.
  intros sz Hsz.
  unfold align_to_4.
  assert (Hpos: 4 <> 0) by lia.
  pose proof (Z.div_mod (sz + 3) 4 Hpos) as Hdm.
  assert (0 <= (sz + 3) mod 4 < 4) by (apply Z.mod_pos_bound; lia).
  rewrite (Z.mul_comm ((sz + 3) / 4) 4).
  lia.
Qed.

Theorem align_to_4_mod_4_zero : forall sz,
  align_to_4 sz mod 4 = 0.
Proof.
  intros sz.
  unfold align_to_4.
  apply Z_mod_mult.
Qed.
