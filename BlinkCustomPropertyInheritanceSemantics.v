From Stdlib Require Import ZArith Lia.
Open Scope Z_scope.

(* CSS Variables 1 §3 Custom Property Inheritance Pass-Through *)
Definition resolve_custom_property (local_decl : option Z) (inherited_val : Z) : Z :=
  match local_decl with
  | Some v => v
  | None => inherited_val
  end.

Theorem declared_property_overrides : forall v inherited_val,
  resolve_custom_property (Some v) inherited_val = v.
Proof.
  intros. unfold resolve_custom_property. reflexivity.
Qed.

Theorem missing_declaration_inherits : forall inherited_val,
  resolve_custom_property None inherited_val = inherited_val.
Proof.
  intros. unfold resolve_custom_property. reflexivity.
Qed.
