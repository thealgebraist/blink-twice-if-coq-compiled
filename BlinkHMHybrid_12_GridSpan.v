(* Formalization generated via HM Hybrid Architecture *)
(* De-imperativized SSA AST + Robinson MGU Row Typing + WP Assertion Mining + Dale Miller Presburger LIA *)
Require Import ZArith.
Require Import Bool.
Require Import Lia.
Open Scope Z_scope.

Record GridSpan := mkGridSpan {
  gridspan_start_line : Z;
  gridspan_end_line : Z
}.

Definition shift_span (line : Z) (offset : Z) : Z :=
  line + offset.

Theorem shift_span_preserves_length :
  forall (s e off : Z), shift_span e off - shift_span s off = e - s.
Proof.
  intros s e off. unfold shift_span. ring.
Qed.
