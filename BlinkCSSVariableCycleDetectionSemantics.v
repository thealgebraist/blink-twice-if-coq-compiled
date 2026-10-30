Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink CSS Variable Cycle Detection Semantics *)
(** CSS Custom Properties 1 §3: circular var() reference yields guaranteed-invalid *)

Inductive VarResolution :=
  | ResolvedVal (v : Z)
  | GuaranteedInvalid.

Definition resolve_var_dependency (has_cycle : bool) (val : Z) : VarResolution :=
  if has_cycle then GuaranteedInvalid else ResolvedVal val.

Theorem cyclic_var_is_guaranteed_invalid : forall v,
  resolve_var_dependency true v = GuaranteedInvalid.
Proof.
  intros v; reflexivity.
Qed.

Theorem acyclic_var_is_resolved : forall v,
  resolve_var_dependency false v = ResolvedVal v.
Proof.
  intros v; reflexivity.
Qed.
