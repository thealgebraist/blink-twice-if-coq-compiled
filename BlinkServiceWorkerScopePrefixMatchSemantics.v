Require Import ZArith.
Require Import Lia.
Require Import List.
Require Import Bool.
Import ListNotations.
Open Scope Z_scope.

(** * Blink Service Worker Scope Prefix Matching Semantics *)
(** Service Workers §3.1: request matched by scope iff request path has scope prefix *)

Fixpoint scope_matches (scope_prefix request_path : list Z) : bool :=
  match scope_prefix with
  | [] => true
  | s :: ss =>
    match request_path with
    | [] => false
    | r :: rs => (s =? r) && scope_matches ss rs
    end
  end.

Theorem root_scope_matches_all : forall req,
  scope_matches [] req = true.
Proof.
  intros req. reflexivity.
Qed.

Theorem scope_matches_self : forall s,
  scope_matches s s = true.
Proof.
  induction s as [| x xs IH]; auto.
  cbn. rewrite Z.eqb_refl. cbn.
  exact IH.
Qed.
