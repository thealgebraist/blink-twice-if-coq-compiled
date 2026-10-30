(* Blink2Coq HTML/CSS Synthesis for CSSCustomProperty *)
(* Source: renderer/core/css/resolver/style_cascade.cc *)

Require Import ZArith Bool. Open Scope Z_scope.
Definition resolve_var_cycle (val fallback : Z) (has_cycle : bool) : Z :=
  if has_cycle then fallback else val.
Theorem var_cycle_falls_back : forall val fallback,
  resolve_var_cycle val fallback true = fallback.
Proof. intros. reflexivity. Qed.
