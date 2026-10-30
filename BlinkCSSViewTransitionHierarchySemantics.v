Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink View Transitions Pseudo Elements Semantics *)
(** CSS View Transitions 1 §3: ::view-transition tree depth strict progression *)

Definition next_view_transition_layer (current_depth : Z) : Z :=
  current_depth + 1.

Theorem view_transition_layer_strictly_monotonic : forall d,
  d < next_view_transition_layer d.
Proof.
  intros d.
  unfold next_view_transition_layer; lia.
Qed.
