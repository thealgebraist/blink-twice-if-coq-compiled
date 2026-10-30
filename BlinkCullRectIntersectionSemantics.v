Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Cull Rect Intersection Semantics *)
(** Blink Paint Culling §1: out-of-view geometry discarded *)

Definition is_culled (rect_max cull_min : Z) : bool :=
  rect_max <? cull_min.

Theorem culled_when_strictly_before : forall r c,
  r < c ->
  is_culled r c = true.
Proof.
  intros r c H.
  unfold is_culled.
  apply Z.ltb_lt; exact H.
Qed.

Theorem not_culled_when_overlapping : forall r c,
  c <= r ->
  is_culled r c = false.
Proof.
  intros r c H.
  unfold is_culled.
  apply Z.ltb_ge; exact H.
Qed.
