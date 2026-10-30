Require Import ZArith.
Require Import List.
Import ListNotations.
Open Scope Z_scope.

(** * Blink Payment Details Modifier Override Semantics *)
(** Payment Request API §5.7: PaymentDetailsModifier total override *)

Fixpoint lookup_modifier_override (method : Z) (mods : list (Z * Z)) : option Z :=
  match mods with
  | [] => None
  | (m, override_tot) :: rest =>
      if method =? m then Some override_tot else lookup_modifier_override method rest
  end.

Definition effective_total (base_total : Z) (method : Z) (mods : list (Z * Z)) : Z :=
  match lookup_modifier_override method mods with
  | Some override_tot => override_tot
  | None              => base_total
  end.

Theorem modifier_overrides_when_matched : forall base method override_tot rest,
  effective_total base method ((method, override_tot) :: rest) = override_tot.
Proof.
  intros base method override_tot rest.
  unfold effective_total.
  simpl.
  rewrite Z.eqb_refl.
  reflexivity.
Qed.

Theorem base_retained_when_no_modifiers : forall base method,
  effective_total base method [] = base.
Proof.
  intros base method.
  unfold effective_total.
  reflexivity.
Qed.
