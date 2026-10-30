### 1. Core Data Structures in Chromium Blink Out-Of-Flow (OOF) Positioning

In Chromium's Blink layout engine (specifically the LayoutNG architecture located within `third_party/blink/renderer/core/layout/`), absolute positioning and centering are governed by a pipeline of logical coordinate structures that abstract away physical writing modes (`horizontal-tb`, `vertical-rl`, etc.) until final fragment generation.

```
+-----------------------------------------------------------------------+
|                         Containing Block (CB)                         |
|                                                                       |
|   |<-- Inset_start -->|                       |<-- Inset_end -->|     |
|   +-------------------+-----------------------+-----------------+     |
|   |                   |     Inset-Modified    |                 |     |
|   |                   |    Containing Block   |                 |     |
|   |                   |         (IMCB)        |                 |     |
|   |                   |                       |                 |     |
|   |                   | |<-Margin->|<-Margin->|                 |     |
|   |                   | |  _start  |   _end   |                 |     |
|   |                   | +----------+----------+                 |     |
|   |                   | |   OOF Border Box    |                 |     |
|   |                   | +---------------------+                 |     |
+---+-------------------+-----------------------+-----------------+-----+
```

#### `LogicalOOFPositionedNode` (`oof_positioned_node.h`)
Represents an out-of-flow positioned element queued for layout in its containing block's coordinate space.
*   **Role:** Bridges the DOM/LayoutObject tree with the OOF layout algorithm (`OutOfFlowLayoutPart`).
*   **Key Fields:**
    *   `box`: The `BlockNode` representing the positioned element.
    *   `static_position`: A `LogicalStaticPosition` struct storing the fallback offset and alignment edges (`kInlineStart`, `kInlineCenter`, `kInlineEnd`, etc.) if insets are `auto`.
    *   `requires_content_before_breaking`: Boolean flag used in fragmentation contexts.

#### `LogicalInsets` / `BoxStrut` (`geometry/box_strut.h`)
In Blink, `BoxStrut` is the foundational geometric primitive representing directional thicknesses around a box in logical coordinates (`inline_start`, `inline_end`, `block_start`, `block_end`). While `LogicalInsets` is conceptualized as the resolved values of `top`, `right`, `bottom`, and `left` mapped to logical axes, Blink represents both resolved insets and computed margins using `BoxStrut` (with underlying values stored as fixed-point `LayoutUnit`s, typically $1/64\text{th}$ of a pixel).
*   **Key Fields:** `LayoutUnit inline_start`, `inline_end`, `block_start`, `block_end`.
*   **Role in OOF:** Holds the resolved inset offsets from the containing block edges and, separately, the resolved margin struts computed during the absolute positioning sizing/margin phase.

#### `AbsolutePosition` / `LogicalOofDimensions` (`absolute_utils.h`)
While CSS specifications refer abstractly to the "Absolute Position" state, Blink concrete implementation encapsulates the output of the absolute positioning equations in `LogicalOofDimensions` (computed via `ComputeOutOfFlowInlineDimensions` and `ComputeOutOfFlowBlockDimensions`).
*   **Key Fields:**
    *   `LogicalSize size`: The resolved border-box dimensions ($\text{inline\_size}, \text{block\_size}$) of the OOF node.
    *   `BoxStrut inset`: The final effective insets from the containing block edges (combining explicit insets, static positions, and auto-margins).
    *   `BoxStrut margins`: The resolved `LayoutUnit` values for `margin-inline-start`, `margin-inline-end`, `margin-block-start`, and `margin-block-end`.

---

### 2. Inset-Modified Containing Block (IMCB) & Free Space Determination

Per **CSS Positioned Layout Module Level 3 § 5 (Absolute Positioning Layout Model)** and Blink's `ComputeOutOfFlowInlineDimensions` / `ComputeOutOfFlowBlockDimensions` (`absolute_utils.cc`):

Let $CB_{\text{size}}$ be the size of the containing block along a given logical axis (inline or block). 
An absolutely positioned box specifies two opposing insets along this axis: $\text{Inset}_{\text{start}}$ and $\text{Inset}_{\text{end}}$.

#### Step 1: Computing the IMCB
When both $\text{Inset}_{\text{start}}$ and $\text{Inset}_{\text{end}}$ are non-`auto` (definite values resolved against $CB_{\text{size}}$), the **Inset-Modified Containing Block (IMCB)** size along that axis is defined as:

$$\text{IMCB}_{\text{size}} = CB_{\text{size}} - (\text{Inset}_{\text{start}} + \text{Inset}_{\text{end}})$$

#### Step 2: Resolving Box Size and Determining Free Space
Once the element's $\text{BorderBox}_{\text{size}}$ is resolved (either via an explicit size like `width: 200px`, intrinsic sizing like `fit-content`, or stretched to fit the IMCB), the layout engine calculates the remaining **Free Space** ($\text{FreeSpace}$) available within the IMCB for margin distribution:

$$\text{FreeSpace} = \text{IMCB}_{\text{size}} - \text{BorderBox}_{\text{size}}$$

Substituting $\text{IMCB}_{\text{size}}$, we get the fundamental conservation equation of CSS Absolute Positioning:

$$\text{FreeSpace} = CB_{\text{size}} - (\text{Inset}_{\text{start}} + \text{Inset}_{\text{end}} + \text{BorderBox}_{\text{size}})$$

*(Note: If $\text{BorderBox}_{\text{size}}$ exceeds $\text{IMCB}_{\text{size}}$, $\text{FreeSpace}$ becomes negative, representing an overflow condition within the inset constraints).*

---

### 3. Equal Distribution of Free Space (Auto-Margin Centering)

When an author specifies `inset: 0; margin: auto;` (with a definite `width`/`height`), both opposing insets are definite ($0$) and both opposing margins ($\text{Margin}_{\text{start}}, \text{Margin}_{\text{end}}$) are `auto`.

According to **CSS Positioned Layout 3 § 5.3 (Resolving Margins)**:
1.  **Inline Axis:** If both `margin-inline-start` and `margin-inline-end` are `auto`, and $\text{FreeSpace} \ge 0$, the margins are set to equal values:
    $$\text{Margin}_{\text{start}} = \text{Margin}_{\text{end}} = \frac{\text{FreeSpace}}{2}$$
    *(Directionality Fallback)*: Under strict CSS 2.1 / CSS Position 3 legacy rules for the inline axis, if $\text{FreeSpace} < 0$, `margin-inline-start` is clamped to $0$ and `margin-inline-end` absorbs the negative overflow ($\text{Margin}_{\text{end}} = \text{FreeSpace}$). However, for true centering invariants where $\text{FreeSpace} \ge 0$ (or in the block axis unconditionally), space is bisected symmetrically.
2.  **Block Axis:** If both `margin-block-start` and `margin-block-end` are `auto`, they unconditionally bisect the free space regardless of sign:
    $$\text{Margin}_{\text{start}} = \text{Margin}_{\text{end}} = \frac{\text{FreeSpace}}{2}$$

#### Blink Fixed-Point Arithmetic (`LayoutUnit`) Nuance
In rational arithmetic ($\mathbb{Q}$ or $\mathbb{R}$), division by 2 is exact. In Blink's `absolute_utils.cc`, dimensions are represented as integer-backed `LayoutUnit`s:
```cpp
// Simplified from third_party/blink/renderer/core/layout/absolute_utils.cc
LayoutUnit free_space = imcb_size - border_box_size;
if (margin_start_is_auto && margin_end_is_auto) {
  margins.start = free_space / 2;
  margins.end = free_space - margins.start; // Preserves total space under odd subpixels
}
```
When modeled over exact Rationals ($\mathbb{Q}$) or Reals ($\mathbb{R}$), or over even integer subpixels, $\text{ FreeSpace } - (\text{FreeSpace } / 2) \equiv \text{FreeSpace } / 2$, achieving exact mathematical symmetry.

---

### 4. Mathematical Invariants

Under the standard absolute centering regime ($\text{Inset}_{\text{start}} \neq \text{auto}$, $\text{Inset}_{\text{end}} \neq \text{auto}$, $\text{Margin}_{\text{start}} = \text{auto}$, $\text{Margin}_{\text{end}} = \text{auto}$, and $\text{FreeSpace} \ge 0$):

1.  **Exact Centering Symmetry:**
    The computed start margin equals the computed end margin:
    $$\text{Margin}_{\text{start}} = \text{Margin}_{\text{end}}$$
    Furthermore, the geometric midpoint of the positioned element's border box aligns perfectly with the geometric midpoint of the IMCB:
    $$\text{Inset}_{\text{start}} + \text{Margin}_{\text{start}} + \frac{\text{BorderBox}_{\text{size}}}{2} = \text{Inset}_{\text{start}} + \frac{\text{IMCB}_{\text{size}}}{2}$$

2.  **Total Space Conservation:**
    The sum of all resolved segments along the axis equals the total dimension of the containing block:
    $$\text{Inset}_{\text{start}} + \text{Margin}_{\text{start}} + \text{BorderBox}_{\text{size}} + \text{Margin}_{\text{end}} + \text{Inset}_{\text{end}} = CB_{\text{size}}$$

3.  **Non-Negativity under Positive Free Space:**
    Whenever the element's border-box fits within the Inset-Modified Containing Block ($\text{Inset}_{\text{start}} + \text{Inset}_{\text{end}} + \text{BorderBox}_{\text{size}} \le CB_{\text{size}}$), the resulting auto margins are guaranteed to be non-negative:
    $$\text{FreeSpace} \ge 0 \implies \text{Margin}_{\text{start}} \ge 0 \land \text{Margin}_{\text{end}} \ge 0$$

---

### 5. Rocq / Coq Formalization (`BlinkAbsoluteCenteringSemantics.v`)

The following self-contained Rocq (Coq) script formalizes both the **Exact Rational ($\mathbb{Q}$) CSS Specification Model** (where division by 2 is perfectly symmetric) and the **Discrete Subpixel ($\mathbb{Z}$) Blink `LayoutUnit` Model**, proving all three invariants cleanly without axioms.

```coq
(** * BlinkAbsoluteCenteringSemantics.v
    Formal verification of Chromium Blink Out-Of-Flow (OOF) Absolute Centering
    against CSS Positioned Layout Module Level 3 § 5. *)

From Coq Require Import QArith QArith_base Lqa.
From Coq Require Import ZArith Lia.

Open Scope Q_scope.

(* ========================================================================== *)
(* PART 1: Core Data Structures (Rational Spec Model)                         *)
(* ========================================================================== *)

(** Represents a CSS length or inset/margin value that can be 'auto' or definite. *)
Inductive CssLength : Type :=
  | Auto : CssLength
  | Definite (val : Q) : CssLength.

(** Represents a 1D slice (Inline or Block axis) of Blink's BoxStrut / LogicalInsets *)
Record AxisStrut : Type := mkAxisStrut {
  start_val : Q;
  end_val   : Q
}.

(** Input parameters for a 1D Out-Of-Flow Positioned Node layout pass *)
Record LogicalOOFNodeInput : Type := mkOOFInput {
  cb_size         : Q;          (* Containing Block size along the axis *)
  inset_start_in  : CssLength;  (* Unresolved start inset *)
  inset_end_in    : CssLength;  (* Unresolved end inset *)
  border_box_size : Q;          (* Resolved BorderBox size of the OOF node *)
  margin_start_in : CssLength;  (* Unresolved start margin *)
  margin_end_in   : CssLength;  (* Unresolved end margin *)
  static_pos      : Q           (* Fallback static position *)
}.

(** Output structure analogous to Blink's LogicalOofDimensions (1D projection) *)
Record AbsolutePosition : Type := mkAbsPos {
  resolved_size    : Q;
  resolved_insets  : AxisStrut;
  resolved_margins : AxisStrut;
  final_offset     : Q          (* Offset from CB start edge: inset_start + margin_start *)
}.

(* ========================================================================== *)
(* PART 2: IMCB & Free Space Calculation                                      *)
(* ========================================================================== *)

(** Computes the Inset-Modified Containing Block (IMCB) size given resolved insets. *)
Definition compute_imcb_size (cb : Q) (insets : AxisStrut) : Q :=
  cb - (insets.(start_val) + insets.(end_val)).

(** Computes FreeSpace = CB_size - (Inset_start + Inset_end + BorderBox_size). *)
Definition compute_free_space (cb : Q) (insets : AxisStrut) (bb_size : Q) : Q :=
  cb - (insets.(start_val) + insets.(end_val) + bb_size).

Lemma imcb_free_space_equiv : forall cb insets bb_size,
  compute_free_space cb insets bb_size == compute_imcb_size cb insets - bb_size.
Proof.
  intros cb insets bb_size.
  unfold compute_free_space, compute_imcb_size.
  lra.
Qed.

(* ========================================================================== *)
(* PART 3: Margin Resolution & Equal Distribution of Free Space               *)
(* ========================================================================== *)

(** Resolves opposing margins according to CSS Positioned Layout 3 § 5.3. *)
Definition resolve_margins (free_space : Q) (m_start m_end : CssLength) : AxisStrut :=
  match m_start, m_end with
  | Auto, Auto =>
      (* Both margins are auto: bisect the free space equally *)
      let half := free_space / (2#1) in
      mkAxisStrut half half
  | Auto, Definite me =>
      mkAxisStrut (free_space - me) me
  | Definite ms, Auto =>
      mkAxisStrut ms (free_space - ms)
  | Definite ms, Definite me =>
      mkAxisStrut ms me
  end.

(** Full 1D Absolute Positioning layout step when insets are definite. *)
Definition layout_absolute_axis (input : LogicalOOFNodeInput) (i_start i_end : Q) : AbsolutePosition :=
  let insets := mkAxisStrut i_start i_end in
  let free_space := compute_free_space input.(cb_size) insets input.(border_box_size) in
  let margins := resolve_margins free_space input.(margin_start_in) input.(margin_end_in) in
  mkAbsPos
    input.(border_box_size)
    insets
    margins
    (i_start + margins.(start_val)).

(* =