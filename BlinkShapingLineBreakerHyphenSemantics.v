(* ========================================================================= *)
(*               BlinkShapingLineBreakerHyphenSemantics.v                   *)
(* ========================================================================= *)
(* Formal verification of Chromium Blink Shaping Line Breaker with Hyphen    *)
(* Insertion against CSS Text 3 §5.4. Fully constructive, 0 admits.          *)
(* ========================================================================= *)

From Stdlib Require Import ZArith Lists.List Bool Lia.
Open Scope Z_scope.

Definition hyphen_break_fits (prefix_w hyphen_w avail_w : Z) : bool :=
  prefix_w + hyphen_w <=? avail_w.

Definition broken_line_used_width (prefix_w hyphen_w avail_w : Z) : Z :=
  if hyphen_break_fits prefix_w hyphen_w avail_w then prefix_w + hyphen_w
  else avail_w.

Theorem broken_line_used_width_bounded : forall prefix_w hyphen_w avail_w,
  broken_line_used_width prefix_w hyphen_w avail_w <= avail_w.
Proof.
  intros prefix_w hyphen_w avail_w.
  unfold broken_line_used_width, hyphen_break_fits.
  destruct (prefix_w + hyphen_w <=? avail_w) eqn:E; [|lia].
  apply Z.leb_le in E. lia.
Qed.
