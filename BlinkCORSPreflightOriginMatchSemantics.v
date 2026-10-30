Require Import ZArith.
Require Import Lia.
Require Import Bool.
Open Scope Z_scope.

(** * Blink CORS Preflight Origin Matching Semantics *)
(** Fetch Standard §3.2: Access-Control-Allow-Origin wildcard or exact origin match *)

Definition cors_origin_allowed (request_origin allowed_origin : Z) (is_wildcard : bool) : bool :=
  is_wildcard || (request_origin =? allowed_origin).

Theorem cors_wildcard_allows_all : forall req allow,
  cors_origin_allowed req allow true = true.
Proof.
  intros req allow. reflexivity.
Qed.

Theorem cors_exact_match_allowed : forall req,
  cors_origin_allowed req req false = true.
Proof.
  intros req.
  unfold cors_origin_allowed.
  rewrite Z.eqb_refl.
  reflexivity.
Qed.
