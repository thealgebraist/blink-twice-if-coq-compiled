(* ========================================================================= *)
(*               BlinkFlexBaselineSynthesisSemantics.v                       *)
(* ========================================================================= *)
(* Formal semantics of Chromium Blink Flexbox Baseline Alignment &          *)
(* Synthesis per W3C CSS Flexible Box 1 §8.5 & CSS Box Alignment 3 §9.       *)
(* Strictly verified with 0 admits.                                          *)
(* ========================================================================= *)

From Stdlib Require Import ZArith Lists.List Bool.Bool Lia.
Open Scope Z_scope.

Record FlexItemBaselineData := {
  item_margin_before : Z;
  item_border_box_cross : Z;
  item_margin_after : Z;
  item_font_baseline : option Z
}.

Definition item_margin_box_cross (it : FlexItemBaselineData) : Z :=
  item_margin_before it + item_border_box_cross it + item_margin_after it.

Definition synthesize_baseline (it : FlexItemBaselineData) : Z :=
  match item_font_baseline it with
  | Some b => b
  | None => item_border_box_cross it
  end.

Definition item_ascent (it : FlexItemBaselineData) : Z :=
  item_margin_before it + synthesize_baseline it.

Definition item_descent (it : FlexItemBaselineData) : Z :=
  item_margin_box_cross it - item_ascent it.

Fixpoint line_max_ascent (items : list FlexItemBaselineData) : Z :=
  match items with
  | nil => 0
  | it :: rest => Z.max (item_ascent it) (line_max_ascent rest)
  end.

Fixpoint line_max_descent (items : list FlexItemBaselineData) : Z :=
  match items with
  | nil => 0
  | it :: rest => Z.max (item_descent it) (line_max_descent rest)
  end.

Definition baseline_aligned_line_cross_size (items : list FlexItemBaselineData) : Z :=
  line_max_ascent items + line_max_descent items.

Definition item_baseline_offset (items : list FlexItemBaselineData) (it : FlexItemBaselineData) : Z :=
  line_max_ascent items - item_ascent it.

Theorem ascent_plus_descent_conservation : forall it,
  item_ascent it + item_descent it = item_margin_box_cross it.
Proof.
  intros it.
  unfold item_descent.
  lia.
Qed.

Theorem fallback_baseline_bounded : forall it,
  item_font_baseline it = None ->
  item_border_box_cross it >= 0 ->
  0 <= synthesize_baseline it /\ synthesize_baseline it <= item_border_box_cross it.
Proof.
  intros it Hnone Hbb.
  unfold synthesize_baseline.
  rewrite Hnone.
  lia.
Qed.

Lemma in_items_ascent_le_max : forall it items,
  In it items ->
  item_ascent it <= line_max_ascent items.
Proof.
  intros it items.
  induction items as [|hd rest IH]; cbn.
  - intros [].
  - intros [Heq | Hin].
    + subst. apply Z.le_max_l.
    + apply IH in Hin.
      pose proof (Z.le_max_r (item_ascent hd) (line_max_ascent rest)).
      lia.
Qed.

Lemma in_items_descent_le_max : forall it items,
  In it items ->
  item_descent it <= line_max_descent items.
Proof.
  intros it items.
  induction items as [|hd rest IH]; cbn.
  - intros [].
  - intros [Heq | Hin].
    + subst. apply Z.le_max_l.
    + apply IH in Hin.
      pose proof (Z.le_max_r (item_descent hd) (line_max_descent rest)).
      lia.
Qed.

Theorem item_baseline_offset_nonneg : forall it items,
  In it items ->
  item_baseline_offset items it >= 0.
Proof.
  intros it items Hin.
  unfold item_baseline_offset.
  apply in_items_ascent_le_max in Hin.
  lia.
Qed.

Theorem item_fits_in_baseline_line_cross_size : forall it items,
  In it items ->
  item_baseline_offset items it + item_margin_box_cross it <= baseline_aligned_line_cross_size items.
Proof.
  intros it items Hin.
  unfold item_baseline_offset, baseline_aligned_line_cross_size.
  pose proof (in_items_descent_le_max it items Hin) as Hdescent.
  rewrite <- (ascent_plus_descent_conservation it).
  lia.
Qed.

Theorem line_cross_size_ge_item_margin_box : forall it items,
  In it items ->
  item_margin_box_cross it <= baseline_aligned_line_cross_size items.
Proof.
  intros it items Hin.
  pose proof (item_fits_in_baseline_line_cross_size it items Hin) as Hfit.
  pose proof (item_baseline_offset_nonneg it items Hin) as Hoffset.
  lia.
Qed.

