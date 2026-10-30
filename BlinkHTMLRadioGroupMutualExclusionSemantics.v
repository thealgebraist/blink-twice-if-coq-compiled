Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Radio Group Mutual Exclusion Semantics *)
(** HTML Standard §4.10.5.1: radio selection state assignment *)

Definition select_radio (prev_selected : bool) (new_selected : bool) : bool :=
  new_selected.

Theorem radio_select_sets_state : forall p s,
  select_radio p s = s.
Proof.
  intros p s; reflexivity.
Qed.
