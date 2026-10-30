# Formal Verification Report: Agent 695
**Topic:** Collapsed Table Border Conflict Resolution: Border Width and Style Precedence  
**Chromium Source:** `third_party/blink/renderer/core/layout/table/table_borders.cc`  
**Specification:** CSS 2.1 §17.6.2.1 (Border Conflict Resolution) & CSS Table Module Level 3  
**Formal Theory Target:** `BlinkTableCollapsedBorderWidthStylePrecedenceSemantics.v`  
**Mathematical Property:** $\text{border\_priority}(b) = (b.\text{is\_hidden}, b.\text{width}, b.\text{style\_precedence}, b.\text{source\_precedence})$; strict/total lexicographical maximization.

---

## 1. Normative W3C Specification Requirements

In the CSS collapsing border model (`border-collapse: collapse`), adjacent table elements (cells, rows, row groups, columns, column groups, and the table itself) share borders at their common edges. Because each element may specify distinct border styles, widths, and colors for the shared edge, CSS 2.1 Section 17.6.2.1 defines a deterministic conflict resolution algorithm to select the winning border at every edge segment:

1. **Rule 1 (Suppression via `hidden`):** Borders with the `border-style` of `hidden` suppress all other borders at the shared edge. If any competing border has style `hidden`, the resolved border is `none` (width `0`), inhibiting rendering at that edge.
2. **Rule 2 (De-prioritization of `none`):** Borders with a style of `none` have the lowest priority. Only if *all* competing borders at an edge have style `none` (or effective width `0` without `hidden`) will the resulting edge be omitted.
3. **Rule 3 (Width and Style Precedence):** If none of the styles are `hidden` and at least one is not `none`, then narrow borders are discarded in favor of wider ones. If several competing borders have the same `border-width`, then styles are preferred in the following strictly decreasing order of precedence:
   $$\texttt{double} > \texttt{solid} > \texttt{dashed} > \texttt{dotted} > \texttt{ridge} > \texttt{outset} > \texttt{groove} > \texttt{inset}$$
4. **Rule 4 (Element Source Precedence):** If border styles and widths are identical among the top contenders, the winner is chosen by the structural type of the element declaring the border, in decreasing order:
   $$\texttt{cell} > \texttt{row} > \texttt{row group} > \texttt{column} > \texttt{column group} > \texttt{table}$$
   If two elements of the same type conflict (e.g., two adjacent cells), the one further to the left (in `ltr` inline progression) or further to the top (in `tb` block progression) wins.

---

## 2. Blink Implementation Details and Invariants

In Chromium Blink's LayoutNG table architecture (`third_party/blink/renderer/core/layout/table/table_borders.cc`), border conflict resolution is computed during the construction of `TableBorders` via `TableBorders::ComputeCollapsedBorders`. Each edge in the table grid is represented as a slot in a flat vector of `BoxSide` edges, populated by sequentially merging candidate borders from cells, sections, rows, columns, and the table frame.

### Core Data Structures and Precedence Mapping

Blink maps `EBorderStyle` to numerical precedence values or compares them directly via `CompareBorders`:

```cpp
// Conceptual mapping inside third_party/blink/renderer/core/layout/table/table_borders.cc
enum class EBorderStylePrecedence {
  kNone = 0,
  kInset = 1,
  kGroove = 2,
  kOutset = 3,
  kRidge = 4,
  kDotted = 5,
  kDashed = 6,
  kSolid = 7,
  kDouble = 8,
  kHidden = 9
};
```

### Algorithmic Invariants in `table_borders.cc`

1. **Effective Width Normalization:** Before comparing widths, if a border's style is `EBorderStyle::kNone` or `EBorderStyle::kHidden`, its effective visual width for layout purposes is `0`, though `kHidden` retains its supreme precedence flag during comparison. Conversely, if a border has a non-`kHidden` style (e.g., `kSolid`) but its specified width is `0px`, Blink treats it as absent/non-winning against any visible border, while preserving `kHidden`'s ability to suppress borders regardless of its specified `border-width` property.
2. **Lexicographical Tuple Comparison:** When `MergeBorder` evaluates an existing edge candidate $b_1$ against a newly encountered candidate $b_2$ (where $b_1$ was emitted by an element with higher or equal structural source precedence due to traversal order):
   - First, check if either border is `kHidden`. If so, the `kHidden` border unconditionally dominates.
   - Second, compare resolved `width` (in layout units / pixels). The strictly wider border wins.
   - Third, if widths are equal, compare `EBorderStyle` according to Rule 3.
   - Fourth, if styles are also equal, the traversal order invariant ensures that candidates are visited in source precedence order (`kCell`, `kRow`, `kRowGroup`, `kColumn`, `kColumnGroup`, `kTable`), or via explicit source priority tags. Thus, $b_1$ is retained on ties.
3. **Associativity and Idempotence:** Because the conflict resolution relation defines a strict weak order (and a total order when augmented with unique traversal/source indices), iterative pairwise reduction over a non-empty list of candidate borders is associative, commutative (with explicit source tags), and yields the unique maximum element.

---

## 3. Formal Specification in Rocq/Coq

Below is the complete, self-contained formalization of `BlinkTableCollapsedBorderWidthStylePrecedenceSemantics.v`. It models CSS border styles, element sources, border structures, normalization invariants, the tuple-based priority metric, and Blink's operational `resolve_border_conflict` function.

```coq
(** * BlinkTableCollapsedBorderWidthStylePrecedenceSemantics.v
    Formal Verification of W3C CSS 2.1 §17.6.2.1 & Blink Table Borders
    Source: third_party/blink/renderer/core/layout/table/table_borders.cc *)

From Coq Require Import ZArith.
From Coq Require Import Lia.
From Coq Require Import Bool.
From Coq Require Import List.
Import ListNotations.

Open Scope Z_scope.

(** ** 1. Border Style and Source Precedence Enumerations *)

Inductive BorderStyle : Type :=
  | BS_None
  | BS_Inset
  | BS_Groove
  | BS_Outset
  | BS_Ridge
  | BS_Dotted
  | BS_Dashed
  | BS_Solid
  | BS_Double
  | BS_Hidden.

Scheme Equality for BorderStyle.

(** Maps BorderStyle to its CSS 2.1 §17.6.2.1 numerical style precedence. *)
Definition style_precedence (s : BorderStyle) : Z :=
  match s with
  | BS_None   => 0
  | BS_Inset  => 1
  | BS_Groove => 2
  | BS_Outset => 3
  | BS_Ridge  => 4
  | BS_Dotted => 5
  | BS_Dashed => 6
  | BS_Solid  => 7
  | BS_Double => 8
  | BS_Hidden => 9
  end.

Definition is_hidden (s : BorderStyle) : bool :=
  match s with
  | BS_Hidden => true
  | _ => false
  end.

Definition is_hidden_Z (s : BorderStyle) : Z :=
  if is_hidden s then 1 else 0.

(** CSS 2.1 §17.6.2.1 Rule 4: Element source type precedence. *)
Inductive BorderSource : Type :=
  | Src_Table
  | Src_ColGroup
  | Src_Col
  | Src_RowGroup
  | Src_Row
  | Src_Cell.

Scheme Equality for BorderSource.

Definition source_precedence (src : BorderSource) : Z :=
  match src with
  | Src_Table    => 0
  | Src_ColGroup => 1
  | Src_Col      => 2
  | Src_RowGroup => 3
  | Src_Row      => 4
  | Src_Cell     => 5
  end.

(** ** 2. Collapsed Border Representation and Well-Formedness *)

Record CollapsedBorder : Type := mkBorder {
  b_style  : BorderStyle;
  b_width  : Z;            (** Resolved layout width in subpixels/px (>= 0) *)
  b_source : BorderSource; (** Originating table box type *)
  b_order  : Z             (** Tie-breaker for spatial/DOM order (higher = earlier/left/top) *)
}.

(** In Blink, a border's effective width is 0 if its style is 'none' or 'hidden',
    and non-negative for all styles. *)
Definition EffectiveWidth (b : CollapsedBorder) : Z :=
  match b.(b_style) with
  | BS_None | BS_Hidden => 0
  | _ => Z.max 0 b.(b_width)
  end.

(** Well-formedness predicate for a normalized Blink CollapsedBorder candidate. *)
Definition WF_Border (b : CollapsedBorder) : Prop :=
  b.(b_width) >= 0 /\
  (b.(b_style) = BS_None -> b.(b_width) = 0) /\
  (b.(b_style) = BS_Hidden -> b.(b_width) = 0).

(** Normalize any raw border into a well-formed Blink border candidate. *)
Definition normalize_border (b : CollapsedBorder) : CollapsedBorder :=
  mkBorder
    b.(b_style)
    (EffectiveWidth b)
    b.(b_source)
    b.(b_order).

(** ** 3. Mathematical Priority Tuple and Lexicographical Order *)

(** Priority tuple:
    1. is_hidden (0 or 1)
    2. effective width (>= 0)
    3. style_precedence (0..9)
    4. source_precedence (0..5)
    5. spatial/DOM tie-breaker order *)
Definition BorderPriority : Type := (Z * Z * Z * Z * Z)%type.

Definition border_priority (b : CollapsedBorder) : BorderPriority :=
  (is_hidden_Z b.(b_style),
   EffectiveWidth b,
   style_precedence b.(b_style),
   source_precedence b.(b_source),
   b.(b_order)).

(** Lexicographical comparison of 5-tuples: returns true iff p1 >= p2 *)
Definition priority_ge_bool (p1 p2 : BorderPriority) : bool :=
  let '(h1, w1, s1, src1, o1) := p1 in
  let '(h2, w2, s2, src2, o2) := p2 in
  if Z.gtb h1 h2 then true
  else if Z.ltb h1 h2 then false
  else if Z.gtb w1 w2 then true
  else if Z.ltb w1 w2 then false
  else if Z.gtb s1 s2 then true
  else if Z.ltb s1 s2 then false
  else if Z.gtb src1 src2 then true
  else if Z.ltb src1 src2 then false
  else Z.geb o1 o2.

(** Propositional lexicographical non-strict inequality (p1 >= p2) *)
Definition priority_ge (p1 p2 : BorderPriority) : Prop :=
  let '(h1, w1, s1, src1, o1) := p1 in
  let '(h2, w2, s2, src2, o2) := p2 in
  h1 > h2 \/
  (h1 = h2 /\ w1 > w2) \/
  (h1 = h2 /\ w1 = w2 /\ s1 > s2) \/
  (h1 = h2 /\ w1 = w2 /\ s1 = s2 /\ src1 > src2) \/
  (h1 = h2 /\ w1 = w2 /\ s1 = s2 /\ src1 = src2 /\ o1 >= o2).

(** Propositional lexicographical strict inequality (p1 > p2) *)
Definition priority_gt (p1 p2 : BorderPriority) : Prop :=
  let '(h1, w1, s1, src1, o1) := p1 in
  let '(h2, w2, s2, src2, o2) := p2 in
  h1 > h2 \/
  (h1 = h2 /\ w1 > w2) \/
  (h1 = h2 /\ w1 = w2 /\ s1 > s2) \/
  (h1 = h2 /\ w1 = w2 /\ s1 = s2 /\ src1 > src2) \/
  (h1 = h2 /\ w1 = w2 /\ s1 = s2 /\ src1 = src2 /\ o1 > o2).

(** ** 4. Blink Operational Conflict Resolution Function *)

(** Mirrors `CompareBorders` / `MergeBorder` in `table_borders.cc`:
    If `b1` has priority >= `b2`, keep `b1`; otherwise select `b2`. *)
Definition resolve_pair (b1 b2 : CollapsedBorder) : CollapsedBorder :=
  if priority_ge_bool (border_priority b1) (border_priority b2)
  then b1
  else b2.

(** Iterative border conflict resolution over a list of competing borders,
    starting from a default `none` table border. *)
Definition default_border : CollapsedBorder :=
  mkBorder BS_None 0 Src_Table 0.

Definition resolve_list (candidates : list CollapsedBorder) : CollapsedBorder :=
  fold_left resolve_pair candidates default_border.
```

---

## 4. Concrete Theorems and Complete Rocq/Coq Proofs

The following block contains the complete, self-contained verification proofs establishing well-formedness preservation, equivalence between boolean operational semantics and propositional priority ordering, total pre-order properties (reflexivity, transitivity, totality, antisymmetry), CSS 2.1 §17.6.2.1 rule compliance (`hidden` dominance, `width` dominance, `style` dominance, `source` dominance), and list-level maximization invariants.

```coq
(** ** 5. Formal Verification Theorems and Proofs *)

(** *** Theorem 1: Normalization establishes Well-Formedness *)
Theorem normalize_border_wf : forall b : CollapsedBorder,
  WF_Border (normalize_border b).
Proof.
  intros [st w src ord].
  unfold normalize_border, WF_Border, EffectiveWidth; simpl.
  destruct st; repeat split; try lia; intros Hdisc; discriminate.
Qed.

(** *** Theorem 2: Equivalence of Boolean and Propositional Priority Order *)
Theorem priority_