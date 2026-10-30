Require Import ZArith.
Require Import Lia.
Require Import Bool.
Open Scope Z_scope.

(** * Blink HTTP Method Safety & Idempotence Semantics *)
(** RFC 9110 §9.2: safe methods are idempotent *)

Definition M_GET      : Z := 1.
Definition M_HEAD     : Z := 2.
Definition M_OPTIONS  : Z := 3.
Definition M_TRACE    : Z := 4.
Definition M_PUT      : Z := 5.
Definition M_DELETE   : Z := 6.
Definition M_POST     : Z := 7.

Definition is_safe_method (m : Z) : bool :=
  (m =? M_GET) || (m =? M_HEAD) || (m =? M_OPTIONS) || (m =? M_TRACE).

Definition is_idempotent_method (m : Z) : bool :=
  is_safe_method m || (m =? M_PUT) || (m =? M_DELETE).

Theorem safe_implies_idempotent : forall m,
  is_safe_method m = true ->
  is_idempotent_method m = true.
Proof.
  intros m Hsafe.
  unfold is_idempotent_method.
  rewrite Hsafe.
  reflexivity.
Qed.

Theorem post_is_not_idempotent :
  is_idempotent_method M_POST = false.
Proof.
  reflexivity.
Qed.
