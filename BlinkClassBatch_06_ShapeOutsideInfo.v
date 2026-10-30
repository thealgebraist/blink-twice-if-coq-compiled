(* Blink2Coq Synthesis for ShapeOutsideInfo *)
(* Source: third_party/blink/renderer/core/layout/shapes/shape_outside_info.cc *)

Require Import ZArith Lia. Open Scope Z_scope.
Definition expand_shape_margin (bound margin : Z) : Z := bound + margin.
Theorem shape_margin_expansion_monotonic : forall bound margin,
  0 <= margin -> bound <= expand_shape_margin bound margin.
Proof. intros. unfold expand_shape_margin. lia. Qed.
