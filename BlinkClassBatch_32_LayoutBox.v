(* Blink2Coq Synthesis for LayoutBox *)
(* Source: third_party/blink/renderer/core/layout/layout_box.cc *)

Require Import ZArith Lia. Open Scope Z_scope.
Definition layout_totality_valid (cb_w avail_w : Z) : bool :=
  (0 <? cb_w) && (0 <=? avail_w).
Theorem grand_totality_layout_progress : forall cb_w avail_w,
  0 < cb_w -> 0 <= avail_w -> layout_totality_valid cb_w avail_w = true.
Proof.
  intros cb_w av_w H1 H2. unfold layout_totality_valid.
  apply andb_true_intro; split; [apply Z.ltb_lt; lia | apply Z.leb_le; lia].
Qed.
