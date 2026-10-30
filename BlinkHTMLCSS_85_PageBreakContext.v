(* Blink2Coq HTML/CSS Synthesis for PageBreakContext *)
(* Source: renderer/core/layout/paged_media/page_break_context.cc *)

From Stdlib Require Import ZArith Lia. Open Scope Z_scope.
Definition next_page_number (p : Z) : Z := p + 1.
Theorem page_number_monotonic : forall p,
  p < next_page_number p.
Proof. intros. unfold next_page_number. lia. Qed.
