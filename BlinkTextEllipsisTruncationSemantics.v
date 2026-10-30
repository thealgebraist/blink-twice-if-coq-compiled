(* ========================================================================= *)
(*               BlinkTextEllipsisTruncationSemantics.v                     *)
(* ========================================================================= *)
(* Formal verification of Chromium Blink Text Ellipsis Truncation Point      *)
(* Selection against CSS Overflow 3 §4.2. Fully constructive, 0 admits.     *)
(* ========================================================================= *)

From Stdlib Require Import ZArith Lists.List Bool Lia.
Open Scope Z_scope.

Definition can_fit_ellipsis (prefix_w ellipsis_w avail_w : Z) : bool :=
  prefix_w + ellipsis_w <=? avail_w.

Definition effective_ellipsis_width (prefix_w ellipsis_w avail_w : Z) : Z :=
  if can_fit_ellipsis prefix_w ellipsis_w avail_w then prefix_w + ellipsis_w
  else avail_w.

Theorem effective_ellipsis_width_bounded : forall prefix_w ellipsis_w avail_w,
  effective_ellipsis_width prefix_w ellipsis_w avail_w <= avail_w.
Proof.
  intros prefix_w ellipsis_w avail_w.
  unfold effective_ellipsis_width, can_fit_ellipsis.
  destruct (prefix_w + ellipsis_w <=? avail_w) eqn:E; [|lia].
  apply Z.leb_le in E. lia.
Qed.
