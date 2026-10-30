Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink FormData Entry Appending Semantics *)
(** XHR / Fetch §4: entry list monotonic accumulation *)

Definition append_form_entry (entry_count : Z) : Z :=
  entry_count + 1.

Theorem form_data_strictly_monotonic : forall c,
  c < append_form_entry c.
Proof.
  intros c.
  unfold append_form_entry; lia.
Qed.
