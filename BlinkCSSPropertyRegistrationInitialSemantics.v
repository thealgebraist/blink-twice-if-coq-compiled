Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink CSS @property Registration Semantics *)
(** CSS Properties and Values 1 §2: registered default initial value *)

Definition resolve_registered_property (is_specified : bool) (specified_val initial_val : Z) : Z :=
  if is_specified then specified_val else initial_val.

Theorem initial_value_used_when_unspecified : forall s init,
  resolve_registered_property false s init = init.
Proof.
  intros s init; reflexivity.
Qed.

Theorem specified_value_used_when_specified : forall s init,
  resolve_registered_property true s init = s.
Proof.
  intros s init; reflexivity.
Qed.
