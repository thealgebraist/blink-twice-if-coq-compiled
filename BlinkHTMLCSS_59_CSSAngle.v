(* Blink2Coq HTML/CSS Synthesis for CSSAngle *)
(* Source: renderer/core/css/css_math_expression_node.cc *)

Require Import ZArith Lia. Open Scope Z_scope.
Definition normalize_angle_deg (d : Z) : Z := d mod 360.
Theorem angle_deg_normalized : forall d,
  0 <= normalize_angle_deg d < 360.
Proof. intros. unfold normalize_angle_deg. apply Z.mod_pos_bound. lia. Qed.
