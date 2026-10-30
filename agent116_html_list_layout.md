### 1. Ordered (`<ol>`) & Unordered (`<ul>`) List Semantics

In Chromium Blink (`third_party/blink/renderer/core/html/html_olist_element.cc`, `list_item_ordinal.cc`, and `layout/layout_list_item.cc`), list layout is governed by the interaction between HTML §4.4.4–4.4.8 and CSS Lists and Counters Module Level 3 §3.

*   **Ordered List (`<ol>`) Counter Sequence:**
    An `<ol>` element establishes a scoped counter `list-item`. By default, without `reversed` or explicit `start`/`value` attributes, the counter is initialized to `0` at the `<ol>` root. For a sequence of $N$ child `<li>` elements indexed $k \in \{0, 1, \dots, N-1\}$, each `<li>` increments the `list-item` counter by $1$ upon entry (`counter-increment: list-item 1`). Consequently, the $k$-th `<li>` (0-indexed) receives the ordinal value:
    $$\text{ordinal}(k) = \text{start} + k = 1 + k \in \{1, 2, \dots, N\}$$
    Blink computes this lazily via `ListItemOrdinal::Value()`, traversing the DOM in tree order to resolve ordinals and invalidating downstream items when DOM mutations occur.
*   **Unordered List (`<ul>`) Bullet Marker:**
    A `<ul>` element groups `<li>` items without numerical ordering. In Blink's `LayoutListMarker` / `ListMarker`, when `list-style-type` is `disc` (default for level 1 `<ul>`), `circle`, or `square`, the marker is rendered as a glyph or geometric path rather than a formatted counter string. While `<li>` elements inside a `<ul>` still technically increment the `list-item` counter per CSS Lists 3 §3.4 unless suppressed, the marker's visual representation (`MarkerType::kStaticSymbol`) ignores the counter value and renders a static bullet glyph.

---

### 2. Marker Indentation and List Padding

Per HTML §15.3.4 (Rendering: Lists) and Blink’s default user-agent stylesheet (`html.css`):

```css
ul, menu, dir {
    display: block;
    list-style-type: disc;
    margin-block-start: 1em;
    margin-block-end: 1em;
    padding-inline-start: 40px;
}
ol {
    display: block;
    list-style-type: decimal;
    margin-block-start: 1em;
    margin-block-end: 1em;
    padding-inline-start: 40px;
}
li {
    display: list-item;
}
```

*   **List Padding:** Both `<ol>` and `<ul>` apply a default `padding-inline-start: 40px` (40 CSS pixels on the left in `ltr` horizontal writing modes). The content box of the list—and therefore the inline-start edge of all child `<li>` border/content boxes— begins at $x = 40\text{px}$ relative to the list's border box.
*   **Marker Box Positioning (`outside` vs. `inside`):**
    By default, `list-style-position` is `outside`. Blink generates a `::marker` pseudo-element as the first child of the `<li>` (`LayoutOutsideListMarker`). During block/inline layout (`ng_unpositioned_list_marker.cc`), the outside marker is taken out of normal inline flow and positioned in the negative inline-start direction relative to the `<li>` principal box. Specifically, if the `<li>` starts at $x_{\text{li}} = 40\text{px}$ and the marker has inline advance width $w_m$ (including its trailing margin/suffix space), the marker is placed at:
    $$x_m = x_{\text{li}} - w_m = 40\text{px} - w_m$$
    Thus, the marker occupies the interval $[40 - w_m, 40]$ within the parent list's 40px inline-start padding region.

---

### 3. Core Layout Invariants

1.  **Strictly Increasing Counter Invariant (`<ol>`):**
    For any non-reversed `<ol>` without mid-list `@value` overrides, for all list item indices $i, j$ where $0 \le i < j < N$, the resolved ordinal satisfies $\text{ordinal}(i) < \text{ordinal}(j)$, and specifically $\text{ordinal}(i+1) = \text{ordinal}(i) + 1$.
2.  **Marker Padding-Box Containment Invariant:**
    Assuming `list-style-position: outside`, `padding-inline-start` $P = 40\text{px}$, and a marker inline width $w_m \le P$, the marker's horizontal bounding interval $[x_m, x_m + w_m]$ lies strictly within the parent list's padding area $[0, P]$, never overflowing the list's inline-start border edge ($x_m \ge 0$) or overlapping the `<li>` principal content box ($x_m + w_m \le x_{\text{li}}$).
3.  **List Item Vertical Stacking Invariant:**
    In normal block flow (`writing-mode: horizontal-tb`) with non-negative vertical margins and positive item heights $h_k > 0$, child `<li>` boxes stack monotonically along the block (Y) axis. For consecutive items $k$ and $k+1$:
    $$y_{k+1} \ge y_k + h_k > y_k$$
    ensuring disjoint vertical bounding intervals $[y_k, y_k + h_k)$ and $[y_{k+1}, y_{k+1} + h_{k+1})$.

---

### 4. Formal Verification: `BlinkHTMLListLayoutSemantics.v`

The following Coq development formalizes the DOM list model, Blink's layout geometry computation, and proves the three core invariants without axioms or unfinished proofs.

```coq
(** * BlinkHTMLListLayoutSemantics.v
    Formal verification of Chromium Blink List Item Layout against
    HTML §4.4.4-4.4.8 and CSS Lists Module Level 3 §3. *)

Require Import Coq.Lists.List.
Require Import Coq.Arith.Arith.
Require Import Coq.micromega.Lia.
Import ListNotations.

(** ** 1. DOM and Style Primitives *)

Inductive ListKind : Type :=
  | OL : nat -> ListKind (** Ordered list with start value (default 1) *)
  | UL : ListKind.       (** Unordered list *)

Inductive MarkerStylePosition : Type :=
  | Outside : MarkerStylePosition
  | Inside  : MarkerStylePosition.

Inductive MarkerContent : Type :=
  | OrdinalMarker : nat -> MarkerContent
  | BulletMarker  : MarkerContent.

(** Input specification for a single <li> element before layout *)
Record ListItemSpec : Type := mkListItemSpec {
  li_height       : nat; (** Computed block size (height) of the <li> *)
  li_marker_width : nat  (** Computed inline size of the ::marker box + margin *)
}.

(** Input specification for a parent <ol> or <ul> container *)
Record ListContainerSpec : Type := mkListContainerSpec {
  lc_kind          : ListKind;
  lc_padding_start : nat; (** Default UA stylesheet: 40px *)
  lc_marker_pos    : MarkerStylePosition;
  lc_items         : list ListItemSpec
}.

(** Default UA padding constant per HTML §15.3.4 / Blink html.css *)
Definition UA_DEFAULT_LIST_PADDING : nat := 40.

(** ** 2. Layout Output Boxes *)

Record Box2D : Type := mkBox2D {
  box_x : nat;
  box_y : nat;
  box_w : nat;
  box_h : nat
}.

Record LayoutListItem : Type := mkLayoutListItem {
  lli_index      : nat;           (** 0-based child index k *)
  lli_marker     : MarkerContent; (** Resolved marker content *)
  lli_marker_box : Box2D;         (** Positioned ::marker box *)
  lli_item_box   : Box2D          (** Principal <li> border/content box *)
}.

(** ** 3. Blink List Layout Semantics *)

(** Resolve marker content for the k-th list item (0-indexed) *)
Definition resolve_marker (kind : ListKind) (k : nat) : MarkerContent :=
  match kind with
  | OL start_val => OrdinalMarker (start_val + k)
  | UL           => BulletMarker
  end.

(** Extract the numeric ordinal if the marker is an OrdinalMarker *)
Definition get_ordinal (m : MarkerContent) : option nat :=
  match m with
  | OrdinalMarker n => Some n
  | BulletMarker    => None
  end.

(** Compute layout for a single <li> at index k, vertical offset cur_y *)
Definition layout_single_item
  (kind : ListKind)
  (padding_start : nat)
  (pos : MarkerStylePosition)
  (k : nat)
  (cur_y : nat)
  (container_w : nat)
  (spec : ListItemSpec) : LayoutListItem :=
  let m_content := resolve_marker kind k in
  let mw := li_marker_width spec in
  let h  := li_height spec in
  match pos with
  | Outside =>
      (** Outside marker is placed in the padding area to the left of the <li> box *)
      let marker_x := padding_start - mw in
      let m_box := mkBox2D marker_x cur_y mw h in
      let i_box := mkBox2D padding_start cur_y container_w h in
      mkLayoutListItem k m_content m_box i_box
  | Inside =>
      (** Inside marker is placed at the start of the <li> box *)
      let m_box := mkBox2D padding_start cur_y mw h in
      let i_box := mkBox2D padding_start cur_y container_w h in
      mkLayoutListItem k m_content m_box i_box
  end.

(** Fold over all <li> specs to stack them vertically along the block axis *)
Fixpoint layout_items_aux
  (kind : ListKind)
  (padding_start : nat)
  (pos : MarkerStylePosition)
  (k : nat)
  (cur_y : nat)
  (container_w : nat)
  (specs : list ListItemSpec) : list LayoutListItem :=
  match specs with
  | [] => []
  | spec :: rest =>
      let item := layout_single_item kind padding_start pos k cur_y container_w spec in
      let next_y := cur_y + li_height spec in
      item :: layout_items_aux kind padding_start pos (S k) next_y container_w rest
  end.

Definition layout_list (container_w : nat) (c : ListContainerSpec) : list LayoutListItem :=
  layout_items_aux (lc_kind c) (lc_padding_start c) (lc_marker_pos c) 0 0 container_w (lc_items c).

(** ** 4. Proofs of Core Layout Invariants *)

(** *** Invariant 1: Ordered List (<ol>) Counter Sequence & Strict Monotonicity *)

Lemma layout_items_aux_length :
  forall kind pad pos k y cw specs,
    length (layout_items_aux kind pad pos k y cw specs) = length specs.
Proof.
  intros kind pad pos k y cw specs.
  revert k y.
  induction specs as [| s rest IH]; intros k y; simpl.
  - reflexivity.
  - f_equal. apply IH.
Qed.

Lemma layout_items_aux_nth_marker :
  forall kind pad pos k y cw specs idx d,
    idx < length specs ->
    lli_marker (nth idx (layout_items_aux kind pad pos k y cw specs) d) =
    resolve_marker kind (k + idx).
Proof.
  intros kind pad pos k y cw specs.
  revert k y.
  induction specs as [| s rest IH]; intros k y idx d Hlt; simpl in *.
  - lia.
  - destruct idx as [| idx'].
    + simpl. f_equal. lia.
    + simpl. rewrite IH by lia. f_equal. lia.
Qed.

(** Theorem 1A: In a default <ol> (start = 1), the k-th item (0-indexed)
    receives ordinal k + 1 (i.e., 1, 2, ..., N). *)
Theorem ol_default_ordinal_sequence :
  forall pad pos cw specs idx d,
    idx < length specs ->
    let c := mkListContainerSpec (OL 1) pad pos specs in
    lli_marker (nth idx (layout_list cw c) d) = OrdinalMarker (1 + idx).
Proof.
  intros pad pos cw specs idx d Hlt c.
  unfold layout_list, c. simpl.
  rewrite layout_items_aux_nth_marker by assumption.
  simpl. reflexivity.
Qed.

(** Theorem 1B: In any <ol>, ordinals are strictly increasing with item index. *)
Theorem ol_counter_strictly_increasing :
  forall start_val pad pos cw specs i j d,
    i < j ->
    j < length specs ->
    let c := mkListContainerSpec (OL start_val) pad pos specs in
    let items := layout_list cw c in
    exists ord_i ord_j,
      get_ordinal (lli_marker (nth i items d)) = Some ord_i /\
      get_ordinal (lli_marker (nth j items d)) = Some ord_j /\
      ord_i < ord_j.
Proof.
  intros start_val pad pos cw specs i j d Hij Hj c items.
  unfold items, layout_list, c. simpl.
  rewrite layout_items_aux_nth_marker by lia.
  rewrite layout_items_aux_nth_marker by lia.
  simpl.
  exists (start_val + i), (start_val + j).
   repeat split; lia.
Qed.

(** Theorem 1C: In any <ul>, every item receives a BulletMarker. *)
Theorem ul_all_bullet_markers :
  forall pad pos cw specs idx d,
    idx < length specs ->
    let c := mkListContainerSpec UL pad pos specs in
    lli_marker (nth idx (layout_list cw c) d) = BulletMarker.
Proof.
  intros pad pos cw specs idx d Hlt c.
  unfold layout_list, c. simpl.
  rewrite layout_items_aux_nth_marker by assumption.
  simpl. reflexivity.
Qed.

(** *** Invariant 2: Marker Fits Inside List Padding Box *)

(** Predicates for horizontal containment in [0, padding_start] *)
Definition