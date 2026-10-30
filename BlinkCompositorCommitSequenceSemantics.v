Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Compositor Commit Frame Token Semantics *)
(** HTML / Rendering §7.5: frame token strictly monotonic on commit *)

Definition next_commit_token (t : Z) : Z :=
  t + 1.

Theorem commit_token_strictly_monotonic : forall t,
  t < next_commit_token t.
Proof.
  intros t.
  unfold next_commit_token; lia.
Qed.
