Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink SVG Marker Auto-Start-Reverse Semantics *)
(** SVG 2 §11.6.2: 180-degree start marker reversal involution *)

Definition reverse_marker_angle (deg : Z) : Z :=
  (deg + 180) mod 360.

Theorem reverse_marker_involution : forall deg,
  reverse_marker_angle (reverse_marker_angle deg) = deg mod 360.
Proof.
  intros deg.
  unfold reverse_marker_angle.
  rewrite Zplus_mod_idemp_l.
  replace (deg + 180 + 180) with (deg + 1 * 360) by lia.
  rewrite Z_mod_plus_full.
  reflexivity.
Qed.
