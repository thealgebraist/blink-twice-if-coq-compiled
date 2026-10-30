(* Blink2Coq HTML/CSS Synthesis for AlignmentUtils *)
(* Source: renderer/core/layout/alignment_utils.cc *)

From Stdlib Require Import ZArith Lia. Open Scope Z_scope.
Definition center_offset (wc wi : Z) : Z := (wc - wi) / 2.
Theorem center_offset_bounded : forall wc wi,
  0 <= wi <= wc -> 0 <= center_offset wc wi <= wc.
Proof.
  intros wc wi [H1 H2]. unfold center_offset.
  assert (0 <= wc - wi) by lia.
  split.
  - apply Z.div_pos; lia.
  - assert (wc - wi <= wc) by lia.
    apply Z.div_le_upper_bound; lia.
Qed.
