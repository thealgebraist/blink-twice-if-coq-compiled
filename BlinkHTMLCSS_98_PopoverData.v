(* Blink2Coq HTML/CSS Synthesis for PopoverData *)
(* Source: renderer/core/html/html_popover_element.cc *)

From Stdlib Require Import ZArith Lia. Open Scope Z_scope.
Definition pop_popover_stack (sz : Z) : Z := Z.max 0 (sz - 1).
Theorem popover_dismiss_strictly_decreases : forall sz,
  0 < sz -> pop_popover_stack sz < sz.
Proof.
  intros sz Hpos. unfold pop_popover_stack.
  assert (sz - 1 < sz) by lia.
  assert (0 <= sz - 1) by lia.
  rewrite (Z.max_r 0 (sz - 1)); lia.
Qed.
