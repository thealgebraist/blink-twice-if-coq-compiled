Require Import ZArith.
Require Import Bool.
Require Import Lia.
Open Scope Z_scope.

Record MarginStrut := mkMarginStrut {
  ms_pos : Z;
  ms_neg : Z;
  ms_quirk_pos : Z;
  ms_quirky_start : bool
}.

Definition margin_strut_invariant (ms : MarginStrut) : Prop :=
  0 <= ms_pos ms /\ ms_neg ms <= 0 /\ 0 <= ms_quirk_pos ms.

Definition margin_strut_append (ms : MarginStrut) (val : Z) (is_quirk : bool) : MarginStrut :=
  if ms_quirky_start ms && is_quirk then ms
  else if val <? 0 then
    mkMarginStrut (ms_pos ms) (Z.min val (ms_neg ms)) (ms_quirk_pos ms) (ms_quirky_start ms)
  else if is_quirk then
    mkMarginStrut (ms_pos ms) (ms_neg ms) (Z.max val (ms_quirk_pos ms)) (ms_quirky_start ms)
  else
    mkMarginStrut (Z.max val (ms_pos ms)) (ms_neg ms) (ms_quirk_pos ms) (ms_quirky_start ms).

Theorem margin_strut_append_preserves_invariant :
  forall (ms : MarginStrut) (val : Z) (is_quirk : bool),
    margin_strut_invariant ms ->
    margin_strut_invariant (margin_strut_append ms val is_quirk).
Proof.
  intros ms val is_quirk [Hpos [Hneg Hqpos]].
  unfold margin_strut_append.
  destruct (ms_quirky_start ms && is_quirk) eqn:E1.
  - split; [exact Hpos | split; [exact Hneg | exact Hqpos]].
  - destruct (val <? 0) eqn:Eval.
    + apply Z.ltb_lt in Eval. simpl.
      split; [exact Hpos | split; [apply Z.min_le_iff; right; exact Hneg | exact Hqpos]].
    + apply Z.ltb_ge in Eval.
      destruct is_quirk.
      * simpl. split; [exact Hpos | split; [exact Hneg | apply Z.max_le_iff; left; exact Eval]].
      * simpl. split; [apply Z.max_le_iff; left; exact Eval | split; [exact Hneg | exact Hqpos]].
Qed.
