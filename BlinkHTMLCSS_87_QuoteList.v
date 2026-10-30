(* Blink2Coq HTML/CSS Synthesis for QuoteList *)
(* Source: renderer/core/layout/list/quote_list.cc *)

From Stdlib Require Import ZArith Lia. Open Scope Z_scope.
Definition close_quote_depth (d : Z) : Z := Z.max 0 (d - 1).
Theorem quote_depth_nonnegative : forall d,
  0 <= close_quote_depth d.
Proof. intros. unfold close_quote_depth. apply Z.le_max_l. Qed.
