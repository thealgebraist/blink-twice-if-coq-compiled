Require Import ZArith.
Require Import Lia.
Require Import Bool.
Open Scope Z_scope.

(** * Blink WebAuthn User Verification Satisfiability Semantics *)
(** WebAuthn Level 3 §5.1.2: UV requirement evaluation *)

Definition UV_DISCOURAGED : Z := 0.
Definition UV_PREFERRED   : Z := 1.
Definition UV_REQUIRED    : Z := 2.

Definition is_uv_satisfied (req : Z) (uv_present : bool) : bool :=
  if req =? UV_REQUIRED then uv_present
  else true.

Theorem uv_required_demands_present :
  is_uv_satisfied UV_REQUIRED false = false /\
  is_uv_satisfied UV_REQUIRED true = true.
Proof.
  split; reflexivity.
Qed.
