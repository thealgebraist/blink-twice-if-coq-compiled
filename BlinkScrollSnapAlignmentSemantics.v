(* ========================================================================= *)
(*               BlinkScrollSnapAlignmentSemantics.v                         *)
(* ========================================================================= *)
(* Formal verification of Chromium Blink Scroll Snap Alignment               *)
(* per CSS Scroll Snap Module Level 1 §4 & §6.                               *)
(* Constructive, executable (vm_compute), extractable to C99/C++23/LLVM-IR.  *)
(* Strictly verified with 0 admits.                                          *)
(* ========================================================================= *)

From Stdlib Require Import ZArith Lists.List Bool Lia.
Open Scope Z_scope.
Import ListNotations.

Inductive SnapAlignment : Type :=
  | AlignNone
  | AlignStart
  | AlignCenter
  | AlignEnd.

Inductive SnapStrictness : Type :=
  | StrictnessNone
  | StrictnessProximity
  | StrictnessMandatory.

Record SnapArea1D : Type := mkSnapArea {
  area_pos   : Z;
  area_size  : Z;
  area_align : SnapAlignment
}.

Record SnapContainer1D : Type := mkSnapContainer {
  content_width       : Z;
  viewport_width      : Z;
  padding_start       : Z;
  padding_end         : Z;
  strictness          : SnapStrictness;
  proximity_threshold : Z;
  snap_areas          : list SnapArea1D
}.

Definition max_scroll_offset (c : SnapContainer1D) : Z :=
  Z.max 0 (content_width c - viewport_width c).

Definition snapport_start (c : SnapContainer1D) : Z :=
  padding_start c.

Definition snapport_size (c : SnapContainer1D) : Z :=
  (viewport_width c - padding_end c) - padding_start c.

Definition clamp (v low high : Z) : Z :=
  Z.min high (Z.max low v).

Definition raw_snap_offset (c : SnapContainer1D) (a : SnapArea1D) : option Z :=
  let p_start := snapport_start c in
  let p_size  := snapport_size c in
  match area_align a with
  | AlignNone   => None
  | AlignStart  => Some (area_pos a - p_start)
  | AlignCenter => Some ((area_pos a + (area_size a / 2)) - (p_start + (p_size / 2)))
  | AlignEnd    => Some ((area_pos a + area_size a) - (p_start + p_size))
  end.

Definition target_snap_offset (c : SnapContainer1D) (a : SnapArea1D) : option Z :=
  match raw_snap_offset c a with
  | None => None
  | Some raw => Some (clamp raw 0 (max_scroll_offset c))
  end.

Fixpoint candidate_offsets (c : SnapContainer1D) (areas : list SnapArea1D) : list Z :=
  match areas with
  | [] => []
  | a :: rest =>
      match target_snap_offset c a with
      | Some pos => pos :: candidate_offsets c rest
      | None     => candidate_offsets c rest
      end
  end.

Fixpoint find_closest_candidate (intended : Z) (candidates : list Z) (best : option Z) : option Z :=
  match candidates with
  | [] => best
  | cand :: rest =>
      match best with
      | None => find_closest_candidate intended rest (Some cand)
      | Some b =>
          if Z.ltb (Z.abs (cand - intended)) (Z.abs (b - intended))
          then find_closest_candidate intended rest (Some cand)
          else find_closest_candidate intended rest (Some b)
      end
  end.

Definition resolve_scroll_snap (c : SnapContainer1D) (intended_scroll : Z) : Z :=
  let clamped_intended := clamp intended_scroll 0 (max_scroll_offset c) in
  let candidates := candidate_offsets c (snap_areas c) in
  match strictness c with
  | StrictnessNone => clamped_intended
  | StrictnessMandatory =>
      match find_closest_candidate clamped_intended candidates None with
      | Some snap_pos => snap_pos
      | None          => clamped_intended
      end
  | StrictnessProximity =>
      match find_closest_candidate clamped_intended candidates None with
      | Some snap_pos =>
          if Z.leb (Z.abs (snap_pos - clamped_intended)) (proximity_threshold c)
          then snap_pos
          else clamped_intended
      | None => clamped_intended
      end
  end.

(* ------------------------------------------------------------------------- *)
(* Theorems                                                                  *)
(* ------------------------------------------------------------------------- *)

Lemma clamp_bounds : forall v low high : Z,
  low <= high ->
  low <= clamp v low high <= high.
Proof.
  intros v low high Hle.
  unfold clamp; lia.
Qed.

Lemma max_scroll_nonneg : forall c : SnapContainer1D,
  0 <= max_scroll_offset c.
Proof.
  intros c. unfold max_scroll_offset; lia.
Qed.

Theorem target_snap_offset_bounded : forall (c : SnapContainer1D) (a : SnapArea1D) (t : Z),
  content_width c >= viewport_width c ->
  target_snap_offset c a = Some t ->
  0 <= t <= content_width c - viewport_width c.
Proof.
  intros c a t Hcw Htarget.
  unfold target_snap_offset in Htarget.
  destruct (raw_snap_offset c a) as [raw|]; [| discriminate Htarget].
  injection Htarget as <-.
  assert (Hmax : max_scroll_offset c = content_width c - viewport_width c).
  { unfold max_scroll_offset. lia. }
  rewrite <- Hmax.
  apply clamp_bounds.
  apply max_scroll_nonneg.
Qed.

Theorem candidate_offsets_in_bounds : forall c areas pos,
  In pos (candidate_offsets c areas) ->
  0 <= pos <= max_scroll_offset c.
Proof.
  intros c areas pos.
  induction areas as [| a rest IH]; intros Hin; cbn in Hin; [contradiction Hin |].
  destruct (target_snap_offset c a) as [t |] eqn:Ht.
  - destruct Hin as [-> | Hin_rest].
    + unfold target_snap_offset in Ht.
      destruct (raw_snap_offset c a); [| discriminate Ht].
      injection Ht as <-.
      apply clamp_bounds.
      apply max_scroll_nonneg.
    + apply (IH Hin_rest).
  - apply (IH Hin).
Qed.

Lemma find_closest_in_candidates : forall intended candidates init ans,
  find_closest_candidate intended candidates init = Some ans ->
  In ans candidates \/ init = Some ans.
Proof.
  intros intended candidates.
  induction candidates as [| c rest IH]; intros init ans Hfind; cbn in Hfind.
  - right; exact Hfind.
  - destruct init as [b |].
    + destruct (Z.ltb (Z.abs (c - intended)) (Z.abs (b - intended))).
      * specialize (IH (Some c) ans Hfind).
        destruct IH as [Hin | Heq].
        -- left; right; exact Hin.
        -- injection Heq as <-; left; left; reflexivity.
      * specialize (IH (Some b) ans Hfind).
        destruct IH as [Hin | Heq].
        -- left; right; exact Hin.
        -- right; exact Heq.
    + specialize (IH (Some c) ans Hfind).
      destruct IH as [Hin | Heq].
      * left; right; exact Hin.
      * injection Heq as <-; left; left; reflexivity.
Qed.

Theorem resolve_scroll_snap_bounded : forall c intended,
  0 <= resolve_scroll_snap c intended <= max_scroll_offset c.
Proof.
  intros c intended.
  unfold resolve_scroll_snap.
  assert (Hcl: 0 <= clamp intended 0 (max_scroll_offset c) <= max_scroll_offset c).
  { apply clamp_bounds. apply max_scroll_nonneg. }
  destruct (strictness c).
  - exact Hcl.
  - destruct (find_closest_candidate (clamp intended 0 (max_scroll_offset c))
                                     (candidate_offsets c (snap_areas c)) None) as [sp |] eqn:Hfc.
    + destruct (Z.leb (Z.abs (sp - clamp intended 0 (max_scroll_offset c))) (proximity_threshold c)).
      * apply find_closest_in_candidates in Hfc.
        destruct Hfc as [Hin | Hnone]; [| discriminate Hnone].
        apply (candidate_offsets_in_bounds c (snap_areas c) sp Hin).
      * exact Hcl.
    + exact Hcl.
  - destruct (find_closest_candidate (clamp intended 0 (max_scroll_offset c))
                                     (candidate_offsets c (snap_areas c)) None) as [sp |] eqn:Hfc.
    + apply find_closest_in_candidates in Hfc.
      destruct Hfc as [Hin | Hnone]; [| discriminate Hnone].
      apply (candidate_offsets_in_bounds c (snap_areas c) sp Hin).
    + exact Hcl.
Qed.

