Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Media Query Boolean Evaluation Semantics *)
(** Media Queries 4 §3: min-width threshold evaluation soundness *)

Definition eval_min_width (viewport_w threshold : Z) : bool :=
  threshold <=? viewport_w.

Theorem min_width_satisfied : forall vp th,
  th <= vp ->
  eval_min_width vp th = true.
Proof.
  intros vp th H.
  unfold eval_min_width.
  apply Z.leb_le; exact H.
Qed.
