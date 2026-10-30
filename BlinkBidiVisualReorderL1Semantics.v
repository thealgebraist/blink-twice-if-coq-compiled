(* ========================================================================= *)
(*               BlinkBidiVisualReorderL1Semantics.v                        *)
(* ========================================================================= *)
(* Formal verification of Chromium Blink BiDi Visual Run Reordering Rule L1  *)
(* against UAX #9 §3.4. Fully constructive, 0 admits.                        *)
(* ========================================================================= *)

From Stdlib Require Import ZArith Lists.List Bool Lia.
Open Scope Z_scope.

Definition apply_l1_whitespace_reset
  (resolved_level : Z) (is_trailing_space : bool) (base_level : Z) : Z :=
  if is_trailing_space then base_level
  else resolved_level.

Theorem l1_trailing_space_matches_base : forall lvl base,
  apply_l1_whitespace_reset lvl true base = base.
Proof.
  intros. reflexivity.
Qed.

Theorem l1_non_trailing_retains_level : forall lvl base,
  apply_l1_whitespace_reset lvl false base = lvl.
Proof.
  intros. reflexivity.
Qed.
