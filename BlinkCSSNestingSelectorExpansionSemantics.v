Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink CSS Nesting & Selector Specificity Semantics *)
(** CSS Nesting 1 §3: & selector preserves parent specificity *)

Definition nesting_expanded_specificity (parent_spec : Z) : Z :=
  parent_spec.

Theorem nesting_specificity_preserves_parent : forall p,
  nesting_expanded_specificity p = p.
Proof.
  intros p; reflexivity.
Qed.
