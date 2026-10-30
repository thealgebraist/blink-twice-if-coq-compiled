Require Import ZArith.
Require Import Bool.
Open Scope Z_scope.

(** * Blink Push UserVisibleOnly Requirement Semantics *)
(** Push API §6: userVisibleOnly must be true in Chromium *)

Definition options_valid (user_visible_only : bool) : bool :=
  user_visible_only.

Theorem user_visible_only_mandatory : forall uvo,
  options_valid uvo = true <-> uvo = true.
Proof.
  intros uvo.
  unfold options_valid.
  split; auto.
Qed.
