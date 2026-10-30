Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink CSS Custom Property Inheritance Semantics *)
(** CSS Custom Properties 1 §2: custom property inheritance down DOM tree *)

Definition inherit_custom_property (parent_val own_val : option Z) : option Z :=
  match own_val with
  | Some v => Some v
  | None => parent_val
  end.

Theorem own_custom_property_overrides_parent : forall p v,
  inherit_custom_property p (Some v) = Some v.
Proof.
  intros p v; reflexivity.
Qed.

Theorem inherit_parent_when_unspecified : forall p,
  inherit_custom_property p None = p.
Proof.
  intros p; reflexivity.
Qed.
