Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink :where() Zero Specificity Semantics *)
(** CSS Selectors 4 §4.3: specificity of :where(...) is identically 0 *)

Definition where_specificity (arg_spec : Z) : Z :=
  0.

Theorem where_always_zero : forall s,
  where_specificity s = 0.
Proof.
  intros s; reflexivity.
Qed.
