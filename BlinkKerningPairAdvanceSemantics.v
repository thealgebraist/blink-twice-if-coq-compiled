Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Kerning Pair Advance Semantics *)
(** CSS Text 4 §4: pair kerning adjustment *)

Definition apply_pair_kerning (base_advance kern_val : Z) : Z :=
  base_advance + kern_val.

Theorem zero_kerning_is_identity : forall adv,
  apply_pair_kerning adv 0 = adv.
Proof.
  intros adv.
  unfold apply_pair_kerning; lia.
Qed.

Theorem kerning_additive_composition : forall adv k1 k2,
  apply_pair_kerning (apply_pair_kerning adv k1) k2 =
  apply_pair_kerning adv (k1 + k2).
Proof.
  intros adv k1 k2.
  unfold apply_pair_kerning; lia.
Qed.
