Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink :is() Maximum Specificity Semantics *)
(** CSS Selectors 4 §4.2: specificity of :is(s1, s2) equals max(spec(s1), spec(s2)) *)

Definition resolve_is_specificity (s1 s2 : Z) : Z :=
  Z.max s1 s2.

Theorem is_specificity_ge_first : forall s1 s2,
  s1 <= resolve_is_specificity s1 s2.
Proof.
  intros s1 s2.
  unfold resolve_is_specificity; lia.
Qed.

Theorem is_specificity_ge_second : forall s1 s2,
  s2 <= resolve_is_specificity s1 s2.
Proof.
  intros s1 s2.
  unfold resolve_is_specificity; lia.
Qed.
