(* Blink2Coq Synthesis for LineBreaker *)
(* Source: third_party/blink/renderer/core/layout/inline/line_breaker.cc *)

Require Import ZArith Lia. Open Scope Z_scope.
Definition consume_inline_space (avail item_w : Z) : Z := avail - item_w.
Theorem consume_inline_space_monotonic : forall avail item_w,
  0 <= item_w -> consume_inline_space avail item_w <= avail.
Proof. intros. unfold consume_inline_space. lia. Qed.
