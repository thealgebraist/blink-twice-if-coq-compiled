(**
  BlinkPaintLayerStackingSemantics.v
  Formal specification of Chromium Blink paint layer stacking order and tree walk
  derived from third_party/blink/renderer/core/paint/paint_layer.cc and paint_layer_stacking_node.cc
  according to CSS 2.1 Appendix E (Elaborate description of Stacking Contexts) and CSS Color 4.
*)

From Stdlib Require Import ZArith.BinInt.
From Stdlib Require Import Lists.List.
From Stdlib Require Import Bool.Bool.
From Stdlib Require Import Lia.
Import ListNotations.
Open Scope Z_scope.

(** 1. Stacking Context Painting Phases (CSS 2.1 Appendix E) *)
Inductive StackingPhase : Type :=
  | Phase1_StackingRootBackground
  | Phase2_NegativeZIndex
  | Phase3_InFlowBlockDescendants
  | Phase4_NonPositionedFloats
  | Phase5_NormalFlowInlines
  | Phase6_ZeroZIndexAndAuto
  | Phase7_PositiveZIndex.

Definition phase_rank (p : StackingPhase) : Z :=
  match p with
  | Phase1_StackingRootBackground => 1
  | Phase2_NegativeZIndex         => 2
  | Phase3_InFlowBlockDescendants => 3
  | Phase4_NonPositionedFloats    => 4
  | Phase5_NormalFlowInlines      => 5
  | Phase6_ZeroZIndexAndAuto      => 6
  | Phase7_PositiveZIndex         => 7
  end.

Lemma phase_rank_in_bounds : forall p : StackingPhase,
    1 <= phase_rank p <= 7.
Proof.
  destruct p; simpl; lia.
Qed.

Lemma phase_rank_inj : forall p1 p2 : StackingPhase,
    phase_rank p1 = phase_rank p2 -> p1 = p2.
Proof.
  destruct p1; destruct p2; simpl; intros H; try reflexivity; try discriminate.
Qed.

Definition phase_order_lt (p1 p2 : StackingPhase) : Prop :=
  phase_rank p1 < phase_rank p2.

Theorem phase_order_transitive : forall p1 p2 p3 : StackingPhase,
    phase_order_lt p1 p2 -> phase_order_lt p2 p3 -> phase_order_lt p1 p3.
Proof.
  unfold phase_order_lt.
  intros p1 p2 p3 H12 H23.
  lia.
Qed.

Theorem phase_order_irreflexive : forall p : StackingPhase,
    ~ phase_order_lt p p.
Proof.
  unfold phase_order_lt.
  intros p H.
  lia.
Qed.

Theorem phase_order_asymmetric : forall p1 p2 : StackingPhase,
    phase_order_lt p1 p2 -> ~ phase_order_lt p2 p1.
Proof.
  unfold phase_order_lt.
  intros p1 p2 H1 H2.
  lia.
Qed.

(** Appendix E Phase Separation Theorems *)
Theorem negative_z_precedes_normal_flow_blocks :
    phase_order_lt Phase2_NegativeZIndex Phase3_InFlowBlockDescendants.
Proof.
  unfold phase_order_lt; simpl; lia.
Qed.

Theorem normal_flow_inlines_precede_zero_z :
    phase_order_lt Phase5_NormalFlowInlines Phase6_ZeroZIndexAndAuto.
Proof.
  unfold phase_order_lt; simpl; lia.
Qed.

Theorem zero_z_precedes_positive_z :
    phase_order_lt Phase6_ZeroZIndexAndAuto Phase7_PositiveZIndex.
Proof.
  unfold phase_order_lt; simpl; lia.
Qed.

(** 2. Paint Layer Representation *)
Record PaintLayerItem := {
  layer_id : Z;
  z_index : Z;
  is_positioned : bool;
  is_stacking_context : bool;
  dom_tree_order : Z
}.

(** Classify descendant into stacking phase *)
Definition classify_layer_phase (root : bool) (item : PaintLayerItem) : StackingPhase :=
  if root then Phase1_StackingRootBackground
  else if item.(is_positioned) || item.(is_stacking_context) then
    if item.(z_index) <? 0 then Phase2_NegativeZIndex
    else if item.(z_index) =? 0 then Phase6_ZeroZIndexAndAuto
    else Phase7_PositiveZIndex
  else Phase3_InFlowBlockDescendants.

(** Blink Stacking Order Comparator (paint_layer_stacking_node.cc CompareZOrder) *)
Definition layer_paint_order_lt (a b : PaintLayerItem) : Prop :=
  let pa := classify_layer_phase false a in
  let pb := classify_layer_phase false b in
  if Z.ltb (phase_rank pa) (phase_rank pb) then True
  else if Z.ltb (phase_rank pb) (phase_rank pa) then False
  else
    (* Same phase: compare z_index first, then tree order *)
    if Z.ltb a.(z_index) b.(z_index) then True
    else if Z.ltb b.(z_index) a.(z_index) then False
    else a.(dom_tree_order) < b.(dom_tree_order).

Theorem equal_z_index_preserves_tree_order :
  forall a b : PaintLayerItem,
    classify_layer_phase false a = classify_layer_phase false b ->
    a.(z_index) = b.(z_index) ->
    a.(dom_tree_order) < b.(dom_tree_order) ->
    layer_paint_order_lt a b.
Proof.
  intros a b Hphase Hz Htree.
  unfold layer_paint_order_lt.
  rewrite Hphase.
  rewrite Z.ltb_irrefl.
  rewrite Hz.
  rewrite Z.ltb_irrefl.
  exact Htree.
Qed.

Theorem distinct_phase_subsumes_z_index :
  forall a b : PaintLayerItem,
    phase_order_lt (classify_layer_phase false a) (classify_layer_phase false b) ->
    layer_paint_order_lt a b.
Proof.
  intros a b Horder.
  unfold layer_paint_order_lt.
  unfold phase_order_lt in Horder.
  destruct (Z.ltb_spec (phase_rank (classify_layer_phase false a)) (phase_rank (classify_layer_phase false b))) as [Hlt | Hge].
  - reflexivity.
  - lia.
Qed.

Theorem negative_z_layer_paints_before_positive :
  forall a b : PaintLayerItem,
    a.(is_positioned) = true ->
    b.(is_positioned) = true ->
    a.(z_index) < 0 ->
    b.(z_index) > 0 ->
    layer_paint_order_lt a b.
Proof.
  intros a b Hposa Hposb Hnega Hposzb.
  apply distinct_phase_subsumes_z_index.
  unfold classify_layer_phase.
  rewrite Hposa.
  rewrite Hposb.
  simpl.
  destruct (a.(z_index) <? 0) eqn:Ea; [|lia].
  destruct (b.(z_index) <? 0) eqn:Eb; [lia|].
  destruct (b.(z_index) =? 0) eqn:E0b; [lia|].
  unfold phase_order_lt.
  simpl.
  lia.
Qed.
