(* Formalization generated via HM Hybrid Architecture *)
(* De-imperativized SSA AST + Robinson MGU Row Typing + WP Assertion Mining + Dale Miller Presburger LIA *)
Require Import ZArith.
Require Import Bool.
Require Import Lia.
Open Scope Z_scope.

Record SkiaSDFCoverageAlpha := mkSkiaSDFCoverageAlpha {
  skiasdfcoveragealpha_signed_dist_q8 : Z
}.

Definition sdf_coverage_u8 (sd_q8 : Z) : Z :=
  Z.max 0 (Z.min 255 (128 - sd_q8)).

Theorem sdf_coverage_u8_bounded :
  forall (sd_q8 : Z), 0 <= sdf_coverage_u8 sd_q8 <= 255.
Proof.
  intros sd_q8. unfold sdf_coverage_u8. lia.
Qed.
