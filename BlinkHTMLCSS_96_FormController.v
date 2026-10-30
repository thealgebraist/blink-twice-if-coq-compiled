(* Blink2Coq HTML/CSS Synthesis for FormController *)
(* Source: renderer/core/html/forms/form_controller.cc *)

From Stdlib Require Import ZArith Bool Lia String. Open Scope string_scope. Open Scope Z_scope.
Definition form_state := string -> Z.
Definition set_form_state (m : form_state) (k : string) (v : Z) : form_state :=
  fun key => if string_dec k key then v else m key.
Theorem form_state_retrieval_exact : forall m k v,
  set_form_state m k v k = v.
Proof.
  intros. unfold set_form_state.
  destruct (string_dec k k); [reflexivity | congruence].
Qed.
