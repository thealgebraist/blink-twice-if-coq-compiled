(* Blink2Coq HTML/CSS Synthesis for CounterManager *)
(* Source: renderer/core/css/counter_manager.cc *)

From Stdlib Require Import ZArith Lia. Open Scope Z_scope.
Definition apply_counter_increment (c delta : Z) : Z := c + delta.
Theorem counter_increment_additivity : forall c d1 d2,
  apply_counter_increment (apply_counter_increment c d1) d2 =
  apply_counter_increment c (d1 + d2).
Proof. intros. unfold apply_counter_increment. lia. Qed.
