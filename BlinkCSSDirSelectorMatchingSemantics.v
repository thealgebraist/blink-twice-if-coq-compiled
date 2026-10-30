Require Import ZArith.
Require Import Lia.
Require Import Bool.
Open Scope Z_scope.

(** * Blink :dir() Directionality Matching Semantics *)
(** CSS Selectors 4 §11: effective directionality boolean branch *)

Definition matches_dir (is_rtl target_rtl : bool) : bool :=
  Bool.eqb is_rtl target_rtl.

Theorem dir_matches_same : forall d,
  matches_dir d d = true.
Proof.
  intros d.
  unfold matches_dir.
  apply Bool.eqb_reflx.
Qed.
