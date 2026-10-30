(* Blink2Coq HTML/CSS Synthesis for ColorGamutMapping *)
(* Source: renderer/core/css/color_gamut_mapping.cc *)

From Stdlib Require Import ZArith Lia. Open Scope Z_scope.
Definition clamp_gamut (c : Z) : Z :=
  Z.max 0 (Z.min 255 c).
Theorem gamut_bounds : forall c,
  0 <= clamp_gamut c <= 255.
Proof.
  intros c. unfold clamp_gamut.
  split.
  - apply Z.le_max_l.
  - apply Z.max_lub; [lia | apply Z.le_min_l].
Qed.
