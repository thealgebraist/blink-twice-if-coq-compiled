From Stdlib Require Import ZArith Lia.
Open Scope Z_scope.

(* CSS 2.1 §8.3.1 Self-Collapsing Box Margin Strut *)
Record MarginStrut := {
  ms_pos : Z;
  ms_neg : Z
}.

Definition join_self_collapsing_struts (top_s : MarginStrut) (bot_s : MarginStrut) : MarginStrut :=
  {| ms_pos := Z.max (ms_pos top_s) (ms_pos bot_s);
     ms_neg := Z.min (ms_neg top_s) (ms_neg bot_s) |}.

Theorem join_preserves_pos_nonneg : forall top_s bot_s,
  ms_pos top_s >= 0 ->
  ms_pos bot_s >= 0 ->
  ms_pos (join_self_collapsing_struts top_s bot_s) >= 0.
Proof.
  intros top_s bot_s H1 H2.
  cbn.
  apply Z.le_ge.
  apply (Z.le_trans _ (ms_pos top_s)).
  - lia.
  - apply Z.le_max_l.
Qed.

Theorem join_preserves_neg_nonpos : forall top_s bot_s,
  ms_neg top_s <= 0 ->
  ms_neg bot_s <= 0 ->
  ms_neg (join_self_collapsing_struts top_s bot_s) <= 0.
Proof.
  intros top_s bot_s H1 H2.
  cbn.
  apply (Z.le_trans _ (ms_neg top_s)).
  - apply Z.le_min_l.
  - lia.
Qed.
