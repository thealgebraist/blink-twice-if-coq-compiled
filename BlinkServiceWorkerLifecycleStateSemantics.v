Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Service Worker Lifecycle State Progression Semantics *)
(** Service Workers §3.2: monotonic lifecycle progression *)

Definition LIFECYCLE_PARSED     : Z := 0.
Definition LIFECYCLE_INSTALLING : Z := 1.
Definition LIFECYCLE_INSTALLED  : Z := 2.
Definition LIFECYCLE_ACTIVATING : Z := 3.
Definition LIFECYCLE_ACTIVATED  : Z := 4.
Definition LIFECYCLE_REDUNDANT  : Z := 5.

Definition lifecycle_rank (st : Z) : Z := st.

Theorem lifecycle_monotonically_advances :
  lifecycle_rank LIFECYCLE_PARSED < lifecycle_rank LIFECYCLE_INSTALLING /\
  lifecycle_rank LIFECYCLE_INSTALLING < lifecycle_rank LIFECYCLE_INSTALLED /\
  lifecycle_rank LIFECYCLE_INSTALLED < lifecycle_rank LIFECYCLE_ACTIVATING /\
  lifecycle_rank LIFECYCLE_ACTIVATING < lifecycle_rank LIFECYCLE_ACTIVATED /\
  lifecycle_rank LIFECYCLE_ACTIVATED < lifecycle_rank LIFECYCLE_REDUNDANT.
Proof.
  unfold lifecycle_rank, LIFECYCLE_PARSED, LIFECYCLE_INSTALLING,
         LIFECYCLE_INSTALLED, LIFECYCLE_ACTIVATING, LIFECYCLE_ACTIVATED, LIFECYCLE_REDUNDANT.
  lia.
Qed.

Theorem redundant_is_terminal_rank : forall s,
  0 <= s <= 5 ->
  lifecycle_rank s <= lifecycle_rank LIFECYCLE_REDUNDANT.
Proof.
  intros s Hbounds.
  unfold lifecycle_rank, LIFECYCLE_REDUNDANT.
  lia.
Qed.
