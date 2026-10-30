Require Import ZArith.
Require Import Bool.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Badging Count Clamping Semantics *)
(** Badging API §4.1: setAppBadge(contents) contents clamped to >= 1 *)

Definition clamp_badge_count (c : Z) : Z :=
  if c <=? 0 then 1 else c.

Theorem clamp_badge_count_positive : forall c,
  clamp_badge_count c >= 1.
Proof.
  intros c.
  unfold clamp_badge_count.
  destruct (c <=? 0) eqn:E.
  - lia.
  - apply Z.leb_gt in E. lia.
Qed.
