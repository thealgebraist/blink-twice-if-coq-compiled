Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink ScrollingCoordinator Sync Semantics *)
(** Blink Scrolling Architecture §2: compositor scroll offset matches main thread on commit *)

Definition commit_scroll_offset (main_thread_offset : Z) : Z :=
  main_thread_offset.

Theorem compositor_offset_matches_main_thread : forall off,
  commit_scroll_offset off = off.
Proof.
  intros off.
  reflexivity.
Qed.
