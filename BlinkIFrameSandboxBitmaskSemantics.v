Require Import Bool.

(** * Blink IFrame Sandbox Flags Semantics *)
(** HTML Standard §4.8.5: sandbox directives compose monotonically *)

Record SandboxPermissions := {
  sandbox_allow_scripts     : bool;
  sandbox_allow_same_origin : bool;
  sandbox_allow_forms       : bool
}.

Definition compose_sandbox (p1 p2 : SandboxPermissions) : SandboxPermissions := {|
  sandbox_allow_scripts     := sandbox_allow_scripts p1 && sandbox_allow_scripts p2;
  sandbox_allow_same_origin := sandbox_allow_same_origin p1 && sandbox_allow_same_origin p2;
  sandbox_allow_forms       := sandbox_allow_forms p1 && sandbox_allow_forms p2
|}.

Theorem sandbox_composition_preserves_restrictions : forall p1 p2,
  sandbox_allow_scripts (compose_sandbox p1 p2) = true ->
  sandbox_allow_scripts p1 = true /\ sandbox_allow_scripts p2 = true.
Proof.
  intros p1 p2 H.
  unfold compose_sandbox in H. cbn in H.
  apply andb_prop in H.
  exact H.
Qed.
