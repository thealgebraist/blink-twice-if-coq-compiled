Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink AXRole Determination Semantics *)
(** WAI-ARIA 1.2 §5: explicit ARIA role overrides native role *)

Definition resolve_role (has_aria_role : bool) (aria_role native_role : Z) : Z :=
  if has_aria_role then aria_role else native_role.

Theorem aria_role_overrides_native : forall ar nr,
  resolve_role true ar nr = ar.
Proof.
  intros ar nr; reflexivity.
Qed.

Theorem native_role_used_when_no_aria : forall ar nr,
  resolve_role false ar nr = nr.
Proof.
  intros ar nr; reflexivity.
Qed.
