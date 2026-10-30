Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Adjoining Floats Clearance Semantics *)
(** CSS 2.1 §9.5.2: clear property clearance calculation *)

Definition compute_clearance (float_bottom hypothetical_top margin_top : Z) : Z :=
  Z.max 0 (float_bottom - (hypothetical_top + margin_top)).

Theorem clearance_nonneg : forall fb ht mt,
  compute_clearance fb ht mt >= 0.
Proof.
  intros fb ht mt.
  unfold compute_clearance.
  apply Z.le_ge.
  apply Z.le_max_l.
Qed.

Theorem clearance_clears_float : forall fb ht mt,
  ht + mt + compute_clearance fb ht mt >= fb.
Proof.
  intros fb ht mt.
  unfold compute_clearance.
  pose proof (Z.le_max_r 0 (fb - (ht + mt))).
  lia.
Qed.
