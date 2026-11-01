(* Formalization generated via HM Hybrid Architecture *)
(* De-imperativized SSA AST + Robinson MGU Row Typing + WP Assertion Mining + Dale Miller Presburger LIA *)
Require Import ZArith.
Require Import Bool.
Require Import Lia.
Open Scope Z_scope.

Record FloatExclusionBand := mkFloatExclusionBand {
  floatexclusionband_cb_left : Z;
  floatexclusionband_cb_right : Z;
  floatexclusionband_left_float_edge : Z;
  floatexclusionband_right_float_edge : Z
}.

Definition float_band_avail_width (cb_l : Z) (cb_r : Z) (fl_r : Z) (fr_l : Z) : Z :=
  Z.max 0 (Z.min cb_r fr_l - Z.max cb_l fl_r).

Theorem float_band_avail_width_within_cb :
  forall (cb_l cb_r fl_r fr_l : Z), cb_l <= cb_r -> 0 <= float_band_avail_width cb_l cb_r fl_r fr_l <= cb_r - cb_l.
Proof.
  intros cb_l cb_r fl_r fr_l Hcb. unfold float_band_avail_width. lia.
Qed.
