From Stdlib Require Import ZArith Lia.
Open Scope Z_scope.

(* CSS Cascading 5 §3 Cascade Origin 8-Tier Priority Ranking *)
Inductive CascadeOriginTier :=
  | TierUANormal
  | TierUserNormal
  | TierAuthorNormal
  | TierAnimation
  | TierAuthorImportant
  | TierUserImportant
  | TierUAImportant
  | TierTransition.

Definition tier_rank (t : CascadeOriginTier) : Z :=
  match t with
  | TierUANormal         => 0
  | TierUserNormal       => 1
  | TierAuthorNormal     => 2
  | TierAnimation        => 3
  | TierAuthorImportant  => 4
  | TierUserImportant    => 5
  | TierUAImportant      => 6
  | TierTransition       => 7
  end.

Definition tier_beats (t1 t2 : CascadeOriginTier) : Prop :=
  tier_rank t1 > tier_rank t2.

Theorem transition_beats_all : forall t,
  t <> TierTransition ->
  tier_beats TierTransition t.
Proof.
  intros t Hneq. unfold tier_beats, tier_rank.
  destruct t; try lia; contradiction Hneq; reflexivity.
Qed.

Theorem ua_important_beats_author_important :
  tier_beats TierUAImportant TierAuthorImportant.
Proof.
  unfold tier_beats; cbn. lia.
Qed.

Theorem tier_beats_transitive : forall t1 t2 t3,
  tier_beats t1 t2 ->
  tier_beats t2 t3 ->
  tier_beats t1 t3.
Proof.
  intros t1 t2 t3. unfold tier_beats. lia.
Qed.
