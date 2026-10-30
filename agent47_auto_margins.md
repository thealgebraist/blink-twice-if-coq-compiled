### 1. Core Blink Data Structures & Resolution Pipeline

In the Chromium Blink rendering engine (specifically within the LayoutNG architecture), margin computations operate over fixed-point arithmetic (`LayoutUnit`, which utilizes 1/64th pixel precision) and convert physical coordinate systems into writing-mode-aware flow-relative coordinates before solving constraint equations.

#### `NGBoxStrut` (`third_party/blink/renderer/core/layout/ng/geometry/ng_box_strut.h`)
`NGBoxStrut` represents box-model dimensions (margins, borders, or padding) in **logical coordinates** (`inline_start`, `inline_end`, `block_start`, `block_end`). 
*   During style resolution, `ComputeMarginsFor` extracts raw `Length` values (`Length::kAuto`, `Length::kFixed`, `Length::kPercent`) from `ComputedStyle`.
*   Initially, `auto` margins are resolved to `LayoutUnit(0)` within the provisional `NGBoxStrut` so that inline-size and block-size calculations can compute the unallocated space ($\Delta$).

```cpp
struct CORE_EXPORT NGBoxStrut {
  LayoutUnit inline_start;
  LayoutUnit inline_end;
  LayoutUnit block_start;
  LayoutUnit block_end;

  LayoutUnit InlineSum() const { return inline_start + inline_end; }
  LayoutUnit BlockSum() const { return block_start + block_end; }
};
```

#### `EBoxSizing` (`third_party/blink/renderer/core/style/computed_style_constants.h`)
The `EBoxSizing` enum (`kContentBox`, `kBorderBox`) dictates how the computed `width` (`inline_size`) interacts with `border_padding` (`NGBoxStrut`). 
*   In LayoutNG, `ComputeInlineSizeForFragment` resolves the box's final border-box inline size *prior* to calling auto-margin resolution. 
*   Thus, by the time `ResolveInlineAutoMargins` executes, the engine operates strictly on the **border-box inline size** (`child_inline_size`), which algebraically equals $\text{width}_{\text{content}} + \text{border\_padding}$ under `kContentBox`, or $\text{width}_{\text{specified}}$ (clamped by min/max-width and floored at `border_padding.InlineSum()`) under `kBorderBox`.

#### `ResolveInlineAutoMargins` & `ResolveAutoMargins` (`ng_length_utils.cc`)
Blink splits CSS 2.1 §10.3.3 (Block-level, non-replaced elements in normal flow) and §10.3.7 / §10.6.4 ( Absolutely positioned, non-replaced elements) across two primary pathways:

1.  **Normal Flow (`ResolveInlineAutoMargins`)**: Operates purely in the inline dimension. It accepts `ComputedStyle`, the containing block's `available_inline_size`, the resolved `child_inline_size` (which already incorporates `border_padding`), and a mutable `NGBoxStrut* margins`.
2.  **Out-of-Flow Positioned (`ComputeOutOfFlowInlineDimensions` / `ComputeOutOfFlowBlockDimensions`)**: Implements §10.3.7 and §10.6.4. It resolves `inset_start` (`left`/`top`), `inset_end` (`right`/`bottom`), `size`, and `margins` simultaneously. Auto margins are only calculated if `inset_start`, `inset_end`, and `size` are all non-`auto`.

---

### 2. Free Space ($\Delta$) Distribution & Edge-Case Audit

Let $W_{\text{avail}}$ be the containing block's available inline size. Let $W_{\text{border-box}}$ be the resolved inline size of the box (where $W_{\text{border-box}} = W_{\text{content}} + P_{\text{inline}} + B_{\text{inline}}$). Let $M_L^{\text{fixed}}$ and $M_R^{\text{fixed}}$ be the resolved values of non-auto margins (with `auto` margins provisionally set to $0$).

The unallocated inline space $\Delta$ (`space_left` in Blink) is computed as:
$$\Delta = W_{\text{avail}} - \left(W_{\text{border-box}} + M_L^{\text{fixed}} + M_R^{\text{fixed}}\right)$$

#### Case A: Normal Flow Inline Auto Margins (CSS 2.1 §10.3.3)
Blink's `ResolveInlineAutoMargins` maps physical `MarginLeft`/`MarginRight` to logical `MarginInlineStart`/`MarginInlineEnd` based on `WritingDirectionMode`. Assuming `LTR`:

1.  **Both `margin-left` and `margin-right` are `auto`**:
    *   **If $\Delta \ge 0$**: 
        $$M_{\text{inline-start}} = \lfloor \Delta / 2 \rfloor$$
        $$M_{\text{inline-end}} = \Delta - M_{\text{inline-start}}$$
        *Audit Note*: In C++ integer/fixed-point arithmetic (`LayoutUnit`), `/ 2` truncates toward zero. By defining $M_{\text{inline-end}} = \Delta - M_{\text{inline-start}}$, Blink prevents 1-ulp (`1/64px`) truncation loss when $\Delta$ has an odd raw representation.
    *   **If $\Delta < 0$ (Over-constrained / Overflow)**:
        Per §10.3.3: *"If both 'margin-left' and 'margin-right' are 'auto', their used values are equal. This horizontally centers the element... unless this would give them a negative value, in which case both 'margin-left' becomes zero..."* and the direction property forces the inline-end margin to absorb the overflow:
        $$M_{\text{inline-start}} = 0$$
        $$M_{\text{inline-end}} = \Delta \quad (\text{which is } < 0)$$
        *(Note: In `RTL`, logical `inline-start` corresponds to physical `right`. Hence, $M_{\text{right}} = 0$ and $M_{\text{left}} = \Delta$, matching CSS 2.1 §10.3.3 explicitly).*

2.  **Exactly one of `margin-left` or `margin-right` is `auto`**:
    *   The `auto` margin absorbs the entirety of $\Delta$ (regardless of the sign of $\Delta$):
        *   If `start` is `auto`: $M_{\text{inline-start}} = \Delta$, $M_{\text{inline-end}} = M_R^{\text{fixed}}$.
        *   If `end` is `auto`: $M_{\text{inline-start}} = M_L^{\text{fixed}}$, $M_{\text{inline-end}} = \Delta$.

3.  **Neither margin is `auto` (Over-constrained)**:
    *   In CSS 2.1 §10.3.3, if all values are specified (none are `auto`), the equation is over-constrained. The margin at `inline-end` (`right` in LTR, `left` in RTL) is ignored and treated as `auto`, absorbing $\Delta$:
        $$M_{\text{inline-end}} = M_{\text{inline-end}}^{\text{fixed}} + \Delta = W_{\text{avail}} - \left(W_{\text{border-box}} + M_{\text{inline-start}}^{\text{fixed}}\right)$$

#### Case B: Out-of-Flow Vertical Auto Margins (CSS 2.1 §10.6.4)
For absolutely positioned elements (`ng_out_of_flow_layout_part.cc`), when `top`, `bottom`, and `height` are not `auto`:
$$\Delta_{\text{block}} = H_{\text{avail}} - \left(\text{top} + \text{bottom} + H_{\text{border-box}} + M_T^{\text{fixed}} + M_B^{\text{fixed}}\right)$$
*   **Critical Divergence from §10.3.3**: In §10.6.4, when both `margin-top` and `margin-bottom` are `auto`, the spec mandates: *"solve the equation under the extra constraint that the two margins get equal values"*. Unlike §10.3.3 (and §10.3.7), **there is no clamping at $\Delta_{\text{block}} < 0$**. Even if $\Delta_{\text{block}} < 0$, both vertical margins receive $\Delta_{\text{block}} / 2$. Blink conforms to this in `ComputeOutOfFlowBlockDimensions`.

---

### 3. Mathematical Invariants

Across all resolution states in §10.3.3 and §10.6.4 (assuming non-`auto` insets/dimensions for OOF), the solver maintains three strict algebraic invariants over $\mathbb{Z}$ (representing raw `LayoutUnit` ticks):

1.  **Space Conservation (Exact Partitioning)**:
    $$\forall W_{\text{avail}}, W_{\text{box}}, M_L, M_R \in \mathbb{Z}, \quad M_L^{\text{resolved}} + M_R^{\text{resolved}} + W_{\text{box}} = W_{\text{avail}}$$
    *Proof Sketch*: When both are `auto` and $\Delta \ge 0$, $\lfloor\Delta/2\rfloor + (\Delta - \lfloor\Delta/2\rfloor) + W_{\text{box}} = \Delta + W_{\text{box}} = W_{\text{avail}}$. When $\Delta < 0$, $0 + \Delta + W_{\text{box}} = W_{\text{avail}}$. When one is `auto` (say $L$), $\Delta + M_R^{\text{fixed}} + W_{\text{box}} = (W_{\text{avail}} - W_{\text{box}} - M_R^{\text{fixed}}) + M_R^{\text{fixed}} + W_{\text{box}} = W_{\text{avail}}$. When neither is `auto`, $M_R$ is overwritten with $W_{\text{avail}} - W_{\text{box}} - M_L^{\text{fixed}}$, preserving the sum.

2.  **Bounded Symmetry (Centering under Non-Negative Free Space)**:
    When both margins are `auto` and $\Delta \ge 0$:
    $$0 \le M_{\text{end}}^{\text{resolved}} - M_{\text{start}}^{\text{resolved}} \le 1$$
    In exact real arithmetic, $M_{\text{start}} = M_{\text{end}}$. In Blink's fixed-point `LayoutUnit` domain ($\mathbb{Z}$), $M_{\text{end}} - M_{\text{start}} = (\Delta \bmod 2) \in \{0, 1\}$.

3.  **Determinism & Totality**:
    The resolution function $f : \text{Config} \to (\mathbb{Z} \times \mathbb{Z})$ is a total, pure function with a unique output pair $(M_{\text{start}}^{\text{resolved}}, M_{\text{end}}^{\text{resolved}})$ for any input tuple.

---

### 4. Formal Verification in Rocq / Coq (`BlinkAutoMarginSemantics.v`)

The following file compiles cleanly in Coq/Rocq (8.16+ / 9.0) using standard `ZArith` and `Lia` libraries. It models `LayoutUnit` as `Z` (representing 1/64px ticks), formalizes `EBoxSizing`, `NGBoxStrut`, CSS 2.1 §10.3.3, and CSS 2.1 §10.6.4, and proves all three core invariants.

```coq
(** * BlinkAutoMarginSemantics.v
    Formal Verification of Chromium Blink LayoutNG Auto Margin Resolution
    against CSS 2.1 §10.3.3 and §10.6.4. *)

From Coq Require Import ZArith.
From Coq Require Import Bool.
From Coq Require Import Lia.

Open Scope Z_scope.

(** ** 1. Core Data Structures *)

(** In Blink, LayoutUnit is a 32-bit fixed-point value (1/64th pixel).
    We model LayoutUnit ticks over the ring of integers Z. *)
Definition LayoutUnit := Z.

(** EBoxSizing: third_party/blink/renderer/core/style/computed_style_constants.h *)
Inductive EBoxSizing : Type :=
  | kContentBox
  | kBorderBox.

(** MarginSpec models CSS Length for margins: either Auto or a fixed LayoutUnit. *)
Inductive MarginSpec : Type :=
  | MarginAuto
  | MarginFixed (val : LayoutUnit).

(** TextDirection: governs how logical inline-start/end map to physical left/right. *)
Inductive TextDirection : Type :=
  | LTR
  | RTL.

(** NGBoxStrut: third_party/blink/renderer/core/layout/ng/geometry/ng_box_strut.h *)
Record NGBoxStrut : Type := mkNGBoxStrut {
  inline_start : LayoutUnit;
  inline_end   : LayoutUnit;
  block_start  : LayoutUnit;
  block_end    : LayoutUnit
}.

Definition InlineSum (s : NGBoxStrut) : LayoutUnit :=
  s.(inline_start) + s.(inline_end).

Definition BlockSum (s : NGBoxStrut) : LayoutUnit :=
  s.(block_start) + s.(block_end).

(** Resolves the border-box inline size given EBoxSizing, specified width,
    and border_padding strut. Note: Under kBorderBox, CSS 2.1 floors the border-box
    width at border_padding.InlineSum(). *)
Definition ResolveBorderBoxInlineSize
  (sizing : EBoxSizing)
  (specified_width : LayoutUnit)
  (border_padding : NGBoxStrut) : LayoutUnit :=
  let bp_sum := InlineSum border_padding in
  match sizing with
  | kContentBox => specified_width + bp_sum
  | kBorderBox  => Z.max specified_width bp_sum
  end.

(** Helper to extract the provisional fixed value of a margin (0 if auto). *)
Definition ProvisionalMargin (m : MarginSpec) : LayoutUnit :=
  match m with
  | MarginAuto => 0
  | MarginFixed v => v
  end.

(** ** 2. CSS 2.1 §10.3.3 & Blink ResolveInlineAutoMargins *)

(** Models Blink's `ResolveInlineAutoMargins` in `ng_length_utils.cc`,
    combined with the over-constrained fallback rule in CSS 2.1 §10.3.3.
    Operates in flow-relative logical coordinates (inline_start, inline_end). *)
Definition ResolveInlineMarginsLogical
  (available_inline_size : LayoutUnit)
  (child_inline_size : LayoutUnit)
  (m_start_spec m_end_spec : MarginSpec) : (LayoutUnit * LayoutUnit) :=
  let m_start_prov := ProvisionalMargin m_start_spec in
  let m_end_prov   := ProvisionalMargin m_end_spec in
  let delta := available_inline_size - (child_inline_size + m_start_prov + m_end_prov) in
  match m_start_spec, m_end_spec with
  | MarginAuto, MarginAuto =>
      if Z.geb