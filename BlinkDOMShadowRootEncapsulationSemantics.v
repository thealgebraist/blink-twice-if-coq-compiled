Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink ShadowRoot Encapsulation Semantics *)
(** DOM Standard §4.2.2: shadow tree elements inaccessible from light tree *)

Definition lookup_by_id_in_light_tree (is_in_shadow : bool) (elem_id : Z) : option Z :=
  if is_in_shadow then None else Some elem_id.

Theorem shadow_element_hidden_from_light_tree : forall eid,
  lookup_by_id_in_light_tree true eid = None.
Proof.
  intros eid; reflexivity.
Qed.

Theorem light_element_accessible : forall eid,
  lookup_by_id_in_light_tree false eid = Some eid.
Proof.
  intros eid; reflexivity.
Qed.
