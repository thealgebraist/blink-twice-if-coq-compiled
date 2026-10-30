### 1. Core Data Structures in Blink Line Box Builder

In Chromium's Blink rendering engine (specifically within LayoutNG / `third_party/blink/renderer/core/layout/inline/`), text alignment during inline formatting context layout is governed by the following core structures:

*   **`ETextAlign` (`computed_style_constants.h`)**:
    An enumeration representing the computed `text-align` property value:
    ```cpp
    enum class ETextAlign : uint8_t {
      kLeft, kRight, kCenter, kJustify, kWebkitLeft, kWebkitRight, kWebkitCenter, kStart, kEnd, kMatchParent
    };
    ```
    During line breaking and logical-to-physical resolution (`InlineLayoutAlgorithm`), logical values (`kStart`, `kEnd`) are resolved against the line's `TextDirection` (`kLtr` or `kRtl`) into physical equivalents (`kLeft`, `kRight`, `kCenter`, `kJustify`).

*   **`LineBoxFragmentBuilder` (`line_box_fragment_builder.h`)**:
    Constructs the physical `PhysicalLineBoxFragment`. It holds a `LogicalLineItems` buffer containing `LogicalLineItem` elements, each with a `rect` (`LogicalRect` composed of `LogicalOffset` and `LayoutSize`).
    *   `LayoutUnit` (fixed-point 26.6 arithmetic, `1/64`th of a pixel) represents scalar coordinates: $W_{\text{line}}$ (`inline_size`) and $W_{\text{content}}$ (`content_inline_size`).

*   **`PhysicalOffset` & `LogicalOffset` (`geometry/physical_offset.h`, `geometry/logical_offset.h`)**:
    Before fragment finalization, `InlineLayoutAlgorithm::ApplyTextAlign` shifts the `inline_offset` of all `LogicalLineItem` children in the line box by the computed alignment delta $\Delta_{\text{align}}$ before converting `LogicalOffset` (`inline_offset`, `block_offset`) to `PhysicalOffset` (`left`, `top`).

---

### 2. Offset Computation for Line Items

In `InlineLayoutAlgorithm::ApplyTextAlign(LineInfo* line_info)`, given available line box inline size $W_{\text{line}}$ (`available_width`) and the natural inline size of the unaligned line contents $W_{\text{content}}$ (`width`), the remaining free space is:
$$S_{\text{free}} = W_{\text{line}} - W_{\text{content}}$$

For standard physical alignments (after resolving directionality and prior to clamping or overflow handling when $W_{\text{line}} \ge W_{\text{content}}$), the inline offset $\Delta_{\text{align}}$ applied to each item on the line is:

1.  **`text-align: left` (`ETextAlign::kLeft` / `kWebkitLeft`)**:
    $$\Delta_{\text{align}} = 0$$
2.  **`text-align: center` (`ETextAlign::kCenter` / `kWebkitCenter`)**:
    $$\Delta_{\text{align}} = \frac{W_{\text{line}} - W_{\text{content}}}{2}$$
    *(Note: In Blink's `LayoutUnit`, division by 2 is integer/fixed-point truncation towards zero: `free_space / 2`).*
3.  **`text-align: right` (`ETextAlign::kRight` / `kWebkitRight`)**:
    $$\Delta_{\text{align}} = W_{\text{line}} - W_{\text{content}}$$

*(Per CSS Text Module Level 3 §7.1, `justify` falls back to `start` on the last line or when expansion opportunities do not exist, otherwise distributing $S_{\text{free}}$ across justification opportunities rather than shifting the line origin).*

---

### 3. Special UA Default: `<th>` Table Header Cells

In Blink's User Agent stylesheet (`third_party/blink/renderer/core/html/resources/html.css`) and HTML specification rendering rules:
```css
th {
     display: table-cell;
     vertical-align: inherit;
     font-weight: bold;
     text-align: internal-center; /* Maps to ETextAlign::kCenter behavior */
}
```
While standard block/table containers (`<td>`, `<div>`, `<p>`) inherit `text-align: start` from the root defaults, `<th>` elements explicitly default to centered alignment unless overridden by author stylesheets or inheritance rules on child tables.

---

### 4. Mathematical Invariants

Assuming non-overflowing inline content ($0 \le W_{\text{content}} \le W_{\text{line}}$) over $\mathbb{Z}$ (modeling Blink's `LayoutUnit` raw integer ticks):

1.  **Non-Negativity (`offset_nonneg`)**:
    $$\forall W_{\text{line}}, W_{\text{content}} \in \mathbb{Z}, \quad W_{\text{content}} \le W_{\text{line}} \implies \Delta_{\text{align}} \ge 0$$
2.  **Bounding Box Containment (`offset_plus_content_le_line`)**:
    $$\forall W_{\text{line}}, W_{\text{content}} \in \mathbb{Z}, \quad 0 \le W_{\text{content}} \le W_{\text{line}} \implies \Delta_{\text{align}} + W_{\text{content}} \le W_{\text{line}}$$
3.  **Centering Symmetry (`center_symmetry`)**:
    Let $L_{\text{margin}} = \Delta_{\text{center}}$ be the left margin and $R_{\text{margin}} = W_{\text{line}} - (\Delta_{\text{center}} + W_{\text{content}})$ be the right margin. Under integer division:
    $$0 \le R_{\text{margin}} - L_{\text{margin}} \le 1$$
    And when $(W_{\text{line}} - W_{\text{content}})$ is even, $L_{\text{margin}} = R_{\text{margin}}$ exactly.

---

### 5. Concrete Rocq/Coq Formalization (`BlinkTextAlignGeometrySemantics.v`)

```coq
(** * BlinkTextAlignGeometrySemantics.v
    Formal Audit of Chromium Blink Text Align vs CSS Text 3 §7 (Agent 107) *)

From Coq Require Import ZArith.
From Coq Require Import Lia.
Open Scope Z_scope.

(** ** 1. Core Data Structures *)

(** Physical resolved ETextAlign states after BiDi/Direction resolution *)
Inductive ETextAlign : Type :=
  | AlignLeft
  | AlignCenter
  | AlignRight.

(** HTML Element Tag Subset for UA Default Resolution *)
Inductive HTMLElementTag : Type :=
  | TagDiv
  | TagP
  | TagTd
  | TagTh.

(** Directionality for resolving initial 'start' alignment *)
Inductive TextDirection : Type :=
  | DirLTR
  | DirRTL.

(** Logical Line Box Geometry Input *)
Record LineBoxMetrics : Type := mkLineBoxMetrics {
  w_line    : Z; (* Available inline size in LayoutUnit ticks *)
  w_content : Z  (* Natural inline size of line items in LayoutUnit ticks *)
}.

(** Physical / Logical Offset Output *)
Record LineItemOffset : Type := mkLineItemOffset {
  inline_offset : Z;
  block_offset  : Z
}.

(** ** 2. UA Stylesheet Default Resolution (Blink html.css) *)

Definition ua_default_text_align (tag : HTMLElementTag) (dir : TextDirection) : ETextAlign :=
  match tag with
  | TagTh => AlignCenter (* th defaults to internal-center / center *)
  | _     =>
      match dir with
      | DirLTR => AlignLeft
      | DirRTL => AlignRight
      end
  end.

Theorem th_defaults_to_center :
  forall (dir : TextDirection),
    ua_default_text_align TagTh dir = AlignCenter.
Proof.
  intros dir. reflexivity.
Qed.

(** ** 3. Offset Computation (InlineLayoutAlgorithm::ApplyTextAlign) *)

Definition compute_text_align_offset (align : ETextAlign) (m : LineBoxMetrics) : Z :=
  let free_space := m.(w_line) - m.(w_content) in
  match align with
  | AlignLeft   => 0
  | AlignCenter => Z.div free_space 2
  | AlignRight  => free_space
  end.

Definition apply_line_box_alignment
  (align : ETextAlign) (m : LineBoxMetrics) (item : LineItemOffset) : LineItemOffset :=
  mkLineItemOffset
    (item.(inline_offset) + compute_text_align_offset align m)
    item.(block_offset).

(** ** 4. Mathematical Invariants & Proofs *)

(** Invariant 1: Offset is non-negative when W_line >= W_content *)
Theorem offset_nonneg :
  forall (align : ETextAlign) (m : LineBoxMetrics),
    m.(w_content) <= m.(w_line) ->
    0 <= compute_text_align_offset align m.
Proof.
  intros align [wl wc] Hle.
  unfold compute_text_align_offset; simpl in *.
  destruct align.
  - (* AlignLeft *)
    lia.
  - (* AlignCenter *)
    apply Z.div_pos; lia.
  - (* AlignRight *)
    lia.
Qed.

(** Invariant 2: Offset + W_content <= W_line when W_line >= W_content *)
Theorem offset_plus_content_le_line :
  forall (align : ETextAlign) (m : LineBoxMetrics),
    0 <= m.(w_content) ->
    m.(w_content) <= m.(w_line) ->
    compute_text_align_offset align m + m.(w_content) <= m.(w_line).
Proof.
  intros align [wl wc] Hnonneg Hle.
  unfold compute_text_align_offset; simpl in *.
  destruct align.
  - (* AlignLeft *)
    lia.
  - (* AlignCenter *)
    assert (Hdiv : (wl - wc) / 2 <= wl - wc).
    { apply Z.div_le_upper_bound; lia. }
    lia.
  - (* AlignRight *)
    lia.
Qed.

(** Invariant 3a: Centering Symmetry (Bounded quantization error <= 1 LayoutUnit tick) *)
Theorem center_symmetry_bounded :
  forall (m : LineBoxMetrics),
    m.(w_content) <= m.(w_line) ->
    let left_margin  := compute_text_align_offset AlignCenter m in
    let right_margin := m.(w_line) - (left_margin + m.(w_content)) in
    0 <= right_margin - left_margin /\ right_margin - left_margin <= 1.
Proof.
  intros [wl wc] Hle.
  unfold compute_text_align_offset; simpl in *.
  set (free := wl - wc).
  assert (Hmod : free = 2 * (free / 2) + (free mod 2)) by (apply Z.div_mod; lia).
  assert (Hrem : 0 <= free mod 2 < 2) by (apply Z.mod_pos_bound; lia).
  unfold free in *.
  lia.
Qed.

(** Invariant 3b: Exact Centering Symmetry when free space is even *)
Theorem center_symmetry_exact_even :
  forall (m : LineBoxMetrics),
    (m.(w_line) - m.(w_content)) mod 2 = 0 ->
    let left_margin  := compute_text_align_offset AlignCenter m in
    let right_margin := m.(w_line) - (left_margin + m.(w_content)) in
    left_margin = right_margin.
Proof.
  intros [wl wc] Heven.
  unfold compute_text_align_offset; simpl in *.
  set (free := wl - wc) in *.
  assert (Hdiv : free = 2 * (free / 2) + (free mod 2)) by (apply Z.div_mod; lia).
  rewrite Heven in Hdiv.
  unfold free in *.
  lia.
Qed.

(** Invariant 4: End-to-End `th` Line Box Containment Guarantee *)
Corollary th_line_box_containment :
  forall (dir : TextDirection) (m : LineBoxMetrics),
    0 <= m.(w_content) ->
    m.(w_content) <= m.(w_line) ->
    let align := ua_default_text_align TagTh dir in
    let off   := compute_text_align_offset align m in
    0 <= off /\ off + m.(w_content) <= m.(w_line).
Proof.
  intros dir m Hc Hle.
  simpl.
  split.
  - apply offset_nonneg; assumption.
  - apply offset_plus_content_le_line; assumption.
Qed.
```