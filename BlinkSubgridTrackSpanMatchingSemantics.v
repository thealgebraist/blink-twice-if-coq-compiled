Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Subgrid Track Span Matching Semantics *)
(** CSS Grid 2 §2: subgrid track span matches parent grid span *)

Definition subgrid_track_span (parent_start parent_end : Z) : Z :=
  Z.max 0 (parent_end - parent_start).

Theorem subgrid_span_nonneg : forall s e,
  0 <= subgrid_track_span s e.
Proof.
  intros s e.
  unfold subgrid_track_span; lia.
Qed.

Theorem subgrid_span_exact : forall s e,
  s <= e ->
  subgrid_track_span s e = e - s.
Proof.
  intros s e H.
  unfold subgrid_track_span; lia.
Qed.
