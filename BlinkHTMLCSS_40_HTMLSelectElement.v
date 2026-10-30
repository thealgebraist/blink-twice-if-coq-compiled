(* Blink2Coq HTML/CSS Synthesis for HTMLSelectElement *)
(* Source: renderer/core/html/forms/html_select_element.cc *)

Require Import ZArith Lia. Open Scope Z_scope.
Definition clamp_select_index (idx count : Z) : Z :=
  if idx <? 0 then 0 else if count - 1 <? idx then count - 1 else idx.
Theorem select_index_bounded : forall idx count,
  0 < count -> 0 <= clamp_select_index idx count < count.
Proof.
  intros idx cnt Hcnt. unfold clamp_select_index.
  destruct (idx <? 0) eqn:E1; [apply Z.ltb_lt in E1; lia | apply Z.ltb_ge in E1].
  destruct (cnt - 1 <? idx) eqn:E2; [apply Z.ltb_lt in E2; lia | apply Z.ltb_ge in E2; lia].
Qed.
