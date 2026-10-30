# Formal Verification Report: Table `<colgroup>` and `<col>` Span Clamping and Bounding Semantics in Chromium Blink

**Agent ID:** Formal Verification Agent 696  
**Specialization:** W3C/WHATWG Layout Rules (Grid, Tables, Shapes) in Chromium Blink  
**Target Source:** `third_party/blink/renderer/core/layout/table/table_layout_algorithm_types.cc`  
**Specification:** WHATWG HTML Living Standard §4.9.3 (`<colgroup>`) & §4.9.4 (`<col>`); W3C CSS Tables Module Level 3  
**Formal Theory Target:** `BlinkTableColgroupSpanClampingSemantics.v`  

---

## 1. Normative Specification Requirements

### 1.1 WHATWG HTML Living Standard (§4.9.3 & §4.9.4)
According to the WHATWG HTML Living Standard:
* **§4.9.3 The `colgroup` element:** If the `colgroup` element contains no `col` elements, it may have a `span` content attribute specified, whose value must be a valid non-negative integer greater than zero and less than or equal to 1000.
* **§4.9.4 The `col` element:** The `col` element may have a `span` content attribute specified, whose value must be a valid non-negative integer greater than zero and less than or equal to 1000.
* **Parsing and Clamping Rules (HTML §2.4.4.2 & §4.9.12):** When parsing the `span` attribute for layout and DOM reflection:
  1. Parse the attribute using the rules for parsing non-negative integers.
  2. If parsing fails, or if the parsed value is $0$, the default value is $1$.
  3. If the parsed value exceeds $1000$, it is clamped to $1000$.

Thus, for any raw integer input $s \in \mathbb{Z}$ representing the parsed or internal span candidate before layout column generation, the effective layout span is governed by the mathematical clamping operator:
$$\text{clamp\_span}(s) = \max(1, \min(s, 1000))$$

### 1.2 W3C CSS Tables Module Level 3
In CSS Tables Level 3 (§3.1 Table Structure & §3.4 Column Generation):
* `table-column-group` (`<colgroup>`) and `table-column` (`<col>`) boxes define structural columns in the table grid.
* A `table-column-group` box with $k > 0$ child `table-column` boxes derives its effective column span exclusively from the sum of the spans of its children, ignoring its own `span` attribute.
* A childless `table-column-group` box or a standalone `table-column` box occupies $\text{clamp\_span}(s) \in [1, 1000]$ consecutive columns in the table column grid.

---

## 2. Chromium Blink Implementation Details and Invariants

In Chromium's LayoutNG Table architecture (`third_party/blink/renderer/core/layout/table/`), table column definitions are normalized into `TableTypes::Column` structures inside `table_layout_algorithm_types.cc` and `layout_table_column.cc`.

### 2.1 Source Code Architecture
In `third_party/blink/renderer/core/html/table_constants.h`:
```cpp
constexpr unsigned kDefaultColSpan = 1u;
constexpr unsigned kMinColSpan = 1u;
constexpr unsigned kMaxColSpan = 1000u;
```

In `HTMLTableColElement::ParseAttribute` (`html_table_col_element.cc`):
```cpp
if (params.name == html_names::kSpanAttr) {
  unsigned new_span = 0;
  if (!ParseHTMLClampedNonNegativeInteger(params.new_value, kMinColSpan,
                                          kMaxColSpan, new_span)) {
    new_span = kDefaultColSpan;
  }
  span_ = new_span;
}
```

In `third_party/blink/renderer/core/layout/table/table_layout_algorithm_types.cc`, `TableTypes::CreateColumn` and the column visitor (`ColumnLocationsBuilder` / `TableChildIterator`) consume `LayoutTableColumn::Span()` to instantiate column descriptors:

```cpp
// Conceptual flow in table_layout_algorithm_types.cc
TableTypes::Column TableTypes::CreateColumn(
    const ComputedStyle& style,
    std::optional<LayoutUnit> default_inline_size,
    unsigned span) {
  // Invariant: span is guaranteed to be within [1, 1000]
  DCHECK_GE(span, 1u);
  DCHECK_LE(span, 1000u);
  ...
}
```

### 2.2 Core Layout Invariants
1. **Strict Positivity Invariant:** Every `<col>` and childless `<colgroup>` contributes at least $1$ column to the table grid ($\text{span} \ge 1$). Zero-span columns cannot exist in the layout tree, preventing division-by-zero during column width distribution (`TableLayoutAlgorithmAuto`).
2. **Algorithmic Complexity Bounding Invariant:** Every `<col>` and childless `<colgroup>` contributes at most $1000$ columns per element ($\text{span} \le 1000$), mitigating DoS memory exhaustion attacks in column vector allocation (`Vector<TableTypes::Column>`).
3. **Child Precedence Invariant:** If a `LayoutTableColumn` (`kColumnGroup`) has children (`kColumn`), its own `span` attribute is ignored; its effective span in the column grid is the sum of the clamped spans of its child `kColumn` boxes, which is strictly bounded by $[N, 1000 \cdot N]$ where $N \ge 1$ is the number of children.
4. **Idempotence & Monotonicity:** Re-applying the clamping function during style recalc or anonymous box generation is idempotent, and order relations between requested spans are preserved.

---

## 3. Formal Specification & Verification in Rocq/Coq

Below is the complete, self-contained formalization and verification of `BlinkTableColgroupSpanClampingSemantics.v`. It uses standard `ZArith`, `List`, `Bool`, and `Lia` libraries with **zero admits**.

```coq
(** * BlinkTableColgroupSpanClampingSemantics.v
    Formal Verification of HTML/CSS Table <colgroup> and <col> Span Clamping
    and Column Grid Bounding in Chromium Blink (table_layout_algorithm_types.cc).
*)

From Coq Require Import ZArith.
From Coq Require Import List.
From Coq Require Import Bool.
From Coq Require Import Lia.
Import ListNotations.

Open Scope Z_scope.

(** ** 1. Constants and Specification Definitions *)

(** HTML Living Standard §4.9.3 / §4.9.4 constants in table_constants.h *)
Definition kDefaultColSpan : Z := 1.
Definition kMinColSpan : Z := 1.
Definition kMaxColSpan : Z := 1000.

(** Core mathematical clamping operator:
    clamp_span(span) = max(1, min(span, 1000)) *)
Definition clamp_span (s : Z) : Z :=
  Z.max kMinColSpan (Z.min s kMaxColSpan).

(** HTML attribute parser model:
    Represents ParseHTMLClampedNonNegativeInteger fallback behavior.
    If input is None (unparseable/missing) or <= 0, falls back to kDefaultColSpan (1),
    otherwise clamps to [1, 1000]. Note that clamping any s <= 0 via clamp_span
    naturally yields 1 as well. *)
Definition parse_html_col_span (raw_attr : option Z) : Z :=
  match raw_attr with
  | None => kDefaultColSpan
  | Some s =>
      if s <=? 0 then kDefaultColSpan
      else clamp_span s
  end.

(** Predicate for valid layout column span in TableTypes::Column *)
Definition valid_col_span (s : Z) : Prop :=
  kMinColSpan <= s /\ s <= kMaxColSpan.

(** ** 2. Structural Table Column and Colgroup AST *)

(** A <col> element has an optional raw span attribute *)
Record ColElement := mkCol {
  col_raw_span : option Z
}.

(** A <colgroup> element has an optional raw span attribute and a list of child <col> elements *)
Record ColGroupElement := mkColGroup {
  colgroup_raw_span : option Z;
  colgroup_children : list ColElement
}.

(** Effective span of a single <col> element *)
Definition eval_col_span (c : ColElement) : Z :=
  parse_html_col_span (col_raw_span c).

(** Sum of effective spans of a list of <col> elements *)
Fixpoint sum_col_spans (cols : list ColElement) : Z :=
  match cols with
  | [] => 0
  | c :: cs => eval_col_span c + sum_col_spans cs
  end.

(** Effective span of a <colgroup> element per HTML §4.9.3 & Blink LayoutTableColumn:
    - If it has no <col> children, its effective span is its own clamped span attribute.
    - If it has <col> children, its own span attribute is ignored and its effective
      span is the sum of the effective spans of its <col> children. *)
Definition eval_colgroup_span (cg : ColGroupElement) : Z :=
  match colgroup_children cg with
  | [] => parse_html_col_span (colgroup_raw_span cg)
  | cols => sum_col_spans cols
  end.

(** TableTypes::Column descriptor in table_layout_algorithm_types.cc *)
Record LayoutColumnDescriptor := mkLayoutColDesc {
  desc_span : Z;
  desc_is_grouped : bool
}.

(** Generation of LayoutColumnDescriptors from a ColGroupElement *)
Definition build_colgroup_descriptors (cg : ColGroupElement) : list LayoutColumnDescriptor :=
  match colgroup_children cg with
  | [] => [mkLayoutColDesc (parse_html_col_span (colgroup_raw_span cg)) false]
  | cols => map (fun c => mkLayoutColDesc (eval_col_span c) true) cols
  end.

(** Total columns contributed to the Table Grid by a list of descriptors *)
Fixpoint total_descriptor_span (descs : list LayoutColumnDescriptor) : Z :=
  match descs with
  | [] => 0
  | d :: ds => desc_span d + total_descriptor_span ds
  end.

(** ** 3. Fundamental Theorems on Clamping Operator *)

(** Theorem 1: Lower and Upper Bounding Invariant.
    For all integers s, clamp_span(s) lies strictly within [1, 1000]. *)
Theorem clamp_span_bounds : forall s : Z,
  valid_col_span (clamp_span s).
Proof.
  intros s.
  unfold valid_col_span, clamp_span, kMinColSpan, kMaxColSpan.
  lia.
Qed.

(** Theorem 2: Strict Positivity of Clamped Span.
    Ensures zero-span columns can never be created in Blink table layout. *)
Theorem clamp_span_strictly_positive : forall s : Z,
  0 < clamp_span s.
Proof.
  intros s.
  unfold clamp_span, kMinColSpan, kMaxColSpan.
  lia.
Qed.

(** Theorem 3: Identity on Valid Range.
    If s is already in [1, 1000], clamp_span(s) = s. *)
Theorem clamp_span_identity_in_range : forall s : Z,
  valid_col_span s -> clamp_span s = s.
Proof.
  intros s [Hmin Hmax].
  unfold valid_col_span, clamp_span, kMinColSpan, kMaxColSpan in *.
  lia.
Qed.

(** Theorem 4: Idempotence of Clamping.
    clamp_span(clamp_span(s)) = clamp_span(s). *)
Theorem clamp_span_idempotent : forall s : Z,
  clamp_span (clamp_span s) = clamp_span s.
Proof.
  intros s.
  apply clamp_span_identity_in_range.
  apply clamp_span_bounds.
Qed.

(** Theorem 5: Monotonicity of Clamping.
    If s1 <= s2, then clamp_span(s1) <= clamp_span(s2). *)
Theorem clamp_span_monotonic : forall s1 s2 : Z,
  s1 <= s2 -> clamp_span s1 <= clamp_span s2.
Proof.
  intros s1 s2 Hle.
  unfold clamp_span, kMinColSpan, kMaxColSpan.
  lia.
Qed.

(** Theorem 6: Commutativity of Max/Min Representation.
    max(1, min(s, 1000)) = min(1000, max(1, s)). *)
Theorem clamp_span_sym_form : forall s : Z,
  clamp_span s = Z.min kMaxColSpan (Z.max kMinColSpan s).
Proof.
  intros s.
  unfold clamp_span, kMinColSpan, kMaxColSpan.
  lia.
Qed.

(** Theorem 7: Equivalence of HTML Parser Fallback and Direct Clamping.
    For any Some s, parse_html_col_span (Some s) is identical to clamp_span s. *)
Theorem parse_some_eq_clamp : forall s : Z,
  parse_html_col_span (Some s) = clamp_span s.
Proof.
  intros s.
  unfold parse_html_col_span, clamp_span, kDefaultColSpan, kMinColSpan, kMaxColSpan.
  destruct (s <=? 0) eqn:Hle.
  - apply Z.leb_le in Hle. lia.
  - apply Z.leb_gt in Hle. lia.
Qed.

(** Theorem 8: Parsed HTML Span Validity.
    For any raw attribute (None or Some s), parse_html_col_span produces a valid span in [1, 1000]. *)
Theorem parse_html_col_span_valid : forall raw : option Z,
  valid_col_span (parse_html_col_span raw).
Proof.
  intros [s | ].
  - rewrite parse_some_eq_clamp. apply clamp_span_bounds.
  - unfold parse_html_col_span, valid_col_span, kDefaultColSpan, kMinColSpan, kMaxColSpan.
    lia.
Qed.

(** ** 4. Structural Colgroup and Grid Generation Theorems *)

(** Theorem 9: Single <col> Element Bounds. *)
Theorem eval_col_span_bounds : forall c : ColElement,
  1 <= eval_col_span c <= 1000.
Proof.
  intros