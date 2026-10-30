(* Blink2Coq Synthesis for LayoutSVGRoot *)
(* Source: third_party/blink/renderer/core/layout/svg/layout_svg_root.cc *)

Require Import ZArith Lia. Open Scope Z_scope.
Theorem svg_aspect_ratio_scale_nonneg : forall num den,
  0 <= num -> 0 < den -> 0 <= num / den.
Proof. intros. apply Z.div_pos; lia. Qed.
