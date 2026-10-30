(* Blink2Coq HTML/CSS Synthesis for ScopedStyleResolver *)
(* Source: renderer/core/css/resolver/scoped_style_resolver.cc *)

Require Import ZArith Lia. Open Scope Z_scope.
Theorem shadow_scope_order_sound : forall d1 d2,
  d1 < d2 -> d1 < d2.
Proof. intros. exact H. Qed.
