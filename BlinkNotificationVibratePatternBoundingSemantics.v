Require Import ZArith.
Require Import Bool.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Notification Vibration Duration Bounding Semantics *)
(** Notifications API §4.1 / Vibration API: single vibration duration bounded by 10000ms *)

Definition clamp_vibration (d : Z) : Z :=
  if d <=? 0 then 0
  else if 10000 <? d then 10000
  else d.

Theorem clamp_vibration_bounds : forall d,
  0 <= clamp_vibration d <= 10000.
Proof.
  intros d.
  unfold clamp_vibration.
  destruct (d <=? 0) eqn:E0.
  - lia.
  - apply Z.leb_gt in E0.
    destruct (10000 <? d) eqn:E1.
    + lia.
    + apply Z.ltb_ge in E1.
      lia.
Qed.
