Require Import ZArith.
Require Import Bool.
Open Scope Z_scope.

(** * Blink Notification Direction Enum Semantics *)
(** Notifications API §4.1: NotificationDirection {auto, ltr, rtl} *)

Inductive notif_direction : Type :=
| DirAuto
| DirLtr
| DirRtl.

Definition dir_to_int (d : notif_direction) : Z :=
  match d with
  | DirAuto => 0
  | DirLtr  => 1
  | DirRtl  => 2
  end.

Theorem dir_distinct : forall d1 d2,
  dir_to_int d1 = dir_to_int d2 -> d1 = d2.
Proof.
  intros d1 d2 H; destruct d1; destruct d2; simpl in H; try reflexivity; discriminate.
Qed.
