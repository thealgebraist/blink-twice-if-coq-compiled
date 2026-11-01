(******************************************************************************)
(*                                                                            *)
(*      BLINK HTML5 ADOPTION AGENCY, FOSTER PARENTING & SKIA PAINT ENGINE     *)
(*                                                                            *)
(*  Machine-Checked Rocq/Coq 9.3.0 Semantics for Pillars 1 & 5 of Chromium    *)
(*  Blink's HTML5 Parser, DOM Tree Construction & Skia 2D Paint Pipeline:     *)
(*                                                                            *)
(*    Pillar 1 (WHATWG HTML5 §13.2 Tokenizer & TreeBuilder Edge Cases):       *)
(*      1. Tokenizer States & Numeric Character Reference Sanitization        *)
(*      2. Insertion Modes, Table Structural Recovery & Foster Parenting      *)
(*      3. Active Formatting Elements (Noah's Ark <= 3) & Adoption Agency     *)
(*                                                                            *)
(*    Pillar 5 (Skia `SkRRect`, Shadows, Gradients, Opacity, Clip & Transform)*)
(*      4. Rounded-Corner `SkRRect` Radius Clamping & Anti-Aliased SDF Alpha  *)
(*      5. Outer `box-shadow` Spread Expansion & Blur Falloff Attenuation     *)
(*      6. Linear-Gradient Stop Interpolation, Group `opacity` Compositing,   *)
(*         Hierarchical `overflow: hidden` Scissor Clipping & 2D `translate`  *)
(*                                                                            *)
(*  Verification Status: 100% Machine-Checked (Strictly 0 Admits, 0 Axioms)   *)
(*                                                                            *)
(******************************************************************************)

From Stdlib Require Import ZArith.
From Stdlib Require Import List.
From Stdlib Require Import Bool.
From Stdlib Require Import Lia.
Require Import BlinkDualModeZSemantics.
Require Import BlinkHTML5TreeBuilderAndCSSCascadeEngine.
Require Import BlinkCSS4InlineAndPositionedLayoutEngine.
Import ListNotations.
Open Scope Z_scope.
#[local] Set Warnings "-register-all".

(* ========================================================================= *)
(* SECTION 1: WHATWG HTML5 TOKENIZER STATES & NUMERIC CHARACTER REFERENCES   *)
(*   Chromium: core/html/parser/html_tokenizer.cc, html_entity_parser.cc     *)
(* ========================================================================= *)

Inductive HTMLTokenizerState : Type :=
  | TS_Data
  | TS_RCDATA
  | TS_RAWTEXT
  | TS_ScriptData
  | TS_TagOpen
  | TS_EndTagOpen
  | TS_TagName
  | TS_BeforeAttrName
  | TS_AttrName
  | TS_AfterAttrName
  | TS_BeforeAttrValue
  | TS_AttrValueDoubleQuoted
  | TS_AttrValueSingleQuoted
  | TS_AttrValueUnquoted
  | TS_SelfClosingStartTag
  | TS_MarkupDeclarationOpen
  | TS_Comment.

(** Initial content tokenizer mode entered after emitting an open start tag *)
Definition tokenizer_state_for_raw_tag (t : HTMLTag) : HTMLTokenizerState :=
  match t with
  | Tag_Style  => TS_RAWTEXT
  | Tag_Script => TS_ScriptData
  | _          => TS_Data
  end.

(** WHATWG §13.2.5.73 Numeric Character Reference End State:
    Null (`0`), UTF-16 surrogates (`0xD800..0xDFFF` = `55296..57343`),
    and values exceeding `0x10FFFF` (`1114111`) map to `U+FFFD` (`65533`). *)
Definition unicode_replacement_char : Z := 65533.

Definition sanitize_numeric_char_ref (cp : Z) : Z :=
  if (cp <=? 0) || (1114111 <? cp) || ((55296 <=? cp) && (cp <=? 57343)) then
    unicode_replacement_char
  else
    cp.

Theorem numeric_char_ref_zero_is_replacement :
  sanitize_numeric_char_ref 0 = unicode_replacement_char.
Proof. reflexivity. Qed.

Theorem numeric_char_ref_surrogate_is_replacement :
  forall cp, 55296 <= cp <= 57343 ->
  sanitize_numeric_char_ref cp = unicode_replacement_char.
Proof.
  intros cp [Hlo Hhi].
  unfold sanitize_numeric_char_ref.
  assert (E1 : (55296 <=? cp) = true) by (apply Z.leb_le; lia).
  assert (E2 : (cp <=? 57343) = true) by (apply Z.leb_le; lia).
  rewrite E1, E2; simpl.
  rewrite Bool.orb_true_r. reflexivity.
Qed.

Theorem numeric_char_ref_valid_unicode_scalar :
  forall cp,
    1 <= sanitize_numeric_char_ref cp <= 1114111 /\
    ~ (55296 <= sanitize_numeric_char_ref cp <= 57343).
Proof.
  intros cp. unfold sanitize_numeric_char_ref, unicode_replacement_char.
  destruct (cp <=? 0) eqn:E0; simpl; [lia |].
  destruct (1114111 <? cp) eqn:Ehi; simpl; [lia |].
  destruct ((55296 <=? cp) && (cp <=? 57343)) eqn:Esurr; simpl; [lia |].
  apply Z.leb_gt in E0.
  apply Z.ltb_ge in Ehi.
  apply Bool.andb_false_iff in Esurr.
  split; [lia |].
  intros [S1 S2].
  destruct Esurr as [F | F].
  - apply Z.leb_gt in F; lia.
  - apply Z.leb_gt in F; lia.
Qed.

Theorem numeric_char_ref_ascii_identity :
  forall cp, 32 <= cp <= 126 -> sanitize_numeric_char_ref cp = cp.
Proof.
  intros cp [Hlo Hhi].
  unfold sanitize_numeric_char_ref.
  assert (E0 : (cp <=? 0) = false) by (apply Z.leb_gt; lia).
  assert (E1 : (1114111 <? cp) = false) by (apply Z.ltb_ge; lia).
  assert (E2 : (55296 <=? cp) = false) by (apply Z.leb_gt; lia).
  rewrite E0, E1, E2; simpl. reflexivity.
Qed.

(* ========================================================================= *)
(* SECTION 2: INSERTION MODES, TABLE RECOVERY & FOSTER PARENTING             *)
(*   Chromium: core/html/parser/html_tree_builder.cc, html_construction_site *)
(* ========================================================================= *)

Inductive HTMLInsertionMode : Type :=
  | IM_Initial
  | IM_BeforeHtml
  | IM_BeforeHead
  | IM_InHead
  | IM_AfterHead
  | IM_InBody
  | IM_Text
  | IM_InTable
  | IM_InTableBody
  | IM_InRow
  | IM_InCell
  | IM_AfterBody.

(** WHATWG §13.2.4.1 "Reset the insertion mode appropriately" (top-down stack scan) *)
Fixpoint compute_insertion_mode_from_stack (stack : list HTMLTag) : HTMLInsertionMode :=
  match stack with
  | [] => IM_InBody
  | Tag_Td :: _ | Tag_Th :: _ => IM_InCell
  | Tag_Tr :: _ => IM_InRow
  | Tag_Tbody :: _ | Tag_Thead :: _ | Tag_Tfoot :: _ => IM_InTableBody
  | Tag_Caption :: _ => IM_InBody
  | Tag_Table :: _ => IM_InTable
  | Tag_Head :: _ => IM_InHead
  | Tag_Body :: _ => IM_InBody
  | _ :: rest => compute_insertion_mode_from_stack rest
  end.

(** Foster parenting triggers when inserting non-table content while the current
    open element is `<table>`, `<thead>`, `<tbody>`, `<tfoot>`, or `<tr>`. *)
Definition is_foster_parenting_tag (t : HTMLTag) : bool :=
  match t with
  | Tag_Table | Tag_Thead | Tag_Tbody | Tag_Tfoot | Tag_Tr => true
  | _ => false
  end.

(** Insert `new_id` immediately before `target_id` in `children` (or append if absent) *)
Fixpoint insert_before_target (children : list Z) (target_id new_id : Z) : list Z :=
  match children with
  | [] => [new_id]
  | c :: cs =>
      if Z.eqb c target_id then
        new_id :: c :: cs
      else
        c :: insert_before_target cs target_id new_id
  end.

Theorem insert_before_target_length :
  forall cs tid nid,
    length (insert_before_target cs tid nid) = S (length cs).
Proof.
  induction cs as [| c cs IH]; intros tid nid; simpl.
  - reflexivity.
  - destruct (Z.eqb c tid); simpl; [reflexivity | rewrite IH; reflexivity].
Qed.

Theorem insert_before_target_preserves_members :
  forall cs tid nid x,
    In x (insert_before_target cs tid nid) <-> (x = nid \/ In x cs).
Proof.
  induction cs as [| c cs IH]; intros tid nid x; simpl.
  - split; intros H.
    + destruct H as [H | []]; left; symmetry; exact H.
    + destruct H as [-> | []]; left; reflexivity.
  - destruct (Z.eqb c tid) eqn:Eq; simpl.
    + split; intros H.
      * destruct H as [H | [H | H]]; [left; symmetry; exact H | right; left; exact H | right; right; exact H].
      * destruct H as [-> | [H | H]]; [left; reflexivity | right; left; exact H | right; right; exact H].
    + split; intros H.
      * destruct H as [H | H].
        -- right; left; exact H.
        -- apply IH in H. destruct H as [H | H]; [left; exact H | right; right; exact H].
      * destruct H as [H | [H | H]].
        -- right; apply IH; left; exact H.
        -- left; exact H.
        -- right; apply IH; right; exact H.
Qed.

(** Entering a `<td>` or `<th>` cell transitions insertion mode to `IM_InCell`
    and turns off foster parenting so normal flow resumes inside the cell! *)
Theorem table_cell_disables_foster_parenting :
  forall rest,
    compute_insertion_mode_from_stack (Tag_Td :: rest) = IM_InCell /\
    is_foster_parenting_tag Tag_Td = false.
Proof.
  intros rest. split; reflexivity.
Qed.

(* ========================================================================= *)
(* SECTION 3: ACTIVE FORMATTING ELEMENTS, NOAH'S ARK & ADOPTION AGENCY       *)
(*   Chromium: core/html/parser/html_formatting_element_list.cc              *)
(* ========================================================================= *)

Inductive AFEEntry : Type :=
  | AFE_Marker : AFEEntry
  | AFE_Element : Z -> Z -> AFEEntry. (* node_id, formatting_signature *)

Fixpoint count_sig_since_marker (afe : list AFEEntry) (sig : Z) : nat :=
  match afe with
  | [] => 0%nat
  | AFE_Marker :: _ => 0%nat
  | AFE_Element _ s :: rest =>
      if Z.eqb s sig then S (count_sig_since_marker rest sig)
      else count_sig_since_marker rest sig
  end.

(** Remove the oldest matching `sig` entry prior to the first `AFE_Marker` *)
Fixpoint remove_oldest_sig_since_marker (afe : list AFEEntry) (sig : Z) : list AFEEntry :=
  match afe with
  | [] => []
  | AFE_Marker :: rest => AFE_Marker :: rest
  | AFE_Element nid s :: rest =>
      if Z.eqb s sig then
        if Nat.eqb (count_sig_since_marker rest sig) 0%nat then rest
        else AFE_Element nid s :: remove_oldest_sig_since_marker rest sig
      else
        AFE_Element nid s :: remove_oldest_sig_since_marker rest sig
  end.

Lemma remove_oldest_decrements_positive_count :
  forall afe sig,
    (1 <= count_sig_since_marker afe sig)%nat ->
    count_sig_since_marker (remove_oldest_sig_since_marker afe sig) sig =
      Nat.pred (count_sig_since_marker afe sig).
Proof.
  induction afe as [| e rest IH]; intros sig Hpos; simpl in *.
  - lia.
  - destruct e as [| nid s].
    + lia.
    + destruct (Z.eqb s sig) eqn:Es.
      * destruct (Nat.eqb (count_sig_since_marker rest sig) 0%nat) eqn:E0.
        -- apply Nat.eqb_eq in E0. rewrite E0. reflexivity.
        -- apply Nat.eqb_neq in E0. simpl. rewrite Es.
           rewrite IH by lia. lia.
      * simpl. rewrite Es. apply IH; exact Hpos.
Qed.

(** Noah's Ark Clause (WHATWG §13.2.4.3): before pushing a formatting element
    with signature `sig`, if at least 3 active elements with `sig` exist after
    the last scope marker, evict the oldest one first! *)
Definition afe_push_noahs_ark (afe : list AFEEntry) (nid sig : Z) : list AFEEntry :=
  let trimmed :=
    if Nat.leb 3%nat (count_sig_since_marker afe sig) then
      remove_oldest_sig_since_marker afe sig
    else
      afe
  in AFE_Element nid sig :: trimmed.

Theorem noahs_ark_preserves_cap_3 :
  forall afe nid sig,
    (count_sig_since_marker afe sig <= 3)%nat ->
    (count_sig_since_marker (afe_push_noahs_ark afe nid sig) sig <= 3)%nat.
Proof.
  intros afe nid sig Hle.
  unfold afe_push_noahs_ark.
  destruct (Nat.leb 3%nat (count_sig_since_marker afe sig)) eqn:E3.
  - apply Nat.leb_le in E3.
    assert (Heq : count_sig_since_marker afe sig = 3%nat) by lia.
    simpl. rewrite Z.eqb_refl.
    rewrite remove_oldest_decrements_positive_count by lia.
    rewrite Heq; simpl; lia.
  - apply Nat.leb_gt in E3.
    simpl. rewrite Z.eqb_refl. lia.
Qed.

Theorem afe_marker_resets_sig_count :
  forall afe sig,
    count_sig_since_marker (AFE_Marker :: afe) sig = 0%nat.
Proof. reflexivity. Qed.

(** Adoption Agency removal of matched formatting element `target_nid`
    preserves all inner unclosed formatting elements for reconstruction! *)
Fixpoint afe_remove_by_node_id (afe : list AFEEntry) (target_nid : Z) : list AFEEntry :=
  match afe with
  | [] => []
  | AFE_Marker :: rest => AFE_Marker :: afe_remove_by_node_id rest target_nid
  | AFE_Element nid s :: rest =>
      if Z.eqb nid target_nid then rest
      else AFE_Element nid s :: afe_remove_by_node_id rest target_nid
  end.

Theorem aaa_remove_outer_preserves_inner_formatting :
  forall inner_id inner_sig outer_id outer_sig rest,
    inner_id <> outer_id ->
    In (AFE_Element inner_id inner_sig)
       (afe_remove_by_node_id
          (AFE_Element inner_id inner_sig :: AFE_Element outer_id outer_sig :: rest)
          outer_id).
Proof.
  intros inner_id inner_sig outer_id outer_sig rest Hneq.
  simpl.
  assert (E : Z.eqb inner_id outer_id = false) by (apply Z.eqb_neq; exact Hneq).
  rewrite E; simpl. left; reflexivity.
Qed.

(* ========================================================================= *)
(* SECTION 4: SKIA `SkRRect` CORNER CLAMPING & ANTI-ALIASED SDF COVERAGE     *)
(*   Chromium: platform/graphics/skia/, CSS Backgrounds & Borders 3 §5.3     *)
(* ========================================================================= *)

(** CSS Backgrounds 3 §5.3: Corner radii must never overlap (`2 * r <= w /\ 2 * r <= h`) *)
Definition clamp_corner_radius (r w h : Z) : Z :=
  Z.max 0 (Z.min r (Z.min (w / 2) (h / 2))).

Theorem clamped_radius_fits_half_dims :
  forall r w h,
    0 <= w -> 0 <= h ->
    let r' := clamp_corner_radius r w h in
    0 <= r' /\ 2 * r' <= w /\ 2 * r' <= h.
Proof.
  intros r w h Hw Hh r'.
  unfold r', clamp_corner_radius.
  assert (Hw2 : 0 <= w / 2 /\ 2 * (w / 2) <= w).
  { split; [apply Z.div_pos; lia | apply Z.mul_div_le; lia]. }
  assert (Hh2 : 0 <= h / 2 /\ 2 * (h / 2) <= h).
  { split; [apply Z.div_pos; lia | apply Z.mul_div_le; lia]. }
  lia.
Qed.

(** Subpixel Signed-Distance-Field (`dist_q8` in 1/256 px units) to `[0..255]` alpha:
    `dist_q8 <= -128` (-0.5px, inside)  => `255`
    `dist_q8 >= +128` (+0.5px, outside) => `0`
    `(-128, +128)`                      => linear anti-aliased ramp `((128 - dist_q8) * 255) / 256` *)
Definition sdf_alpha_255 (dist_q8 : Z) : Z :=
  if dist_q8 <=? -128 then 255
  else if 128 <=? dist_q8 then 0
  else ((128 - dist_q8) * 255) / 256.

Theorem sdf_alpha_255_bounds :
  forall d, 0 <= sdf_alpha_255 d <= 255.
Proof.
  intros d. unfold sdf_alpha_255.
  destruct (d <=? -128) eqn:Elo; [lia |].
  destruct (128 <=? d) eqn:Ehi; [lia |].
  apply Z.leb_gt in Elo.
  apply Z.leb_gt in Ehi.
  split.
  - apply Z.div_pos; lia.
  - apply Z.div_le_upper_bound; lia.
Qed.

Theorem sdf_alpha_255_antitone :
  forall d1 d2, d1 <= d2 -> sdf_alpha_255 d2 <= sdf_alpha_255 d1.
Proof.
  intros d1 d2 Hle. unfold sdf_alpha_255.
  destruct (d1 <=? -128) eqn:E1lo; destruct (d2 <=? -128) eqn:E2lo.
  - lia.
  - apply Z.leb_gt in E2lo.
    destruct (128 <=? d2) eqn:E2hi; [lia |].
    apply Z.leb_gt in E2hi.
    apply Z.div_le_upper_bound; lia.
  - apply Z.leb_gt in E1lo; apply Z.leb_le in E2lo; lia.
  - apply Z.leb_gt in E1lo; apply Z.leb_gt in E2lo.
    destruct (128 <=? d1) eqn:E1hi; destruct (128 <=? d2) eqn:E2hi.
    + lia.
    + apply Z.leb_le in E1hi; apply Z.leb_gt in E2hi; lia.
    + apply Z.leb_gt in E1hi. apply Z.div_pos; lia.
    + apply Z.div_le_mono; lia.
Qed.

(* ========================================================================= *)
(* SECTION 5: OUTER `box-shadow` SPREAD & BLUR FALLOFF ATTENUATION           *)
(*   Chromium: core/paint/box_shadow_painter.cc                              *)
(* ========================================================================= *)

Definition shadow_expanded_extent (box_sz spread : Z) : Z :=
  Z.max 0 (box_sz + 2 * spread).

Definition shadow_falloff_alpha (base_alpha dist blur : Z) : Z :=
  if blur <=? 0 then
    if dist <=? 0 then base_alpha else 0
  else if dist <=? 0 then
    base_alpha
  else if blur <=? dist then
    0
  else
    (base_alpha * (blur - dist)) / blur.

Theorem shadow_falloff_bounded :
  forall a d blur,
    0 <= a <= 255 ->
    0 <= shadow_falloff_alpha a d blur <= a.
Proof.
  intros a d blur [Ha0 Ha255].
  unfold shadow_falloff_alpha.
  destruct (blur <=? 0) eqn:Eb.
  - destruct (d <=? 0); lia.
  - apply Z.leb_gt in Eb.
    destruct (d <=? 0) eqn:Ed0; [lia |].
    destruct (blur <=? d) eqn:Ebd; [lia |].
    apply Z.leb_gt in Ed0; apply Z.leb_gt in Ebd.
    split.
    + apply Z.div_pos; [nia | lia].
    + apply Z.div_le_upper_bound; [lia | nia].
Qed.

Theorem shadow_falloff_zero_beyond_blur :
  forall a d blur,
    0 < blur -> blur <= d ->
    shadow_falloff_alpha a d blur = 0.
Proof.
  intros a d blur Hb Hbd.
  unfold shadow_falloff_alpha.
  assert (E1 : (blur <=? 0) = false) by (apply Z.leb_gt; lia).
  assert (E2 : (d <=? 0) = false) by (apply Z.leb_gt; lia).
  assert (E3 : (blur <=? d) = true) by (apply Z.leb_le; lia).
  rewrite E1, E2, E3; reflexivity.
Qed.

(* ========================================================================= *)
(* SECTION 6: GRADIENTS, GROUP `opacity`, `overflow: hidden` CLIP & TRANSFORM*)
(*   Chromium: core/paint/paint_layer_painter.cc, clip_rect.h                *)
(* ========================================================================= *)

(** Linear gradient channel interpolation between two stops at `0 <= t <= tmax` *)
Definition lerp_gradient_channel (c0 c1 t tmax : Z) : Z :=
  if tmax <=? 0 then c0
  else if t <=? 0 then c0
  else if tmax <=? t then c1
  else (c0 * (tmax - t) + c1 * t) / tmax.

Theorem lerp_gradient_channel_bounds :
  forall c0 c1 t tmax,
    0 <= c0 <= 255 -> 0 <= c1 <= 255 ->
    0 <= lerp_gradient_channel c0 c1 t tmax <= 255.
Proof.
  intros c0 c1 t tmax H0 H1.
  unfold lerp_gradient_channel.
  destruct (tmax <=? 0) eqn:Em; [lia |].
  destruct (t <=? 0) eqn:Et0; [lia |].
  destruct (tmax <=? t) eqn:Ett; [lia |].
  apply Z.leb_gt in Em; apply Z.leb_gt in Et0; apply Z.leb_gt in Ett.
  split.
  - apply Z.div_pos; nia.
  - apply Z.div_le_upper_bound; [lia | nia].
Qed.

Theorem lerp_gradient_endpoints :
  forall c0 c1 tmax,
    0 < tmax ->
    lerp_gradient_channel c0 c1 0 tmax = c0 /\
    lerp_gradient_channel c0 c1 tmax tmax = c1.
Proof.
  intros c0 c1 tmax Hm.
  unfold lerp_gradient_channel.
  assert (E0 : (tmax <=? 0) = false) by (apply Z.leb_gt; lia).
  assert (E1 : (tmax <=? tmax) = true) by (apply Z.leb_le; lia).
  assert (E2 : (tmax <=? 0) = false) by exact E0.
  rewrite E0. simpl. split; [reflexivity |].
  assert (Et0 : (tmax <=? 0) = false) by exact E0.
  rewrite E1. destruct (tmax <=? 0) eqn:Ex; [apply Z.leb_le in Ex; lia | reflexivity].
Qed.

(** Group `opacity` Porter-Duff `source-over` compositing of an offscreen group *)
Definition composite_group_channel (src_c dst_c src_a opacity_u8 : Z) : Z :=
  let eff_a := (src_a * opacity_u8) / 255 in
  (src_c * eff_a + dst_c * (255 - eff_a)) / 255.

Theorem composite_group_zero_opacity_identity :
  forall src_c dst_c src_a,
    0 <= dst_c <= 255 ->
    composite_group_channel src_c dst_c src_a 0 = dst_c.
Proof.
  intros src_c dst_c src_a Hdst.
  unfold composite_group_channel.
  replace (src_a * 0) with 0 by lia.
  change (0 / 255) with 0.
  replace (src_c * 0 + dst_c * (255 - 0)) with (dst_c * 255) by lia.
  apply Z.div_mul; lia.
Qed.

Theorem composite_group_channel_bounds :
  forall src_c dst_c src_a op,
    0 <= src_c <= 255 -> 0 <= dst_c <= 255 ->
    0 <= src_a <= 255 -> 0 <= op <= 255 ->
    0 <= composite_group_channel src_c dst_c src_a op <= 255.
Proof.
  intros src_c dst_c src_a op [Hsc0 Hsc1] [Hdc0 Hdc1] [Hsa0 Hsa1] [Hop0 Hop1].
  unfold composite_group_channel.
  set (eff_a := (src_a * op) / 255).
  assert (Heff : 0 <= eff_a <= 255).
  { unfold eff_a. split; [apply Z.div_pos; [nia | lia] | apply Z.div_le_upper_bound; [lia | nia]]. }
  destruct Heff as [He0 He1].
  split; [apply Z.div_pos; [nia | lia] | apply Z.div_le_upper_bound; [lia | nia]].
Qed.

(** Hierarchical `overflow: hidden` Scissor Clip Intersection *)
Record ClipScissor : Type := mkClipScissor {
  clip_x0 : Z;
  clip_y0 : Z;
  clip_x1 : Z;
  clip_y1 : Z
}.

Definition point_in_clip (px py : Z) (c : ClipScissor) : Prop :=
  clip_x0 c <= px < clip_x1 c /\ clip_y0 c <= py < clip_y1 c.

Definition intersect_clips (a b : ClipScissor) : ClipScissor :=
  mkClipScissor
    (Z.max (clip_x0 a) (clip_x0 b))
    (Z.max (clip_y0 a) (clip_y0 b))
    (Z.min (clip_x1 a) (clip_x1 b))
    (Z.min (clip_y1 a) (clip_y1 b)).

Theorem intersect_clips_exact_conjunction :
  forall px py a b,
    point_in_clip px py (intersect_clips a b) <->
    (point_in_clip px py a /\ point_in_clip px py b).
Proof.
  intros px py a b.
  unfold point_in_clip, intersect_clips; simpl.
  lia.
Qed.

Theorem intersect_clips_never_escapes_parent :
  forall px py parent_clip child_clip,
    point_in_clip px py (intersect_clips parent_clip child_clip) ->
    point_in_clip px py parent_clip.
Proof.
  intros px py p c H.
  apply intersect_clips_exact_conjunction in H.
  exact (proj1 H).
Qed.

(** CSS Color 4 §12.2 & CSS Transforms 1 §6: `opacity < 255` or `has_transform = true`
    establishes a Stacking Context even when `is_positioned = false`! *)
Definition establishes_stacking_context_pillar5
    (is_positioned has_z : bool) (opacity_u8 : Z) (has_transform : bool) : bool :=
  (is_positioned && has_z) || (opacity_u8 <? 255) || has_transform.

Theorem opacity_below_one_creates_stacking_context :
  forall is_pos has_z op has_tf,
    op < 255 ->
    establishes_stacking_context_pillar5 is_pos has_z op has_tf = true.
Proof.
  intros is_pos has_z op has_tf Hlt.
  unfold establishes_stacking_context_pillar5.
  assert (E : (op <? 255) = true) by (apply Z.ltb_lt; lia).
  rewrite E. rewrite Bool.orb_true_r; simpl. reflexivity.
Qed.

Theorem transform_creates_stacking_context :
  forall is_pos has_z op,
    establishes_stacking_context_pillar5 is_pos has_z op true = true.
Proof.
  intros is_pos has_z op.
  unfold establishes_stacking_context_pillar5.
  rewrite Bool.orb_true_r. reflexivity.
Qed.
