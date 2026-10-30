Require Import ZArith.
Require Import Lia.
Require Import List.
Require Import Bool.
Import ListNotations.
Open Scope Z_scope.

(** * Blink Cookie Domain & Path Prefix Matching Semantics *)
(** RFC 6265bis §5.4: cookie path prefix matching *)

Fixpoint cookie_path_matches (cookie_path request_path : list Z) : bool :=
  match cookie_path with
  | [] => true
  | x :: xs =>
    match request_path with
    | [] => false
    | y :: ys => (x =? y) && cookie_path_matches xs ys
    end
  end.

Theorem cookie_path_nil_matches_all : forall req,
  cookie_path_matches [] req = true.
Proof.
  intros req. reflexivity.
Qed.

Theorem cookie_path_refl : forall p,
  cookie_path_matches p p = true.
Proof.
  induction p as [| x xs IH]; auto.
  cbn. rewrite Z.eqb_refl. cbn.
  exact IH.
Qed.
