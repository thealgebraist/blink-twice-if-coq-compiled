Require Import ZArith.
Require Import Bool.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Badging Max Display Ceiling Semantics *)
(** Badging API §4.1: display count capped at 99+ *)

Definition display_badge_count (c : Z) : Z :=
  if 99 <? c then 99 else c.

Theorem display_badge_bounded : forall c,
  0 <= c ->
  0 <= display_badge_count c <= 99.
Proof.
  intros c Hc.
  unfold display_badge_count.
  destruct (99 <? c) eqn:E.
  - lia.
  - apply Z.ltb_ge in E. lia.
Qed.
