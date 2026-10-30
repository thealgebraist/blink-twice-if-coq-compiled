### 1. Form Control Intrinsic Minimum Dimensions

In Chromium Blink (`third_party/blink/renderer/core/layout/`), HTML §4.10 form controls map to specialized layout objects (e.g., `LayoutTextControlSingleLine`, `LayoutButton`, `LayoutFlexibleBox`) governed by Modern LayoutNG (`NGBlockLayoutAlgorithm`, `NGFlexLayoutAlgorithm`) alongside User-Agent (UA) stylesheet rules (`html.css`) and `LayoutTheme` metrics.

#### Text Input (`<input type="text">`)
* **HTML §4.10.5.3.5 (`size` attribute):** Specifies a default character width of 20.
* **Blink Calculation:** In `LayoutTextControlSingleLine::IntrinsicLogicalWidths` (and its LayoutNG equivalent `NGBlockNode::ComputeMinMaxSizes`), the intrinsic inline size is derived from the primary font's metrics:
  $$\text{InlineIntrinsicSize} = \text{size} \times \text{AvgCharWidth} + \text{ScrollbarThickness} + \text{InnerEditorPadding}$$
  If the font lacks a valid average character width, Blink falls back to the `'0'` glyph advance (`ZeroWidth`, corresponding to CSS `ch`) or `MaxCharWidth`. When `size` is omitted, $\text{size} = 20$, yielding an intrinsic content width of $\approx 20\text{ch}$.
* **Intrinsic Minimum Width:** Under CSS Sizing, `min-width: auto` for `<input>` resolves to `0` for flex/grid items unless specified, while the preferred intrinsic width (`MinMaxSizes::max_size` and `min_size` for non-shrinkable contexts) clamps to this $20\text{ch}$ metric plus borders and padding.

#### Button (`<button>`, `<input type="button|submit|reset">`)
* **UA Stylesheet & Theme:** `html.css` assigns `box-sizing: border-box`, default padding (`padding-block: 1px; padding-inline: 6px`), and a native appearance (`-webkit-appearance: auto`).
* **Minimum Block Size:** `LayoutTheme::AdjustStyle` and platform themes (`WebThemeEngine`) enforce minimum platform dimensions when `appearance` is active. Even with empty content (`<button></button>`), the block size is bounded below by the font's `Ascent + Descent` (line-height of an anonymous empty inline box generated inside the button's anonymous flex/block wrapper) plus vertical borders and padding:
  $$\text{BlockSize}_{\min} = \max\left(\text{ThemeMinHeight}, \text{LineHeight}_{\text{strut}} + \text{Padding}_{\text{block}} + \text{Border}_{\text{block}}\right)$$

---

### 2. Native Border/Padding Absorption & Baseline Alignment

#### Border and Padding Absorption
1. **`box-sizing`:** Buttons and select elements default to `box-sizing: border-box` in `html.css`, whereas `<input type="text">` defaults to `content-box` (though `appearance: auto` delegates border painting to `ThemePainter`).
2. **Shadow DOM Delegation:** `<input>` constructs an internal UA Shadow DOM containing an inner `<div id="-webkit-input-placeholder">` and `<div id="inner-editor">`. The outer `LayoutObject` absorbs the CSS `border` and `padding`. The `inner-editor` receives an inline-level anonymous block layout with `padding: 0; border: 0`, ensuring that scrolling and text clipping occur strictly inside the outer control's `ContentBoxRect()`.

#### Baseline Alignment in Line Boxes
Form controls are typically `display: inline-block`. In `NGInlineLayoutAlgorithm`, an `inline-block` participates in its parent line box's baseline alignment via `NGLogicalFragment::FirstBaseline()` or `LastBaseline()`.
* **Text Inputs:** The baseline is synthesized from the inner editor's first line box. If the input is empty, `NGBlockLayoutAlgorithm` synthesizes a baseline using the primary font's ascent above the content box top, offset by the top border and padding:
  $$\text{Baseline}_{\text{input}} = \text{Border}_{\text{top}} + \text{Padding}_{\text{top}} + \text{FontAscent}$$
* **Buttons:** `<button>` is laid out by `NGFlexLayoutAlgorithm` (or `NGBlockLayoutAlgorithm` with centering). If the button contains text, its baseline is propagated from the first in-flow line box of its content. Because buttons vertically center their content when an explicit `height` or `min-height` exceeds the text height, the internal content offset shifts by $\Delta y = \max(0, \frac{\text{ContentBoxHeight} - \text{TextLineHeight}}{2})$. Thus:
  $$\text{Baseline}_{\text{button}} = \text{Border}_{\text{top}} + \text{Padding}_{\text{top}} + \Delta y + \text{FontAscent}$$
  When the button is placed in an outer line box (`vertical-align: baseline`), the outer line box aligns its text baseline directly with $\text{Baseline}_{\text{button}}$, guaranteeing visual co-linearity between surrounding inline text and the button's label.

---

### 3. Architectural Invariants

1. **Non-Negativity of Control Dimensions (Invariant 1):** For any combination of CSS author styles (including negative margins or zero font sizes), the computed border-box inline and block dimensions of a form control layout fragment are strictly non-negative ($\ge 0$). Content-box dimensions clamp at $0$ before adding clamped non-negative borders and paddings.
2. **Button Baseline Co-linearity (Invariant 2):** Given a `<button>` with `vertical-align: baseline` containing a single line of text with the same font metrics as the parent inline formatting context, the distance from the parent line box's top to the parent text baseline equals the distance from the parent line box's top to the button's internal text baseline:
   $$\text{LineBox}_{\text{baseline}} = \text{ButtonOffset}_{y} + \text{Baseline}_{\text{button}}$$

---

### 4. Formal Verification in Rocq (Coq)

Below is the self-contained formalization `BlinkHTMLFormControlLayoutSemantics.v`.

```coq
(** * BlinkHTMLFormControlLayoutSemantics.v
    Formal audit of Chromium Blink Form Controls Layout vs HTML §4.10.
    Agent 142 Verification Artifact. *)

From Coq Require Import ZArith.
From Coq Require Import Lia.
Open Scope Z_scope.

(** ** 1. Basic Metrics and Style Primitives *)

Record FontMetrics := mkFontMetrics {
  font_ascent : Z;
  font_descent : Z;
  ch_width : Z; (* Advance width of '0' (U+0030) *)
  font_ascent_nonneg : 0 <= font_ascent;
  font_descent_nonneg : 0 <= font_descent;
  ch_width_nonneg : 0 <= ch_width
}.

Inductive BoxSizing :=
  | ContentBox
  | BorderBox.

Record BoxEdges := mkBoxEdges {
  edge_top : Z;
  edge_bottom : Z;
  edge_left : Z;
  edge_right : Z;
  edge_top_nonneg : 0 <= edge_top;
  edge_bottom_nonneg : 0 <= edge_bottom;
  edge_left_nonneg : 0 <= edge_left;
  edge_right_nonneg : 0 <= edge_right
}.

Definition inline_sum (e : BoxEdges) : Z := edge_left e + edge_right e.
Definition block_sum (e : BoxEdges) : Z := edge_top e + edge_bottom e.

Lemma inline_sum_nonneg : forall e, 0 <= inline_sum e.
Proof.
  intros e. unfold inline_sum.
  pose proof (edge_left_nonneg e).
  pose proof (edge_right_nonneg e).
  lia.
Qed.

Lemma block_sum_nonneg : forall e, 0 <= block_sum e.
Proof.
  intros e. unfold block_sum.
  pose proof (edge_top_nonneg e).
  pose proof (edge_bottom_nonneg e).
  lia.
Qed.

(** ** 2. Form Control Specification & Layout Models *)

Inductive ControlKind :=
  | TextInput (size_attr : option Z) (* None defaults to 20 per HTML §4.10.5.3.5 *)
  | ButtonControl (theme_min_height : Z).

Record ControlStyle := mkControlStyle {
  kind : ControlKind;
  box_sizing : BoxSizing;
  font : FontMetrics;
  border : BoxEdges;
  padding : BoxEdges;
  specified_width : option Z;
  specified_height : option Z
}.

Record LayoutFragment := mkLayoutFragment {
  inline_size : Z;
  block_size : Z;
  first_baseline : Z
}.

(** Clamping helper matching Blink's LayoutUnit::ClampNegativeToZero *)
Definition clamp_nonneg (x : Z) : Z := Z.max 0 x.

Lemma clamp_nonneg_spec : forall x, 0 <= clamp_nonneg x.
Proof. intros x. unfold clamp_nonneg. lia. Qed.

(** Default character width resolution per HTML §4.10 *)
Definition resolve_char_count (sz : option Z) : Z :=
  match sz with
  | Some n => if n <=? 0 then 20 else n
  | None => 20
  end.

Lemma resolve_char_count_pos : forall sz, 0 < resolve_char_count sz.
Proof.
  intros [n|]; unfold resolve_char_count.
  - destruct (n <=? 0) eqn:E; lia.
  - lia.
Qed.

(** Intrinsic content inline size *)
Definition intrinsic_content_inline_size (s : ControlStyle) : Z :=
  match kind s with
  | TextInput sz => (resolve_char_count sz) * (ch_width (font s))
  | ButtonControl _ => 0 (* Button shrinks-to-fit empty label at minimum *)
  end.

(** Intrinsic content block size (single line strut) *)
Definition line_height (f : FontMetrics) : Z :=
  font_ascent f + font_descent f.

Definition intrinsic_content_block_size (s : ControlStyle) : Z :=
  line_height (font s).

(** Border and padding absorption resolver *)
Definition resolve_border_box_size
  (sizing : BoxSizing) (spec : option Z) (intrinsic_content : Z) (bp_sum : Z) : Z :=
  match spec with
  | None => clamp_nonneg intrinsic_content + bp_sum
  | Some val =>
      match sizing with
      | ContentBox => clamp_nonneg val + bp_sum
      | BorderBox => Z.max bp_sum (clamp_nonneg val)
      end
  end.

(** Compute final LayoutFragment for a Form Control *)
Definition layout_form_control (s : ControlStyle) : LayoutFragment :=
  let bp_inline := inline_sum (border s) + inline_sum (padding s) in
  let bp_block  := block_sum (border s) + block_sum (padding s) in
  let raw_inline := resolve_border_box_size
                      (box_sizing s) (specified_width s)
                      (intrinsic_content_inline_size s) bp_inline in
  let raw_block  := resolve_border_box_size
                      (box_sizing s) (specified_height s)
                      (intrinsic_content_block_size s) bp_block in
  let final_block :=
      match kind s with
      | TextInput _ => raw_block
      | ButtonControl min_h => Z.max (clamp_nonneg min_h) raw_block
      end in
  let content_block := Z.max 0 (final_block - bp_block) in
  let lh := line_height (font s) in
  let centering_offset :=
      match kind s with
      | TextInput _ => 0
      | ButtonControl _ => Z.max 0 ((content_block - lh) / 2)
      end in
  let baseline := edge_top (border s) + edge_top (padding s)
                  + centering_offset + font_ascent (font s) in
  mkLayoutFragment raw_inline final_block baseline.

(** ** 3. Parent Line Box Baseline Alignment Model *)

Record LineBoxPlacement := mkLineBoxPlacement {
  line_box_baseline : Z; (* Distance from line box top to line box text baseline *)
  control_offset_y : Z;  (* Distance from line box top to control border-box top *)
  internal_text_baseline_in_line : Z (* Absolute y of control's text baseline *)
}.

(** Aligns an inline-block form control in a parent line box with parent ascent `p_ascent` *)
Definition place_control_in_line_box (p_ascent : Z) (frag : LayoutFragment) : LineBoxPlacement :=
  let lb_base := Z.max ( clamp_nonneg p_ascent ) (first_baseline frag) in
  let ctrl_y  := lb_base - (first_baseline frag) in
  mkLineBoxPlacement lb_base ctrl_y (ctrl_y + first_baseline frag).

(** ** 4. Theorems & Invariant Proofs *)

(** Theorem 1: Default Text Input Intrinsic Width is exactly 20ch + border + padding
    when `size` and `width` are omitted. *)
Theorem default_text_input_width_is_20ch :
  forall f b p h bx,
    let s := mkControlStyle (TextInput None) bx f b p None h in
    inline_size (layout_form_control s) =
      20 * (ch_width f) + inline_sum b + inline_sum p.
Proof.
  intros f b p h bx s.
  unfold layout_form_control, resolve_border_box_size, intrinsic_content_inline_size.
  simpl.
  unfold clamp_nonneg.
  pose proof (ch_width_nonneg f).
  assert (0 <= 20 * ch_width f) by lia.
  rewrite Z.max_r by lia.
  lia.
Qed.

(** Theorem 2 (Invariant 1): Form Control Dimensions and Baselines are Non-Negative
    for all possible author styles and control types. *)
Theorem form_control_dimensions_nonneg :
  forall (s : ControlStyle),
    let frag := layout_form_control s in
    0 <= inline_size frag /\
    0 <= block_size frag /\
    0 <= first_baseline frag.
Proof.
  intros s frag.
  unfold frag, layout_form_control.
  simpl.
  pose proof (inline_sum_nonneg (border s)).
  pose proof (inline_sum_nonneg (padding s)).
  pose proof (block_sum_nonneg (border s)).
  pose proof (block_sum_nonneg (padding s)).
  pose proof (edge_top_nonneg (border s)).
  pose proof (edge_top_nonneg (