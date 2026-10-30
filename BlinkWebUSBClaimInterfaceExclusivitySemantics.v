Require Import ZArith.
Require Import Bool.
Require Import List.
Import ListNotations.
Open Scope Z_scope.

(** * Blink WebUSB Claim Interface Exclusivity Semantics *)
(** WebUSB API §3.3 claimInterface mutual exclusivity *)

Fixpoint is_claimed (iface : Z) (claimed : list Z) : bool :=
  match claimed with
  | [] => false
  | x :: xs => if iface =? x then true else is_claimed iface xs
  end.

Definition claim_iface (iface : Z) (claimed : list Z) : option (list Z) :=
  if is_claimed iface claimed then None else Some (iface :: claimed).

Theorem claim_already_claimed_fails : forall iface claimed,
  is_claimed iface claimed = true ->
  claim_iface iface claimed = None.
Proof.
  intros iface claimed H.
  unfold claim_iface.
  rewrite H.
  reflexivity.
Qed.

Theorem claim_unclaimed_succeeds : forall iface claimed,
  is_claimed iface claimed = false ->
  claim_iface iface claimed = Some (iface :: claimed).
Proof.
  intros iface claimed H.
  unfold claim_iface.
  rewrite H.
  reflexivity.
Qed.
