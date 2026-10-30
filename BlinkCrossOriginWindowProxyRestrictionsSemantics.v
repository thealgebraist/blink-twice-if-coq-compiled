Require Import ZArith.
Require Import Lia.
Require Import Bool.
Open Scope Z_scope.

(** * Blink Cross-Origin WindowProxy Property Access Semantics *)
(** HTML Standard §7.2: cross-origin access restricted to safelisted properties *)

Definition PROP_LOCATION     : Z := 1.
Definition PROP_POSTMESSAGE  : Z := 2.
Definition PROP_CLOSED       : Z := 3.
Definition PROP_CLOSE        : Z := 4.

Definition is_safelisted_property (prop_id : Z) : bool :=
  (prop_id =? PROP_LOCATION) ||
  (prop_id =? PROP_POSTMESSAGE) ||
  (prop_id =? PROP_CLOSED) ||
  (prop_id =? PROP_CLOSE).

Definition window_property_accessible (is_same_origin : bool) (prop_id : Z) : bool :=
  is_same_origin || is_safelisted_property prop_id.

Theorem same_origin_accesses_all_properties : forall p,
  window_property_accessible true p = true.
Proof.
  intros p. reflexivity.
Qed.

Theorem cross_origin_safelisted_location_allowed :
  window_property_accessible false PROP_LOCATION = true.
Proof.
  reflexivity.
Qed.

Theorem cross_origin_non_safelisted_blocked : forall p,
  is_safelisted_property p = false ->
  window_property_accessible false p = false.
Proof.
  intros p Hsafe.
  unfold window_property_accessible.
  rewrite Hsafe.
  reflexivity.
Qed.
