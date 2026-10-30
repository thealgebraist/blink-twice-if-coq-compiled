(* ========================================================================= *)
(*               BlinkGridTrackGrowthSemantics.v                             *)
(* ========================================================================= *)
(* Formal semantics of Chromium Blink CSS Grid Track Growth Algorithm        *)
(* per W3C CSS Grid Layout Module Level 1 §11.5 (Track Sizing Step 2).      *)
(* Strictly verified with 0 admits.                                          *)
(* ========================================================================= *)

From Stdlib Require Import ZArith Lists.List Bool.Bool Lia.
Open Scope Z_scope.

Record GridTrack := {
  base_size : Z;
  growth_limit : option Z
}.

Definition grow_single_track (t : GridTrack) (delta : Z) : GridTrack :=
  let d := Z.max 0 delta in
  let target := base_size t + d in
  let new_base :=
    match growth_limit t with
    | Some m => Z.min m target
    | None => target
    end in
  {| base_size := new_base; growth_limit := growth_limit t |}.

Fixpoint sum_base_sizes (tracks : list GridTrack) : Z :=
  match tracks with
  | nil => 0
  | t :: rest => base_size t + sum_base_sizes rest
  end.

Definition grow_all_tracks (tracks : list GridTrack) (share : Z) : list GridTrack :=
  map (fun t => grow_single_track t share) tracks.

Theorem single_track_growth_monotonic : forall t delta,
  delta >= 0 ->
  base_size t <= match growth_limit t with Some m => m | None => base_size t end ->
  base_size (grow_single_track t delta) >= base_size t.
Proof.
  intros [b gl] delta Hdelta Hlim.
  unfold grow_single_track; cbn in *.
  assert (Hmax: Z.max 0 delta = delta) by lia.
  rewrite Hmax.
  destruct gl as [m|]; cbn.
  - apply Z.le_ge. apply Z.min_glb; lia.
  - lia.
Qed.

Theorem single_track_respects_growth_limit : forall t delta,
  delta >= 0 ->
  forall m, growth_limit t = Some m ->
  base_size (grow_single_track t delta) <= Z.max m (base_size t).
Proof.
  intros [b gl] delta Hdelta m Hgl.
  unfold grow_single_track; cbn in *.
  subst gl.
  pose proof (Z.le_min_l m (b + Z.max 0 delta)).
  pose proof (Z.le_max_l m b).
  lia.
Qed.

Theorem single_track_growth_bounded_by_delta : forall t delta,
  delta >= 0 ->
  base_size (grow_single_track t delta) - base_size t <= delta.
Proof.
  intros [b gl] delta Hdelta.
  unfold grow_single_track; cbn.
  assert (Hmax: Z.max 0 delta = delta) by lia.
  rewrite Hmax.
  destruct gl as [m|]; cbn.
  - pose proof (Z.le_min_r m (b + delta)).
    lia.
  - lia.
Qed.

Theorem sum_base_sizes_nil : sum_base_sizes nil = 0.
Proof. reflexivity. Qed.

Theorem sum_base_sizes_app : forall l1 l2,
  sum_base_sizes (l1 ++ l2) = sum_base_sizes l1 + sum_base_sizes l2.
Proof.
  intros l1 l2.
  induction l1 as [|t rest IH]; cbn.
  - reflexivity.
  - rewrite IH. lia.
Qed.

Theorem grow_all_tracks_monotonic : forall tracks share,
  share >= 0 ->
  (forall t, In t tracks -> base_size t <= match growth_limit t with Some m => m | None => base_size t end) ->
  sum_base_sizes (grow_all_tracks tracks share) >= sum_base_sizes tracks.
Proof.
  intros tracks share Hshare.
  unfold grow_all_tracks.
  induction tracks as [|t rest IH].
  - cbn. lia.
  - intros Hlim.
    cbn [map sum_base_sizes].
    assert (Ht: base_size t <= match growth_limit t with Some m => m | None => base_size t end).
    { apply Hlim. left. reflexivity. }
    assert (Hrest: forall t0, In t0 rest -> base_size t0 <= match growth_limit t0 with Some m => m | None => base_size t0 end).
    { intros t0 Hin. apply Hlim. right. assumption. }
    pose proof (single_track_growth_monotonic t share Hshare Ht) as Hmono_t.
    pose proof (IH Hrest) as Hmono_rest.
    lia.
Qed.

Theorem grow_all_tracks_bounded_by_total_share : forall tracks share,
  share >= 0 ->
  sum_base_sizes (grow_all_tracks tracks share) - sum_base_sizes tracks <= Z.of_nat (length tracks) * share.
Proof.
  intros tracks share Hshare.
  unfold grow_all_tracks.
  induction tracks as [|t rest IH].
  - cbn. lia.
  - cbn [map sum_base_sizes length].
    pose proof (single_track_growth_bounded_by_delta t share Hshare) as Hbound_t.
    rewrite Nat2Z.inj_succ.
    unfold Z.succ.
    rewrite Z.mul_add_distr_r.
    rewrite Z.mul_1_l.
    lia.
Qed.
