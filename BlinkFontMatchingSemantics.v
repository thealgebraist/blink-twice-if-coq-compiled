(* ========================================================================= *)
(*                  BlinkFontMatchingSemantics.v                             *)
(* ========================================================================= *)
(* Formal verification of Chromium Blink Font Matching & Fallback Algorithm   *)
(* per W3C CSS Fonts Module Level 4 §5 (Font Matching Algorithm).            *)
(* Strictly constructive, 0 admits.                                          *)
(* ========================================================================= *)

From Stdlib Require Import ZArith Lists.List Bool Lia.
Open Scope Z_scope.

(** * 1. Core Data Types *)

Record FontFace : Type := mkFontFace {
  font_family_id   : Z;
  font_weight      : Z;
  font_style       : Z;
  font_stretch     : Z;
  supports_unicode : Z -> bool
}.

Record FontRequest : Type := mkFontRequest {
  req_family_id : Z;
  req_weight    : Z;
  req_style     : Z;
  req_stretch   : Z
}.

(** * 2. Font Style Distance Metric (CSS Fonts 4 §5.2) *)

Definition font_style_distance (req : FontRequest) (face : FontFace) : Z :=
  Z.abs (req_weight req - font_weight face) +
  Z.abs (req_style req - font_style face) +
  Z.abs (req_stretch req - font_stretch face).

Theorem font_style_distance_nonneg : forall (req : FontRequest) (face : FontFace),
  font_style_distance req face >= 0.
Proof.
  intros req face.
  unfold font_style_distance.
  pose proof (Z.abs_nonneg (req_weight req - font_weight face)).
  pose proof (Z.abs_nonneg (req_style req - font_style face)).
  pose proof (Z.abs_nonneg (req_stretch req - font_stretch face)).
  lia.
Qed.

Theorem font_style_distance_identical : forall (req : FontRequest) (face : FontFace),
  req_weight req = font_weight face ->
  req_style req = font_style face ->
  req_stretch req = font_stretch face ->
  font_style_distance req face = 0.
Proof.
  intros req face Hw Hs Hstr.
  unfold font_style_distance.
  rewrite Hw, Hs, Hstr.
  do 3 rewrite Z.sub_diag.
  simpl. reflexivity.
Qed.

Theorem font_style_distance_identical_iff : forall (req : FontRequest) (face : FontFace),
  font_style_distance req face = 0 <->
  (req_weight req = font_weight face /\
   req_style req = font_style face /\
   req_stretch req = font_stretch face).
Proof.
  intros req face.
  unfold font_style_distance.
  pose proof (Z.abs_nonneg (req_weight req - font_weight face)).
  pose proof (Z.abs_nonneg (req_style req - font_style face)).
  pose proof (Z.abs_nonneg (req_stretch req - font_stretch face)).
  split.
  - intros Hsum.
    assert (Z.abs (req_weight req - font_weight face) = 0 /\
            Z.abs (req_style req - font_style face) = 0 /\
            Z.abs (req_stretch req - font_stretch face) = 0) by lia.
    destruct H2 as [Hw [Hs Hstr]].
    apply Z.abs_0_iff in Hw.
    apply Z.abs_0_iff in Hs.
    apply Z.abs_0_iff in Hstr.
    split; [lia | split; lia].
  - intros [Hw [Hs Hstr]].
    apply font_style_distance_identical; assumption.
Qed.

Theorem font_style_distance_identical_conj : forall (req : FontRequest) (face : FontFace),
  req_weight req = font_weight face /\
  req_style req = font_style face /\
  req_stretch req = font_stretch face ->
  font_style_distance req face = 0.
Proof.
  intros req face [Hw [Hs Hstr]].
  apply font_style_distance_identical; assumption.
Qed.

Theorem font_style_distance_identical_with_family : forall (req : FontRequest) (face : FontFace),
  req_family_id req = font_family_id face ->
  req_weight req = font_weight face ->
  req_style req = font_style face ->
  req_stretch req = font_stretch face ->
  font_style_distance req face = 0.
Proof.
  intros req face _ Hw Hs Hstr.
  apply font_style_distance_identical; assumption.
Qed.

(** * 3. Best Face Selection (CSS Fonts 4 §5.2) *)

Fixpoint select_best_face_rec (req : FontRequest) (best : FontFace) (faces : list FontFace) : FontFace :=
  match faces with
  | nil => best
  | f :: rest =>
      if font_style_distance req f <? font_style_distance req best then
        select_best_face_rec req f rest
      else
        select_best_face_rec req best rest
  end.

Definition select_best_face (req : FontRequest) (faces : list FontFace) : option FontFace :=
  match faces with
  | nil => None
  | f :: rest => Some (select_best_face_rec req f rest)
  end.

Lemma select_best_face_rec_in : forall (faces : list FontFace) (req : FontRequest) (best : FontFace),
  In (select_best_face_rec req best faces) (best :: faces).
Proof.
  induction faces as [| c cs IH]; intros req best.
  - simpl. left. reflexivity.
  - simpl.
    destruct (font_style_distance req c <? font_style_distance req best) eqn:Hcmp.
    + specialize (IH req c).
      destruct IH as [IHc | IHcs].
      * right. left. assumption.
      * right. right. assumption.
    + specialize (IH req best).
      destruct IH as [IHbest | IHcs].
      * left. assumption.
      * right. right. assumption.
Qed.

Theorem select_best_face_subset : forall (req : FontRequest) (faces : list FontFace) (f : FontFace),
  select_best_face req faces = Some f ->
  In f faces.
Proof.
  intros req faces f Hsel.
  destruct faces as [| f0 fs].
  - discriminate.
  - simpl in Hsel.
    injection Hsel as Hf.
    subst f.
    apply select_best_face_rec_in.
Qed.

Theorem select_best_face_none_iff : forall (req : FontRequest) (faces : list FontFace),
  select_best_face req faces = None <-> faces = nil.
Proof.
  intros req faces.
  destruct faces as [| f fs]; split; intros H; try reflexivity; try discriminate.
Qed.

(** * 4. Fallback Chain Matching (CSS Fonts 4 §5.3) *)

Definition match_font_fallback
  (req : FontRequest)
  (primary_faces generic_faces system_faces : list FontFace)
  (codepoint : Z) : option FontFace :=
  let prim := filter (fun f => supports_unicode f codepoint) primary_faces in
  match select_best_face req prim with
  | Some f => Some f
  | None =>
      let gener := filter (fun f => supports_unicode f codepoint) generic_faces in
      match select_best_face req gener with
      | Some f => Some f
      | None =>
          let sys := filter (fun f => supports_unicode f codepoint) system_faces in
          select_best_face req sys
      end
  end.

Lemma filter_supporting_nonempty : forall (faces : list FontFace) (cp : Z) (f : FontFace),
  In f faces ->
  supports_unicode f cp = true ->
  filter (fun x => supports_unicode x cp) faces <> nil.
Proof.
  intros faces cp f Hin Hsup.
  induction faces as [| x xs IH].
  - contradiction.
  - simpl.
    destruct (supports_unicode x cp) eqn:Hxcov.
    + discriminate.
    + destruct Hin as [Heq | Hinx].
      * subst x. rewrite Hsup in Hxcov. discriminate.
      * apply IH. assumption.
Qed.

Lemma select_best_face_nonempty : forall (req : FontRequest) (faces : list FontFace),
  faces <> nil ->
  exists (f : FontFace), select_best_face req faces = Some f.
Proof.
  intros req faces Hne.
  destruct faces as [| f0 fs].
  - contradiction Hne; reflexivity.
  - simpl. exists (select_best_face_rec req f0 fs). reflexivity.
Qed.

Theorem fallback_chain_hierarchy : forall (req : FontRequest)
  (primary_faces generic_faces system_faces : list FontFace)
  (codepoint : Z) (f : FontFace),
  In f primary_faces ->
  supports_unicode f codepoint = true ->
  exists (matched : FontFace),
    match_font_fallback req primary_faces generic_faces system_faces codepoint = Some matched /\
    In matched primary_faces.
Proof.
  intros req primary_faces generic_faces system_faces codepoint f Hin Hsup.
  unfold match_font_fallback.
  pose proof (filter_supporting_nonempty primary_faces codepoint f Hin Hsup) as Hne.
  destruct (select_best_face_nonempty req (filter (fun f0 => supports_unicode f0 codepoint) primary_faces) Hne) as [matched Hsel].
  rewrite Hsel.
  exists matched.
  split; [reflexivity |].
  apply select_best_face_subset in Hsel.
  apply filter_In in Hsel.
  destruct Hsel as [Hin_prim _].
  assumption.
Qed.

Theorem fallback_chain_hierarchy_supports : forall (req : FontRequest)
  (primary_faces generic_faces system_faces : list FontFace)
  (codepoint : Z) (f : FontFace),
  In f primary_faces ->
  supports_unicode f codepoint = true ->
  exists (matched : FontFace),
    match_font_fallback req primary_faces generic_faces system_faces codepoint = Some matched /\
    In matched primary_faces /\
    supports_unicode matched codepoint = true.
Proof.
  intros req primary_faces generic_faces system_faces codepoint f Hin Hsup.
  unfold match_font_fallback.
  pose proof (filter_supporting_nonempty primary_faces codepoint f Hin Hsup) as Hne.
  destruct (select_best_face_nonempty req (filter (fun f0 => supports_unicode f0 codepoint) primary_faces) Hne) as [matched Hsel].
  rewrite Hsel.
  exists matched.
  split; [reflexivity |].
  apply select_best_face_subset in Hsel.
  apply filter_In in Hsel.
  assumption.
Qed.

Theorem fallback_chain_hierarchy_select : forall (req : FontRequest)
  (primary_faces generic_faces system_faces : list FontFace)
  (codepoint : Z) (f : FontFace),
  In f primary_faces ->
  supports_unicode f codepoint = true ->
  match_font_fallback req primary_faces generic_faces system_faces codepoint =
  select_best_face req (filter (fun c => supports_unicode c codepoint) primary_faces).
Proof.
  intros req primary_faces generic_faces system_faces codepoint f Hin Hsup.
  unfold match_font_fallback.
  pose proof (filter_supporting_nonempty primary_faces codepoint f Hin Hsup) as Hne.
  destruct (select_best_face_nonempty req (filter (fun f0 => supports_unicode f0 codepoint) primary_faces) Hne) as [matched Hsel].
  rewrite Hsel.
  reflexivity.
Qed.

Theorem fallback_chain_hierarchy_independent : forall (req : FontRequest)
  (primary_faces generic_faces1 generic_faces2 system_faces1 system_faces2 : list FontFace)
  (codepoint : Z) (f : FontFace),
  In f primary_faces ->
  supports_unicode f codepoint = true ->
  match_font_fallback req primary_faces generic_faces1 system_faces1 codepoint =
  match_font_fallback req primary_faces generic_faces2 system_faces2 codepoint.
Proof.
  intros req primary_faces generic_faces1 generic_faces2 system_faces1 system_faces2 codepoint f Hin Hsup.
  rewrite (fallback_chain_hierarchy_select req primary_faces generic_faces1 system_faces1 codepoint f Hin Hsup).
  rewrite (fallback_chain_hierarchy_select req primary_faces generic_faces2 system_faces2 codepoint f Hin Hsup).
  reflexivity.
Qed.

Theorem fallback_chain_hierarchy_ex : forall (req : FontRequest)
  (primary_faces generic_faces system_faces : list FontFace)
  (codepoint : Z),
  (exists f : FontFace, In f primary_faces /\ supports_unicode f codepoint = true) ->
  exists (matched : FontFace),
    match_font_fallback req primary_faces generic_faces system_faces codepoint = Some matched /\
    In matched primary_faces.
Proof.
  intros req primary_faces generic_faces system_faces codepoint [f [Hin Hsup]].
  apply (fallback_chain_hierarchy req primary_faces generic_faces system_faces codepoint f Hin Hsup).
Qed.
