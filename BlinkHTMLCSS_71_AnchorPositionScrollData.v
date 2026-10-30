(* Blink2Coq HTML/CSS Synthesis for AnchorPositionScrollData *)
(* Source: renderer/core/layout/anchor_position_scroll_data.cc *)

From Stdlib Require Import ZArith Lia. Open Scope Z_scope.
Definition apply_scroll_comp (pos delta : Z) : Z := pos - delta.
Definition unapply_scroll_comp (pos delta : Z) : Z := pos + delta.
Theorem anchor_scroll_compensation_involution : forall pos delta,
  unapply_scroll_comp (apply_scroll_comp pos delta) delta = pos.
Proof. intros. unfold apply_scroll_comp, unapply_scroll_comp. lia. Qed.
