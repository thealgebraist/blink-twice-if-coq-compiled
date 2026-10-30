(* Blink2Coq HTML/CSS Synthesis for ValidityState *)
(* Source: renderer/core/html/forms/validity_state.cc *)

Require Import ZArith. Open Scope Z_scope.
Definition is_form_valid (mask : Z) : bool := mask =? 0.
Theorem form_zero_mask_valid : is_form_valid 0 = true.
Proof. reflexivity. Qed.
