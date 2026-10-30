Require Import ZArith.
Require Import List.
Import ListNotations.
Open Scope Z_scope.

(** * Blink Payment Shipping Option Uniqueness Semantics *)
(** Payment Request API §5.6: shippingOptions ID uniqueness *)

Fixpoint find_shipping_option (id : Z) (opts : list (Z * Z)) : option Z :=
  match opts with
  | [] => None
  | (opt_id, cost) :: rest =>
      if id =? opt_id then Some cost else find_shipping_option id rest
  end.

Theorem shipping_option_found_head : forall id cost rest,
  find_shipping_option id ((id, cost) :: rest) = Some cost.
Proof.
  intros id cost rest.
  simpl.
  rewrite Z.eqb_refl.
  reflexivity.
Qed.
