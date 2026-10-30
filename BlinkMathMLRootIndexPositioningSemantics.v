Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink MathML Root Index Positioning Semantics *)
(** MathML Core §3.6.2: mroot index notch positioning *)

Record RadicalNotch := {
  notch_x : Z;
  notch_y : Z
}.

Definition position_root_index (notch : RadicalNotch) (index_w index_h : Z) : RadicalNotch :=
  {| notch_x := notch_x notch;
     notch_y := notch_y notch - Z.max 0 index_h |}.

Theorem root_index_y_above_notch : forall notch w h,
  0 <= h ->
  notch_y (position_root_index notch w h) <= notch_y notch.
Proof.
  intros notch w h Hh.
  unfold position_root_index; simpl; lia.
Qed.
