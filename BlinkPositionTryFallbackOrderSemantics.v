Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink @position-try Fallback Evaluation Order Semantics *)
(** CSS Anchor Positioning §4: sequential fallback until overflow eliminated *)

Definition evaluate_position_try (has_overflow : bool) (cur_idx : Z) : Z :=
  if has_overflow then cur_idx + 1 else cur_idx.

Theorem position_try_advances_on_overflow : forall idx,
  evaluate_position_try true idx = idx + 1.
Proof.
  intros idx; reflexivity.
Qed.

Theorem position_try_halts_on_success : forall idx,
  evaluate_position_try false idx = idx.
Proof.
  intros idx; reflexivity.
Qed.
