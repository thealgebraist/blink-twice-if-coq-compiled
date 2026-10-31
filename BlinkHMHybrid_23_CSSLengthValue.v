(* Formalization generated via HM Hybrid Architecture *)
(* De-imperativized SSA AST + Robinson MGU Row Typing + WP Assertion Mining + Dale Miller Presburger LIA *)
Require Import ZArith.
Require Import Bool.
Require Import Lia.
Open Scope Z_scope.

Record CSSLengthValue := mkCSSLengthValue {
  csslengthvalue_raw_val : Z;
  csslengthvalue_unit_kind : Z
}.

Definition resolve_viewport_unit (val : Z) (viewport_extent : Z) : Z :=
  (viewport_extent * val) / 100.

Theorem resolve_viewport_unit_100_identity :
  forall (viewport_extent : Z), resolve_viewport_unit 100 viewport_extent = viewport_extent.
Proof.
  intros viewport_extent. unfold resolve_viewport_unit.
  rewrite Z.div_mul by lia. reflexivity.
Qed.
