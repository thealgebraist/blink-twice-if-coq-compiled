Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Fragment Container Sequence Semantics *)
(** Blink LayoutNG Fragmentation: fragment index monotonicity *)

Record FragmentContainer := {
  container_fragment_index : Z
}.

Definition next_fragment_container (c : FragmentContainer) : FragmentContainer :=
  {| container_fragment_index := container_fragment_index c + 1 |}.

Theorem container_sequence_strictly_monotonic : forall c,
  container_fragment_index c < container_fragment_index (next_fragment_container c).
Proof.
  intros c.
  unfold next_fragment_container; simpl.
  lia.
Qed.
