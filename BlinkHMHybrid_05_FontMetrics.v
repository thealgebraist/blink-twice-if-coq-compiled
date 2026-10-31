(* Formalization generated via HM Hybrid Architecture *)
(* De-imperativized SSA AST + Robinson MGU Row Typing + WP Assertion Mining + Dale Miller Presburger LIA *)
Require Import ZArith.
Require Import Bool.
Require Import Lia.
Open Scope Z_scope.

Record FontMetrics := mkFontMetrics {
  fontmetrics_ascent : Z;
  fontmetrics_descent : Z;
  fontmetrics_line_gap : Z
}.

Definition compute_line_height (a : Z) (d : Z) (g : Z) : Z :=
  a + d + g.

Theorem line_height_monotonic :
  forall (a d g : Z), 0 <= a -> 0 <= d -> 0 <= g -> a <= compute_line_height a d g.
Proof.
  intros a d g Ha Hd Hg. unfold compute_line_height. lia.
Qed.
