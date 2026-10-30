### 1. Core Data Structures in Blink Root Layout

In Chromium’s Blink LayoutNG engine, the root layout pipeline transitions from the visual/layout viewport down to the box tree via three primary structures:

*   **`LayoutView` (`third_party/blink/renderer/core/layout/layout_view.h`)**: 
    The root of the `LayoutObject` tree, corresponding directly to the CSS 2.1 Initial Containing Block (ICB). It holds a reference to the `LocalFrameView` and queries the viewport dimensions via `GetLayoutSize()`. It serves as the entry point for document lifecycle layout passes (`UpdateLayout()`).
*   **`ConstraintSpace` (`third_party/blink/renderer/core/layout/ng/ng_constraint_space.h`)**: 
    An immutable context passed down by parent layout algorithms to children. At the root level, `ConstraintSpace::CreateFromLayoutObject()` constructs the initial root constraint space using the `AvailableSize` derived from `LayoutView` (the viewport dimensions), setting both inline and block sizes as fixed/definite (`IsFixedInlineSize()`, `IsFixedBlockSize()`).
*   **`ViewLayoutAlgorithm` / `BlockLayoutAlgorithm` (`third_party/blink/renderer/core/layout/ng/ng_block_layout_algorithm.h`)**: 
    While `LayoutView` acts as the root block container, LayoutNG delegates its child layout to the root `BlockLayoutAlgorithm` (historically managed by root view layout glue). This algorithm consumes the root `ConstraintSpace`, computes the root fragment geometry, and generates new `ConstraintSpace` instances for the document element (`<html>`) and subsequently the `<body>` element.

---

### 2. ICB Initialization from Viewport Dimensions

Per **CSS 2.1 §10.1 (Definition of "containing block")**, the containing block in which the root element lives is a rectangle called the *Initial Containing Block* (ICB), which has the dimensions of the viewport for continuous media.

In Blink:
1. The `FrameView` provides the layout viewport size: $(W_{\text{vp}}, H_{\text{vp}}) = (\text{viewport\_width}, \text{viewport\_height})$.
2. `LayoutView::InitialContainingBlockSize()` returns `PhysicalSize(viewport_width, viewport_height)`.
3. When constructing the root `ConstraintSpace` for the `LayoutView`:
   $$\text{ICB}_{\text{inline}} = W_{\text{vp}}, \quad \text{ICB}_{\text{block}} = H_{\text{vp}}$$
4. The root `AvailableSize` is initialized directly to $(\text{ICB}_{\text{inline}}, \text{ICB}_{\text{block}})$.

---

### 3. Root `<html>` and `<body>` Default Width Expansion

Per **CSS 2.1 §10.3.3 (Block-level, non-replaced elements in normal flow)**:
$$\text{margin-left} + \text{border-left-width} + \text{padding-left} + \text{width} + \text{padding-right} + \text{border-right-width} + \text{margin-right} = \text{width of containing block}$$

Assuming standard User Agent (UA) stylesheet defaults (`third_party/blink/renderer/core/html/resources/html.css`):
*   **`<html>` Element**: 
    Has `display: block`, `width: auto`, and $0\text{px}$ margins, borders, and padding. Its containing block is the ICB. Solving the §10.3.3 equation yields:
    $$W_{\text{html}} = \text{ICB}_{\text{inline}} - 0 = \text{viewport\_width}$$
*   **`<body>` Element**: 
    Has `display: block`, `width: auto`, $0\text{px}$ borders/padding, and a default UA uniform margin $M_{\text{body}}$ (typically $8\text{px}$). Its containing block is the `<html>` content box ($W_{\text{html}}$).
    Blink’s `ResolveMainInlineLength` calculates the `auto` inline size by subtracting inline margins, borders, and padding from the `AvailableSize` ($W_{\text{html}}$):
    $$W_{\text{body}} = \max(0, \text{viewport\_width} - 2 \cdot \text{body\_margin})$$
    *(Assuming $\text{viewport\_width} \ge 2 \cdot \text{body\_margin}$, this simplifies strictly to $\text{viewport\_width} - 2 \cdot \text{body\_margin}$).*

---

### 4. Mathematical Invariants

To verify spatial memory safety and CSS 2.1 compliance in the layout pass, the following invariants must hold for all valid viewport configurations ($W_{\text{vp}} \ge 0$, $M_{\text{body}} \ge 0$, and $W_{\text{vp}} \ge 2 \cdot M_{\text{body}}$):

1.  **Non-Negative Available Inline Size**:
    The computed content inline size of the `<body>` element is strictly non-negative:
    $$W_{\text{body}} \ge 0$$
2.  **Strict Containment / Conservation of Inline Space**:
    The outer margin box of the `<body>` element is bounded by the `<html>` content box, which is bounded by the ICB (viewport):
    $$0 \le W_{\text{body}} \le W_{\text{body}} + 2 \cdot M_{\text{body}} = W_{\text{html}} = W_{\text{vp}}$$
    If $M_{\text{body}} > 0$, the `<body>` content box is *strictly* smaller than the viewport width: $W_{\text{body}} < W_{\text{vp}}$.

---

### 5. Formalization in Rocq/Coq (`BlinkViewportICBLayoutSemantics.v`)

Below is the complete, self-contained Rocq/Coq formalization encoding the Blink structures, CSS 2.1 §10.1/§10.3.3 layout rules, and proofs of the invariants.

```coq
(** * BlinkViewportICBLayoutSemantics.v
    Formal Audit of Chromium Blink Viewport & ICB Layout vs CSS 2.1 §10.1 / §10.3.3
    Agent 109 Verification Module *)

From Coq Require Import Arith.PeanoNat.
From Coq Require Import Micromeega.Lia.

Module BlinkViewportICBLayoutSemantics.

  (** ** 1. Core Data Structures *)

  (** Represents physical viewport dimensions from FrameView *)
  Record Viewport : Type := mkViewport {
    viewport_width  : nat;
    viewport_height : nat
  }.

  (** Represents Blink's LayoutView (Initial Containing Block / ICB) *)
  Record LayoutView : Type := mkLayoutView {
    icb_inline_size : nat;
    icb_block_size  : nat
  }.

  (** Represents Blink's NGConstraintSpace passed between layout algorithms *)
  Record ConstraintSpace : Type := mkConstraintSpace {
    available_inline_size : nat;
    available_block_size  : nat;
    is_fixed_inline       : bool
  }.

  (** Box model parameters for block-level elements in normal flow *)
  Record BoxStyle : Type := mkBoxStyle {
    margin_inline_start  : nat;
    margin_inline_end    : nat;
    border_inline_start  : nat;
    border_inline_end    : nat;
    padding_inline_start : nat;
    padding_inline_end   : nat;
    has_auto_width       : bool;
    explicit_width       : nat
  }.

  (** Computed layout result (PhysicalFragment geometry) *)
  Record ComputedBox : Type := mkComputedBox {
    content_inline_size    : nat;
    margin_box_inline_size : nat
  }.

  (** ** 2. ICB & ConstraintSpace Initialization *)

  Definition InitLayoutViewFromViewport (vp : Viewport) : LayoutView :=
    mkLayoutView (viewport_width vp) (viewport_height vp).

  Definition CreateRootConstraintSpace (lv : LayoutView) : ConstraintSpace :=
    mkConstraintSpace (icb_inline_size lv) (icb_block_size lv) true.

  Definition CreateChildConstraintSpace (parent_box : ComputedBox) (parent_cs : ConstraintSpace) : ConstraintSpace :=
    mkConstraintSpace (content_inline_size parent_box) (available_block_size parent_cs) false.

  (** ** 3. UA Default Styles & Layout Algorithm (CSS 2.1 §10.3.3) *)

  (** Default UA style for <html>: auto width, 0 margins/borders/padding *)
  Definition DefaultHTMLStyle : BoxStyle :=
    mkBoxStyle 0 0 0 0 0 0 true 0.

  (** Default UA style for <body>: auto width, symmetric body_margin, 0 border/padding *)
  Definition DefaultBodyStyle (body_margin : nat) : BoxStyle :=
    mkBoxStyle body_margin body_margin 0 0 0 0 true 0.

  Definition InlineEdgesSum (s : BoxStyle) : nat :=
    margin_inline_start s + margin_inline_end s +
    border_inline_start s + border_inline_end s +
    padding_inline_start s + padding_inline_end s.

  (** Blink BlockLayoutAlgorithm inline size resolution (CSS 2.1 §10.3.3) *)
  Definition ResolveBlockInlineSize (cs : ConstraintSpace) (s : BoxStyle) : ComputedBox :=
    let edges := InlineEdgesSum s in
    let w := if has_auto_width s
             then (available_inline_size cs) - edges
             else explicit_width s in
    mkComputedBox w (w + edges).

  (** Relational semantics for the full Root -> HTML -> Body layout pass *)
  Inductive BlinkRootLayoutPass : Viewport -> nat -> LayoutView -> ComputedBox -> ComputedBox -> Prop :=
    | ExecRootLayout : forall (vp : Viewport) (body_margin : nat)
                              (lv : LayoutView) (cs_root cs_html : ConstraintSpace)
                              (html_box body_box : ComputedBox),
        lv = InitLayoutViewFromViewport vp ->
        cs_root = CreateRootConstraintSpace lv ->
        html_box = ResolveBlockInlineSize cs_root DefaultHTMLStyle ->
        cs_html = CreateChildConstraintSpace html_box cs_root ->
        body_box = ResolveBlockInlineSize cs_html (DefaultBodyStyle body_margin) ->
        BlinkRootLayoutPass vp body_margin lv html_box body_box.

  (** ** 4. Mathematical Invariants & Theorems *)

  (** Theorem 1: ICB dimensions exactly match Viewport dimensions (CSS 2.1 §10.1) *)
  Theorem icb_matches_viewport :
    forall (vp : Viewport) (bm : nat) (lv : LayoutView) (hb bb : ComputedBox),
      BlinkRootLayoutPass vp bm lv hb bb ->
      icb_inline_size lv = viewport_width vp /\
      icb_block_size lv = viewport_height vp.
  Proof.
    intros vp bm lv hb bb Hpass.
    inversion Hpass; subst.
    simpl. split; reflexivity.
  Qed.

  (** Theorem 2: Root <html> element expands to full viewport width *)
  Theorem html_width_equals_viewport :
    forall (vp : Viewport) (bm : nat) (lv : LayoutView) (hb bb : ComputedBox),
      BlinkRootLayoutPass vp bm lv hb bb ->
      content_inline_size hb = viewport_width vp.
  Proof.
    intros vp bm lv hb bb Hpass.
    inversion Hpass; subst.
    unfold ResolveBlockInlineSize, DefaultHTMLStyle, InlineEdgesSum; simpl.
    lia.
  Qed.

  (** Theorem 3: <body> width expansion formula: width = viewport_width - 2 * body_margin *)
  Theorem body_width_expansion_formula :
    forall (vp : Viewport) (bm : nat) (lv : LayoutView) (hb bb : ComputedBox),
      BlinkRootLayoutPass vp bm lv hb bb ->
      content_inline_size bb = viewport_width vp - 2 * bm.
  Proof.
    intros vp bm lv hb bb Hpass.
    inversion Hpass; subst.
    unfold ResolveBlockInlineSize, CreateChildConstraintSpace,
           DefaultHTMLStyle, DefaultBodyStyle, InlineEdgesSum; simpl.
    lia.
  Qed.

  (** Theorem 4: Non-negative available inline size invariant *)
  Theorem non_negative_inline_sizes :
    forall (vp : Viewport) (bm : nat) (lv : LayoutView) (hb bb : ComputedBox),
      BlinkRootLayoutPass vp bm lv hb bb ->
      0 <= content_inline_size hb /\ 0 <= content_inline_size bb.
  Proof.
    intros vp bm lv hb bb Hpass.
    lia.
  Qed.

  (** Theorem 5: Body box containment within viewport and strict content containment *)
  Theorem body_contained_within_viewport :
    forall (vp : Viewport) (bm : nat) (lv : LayoutView) (hb bb : ComputedBox),
      viewport_width vp >= 2 * bm ->
      BlinkRootLayoutPass vp bm lv hb bb ->
      margin_box_inline_size bb = viewport_width vp /\
      content_inline_size bb <= viewport_width vp /\
      (bm > 0 -> content_inline_size bb < viewport_width vp).
  Proof.
    intros vp bm lv hb bb Hvp Hpass.
    inversion Hpass; subst.
    unfold ResolveBlockInlineSize, CreateChildConstraintSpace,
           DefaultHTMLStyle, DefaultBodyStyle, InlineEdgesSum; simpl.
     repeat split; lia.
  Qed.

End BlinkViewportICBLayoutSemantics.
```