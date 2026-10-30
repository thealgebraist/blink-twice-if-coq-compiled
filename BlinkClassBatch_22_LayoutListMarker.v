(* Blink2Coq Synthesis for LayoutListMarker *)
(* Source: third_party/blink/renderer/core/layout/list/layout_list_marker.cc *)

Require Import ZArith Lia. Open Scope Z_scope.
Theorem list_marker_outside_precedes_content : forall cx mw,
  0 <= mw -> (cx - mw) + mw <= cx.
Proof. intros. lia. Qed.
