Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Orphan Line Count Enforcement Semantics *)
(** CSS Fragmentation 3 §4.1: orphans minimum lines check *)

Definition satisfies_orphan_constraint (lines_before_break orphans_setting : Z) : bool :=
  let min_lines := Z.max 1 orphans_setting in
  min_lines <=? lines_before_break.

Theorem orphan_constraint_sound : forall lines orphans,
  satisfies_orphan_constraint lines orphans = true <-> Z.max 1 orphans <= lines.
Proof.
  intros lines orphans.
  unfold satisfies_orphan_constraint.
  apply Z.leb_le.
Qed.
