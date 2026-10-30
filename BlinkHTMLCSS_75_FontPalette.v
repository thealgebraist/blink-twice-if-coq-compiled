(* Blink2Coq HTML/CSS Synthesis for FontPalette *)
(* Source: renderer/core/css/font_palette.cc *)

From Stdlib Require Import ZArith Lia. Open Scope Z_scope.
Definition clamp_palette_idx (idx num_entries : Z) : Z :=
  if idx <? 0 then 0
  else if (num_entries - 1) <? idx then num_entries - 1
  else idx.
Theorem palette_index_bounded : forall idx num_entries,
  0 < num_entries ->
  0 <= clamp_palette_idx idx num_entries < num_entries.
Proof.
  intros idx num_entries Hpos. unfold clamp_palette_idx.
  destruct (idx <? 0) eqn:E1.
  - apply Z.ltb_lt in E1. lia.
  - apply Z.ltb_ge in E1. destruct ((num_entries - 1) <? idx) eqn:E2.
    + apply Z.ltb_lt in E2. lia.
    + apply Z.ltb_ge in E2. lia.
Qed.
