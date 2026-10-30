Require Import ZArith.
Require Import Bool.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Table Colgroup Span Clamping Semantics *)
(** HTML Spec §4.9.3: colgroup span clamped to [1, 1000] *)

Definition clamp_colgroup_span (span : Z) : Z :=
  if span <=? 1 then 1
  else if 1000 <? span then 1000
  else span.

Theorem clamp_colgroup_span_sound : forall span,
  1 <= clamp_colgroup_span span <= 1000.
Proof.
  intros span.
  unfold clamp_colgroup_span.
  destruct (span <=? 1) eqn:E1.
  - lia.
  - apply Z.leb_gt in E1.
    destruct (1000 <? span) eqn:E2.
    + lia.
    + apply Z.ltb_ge in E2.
      lia.
Qed.
