# Formal Verification Report: Ruby Base and Ruby Text Alignment and Auto-Expansion
**Agent:** 679 (W3C/WHATWG Layout Rules & Chromium Blink LayoutNG Verification)  
**Target Module:** `BlinkRubyBaseTextAlignmentSemantics.v`  
**Chromium Component:** `third_party/blink/renderer/core/layout/inline/ruby_layout_algorithm.cc`  
**W3C Specification:** CSS Ruby Layout Module Level 1, Section 3 (Ruby Box Model and Layout) & Section 4.2 (`ruby-align`)

---

## 1. Normative W3C Specification Requirements

According to the **W3C CSS Ruby Layout Module Level 1** specification, ruby formatting contexts pair inline base text (`display: ruby-base`) with phonetic or semantic annotations (`display: ruby-text`) inside atomic layout pairings known as **ruby columns**.

### 1.1 Ruby Column Width Auto-Expansion (§3.3 "Ruby Box Sizing")
A ruby column consists of one ruby base box and one or more associated ruby annotation boxes (typically one in mono-ruby or group-ruby). When formatting a ruby column along the inline axis:
1. Each constituent level (base and annotation) has an intrinsic content inline-size: $W_{\text{base}} \ge 0$ and $W_{\text{text}} \ge 0$.
2. The inline-size of the ruby column ($W_{\text{col}}$) auto-expands to accommodate the widest level within that column:
   $$W_{\text{col}} = \max(W_{\text{base}}, W_{\text{text}})$$
3. Any level whose intrinsic inline-size $w$ is strictly less than $W_{\text{col}}$ has remaining free space $\Delta w = W_{\text{col}} - w > 0$ distributed within or around its box according to the `ruby-align` property.

### 1.2 Alignment and Space Distribution (§4.2 "Aligning Ruby: the `ruby-align` property")
The `ruby-align` property specifies how text and inline boxes are distributed within their respective ruby base or ruby annotation boxes when the box is narrower than the ruby column width $W_{\text{col}}$:

* **`start`**: The narrow content is aligned with the inline-start edge of the column. Leading offset is $0$; trailing space is $W_{\text{col}} - w$.
* **`center`**: The narrow content is centered within the column width. The free space $W_{\text{col}} - w$ is divided equally between the inline-start and inline-end edges. Under fixed-point integer arithmetic (`LayoutUnit`), the inline-start offset is:
  $$\text{offset}_{\text{center}}(W_{\text{col}}, w) = \left\lfloor \frac{W_{\text{col}} - w}{2} \right\rfloor$$
  and the trailing space is $(W_{\text{col}} - w) - \text{offset}_{\text{center}}(W_{\text{col}}, w)$.
* **`space-between`**: For a sequence of $N$ justification opportunities (inter-character or inter-glyph spaces, where number of items $K = N + 1$):
  * If $N > 0$, the extra space $W_{\text{col}} - w$ is distributed evenly across the $N$ interior gaps. The inline-start and inline-end edges flush with the column boundaries ($\text{offset} = 0$).
  * If $N = 0$ (e.g., a single glyph or unbreakable atomic inline), `space-between` falls back to **`center`** alignment.
* **`space-around`**: The extra space $W_{\text{col}} - w$ is distributed so that each of the $K$ items receives equal space on both sides. Equivalently, there are $N = K - 1$ full-size interior gaps of weight $1$, and two half-size boundary gaps at the inline-start and inline-end edges of weight $\frac{1}{2}$ each (summing to $N + 1 = K$ total unit weights):
  * If $K = 1$ ($N = 0$), the two half-size boundary gaps each receive half of the free space, making it mathematically identical to **`center`** alignment:
    $$\text{offset}_{\text{space-around}}(W_{\text{col}}, w, 1) = \left\lfloor \frac{W_{\text{col}} - w}{2} \right\rfloor$$
  * If $K > 1$, the total free space $\Delta w = W_{\text{col}} - w$ is divided into $2K$ half-shares, or equivalently, the leading and trailing margins combined take $\left\lfloor \frac{\Delta w}{K} \right\rfloor$ (split equally across start and end), and the remaining space is distributed across the $K - 1$ interior gaps.

---

## 2. Chromium Blink Implementation Details and Invariants

In Chromium's LayoutNG architecture (specifically after the `RubyLineBreakable` refactoring in `third_party/blink/renderer/core/layout/inline/`), ruby layout and alignment are handled across `ruby_utils.cc`, `line_breaker.cc`, and `logical_line_builder.cc` (historically encapsulated in `ruby_layout_algorithm.cc`).

### 2.1 Fixed-Point Representation (`LayoutUnit`)
Blink represents inline coordinates and sizes as `LayoutUnit`, a 32-bit signed fixed-point integer with 6 fractional bits ($\frac{1}{64}\text{ px}$ resolution). In formal verification over $\mathbb{Z}$, a `LayoutUnit` is isomorphic to an integer count of $\frac{1}{64}\text{ px}$ quanta. Division by $2$ (`(col_w - w) / 2`) corresponds to integer division (`Z.div` or `Z.quot`, which coincide for non-negative dividends).

### 2.2 Column Auto-Expansion in Blink
When constructing a `LogicalRubyColumn` during line layout:
```cpp
LayoutUnit base_inline_size = base_line_items.InlineSize();
LayoutUnit annotation_inline_size = annotation_line_items.InlineSize();
LayoutUnit ruby_column_width = std::max(base_inline_size, annotation_inline_size);
```
Blink enforces the non-negativity invariant: `base_inline_size >= LayoutUnit()` and `annotation_inline_size >= LayoutUnit()`. Consequently:
1. `ruby_column_width >= base_inline_size`
2. `ruby_column_width >= annotation_inline_size`
3. At least one of the two levels has zero free space (`ruby_column_width - w == 0`), meaning at least one level requires zero inset/justification adjustment.

### 2.3 `ApplyRubyAlign` and Space Distribution (`ruby_utils.cc`)
When `inset = ruby_column_width - width > LayoutUnit()`, Blink computes a pair of `(start_offset, end_offset)` or distributes justification space across `ShapeResult` glyphs:

```cpp
// Conceptual structure of Blink's RubyAlign distribution:
LayoutUnit space = ruby_column_width - content_width;
if (space <= LayoutUnit()) {
  return {LayoutUnit(), LayoutUnit()};
}

switch (ruby_align) {
  case ERubyAlign::kStart:
    return {LayoutUnit(), space};
  case ERubyAlign::kCenter:
    return {space / 2, space - (space / 2)};
  case ERubyAlign::kSpaceBetween:
    if (justification_opportunities == 0) {
      return {space / 2, space - (space / 2)};
    }
    DistributeJustification(line_items, space, justification_opportunities);
    return {LayoutUnit(), LayoutUnit()};
  case ERubyAlign::kSpaceAround:
    if (justification_opportunities == 0) {
      return {space / 2, space - (space / 2)};
    }
    // Total units = justification_opportunities + 1 (since 2 * 0.5 boundary + N interior)
    LayoutUnit edge_space = space / (justification_opportunities + 1);
    LayoutUnit start_offset = edge_space / 2;
    LayoutUnit end_offset = edge_space - start_offset;
    LayoutUnit interior_space = space - edge_space;
    DistributeJustification(line_items, interior_space, justification_opportunities);
    return {start_offset, end_offset};
}
```

### 2.4 Critical Implementation Invariants
To prevent visual overlaps, clipping, or layout instability (`DCHECK` failures in ` InlineLayoutAlgorithm`), Blink relies on five core mathematical invariants:
1. **Column Dominance:** $W_{\text{col}} \ge W_{\text{base}} \land W_{\text{col}} \ge W_{\text{text}}$.
2. **Idempotence on Dominant Level:** For whichever level achieves $W_{\text{col}}$, its leading offset, trailing offset, and interior added justification space are all strictly $0$.
3. **Exact Space Conservation:** For all `ERubyAlign` modes and any number of justification opportunities $N \ge 0$:
   $$\text{start\_offset} + w + \text{interior\_space} + \text{end\_offset} = W_{\text{col}}$$
4. **Non-Negative Offsets & Bounding:** $0 \le \text{start\_offset} \le W_{\text{col}} - w$, $0 \le \text{end\_offset} \le W_{\text{col}} - w$, and $0 \le \text{interior\_space} \le W_{\text{col}} - w$.
5. **Centering / Parity Bounds:** Under `center` (or `space-around`/`space-between` when $N=0$), the difference between trailing and leading offsets is bounded by at most 1 subpixel unit (`LayoutUnit::Epsilon()`):
   $$0 \le \text{end\_offset} - \text{start\_offset} \le 1$$

---

## 3. Formal Specification in Rocq / Coq

Below is the complete, self-contained formalization and verification module `BlinkRubyBaseTextAlignmentSemantics.v`. It models `LayoutUnit` as `Z`, defines the ruby column geometry, specifies all `ruby-align` space-distribution algorithms (`start`, `center`, `space-between`, `space-around`), and proves all structural invariants without any `Admitted` or `axiom` statements.

```coq
(** * BlinkRubyBaseTextAlignmentSemantics.v
    Formal Verification of W3C CSS Ruby Layout Level 1 (§3, §4.2) and
    Chromium Blink Ruby Base/Text Alignment and Auto-Expansion.

    Target Source: third_party/blink/renderer/core/layout/inline/ruby_layout_algorithm.cc
                   third_party/blink/renderer/core/layout/inline/ruby_utils.cc
    Mathematical Properties:
      - ruby_column_width = max(base_width, text_width)
      - center_offset = (col_w - w) / 2
      - space-around / space-between conservation and bounds
*)

From Coq Require Import ZArith.
From Coq Require Import Lia.
From Coq Require Import Bool.
From Coq Require Import List.
Import ListNotations.

Open Scope Z_scope.

(** ** 1. Basic Types and LayoutUnit Representation *)

(** In Chromium Blink, LayoutUnit is a fixed-point number (1/64th pixel quanta).
    We model LayoutUnit directly as an integer count of quanta in Z. *)
Definition LayoutUnit := Z.

(** W3C CSS Ruby Layout 1 §4.2: the `ruby-align` property values *)
Inductive RubyAlign : Type :=
  | RubyAlignStart
  | RubyAlignCenter
  | RubyAlignSpaceBetween
  | RubyAlignSpaceAround.

(** Input metrics for a single level (either ruby-base or ruby-text) within a column.
    - [level_width]: intrinsic content inline-size (w >= 0)
    - [level_gaps]: number of interior justification opportunities (N >= 0),
                    which equals (number of atomic inline items - 1). *)
Record RubyLevelInput : Type := mkRubyLevelInput {
  level_width : LayoutUnit;
  level_gaps  : Z
}.

(** Input metrics for a paired Ruby Column (base + annotation text). *)
Record RubyColumnInput : Type := mkRubyColumnInput {
  base_input : RubyLevelInput;
  text_input : RubyLevelInput;
  base_align : RubyAlign;
  text_align : RubyAlign
}.

(** Computed layout geometry for a single ruby level after alignment and expansion.
    - [start_offset]: inline-start margin/inset before content begins
    - [content_width]: original intrinsic width of the items
    - [interior_space]: total extra justification space distributed across interior gaps
    - [end_offset]: inline-end margin/inset after content ends *)
Record RubyLevelLayout : Type := mkRubyLevelLayout {
  start_offset   : LayoutUnit;
  content_width  : LayoutUnit;
  interior_space : LayoutUnit;
  end_offset     : LayoutUnit
}.

(** Computed layout for the entire Ruby Column. *)
Record RubyColumnLayout : Type := mkRubyColumnLayout {
  column_width : LayoutUnit;
  base_layout  : RubyLevelLayout;
  text_layout  : RubyLevelLayout
}.

(** Well-formedness predicate for a single level input *)
Definition wf_level_input (inp : RubyLevelInput) : Prop :=
  0 <= level_width inp /\ 0 <= level_gaps inp.

(** Well-formedness predicate for a ruby column input *)
Definition wf_column_input (col : RubyColumnInput) : Prop :=
  wf_level_input (base_input col) /\ wf_level_input (text_input col).

(** ** 2. Core Layout Functions *)

(** Ruby column auto-expansion: ruby_column_width = max(base_width, text_width) *)
Definition compute_ruby_column_width (base_w text_w : LayoutUnit) : LayoutUnit :=
  Z.max base_w text_w.

(** Center offset calculation: center_offset = (col_w - w) / 2 *)
Definition compute_center_offset (col_w w : LayoutUnit) : LayoutUnit :=
  (col_w - w) / 2.

(** Compute alignment and space distribution for a single level of width [w]
    with [gaps] interior justification opportunities inside a column of width [col_w]. *)
Definition layout_ruby_level (align : RubyAlign) (col_w : LayoutUnit) (inp : RubyLevelInput)
  : RubyLevelLayout :=
  let w := level_width inp in
  let gaps := level_gaps inp in
  let space := col_w - w in
  if space <=? 0 then
    mkRubyLevelLayout 0 w 0 0
  else
    match align with
    | RubyAlignStart =>
        mkRubyLevelLayout 0 w 0 space
    | RubyAlignCenter =>
        let start_off := compute_center_offset col_w w in
        let end_off := space - start_off in
        mkRubyLevelLayout start_off w 0 end_off
    | RubyAlignSpaceBetween =>
        if gaps <=? 0 then
          let start_off := compute_center_offset col_w w in
          let end_off := space - start