Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink DOMTimer Background Throttling Semantics *)
(** HTML Standard §8.6: background tab timer clamped to >= 1000ms *)

Definition BACKGROUND_MIN_INTERVAL : Z := 1000.

Definition effective_timer_interval (requested_ms : Z) (is_background : bool) : Z :=
  if is_background then Z.max requested_ms BACKGROUND_MIN_INTERVAL
  else requested_ms.

Theorem background_timer_at_least_1000ms : forall req,
  effective_timer_interval req true >= BACKGROUND_MIN_INTERVAL.
Proof.
  intros req.
  unfold effective_timer_interval.
  apply Z.le_ge.
  apply Z.le_max_r.
Qed.

Theorem foreground_timer_unthrottled : forall req,
  effective_timer_interval req false = req.
Proof.
  intros req.
  reflexivity.
Qed.
