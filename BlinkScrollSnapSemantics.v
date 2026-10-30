(** * BlinkScrollSnapSemantics.v
    Formal verification of Chromium Blink Scroll Snap vs CSS Scroll Snap Level 1.
*)

From Stdlib Require Import ZArith.ZArith.
From Stdlib Require Import Lists.List.
From Stdlib Require Import Bool.Bool.
From Stdlib Require Import micromega.Lia.
Import ListNotations.

Open Scope Z_scope.

(** ** 1. Core Data Structures *)

Inductive SnapAlignment : Type :=
  | AlignNone
  | AlignStart
  | AlignEnd
  | AlignCenter.

Inductive SnapStrictness : Type :=
  | StrictnessNone
  | StrictnessProximity
  | StrictnessMandatory.

Record SnapContainerData : Type := mkSnapContainer {
  snap_strictness : SnapStrictness;
  snapport_start  : Z;
  snapport_size   : Z;
  min_scroll      : Z;
  max_scroll      : Z;
  proximity_range : Z
}.

Definition wf_container (c : SnapContainerData) : Prop :=
  min_scroll c <= max_scroll c /\
  0 <= snapport_size c /\
  0 <= proximity_range c.

Record SnapAreaData : Type := mkSnapArea {
  area_align : SnapAlignment;
  area_start : Z;
  area_size  : Z;
  must_snap  : bool
}.

(** ** 2. Snap Target Calculation & Clamping *)

Definition clamp (v low high : Z) : Z :=
  Z.max low (Z.min high v).

Lemma clamp_bounds : forall v low high,
  low <= high ->
  low <= clamp v low high <= high.
Proof.
  intros v low high Hle.
  unfold clamp.
  split.
  - apply Z.le_max_l.
  - apply Z.max_lub_iff. split.
    + exact Hle.
    + apply Z.le_min_l.
Qed.

Definition raw_snap_offset (c : SnapContainerData) (a : SnapAreaData) : option Z :=
  match area_align a with
  | AlignNone => None
  | AlignStart =>
      Some (area_start a - snapport_start c)
  | AlignEnd =>
      let area_end := area_start a + area_size a in
      let snapport_end := snapport_start c + snapport_size c in
      Some (area_end - snapport_end)
  | AlignCenter =>
      let area_center := area_start a + (area_size a / 2) in
      let snapport_center := snapport_start c + (snapport_size c / 2) in
      Some (area_center - snapport_center)
  end.

Definition clamped_snap_offset (c : SnapContainerData) (a : SnapAreaData) : option Z :=
  match raw_snap_offset c a with
  | None => None
  | Some raw => Some (clamp raw (min_scroll c) (max_scroll c))
  end.

Fixpoint collect_clamped_candidates (c : SnapContainerData) (areas : list SnapAreaData) : list Z :=
  match areas with
  | [] => []
  | a :: rest =>
      match clamped_snap_offset c a with
      | Some s => s :: collect_clamped_candidates c rest
      | None => collect_clamped_candidates c rest
      end
  end.

(** ** 3. Candidate Selection *)

Fixpoint find_closest_candidate (target : Z) (candidates : list Z) : option Z :=
  match candidates with
  | [] => None
  | s :: rest =>
      match find_closest_candidate target rest with
      | None => Some s
      | Some best_rest =>
          if Z.abs (s - target) <=? Z.abs (best_rest - target) then
            Some s
          else
            Some best_rest
      end
  end.

Definition resolve_snap_offset
  (c : SnapContainerData) (areas : list SnapAreaData) (intended : Z) : Z :=
  let clamped_intended := clamp intended (min_scroll c) (max_scroll c) in
  match snap_strictness c with
  | StrictnessNone => clamped_intended
  | StrictnessMandatory =>
      let candidates := collect_clamped_candidates c areas in
      match find_closest_candidate clamped_intended candidates with
      | Some s => s
      | None => clamped_intended
      end
  | StrictnessProximity =>
      let candidates := collect_clamped_candidates c areas in
      match find_closest_candidate clamped_intended candidates with
      | Some s =>
          if Z.abs (s - clamped_intended) <=? proximity_range c then
            s
          else
            clamped_intended
      | None => clamped_intended
      end
  end.

(** ** 4. Formal Proofs & Correctness Invariants *)

(** Invariant 1: Clamped candidate is strictly within container scroll limits *)
Theorem clamped_offset_within_bounds :
  forall c a s,
    wf_container c ->
    clamped_snap_offset c a = Some s ->
    min_scroll c <= s <= max_scroll c.
Proof.
  intros c a s Hwf Hsnap.
  unfold clamped_snap_offset in Hsnap.
  destruct (raw_snap_offset c a) as [raw |] eqn:Hraw; [| discriminate].
  inversion Hsnap; subst.
  destruct Hwf as [Hminmax _].
  apply clamp_bounds. exact Hminmax.
Qed.

(** Invariant 2: All collected candidates satisfy container scroll limits *)
Theorem all_candidates_within_bounds :
  forall c areas s,
    wf_container c ->
    In s (collect_clamped_candidates c areas) ->
    min_scroll c <= s <= max_scroll c.
Proof.
  intros c areas.
  induction areas as [| a rest IH]; intros s Hwf Hin.
  - simpl in Hin. contradiction.
  - simpl in Hin.
    destruct (clamped_snap_offset c a) as [cand |] eqn:Hcand.
    + destruct Hin as [Heq | Hin_rest].
      * subst s. eapply clamped_offset_within_bounds; eauto.
      * apply (IH s Hwf Hin_rest).
    + apply (IH s Hwf Hin).
Qed.

(** Invariant 3: Closest candidate is a member of the candidate list *)
Theorem closest_candidate_in_list :
  forall target candidates s,
    find_closest_candidate target candidates = Some s ->
    In s candidates.
Proof.
  intros target candidates.
  induction candidates as [| c cs IH]; intros s Hfind.
  - simpl in Hfind. discriminate.
  - simpl in Hfind.
    destruct (find_closest_candidate target cs) as [best_cs |] eqn:Hrec.
    + destruct (Z.abs (c - target) <=? Z.abs (best_cs - target)) eqn:Hcmp.
      * inversion Hfind; subst. left. reflexivity.
      * inversion Hfind; subst. right. apply IH. reflexivity.
    + inversion Hfind; subst. left. reflexivity.
Qed.

Lemma find_closest_nonempty : forall target c cs,
  exists s, find_closest_candidate target (c :: cs) = Some s.
Proof.
  intros target c cs.
  simpl.
  destruct (find_closest_candidate target cs) as [best |].
  - destruct (Z.abs (c - target) <=? Z.abs (best - target)); eexists; reflexivity.
  - eexists; reflexivity.
Qed.

(** Invariant 4: Closest candidate minimizes distance to target *)
Theorem closest_candidate_minimizes_distance :
  forall target candidates s x,
    find_closest_candidate target candidates = Some s ->
    In x candidates ->
    Z.abs (s - target) <= Z.abs (x - target).
Proof.
  intros target candidates.
  induction candidates as [| c cs IH]; intros s x Hfind Hin.
  - simpl in Hin. contradiction.
  - simpl in Hfind.
    destruct (find_closest_candidate target cs) as [best_cs |] eqn:Hrec.
    + destruct (Z.abs (c - target) <=? Z.abs (best_cs - target)) eqn:Hcmp.
      * inversion Hfind; subst s.
        apply Z.leb_le in Hcmp.
        destruct Hin as [Hx_eq | Hx_in].
        { subst x. lia. }
        { pose proof (IH best_cs x eq_refl Hx_in) as Hdist. lia. }
      * inversion Hfind; subst s.
        apply Z.leb_gt in Hcmp.
        destruct Hin as [Hx_eq | Hx_in].
        { subst x. lia. }
        { apply (IH best_cs x eq_refl Hx_in). }
    + inversion Hfind; subst s.
      destruct Hin as [Hx_eq | Hx_in].
      * subst x. lia.
      * destruct cs as [| c' cs'].
        { contradiction. }
        { destruct (find_closest_nonempty target c' cs') as [s' Hs'].
          rewrite Hs' in Hrec. discriminate. }
Qed.

(** Invariant 5: Scroll Bounds Safety — resolved snap offset is always within bounds *)
Theorem resolve_snap_offset_bounds_safe :
  forall c areas intended,
    wf_container c ->
    min_scroll c <= resolve_snap_offset c areas intended <= max_scroll c.
Proof.
  intros c areas intended Hwf.
  destruct Hwf as [Hminmax [Hsize Hprox]].
  unfold resolve_snap_offset.
  pose proof (clamp_bounds intended (min_scroll c) (max_scroll c) Hminmax) as Hcl_intended.
  destruct (snap_strictness c).
  - (* StrictnessNone *) exact Hcl_intended.
  - (* StrictnessProximity *)
    destruct (find_closest_candidate (clamp intended (min_scroll c) (max_scroll c))
                                     (collect_clamped_candidates c areas)) as [s |] eqn:Hclose.
    + destruct (Z.abs (s - clamp intended (min_scroll c) (max_scroll c)) <=? proximity_range c).
      * pose proof (closest_candidate_in_list (clamp intended (min_scroll c) (max_scroll c))
                                             (collect_clamped_candidates c areas) s Hclose) as Hin.
        apply (all_candidates_within_bounds c areas s); [split; [exact Hminmax | split; assumption] | exact Hin].
      * exact Hcl_intended.
    + exact Hcl_intended.
  - (* StrictnessMandatory *)
    destruct (find_closest_candidate (clamp intended (min_scroll c) (max_scroll c))
                                     (collect_clamped_candidates c areas)) as [s |] eqn:Hclose.
    + pose proof (closest_candidate_in_list (clamp intended (min_scroll c) (max_scroll c))
                                           (collect_clamped_candidates c areas) s Hclose) as Hin.
      apply (all_candidates_within_bounds c areas s); [split; [exact Hminmax | split; assumption] | exact Hin].
    + exact Hcl_intended.
Qed.

(** Invariant 6: Proximity Adherence — displacement never exceeds proximity_range in proximity mode *)
Theorem resolve_snap_proximity_adherence :
  forall c areas intended,
    wf_container c ->
    snap_strictness c = StrictnessProximity ->
    Z.abs (resolve_snap_offset c areas intended - clamp intended (min_scroll c) (max_scroll c)) <= proximity_range c.
Proof.
  intros c areas intended Hwf Hstrict.
  destruct Hwf as [Hminmax [Hsize Hprox]].
  unfold resolve_snap_offset.
  rewrite Hstrict.
  destruct (find_closest_candidate (clamp intended (min_scroll c) (max_scroll c))
                                   (collect_clamped_candidates c areas)) as [s |] eqn:Hclose.
  - destruct (Z.abs (s - clamp intended (min_scroll c) (max_scroll c)) <=? proximity_range c) eqn:Hle.
    + apply Z.leb_le. exact Hle.
    + rewrite Z.sub_diag, Z.abs_0. exact Hprox.
  - rewrite Z.sub_diag, Z.abs_0. exact Hprox.
Qed.
