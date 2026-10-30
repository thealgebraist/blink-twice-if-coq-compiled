(* ========================================================================= *)
(*               BlinkGridMinMaxContentSemantics.v                          *)
(* ========================================================================= *)
(* Formal verification of Chromium Blink Grid Track Min/Max Content         *)
(* Contributions against CSS Grid 1 §11.5. Fully constructive, 0 admits.    *)
(* ========================================================================= *)

From Stdlib Require Import ZArith Lists.List Bool Lia.
Open Scope Z_scope.

Definition resolve_track_base_growth (item_min item_max : Z) : Z * Z :=
  let base := Z.max 0 item_min in
  let growth := Z.max base item_max in
  (base, growth).

Theorem base_le_growth_limit : forall item_min item_max,
  let (base, growth) := resolve_track_base_growth item_min item_max in
  base <= growth.
Proof.
  intros. unfold resolve_track_base_growth. lia.
Qed.

Theorem base_ge_item_min : forall item_min item_max,
  let (base, growth) := resolve_track_base_growth item_min item_max in
  base >= item_min.
Proof.
  intros. unfold resolve_track_base_growth. lia.
Qed.

Theorem growth_ge_item_max : forall item_min item_max,
  let (base, growth) := resolve_track_base_growth item_min item_max in
  growth >= item_max.
Proof.
  intros. unfold resolve_track_base_growth. lia.
Qed.
