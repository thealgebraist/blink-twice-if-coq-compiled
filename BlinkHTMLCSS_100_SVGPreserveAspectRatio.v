(* Blink2Coq HTML/CSS Synthesis for SVGPreserveAspectRatio *)
(* Source: renderer/core/svg/svg_preserve_aspect_ratio.cc *)

From Stdlib Require Import ZArith Lia. Open Scope Z_scope.
Definition aspect_ratio_meet_scale (sx sy : Z) : Z := Z.min sx sy.
Theorem meet_scale_encloses_both : forall sx sy,
  aspect_ratio_meet_scale sx sy <= sx /\ aspect_ratio_meet_scale sx sy <= sy.
Proof.
  intros sx sy. unfold aspect_ratio_meet_scale.
  split; [apply Z.le_min_l | apply Z.le_min_r].
Qed.
