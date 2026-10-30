Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Font Feature Settings Semantics *)
(** CSS Fonts 4 §7.1: OpenType 4-byte tag matching *)

Record FontFeature := {
  feature_tag : Z;
  feature_value : Z
}.

Definition is_feature_enabled (feat : FontFeature) (target_tag : Z) : bool :=
  andb (feature_tag feat =? target_tag) (feature_value feat >? 0).

Theorem matching_positive_feature_enabled : forall tag val,
  0 < val ->
  is_feature_enabled {| feature_tag := tag; feature_value := val |} tag = true.
Proof.
  intros tag val Hval.
  unfold is_feature_enabled; simpl.
  assert (tag =? tag = true) by (apply Z.eqb_eq; reflexivity).
  assert (val >? 0 = true) by (apply Z.gtb_lt; lia).
  rewrite H, H0; reflexivity.
Qed.
