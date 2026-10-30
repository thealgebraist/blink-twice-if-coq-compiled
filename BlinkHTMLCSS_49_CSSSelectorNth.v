(* Blink2Coq HTML/CSS Synthesis for CSSSelectorNth *)
(* Source: renderer/core/css/css_selector.cc *)

Require Import ZArith Lia. Open Scope Z_scope.
Definition nth_index (a b n : Z) : Z := a * n + b.
Theorem nth_index_strictly_monotonic : forall a b n,
  0 < a -> nth_index a b n < nth_index a b (n + 1).
Proof. intros. unfold nth_index. lia. Qed.
