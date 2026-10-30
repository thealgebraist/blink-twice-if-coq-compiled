Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink CSS Layout Worklet Custom Fragment Bounds Semantics *)
(** CSS Layout API 1 §3: custom layout fragment dimension lower bound *)

Definition resolve_worklet_fragment_dimension (req min_dim : Z) : Z :=
  Z.max min_dim req.

Theorem worklet_fragment_satisfies_min : forall r m,
  m <= resolve_worklet_fragment_dimension r m.
Proof.
  intros r m.
  unfold resolve_worklet_fragment_dimension; lia.
Qed.
