Require Import Bool.

(** * Blink Cross-Origin-Embedder-Policy (COEP) Semantics *)
(** HTML Standard §7.4: COEP require-corp requires same-origin or valid CORP header *)

Record COEPContext := {
  coep_require_corp : bool;
  resource_is_same_origin : bool;
  resource_has_corp : bool
}.

Definition coep_resource_allowed (ctx : COEPContext) : bool :=
  if coep_require_corp ctx then
    resource_is_same_origin ctx || resource_has_corp ctx
  else true.

Theorem coep_same_origin_always_allowed : forall req corp,
  coep_resource_allowed {| coep_require_corp := req;
                            resource_is_same_origin := true;
                            resource_has_corp := corp |} = true.
Proof.
  intros req corp.
  unfold coep_resource_allowed. cbn.
  destruct req; auto.
Qed.

Theorem coep_cross_origin_blocked_without_corp :
  coep_resource_allowed {| coep_require_corp := true;
                            resource_is_same_origin := false;
                            resource_has_corp := false |} = false.
Proof.
  reflexivity.
Qed.
