Require Import ZArith.
Require Import Lia.
Require Import Bool.
Open Scope Z_scope.

(** * Blink Fetch Request Mode Method Restriction Semantics *)
(** Fetch Standard §5.4: 'no-cors' mode restricts methods to GET, HEAD, POST *)

Definition METHOD_GET     : Z := 1.
Definition METHOD_HEAD    : Z := 2.
Definition METHOD_POST    : Z := 3.
Definition METHOD_PUT     : Z := 4.
Definition METHOD_DELETE  : Z := 5.

Definition method_allowed_in_no_cors (m : Z) : bool :=
  (m =? METHOD_GET) || (m =? METHOD_HEAD) || (m =? METHOD_POST).

Theorem no_cors_allows_get :
  method_allowed_in_no_cors METHOD_GET = true.
Proof.
  reflexivity.
Qed.

Theorem no_cors_allows_post :
  method_allowed_in_no_cors METHOD_POST = true.
Proof.
  reflexivity.
Qed.

Theorem no_cors_blocks_put :
  method_allowed_in_no_cors METHOD_PUT = false.
Proof.
  reflexivity.
Qed.
