Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Widow Line Count Enforcement Semantics *)
(** CSS Fragmentation 3 §4.1: widows minimum lines check *)

Definition satisfies_widow_constraint (lines_after_break widows_setting : Z) : bool :=
  let min_lines := Z.max 1 widows_setting in
  min_lines <=? lines_after_break.

Theorem widow_constraint_sound : forall lines widows,
  satisfies_widow_constraint lines widows = true <-> Z.max 1 widows <= lines.
Proof.
  intros lines widows.
  unfold satisfies_widow_constraint.
  apply Z.leb_le.
Qed.
