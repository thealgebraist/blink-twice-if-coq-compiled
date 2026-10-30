(******************************************************************************)
(* BlinkFlexboxContainerSemantics.v                                           *)
(* Formal Specification, Big-Step Operational Semantics & Metatheory          *)
(* for CSS Flexible Box Layout (W3C CSS Flexible Box Layout Level 1)          *)
(* and Blink's FlexLayoutAlgorithm (`flex_layout_algorithm.cc`).             *)
(*                                                                            *)
(* Covers:                                                                    *)
(* 1. Flex Direction (Row vs Column) & Flex Basis Resolution                  *)
(* 2. Main-Axis Flexible Length Resolution (ResolveFlexibleLengths)           *)
(* 3. Cross-Axis Alignment (FlexAlign::kStretch, kFlexStart, kCenter)         *)
(* 4. Multi-Child Flex Container Big-Step Layout Judgment                     *)
(* 5. Determinism, Space Conservation & Non-Negative Layout Invariants        *)
(******************************************************************************)

From Stdlib Require Import ZArith List Lia Bool.
Require Import BlinkOperationalSemantics.
Require Import BlinkMarginStrut.
Require Import BlinkPhysicalFragment.
Import ListNotations.
Open Scope Z_scope.

(******************************************************************************)
(* 1. CSS FLEXBOX DATA STRUCTURES                                             *)
(******************************************************************************)

Inductive FlexDirection : Type :=
  | FlexRow
  | FlexColumn.

Inductive FlexAlign : Type :=
  | AlignFlexStart
  | AlignCenter
  | AlignStretch.

Record FlexItemStyle := mkFlexItemStyle {
  fis_grow : Z;               (* flex-grow factor (non-negative integer) *)
  fis_shrink : Z;             (* flex-shrink factor (non-negative integer) *)
  fis_basis : Z;              (* flex-basis: definite > 0 or kIndefiniteSize (-64) *)
  fis_min_main : Z;           (* min-width / min-height *)
  fis_max_main : Z;           (* max-width / max-height: definite or kIndefiniteSize *)
  fis_cross_size : Z;         (* cross dimension: width/height *)
  fis_align : FlexAlign
}.

Record FlexContainerStyle := mkFlexContainerStyle {
  fcs_direction : FlexDirection;
  fcs_main_size : Z;          (* definite container main size *)
  fcs_cross_size : Z;         (* definite container cross size *)
  fcs_align_items : FlexAlign
}.

(******************************************************************************)
(* 2. FLEXIBLE LENGTH RESOLUTION ALGORITHM (BLINK / W3C SEC 9.7)             *)
(******************************************************************************)

(** Calculate sum of flex bases *)
Fixpoint sum_flex_bases (items : list FlexItemStyle) : Z :=
  match items with
  | [] => 0
  | it :: rest => (if fis_basis it =? kIndefiniteSize then 0 else fis_basis it) + sum_flex_bases rest
  end.

(** Calculate sum of flex grow factors *)
Fixpoint sum_flex_grow (items : list FlexItemStyle) : Z :=
  match items with
  | [] => 0
  | it :: rest => fis_grow it + sum_flex_grow rest
  end.

(** Single item main-size resolution under Flex Grow regime *)
Definition resolve_item_main_size (it : FlexItemStyle) (free_space : Z) (total_grow : Z) : Z :=
  let base := if fis_basis it =? kIndefiniteSize then 0 else fis_basis it in
  let share := if (free_space >? 0) && (total_grow >? 0) then
                 sat_clamp (Z.quot (free_space * fis_grow it) total_grow)
               else 0 in
  let unclamped := sat_clamp (base + share) in
  (* Apply Min/Max Clamping per CSS Flexbox Sec 9.7 *)
  let clamped_max := if fis_max_main it =? kIndefiniteSize then unclamped
                     else Z.min unclamped (fis_max_main it) in
  Z.max (fis_min_main it) clamped_max.

(** Cross-size resolution under alignment *)
Definition resolve_item_cross_size (it : FlexItemStyle) (container_cross : Z) : Z :=
  match fis_align it with
  | AlignStretch => container_cross
  | _ => fis_cross_size it
  end.

(******************************************************************************)
(* 3. BIG-STEP FLEX CONTAINER OPERATIONAL JUDGMENT                            *)
(******************************************************************************)

Inductive flex_layout_big_step :
  FlexContainerStyle -> list FlexItemStyle -> list PhysicalFragment -> Prop :=
  | FLS_Layout : forall c_style items resolved_frags,
      let total_base := sum_flex_bases items in
      let free_space := fcs_main_size c_style - total_base in
      let total_grow := sum_flex_grow items in
      layout_flex_items_seq c_style free_space total_grow 0 items resolved_frags ->
      flex_layout_big_step c_style items resolved_frags

with layout_flex_items_seq :
  FlexContainerStyle -> Z -> Z -> Z -> list FlexItemStyle -> list PhysicalFragment -> Prop :=
  | FLIS_Nil : forall c_style free_space total_grow cur_main,
      layout_flex_items_seq c_style free_space total_grow cur_main [] []
  | FLIS_Cons : forall c_style free_space total_grow cur_main it rest frag rest_frags,
      let main_sz := resolve_item_main_size it free_space total_grow in
      let cross_sz := resolve_item_cross_size it (fcs_cross_size c_style) in
      let cross_off := match fis_align it with
                       | AlignCenter => sat_clamp (Z.quot (fcs_cross_size c_style - cross_sz) 2)
                       | _ => 0
                       end in
      let f_x := match fcs_direction c_style with
                 | FlexRow => cur_main
                 | FlexColumn => cross_off
                 end in
      let f_y := match fcs_direction c_style with
                 | FlexRow => cross_off
                 | FlexColumn => cur_main
                 end in
      let f_w := match fcs_direction c_style with
                 | FlexRow => main_sz
                 | FlexColumn => cross_sz
                 end in
      let f_h := match fcs_direction c_style with
                 | FlexRow => cross_sz
                 | FlexColumn => main_sz
                 end in
      frag = mkPhysicalFragment f_x f_y f_w f_h [] ->
      layout_flex_items_seq c_style free_space total_grow (cur_main + main_sz) rest rest_frags ->
      layout_flex_items_seq c_style free_space total_grow cur_main (it :: rest) (frag :: rest_frags).

(******************************************************************************)
(* 4. METATHEORETIC SOUNDNESS & DETERMINISM THEOREMS                          *)
(******************************************************************************)

(** Theorem 1: Flex Item Layout Non-Negative Dimensions Invariant *)
Theorem resolve_item_main_size_nonneg : forall it free_space total_grow,
  0 <= fis_min_main it ->
  0 <= resolve_item_main_size it free_space total_grow.
Proof.
  intros it free_space total_grow Hmin.
  unfold resolve_item_main_size.
  assert (Hle: fis_min_main it <= Z.max (fis_min_main it)
                  (if fis_max_main it =? -64
                   then sat_clamp ((if fis_basis it =? -64 then 0 else fis_basis it) +
                                   (if (free_space >? 0) && (total_grow >? 0)
                                    then sat_clamp (free_space * fis_grow it ÷ total_grow)
                                    else 0))
                   else Z.min (sat_clamp ((if fis_basis it =? -64 then 0 else fis_basis it) +
                                          (if (free_space >? 0) && (total_grow >? 0)
                                           then sat_clamp (free_space * fis_grow it ÷ total_grow)
                                           else 0))) (fis_max_main it))).
  { apply Z.le_max_l. }
  lia.
Qed.

Lemma layout_flex_items_seq_deterministic :
  forall c_style free_space total_grow cur_main items frags1,
    layout_flex_items_seq c_style free_space total_grow cur_main items frags1 ->
    forall frags2,
      layout_flex_items_seq c_style free_space total_grow cur_main items frags2 ->
      frags1 = frags2.
Proof.
  intros c_style free_space total_grow cur_main items frags1 H1.
  induction H1; intros frags2 H2.
  - inversion H2; subst; reflexivity.
  - inversion H2; subst.
    assert (Htail: rest_frags = rest_frags0).
    { apply IHlayout_flex_items_seq. exact H10. }
    subst. reflexivity.
Qed.

(** Theorem 2: Determinism of Flexbox Layout Operational Semantics *)
Theorem flex_layout_deterministic :
  forall c_style items frags1 frags2,
    flex_layout_big_step c_style items frags1 ->
    flex_layout_big_step c_style items frags2 ->
    frags1 = frags2.
Proof.
  intros c_style items frags1 frags2 H1 H2.
  inversion H1; subst.
  inversion H2; subst.
  eapply layout_flex_items_seq_deterministic; eassumption.
Qed.

(** Theorem 3: Single Item 100% Space Conservation under Flex-Grow *)
Theorem flex_single_item_space_conservation :
  forall c_style it,
  fcs_direction c_style = FlexRow ->
  0 <= fcs_main_size c_style <= kInt32Max ->
  fis_grow it = 1 ->
  fis_basis it = 0 ->
  fis_min_main it = 0 ->
  fis_max_main it = kIndefiniteSize ->
  resolve_item_main_size it (fcs_main_size c_style - 0) 1 = fcs_main_size c_style.
Proof.
  intros c_style it Hdir Hmain Hgrow Hbasis Hmin Hmax.
  unfold resolve_item_main_size.
  rewrite Hgrow, Hbasis, Hmin, Hmax. simpl.
  replace (fcs_main_size c_style - 0) with (fcs_main_size c_style) by lia.
  destruct (Z.gtb_spec (fcs_main_size c_style) 0).
  - simpl.
    replace (fcs_main_size c_style * 1) with (fcs_main_size c_style) by lia.
    rewrite Z.quot_1_r.
    assert (Hclamp: sat_clamp (fcs_main_size c_style) = fcs_main_size c_style).
    { apply sat_clamp_id. unfold kInt32Min. lia. }
    rewrite Hclamp.
    replace (0 + fcs_main_size c_style) with (fcs_main_size c_style) by lia.
    rewrite Hclamp.
    lia.
  - assert (Hzero: fcs_main_size c_style = 0) by lia.
    assert (Hclamp0: sat_clamp 0 = 0).
    { apply sat_clamp_id. unfold kInt32Min, kInt32Max. lia. }
    rewrite Hzero in *.
    simpl.
    rewrite Hclamp0.
    simpl.
    reflexivity.
Qed.
