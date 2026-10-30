(* Blink2Coq Synthesis for PaintLayerScrollableArea *)
(* Source: third_party/blink/renderer/core/paint/paint_layer_scrollable_area.cc *)

Require Import ZArith Lia. Open Scope Z_scope.
Theorem scrollable_overflow_monotonic : forall old_ov child_rect,
  old_ov <= Z.max old_ov child_rect.
Proof. intros. apply Z.le_max_l. Qed.
