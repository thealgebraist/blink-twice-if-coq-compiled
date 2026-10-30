Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink ShadowRoot Closed Mode Access Semantics *)
(** DOM Standard §4.2.2: closed shadowRoot returns null *)

Definition access_shadow_root (is_closed : bool) (root_id : Z) : option Z :=
  if is_closed then None else Some root_id.

Theorem closed_shadow_root_returns_none : forall r,
  access_shadow_root true r = None.
Proof.
  intros r; reflexivity.
Qed.

Theorem open_shadow_root_returns_some : forall r,
  access_shadow_root false r = Some r.
Proof.
  intros r; reflexivity.
Qed.
