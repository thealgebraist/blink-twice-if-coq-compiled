Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Inactive Timeline on Zero Range Semantics *)
(** Scroll-driven Animations 1 §2.3: inactive state detection *)

Definition is_scroll_timeline_active (start_pos end_pos : Z) : bool :=
  start_pos <? end_pos.

Theorem zero_range_is_inactive : forall start_pos end_pos,
  end_pos <= start_pos ->
  is_scroll_timeline_active start_pos end_pos = false.
Proof.
  intros start_pos end_pos Hle.
  unfold is_scroll_timeline_active.
  apply Z.ltb_ge.
  lia.
Qed.
