Require Import ZArith.
Require Import Bool.
Open Scope Z_scope.

(** * Blink Notification Permission State Progression Semantics *)
(** Notifications API §4.3: NotificationPermission {default, granted, denied} *)

Inductive notif_perm_state : Type :=
| PermDefault
| PermGranted
| PermDenied.

Definition valid_perm_transition (from_s to_s : notif_perm_state) : bool :=
  match from_s, to_s with
  | PermDefault, PermGranted => true
  | PermDefault, PermDenied  => true
  | PermGranted, PermDenied  => true
  | PermDenied,  _           => false
  | _, _                     => false
  end.

Theorem denied_is_terminal : forall s,
  valid_perm_transition PermDenied s = false.
Proof.
  intros s.
  destruct s; reflexivity.
Qed.
