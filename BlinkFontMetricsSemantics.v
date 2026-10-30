(** * BlinkFontMetricsSemantics.v
    Formal verification of Chromium Blink Font Metrics against W3C CSS Fonts 4 & Inline 3.
*)

From Stdlib Require Import ZArith.ZArith.
From Stdlib Require Import Bool.Bool.
From Stdlib Require Import micromega.Lia.

Open Scope Z_scope.

(** ** 1. Core Data Structures *)

Definition LayoutUnit := Z.

Inductive FontBaseline : Type :=
  | AlphabeticBaseline
  | IdeographicBaseline
  | CentralBaseline
  | HangingBaseline.

Record RawFontTables : Type := mkRawFontTables {
  raw_ascent       : LayoutUnit;
  raw_descent      : LayoutUnit;
  raw_line_gap     : LayoutUnit;
  raw_x_height     : option LayoutUnit;
  glyph_x_bounds   : option LayoutUnit;
  raw_cap_height   : option LayoutUnit;
  glyph_O_bounds   : option LayoutUnit;
  font_size        : LayoutUnit
}.

Record FontMetrics : Type := mkFontMetrics {
  fm_ascent       : LayoutUnit;
  fm_descent      : LayoutUnit;
  fm_line_gap     : LayoutUnit;
  fm_line_spacing : LayoutUnit;
  fm_x_height     : LayoutUnit;
  fm_cap_height   : LayoutUnit
}.

Record FontHeight : Type := mkFontHeight {
  fh_ascent  : LayoutUnit;
  fh_descent : LayoutUnit
}.

Definition fh_line_height (fh : FontHeight) : LayoutUnit :=
  fh_ascent fh + fh_descent fh.

(** ** 2. Synthesized Metrics Semantics *)

Definition clamp_non_neg (v : LayoutUnit) : LayoutUnit :=
  Z.max 0 v.

Definition synthesize_x_height (raw : RawFontTables) (norm_ascent : LayoutUnit) : LayoutUnit :=
  match raw_x_height raw with
  | Some xh => if xh >? 0 then xh else
               match glyph_x_bounds raw with
               | Some gx => if gx >? 0 then gx else (norm_ascent / 2)
               | None => (norm_ascent / 2)
               end
  | None => match glyph_x_bounds raw with
            | Some gx => if gx >? 0 then gx else (norm_ascent / 2)
            | None => if norm_ascent >? 0 
                      then norm_ascent / 2 
                      else (clamp_non_neg (font_size raw)) / 2
            end
  end.

Definition synthesize_cap_height (raw : RawFontTables) (norm_ascent : LayoutUnit) : LayoutUnit :=
  match raw_cap_height raw with
  | Some ch => if ch >? 0 then ch else norm_ascent
  | None => match glyph_O_bounds raw with
            | Some go => if go >? 0 then go else norm_ascent
            | None => norm_ascent
            end
  end.

Definition platform_init_metrics (raw : RawFontTables) : FontMetrics :=
  let a  := clamp_non_neg (raw_ascent raw) in
  let d  := clamp_non_neg (raw_descent raw) in
  let lg := clamp_non_neg (raw_line_gap raw) in
  let ls := a + d + lg in
  let xh := synthesize_x_height raw a in
  let ch := synthesize_cap_height raw a in
  mkFontMetrics a d lg ls xh ch.

Definition get_font_height (fm : FontMetrics) (b : FontBaseline) : FontHeight :=
  let a := fm_ascent fm in
  let d := fm_descent fm in
  match b with
  | AlphabeticBaseline => mkFontHeight a d
  | IdeographicBaseline => mkFontHeight a d
  | CentralBaseline =>
      let total := a + d in
      let central_a := total / 2 in
      let central_d := total - central_a in
      mkFontHeight central_a central_d
  | HangingBaseline =>
      let hanging_a := (a * 4) / 5 in
      let hanging_d := (a + d) - hanging_a in
      mkFontHeight hanging_a hanging_d
  end.

Definition fh_unite (fh1 fh2 : FontHeight) : FontHeight :=
  mkFontHeight (Z.max (fh_ascent fh1) (fh_ascent fh2))
               (Z.max (fh_descent fh1) (fh_descent fh2)).

Definition add_leading (fh : FontHeight) (line_height : LayoutUnit) : FontHeight :=
  let half_leading := (line_height - (fh_ascent fh + fh_descent fh)) / 2 in
  let new_ascent := fh_ascent fh + half_leading in
  let new_descent := line_height - new_ascent in
  mkFontHeight new_ascent new_descent.

(** ** 3. Mathematical Invariants & Verification *)

(** Invariant 1: Line Height Conservation Under Leading Distribution *)
Theorem add_leading_conserves_line_height : forall fh lh,
  fh_line_height (add_leading fh lh) = lh.
Proof.
  intros fh lh.
  unfold fh_line_height, add_leading.
  simpl. lia.
Qed.

(** Invariant 2: Non-negativity of normalized FontMetrics *)
Theorem platform_init_metrics_nonneg : forall raw,
  let fm := platform_init_metrics raw in
  0 <= fm_ascent fm /\
  0 <= fm_descent fm /\
  0 <= fm_line_gap fm /\
  0 <= fm_line_spacing fm.
Proof.
  intros raw fm.
  unfold fm, platform_init_metrics, clamp_non_neg.
  simpl.
  split; [apply Z.le_max_l |].
  split; [apply Z.le_max_l |].
  split; [apply Z.le_max_l |].
  pose proof (Z.le_max_l 0 (raw_ascent raw)).
  pose proof (Z.le_max_l 0 (raw_descent raw)).
  pose proof (Z.le_max_l 0 (raw_line_gap raw)).
  lia.
Qed.

(** Invariant 3: FontHeight Unite Monotonicity *)
Theorem fh_unite_bounds : forall fh1 fh2,
  fh_ascent fh1 <= fh_ascent (fh_unite fh1 fh2) /\
  fh_descent fh1 <= fh_descent (fh_unite fh1 fh2).
Proof.
  intros fh1 fh2.
  unfold fh_unite. simpl.
  split; apply Z.le_max_l.
Qed.

(** Invariant 4: FontHeight Unite Commutativity *)
Theorem fh_unite_comm : forall fh1 fh2,
  fh_unite fh1 fh2 = fh_unite fh2 fh1.
Proof.
  intros [a1 d1] [a2 d2].
  unfold fh_unite. simpl.
  rewrite (Z.max_comm a1 a2).
  rewrite (Z.max_comm d1 d2).
  reflexivity.
Qed.

(** Invariant 5: Central Baseline Preserves Extent (a + d) *)
Theorem central_baseline_preserves_extent : forall fm,
  fh_line_height (get_font_height fm CentralBaseline) = fm_ascent fm + fm_descent fm.
Proof.
  intros fm.
  unfold fh_line_height, get_font_height.
  simpl. lia.
Qed.

