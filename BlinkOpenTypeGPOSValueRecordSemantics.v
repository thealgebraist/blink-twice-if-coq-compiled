Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink OpenType GPOS ValueRecord Semantics *)
(** OpenType GPOS §2: position translation and advance adjustment *)

Record ValueRecord := {
  vr_x_placement : Z;
  vr_y_placement : Z;
  vr_x_advance   : Z;
  vr_y_advance   : Z
}.

Record GlyphPosition := {
  gp_x : Z;
  gp_y : Z;
  gp_x_advance : Z
}.

Definition apply_gpos_value_record (pos : GlyphPosition) (vr : ValueRecord) : GlyphPosition :=
  {| gp_x := gp_x pos + vr_x_placement vr;
     gp_y := gp_y pos + vr_y_placement vr;
     gp_x_advance := gp_x_advance pos + vr_x_advance vr |}.

Theorem zero_value_record_is_identity : forall pos,
  apply_gpos_value_record pos {| vr_x_placement := 0; vr_y_placement := 0; vr_x_advance := 0; vr_y_advance := 0 |} = pos.
Proof.
  intros [x y adv].
  unfold apply_gpos_value_record; simpl.
  f_equal; lia.
Qed.
