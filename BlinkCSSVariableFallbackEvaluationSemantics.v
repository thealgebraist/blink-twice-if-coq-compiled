Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink CSS var() Fallback Evaluation Semantics *)
(** CSS Custom Properties 1 §3: var(--x, fallback) evaluates fallback on invalid *)

Definition eval_var_fallback (is_valid : bool) (val fallback : Z) : Z :=
  if is_valid then val else fallback.

Theorem var_fallback_used_when_invalid : forall v f,
  eval_var_fallback false v f = f.
Proof.
  intros v f; reflexivity.
Qed.

Theorem var_primary_used_when_valid : forall v f,
  eval_var_fallback true v f = v.
Proof.
  intros v f; reflexivity.
Qed.
