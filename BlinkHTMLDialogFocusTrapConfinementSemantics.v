Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Modal Dialog Focus Trap Confinement Semantics *)
(** HTML Standard §4.11.4: modal dialog focus confinement *)

Definition confine_focus (target_in_dialog : bool) (dialog_root fallback : Z) : Z :=
  if target_in_dialog then dialog_root else fallback.

Theorem inside_dialog_focus_preserved : forall r f,
  confine_focus true r f = r.
Proof.
  intros r f; reflexivity.
Qed.

Theorem outside_dialog_focus_rerouted : forall r f,
  confine_focus false r f = f.
Proof.
  intros r f; reflexivity.
Qed.
