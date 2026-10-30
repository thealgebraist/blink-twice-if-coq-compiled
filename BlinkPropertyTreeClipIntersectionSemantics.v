Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Property Tree Clip Intersection Semantics *)
(** CSS Masking 1 §3: 1D interval bounding box intersection *)

Definition intersect_intervals (s1 e1 s2 e2 : Z) : (Z * Z) :=
  (Z.max s1 s2, Z.min e1 e2).

Theorem clip_intersection_subset1 : forall s1 e1 s2 e2,
  s1 <= fst (intersect_intervals s1 e1 s2 e2) /\
  snd (intersect_intervals s1 e1 s2 e2) <= e1.
Proof.
  intros s1 e1 s2 e2.
  unfold intersect_intervals; simpl; lia.
Qed.

Theorem clip_intersection_subset2 : forall s1 e1 s2 e2,
  s2 <= fst (intersect_intervals s1 e1 s2 e2) /\
  snd (intersect_intervals s1 e1 s2 e2) <= e2.
Proof.
  intros s1 e1 s2 e2.
  unfold intersect_intervals; simpl; lia.
Qed.
