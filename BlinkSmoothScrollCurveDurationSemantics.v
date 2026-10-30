Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Smooth Scroll Duration Semantics *)
(** CSSOM View §4: smooth scroll animation duration bounds *)

Definition compute_smooth_scroll_duration (dist : Z) : Z :=
  let d := Z.abs dist in
  Z.max 100 (Z.min 1000 (100 + d / 2)).

Theorem smooth_scroll_duration_bounded : forall dist,
  100 <= compute_smooth_scroll_duration dist <= 1000.
Proof.
  intros dist.
  unfold compute_smooth_scroll_duration.
  lia.
Qed.
