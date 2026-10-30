(* Blink2Coq HTML/CSS Synthesis for StyleResolver *)
(* Source: renderer/core/css/resolver/style_resolver.cc *)

Require Import ZArith Bool. Open Scope Z_scope.
Definition resolve_inherited_value (parent_val initial_val : Z) (is_inherited : bool) : Z :=
  if is_inherited then parent_val else initial_val.
Theorem resolve_inherited_sound : forall p ini,
  resolve_inherited_value p ini true = p.
Proof. intros. reflexivity. Qed.
