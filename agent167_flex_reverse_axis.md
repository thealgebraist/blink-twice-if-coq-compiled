### 1. Coordinate Mapping for Reverse Direction

In Chromium Blink’s Flexbox layout implementation (specifically within `NGFlexLayoutAlgorithm` / `FlexLayoutAlgorithm` and `FlexLine`), items are initially laid out along the main axis assuming a standard progression (`main-start` to `main-end` as $0 \to W_{\text{line}}$). When `flex-direction` is `row-reverse` or `column-reverse` (CSS Flexbox 1 §5.1), the main-start and main-end directions are swapped.

Rather than duplicating the core layout distribution arithmetic for negative progression, Blink computes the normal main-axis offsets first and applies an affine reflection transformation across the container's main-axis content-box size $W_{\text{line}}$ (`main_axis_content_size`).

For a flex item $i$ with normal main-axis offset $x_{\text{normal}, i}$ and main-axis margin-box size $W_{\text{item}, i}$, its physical/logical offset from the non-reversed origin in the reverse direction $x_{\text{rev}, i}$ is given by:

$$x_{\text{rev}, i} = W_{\text{line}} - (x_{\text{normal}, i} + W_{\text{item}, i})$$

**Geometric Interpretation:**
* $x_{\text{normal}, i}$ represents the distance from the normal `main-start` edge to the item's leading edge.
* In a reversed flex line, the normal `main-end` edge becomes the new `main-start` edge (at coordinate $W_{\text{line}}$).
* The item's leading edge must be placed at a distance of $x_{\text{normal}, i}$ from this new `main-start` edge, which puts its trailing edge in the normal coordinate system at $W_{\text{line}} - x_{\text{normal}, i}$.
* Subtracting the item's extent $W_{\text{item}, i}$ yields the coordinate of the item's new leading edge in the normal coordinate frame: $W_{\text{line}} - x_{\text{normal}, i} - W_{\text{item}, i}$.

---

### 2. Formal Invariants

Let a flex line of extent $W_{\text{line}} \ge 0$ contain $n$ items. Each item $i \in \{0, \dots, n-1\}$ occupies a half-open interval $I_{\text{normal}, i} = [x_i, x_i + w_i)$ under normal progression, where $x_i = x_{\text{normal}, i}$ and $w_i = W_{\text{item}, i} \ge 0$. Under the reverse mapping, item $i$ occupies $I_{\text{rev}, i} = [x'_i, x'_i + w_i)$, where $x'_i = W_{\text{line}} - (x_i + w_i)$.

#### Invariant 2.1: Order Reversal and Disjointness
If the normal layout places items sequentially without overlap:
$$\forall i < j, \quad x_i + w_i \le x_j$$
Then in the reverse layout, their relative order is strictly inverted and their intervals remain disjoint:
$$\forall i < j, \quad x'_j + w_j \le x'_i$$
*Proof Sketch:* Since $x_i + w_i \le x_j$, multiplying by $-1$ and adding $W_{\text{line}}$ yields $W_{\text{line}} - x_j \le W_{\text{line}} - (x_i + w_i)$. Recognizing that $x'_j + w_j = W_{\text{line}} - (x_j + w_j) + w_j = W_{\text{line}} - x_j$, we substitute to get $x'_j + w_j \le x'_i$. Thus, $I_{\text{rev}, j}$ precedes $I_{\text{rev}, i}$ with no overlap.

#### Invariant 2.2: Boundary Conformance (Containment)
If all items in the normal layout are contained within the flex line $[0, W_{\text{line}}]$:
$$0 \le x_i \quad \land \quad x_i + w_i \le W_{\text{line}}$$
Then the reversed items are also strictly contained within $[0, W_{\text{line}}]$:
$$0 \le x'_i \quad \land \quad x'_i + w_i \le W_{\text{line}}$$

#### Invariant 2.3: Preservation of Total Occupied Span
For a non-empty sequentially ordered list of items $[0, \dots, n-1]$, the total bounding span from the outer leading edge of the first-placed item to the outer trailing edge of the last-placed item is invariant under axis reversal:
$$\text{Span}_{\text{normal}} = (x_{n-1} + w_{n-1}) - x_0$$
$$\text{Span}_{\text{rev}} = (x'_0 + w_0) - x'_{n-1}$$
$$\text{Span}_{\text{rev}} = (W_{\text{line}} - x_0) - (W_{\text{line}} - (x_{n-1} + w_{n-1})) = (x_{n-1} + w_{n-1}) - x_0 = \text{Span}_{\text{normal}}$$
Furthermore, the sum of individual item widths $\sum_{i=0}^{n-1} w_i$ and the inter-item gaps $(x_{i+1} - (x_i + w_i)) = (x'_i - (x'_{i+1} + w_{i+1}))$ are identically preserved.

---

### 3. Rocq / Coq Formalization (`BlinkFlexReverseAxisSemantics.v`)

The following file is self-contained and compiles cleanly in Coq/Rocq (8.16+ / 8.18+ / 9.0).

```coq
(** * BlinkFlexReverseAxisSemantics.v
    Formal Audit of Chromium Blink Flex Reverse Main Axis Placement
    against CSS Flexible Box Layout Module Level 1, Section 5.1.
    Agent 167 Verification Artifact. *)

From Coq Require Import ZArith.
From Coq Require Import List.
From Coq Require Import Lia.
Import ListNotations.

Open Scope Z_scope.

(** ** 1. Data Definitions & Coordinate Mapping *)

(** A FlexItem is represented by its normal main-axis offset [x_norm]
    and its main-axis margin-box size [w_item]. *)
Record FlexItem : Type := mkItem {
  x_norm : Z;
  w_item : Z
}.

(** The reverse main-axis coordinate transformation:
    x_rev = W_line - (x_norm + w_item) *)
Definition reverse_coord (W_line : Z) (it : FlexItem) : Z :=
  W_line - (x_norm it + w_item it).

(** Transform an item into its reversed placement state. *)
Definition reverse_item (W_line : Z) (it : FlexItem) : FlexItem :=
  mkItem (reverse_coord W_line it) (w_item it).

(** Start and end edges of an item's interval [start, end). *)
Definition item_start (it : FlexItem) : Z := x_norm it.
Definition item_end   (it : FlexItem) : Z := x_norm it + w_item it.

(** ** 2. Predicates & Layout Invariants *)

(** An item has a non-negative size. *)
Definition valid_item (it : FlexItem) : Prop :=
  0 <= w_item it.

(** An item lies completely within the flex line [0, W_line]. *)
Definition within_line (W_line : Z) (it : FlexItem) : Prop :=
  0 <= item_start it /\ item_end it <= W_line.

(** Item [a] precedes item [b] without overlapping: end(a) <= start(b). *)
Definition precedes_disjoint (a b : FlexItem) : Prop :=
  item_end a <= item_start b.

(** Two items are disjoint if one precedes the other. *)
Definition disjoint (a b : FlexItem) : Prop :=
  precedes_disjoint a b \/ precedes_disjoint b a.

(** Inductive predicate for a list of items ordered sequentially left-to-right. *)
Inductive sequentially_ordered : list FlexItem -> Prop :=
  | so_nil  : sequentially_ordered []
  | so_sing : forall x, sequentially_ordered [x]
  | so_cons : forall x y l,
      precedes_disjoint x y ->
      sequentially_ordered (y :: l) ->
      sequentially_ordered (x :: y :: l).

(** Inductive predicate for a list of items ordered sequentially in reverse
    (right-to-left: each element's interval is to the right of the next). *)
Inductive reverse_ordered : list FlexItem -> Prop :=
  | ro_nil  : reverse_ordered []
  | ro_sing : forall x, reverse_ordered [x]
  | ro_cons : forall x y l,
      precedes_disjoint y x ->
      reverse_ordered (y :: l) ->
      reverse_ordered (x :: y :: l).

(** Total occupied bounding span for a non-empty list of items, given a
    first-placed item [first_it] and last-placed item [last_it]. *)
Definition bounding_span (first_it last_it : FlexItem) : Z :=
  item_end last_it - item_start first_it.

(** Sum of individual widths of all items in a flex line. *)
Fixpoint total_item_measure (l : list FlexItem) : Z :=
  match l with
  | [] => 0
  | it :: rest => w_item it + total_item_measure rest
  end.

(** ** 3. Core Verification Theorems *)

(** Theorem 1: Reversing twice is the identity transformation (Involution). *)
Theorem reverse_item_involution : forall (W_line : Z) (it : FlexItem),
  reverse_item W_line (reverse_item W_line it) = it.
Proof.
  intros W_line [x w].
  unfold reverse_item, reverse_coord; simpl.
  f_equal; lia.
Qed.

(** Theorem 2: The trailing edge of a reversed item is at W_line - x_norm. *)
Lemma reverse_item_end : forall (W_line : Z) (it : FlexItem),
  item_end (reverse_item W_line it) = W_line - item_start it.
Proof.
  intros W_line [x w].
  unfold item_end, item_start, reverse_item, reverse_coord; simpl.
  lia.
Qed.

(** Theorem 3: Containment within [0, W_line] is preserved under reversal. *)
Theorem reverse_preserves_within_line : forall (W_line : Z) (it : FlexItem),
  within_line W_line it ->
  within_line W_line (reverse_item W_line it).
Proof.
  intros W_line [x w] [Hstart Hend].
  unfold within_line, item_start, item_end in *; simpl in *.
  unfold reverse_coord; simpl.
  split; lia.
Qed.

(** Theorem 4: Pairwise order is strictly inverted and disjointness is preserved. *)
Theorem reverse_inverts_precedence : forall (W_line : Z) (a b : FlexItem),
  precedes_disjoint a b ->
  precedes_disjoint (reverse_item W_line b) (reverse_item W_line a).
Proof.
  intros W_line [xa wa] [xb wb] Hab.
  unfold precedes_disjoint, item_start, item_end in *; simpl in *.
  unfold reverse_coord; simpl.
  lia.
Qed.

(** Theorem 5: Pairwise disjointness is invariant under reversal. *)
Theorem reverse_preserves_disjoint : forall (W_line : Z) (a b : FlexItem),
  disjoint a b ->
  disjoint (reverse_item W_line a) (reverse_item W_line b).
Proof.
  intros W_line a b [Hab | Hba].
  - right. apply reverse_inverts_precedence. exact Hab.
  - left. apply reverse_inverts_precedence. exact Hba.
Qed.

(** Theorem 6: Inter-item gap between adjacent items is preserved exactly. *)
Theorem reverse_preserves_inter_item_gap : forall (W_line : Z) (a b : FlexItem),
  item_start (reverse_item W_line a) - item_end (reverse_item W_line b) =
  item_start b - item_end a.
Proof.
  intros W_line [xa wa] [xb wb].
  unfold item_start, item_end, reverse_item, reverse_coord; simpl.
  lia.
Qed.

(** Theorem 7: A sequentially ordered list of items becomes reverse-ordered
    when mapped with [reverse_item]. *)
Theorem reverse_map_orders_reversely : forall (W_line : Z) (l : list FlexItem),
  sequentially_ordered l ->
  reverse_ordered (map (reverse_item W_line) l).
Proof.
  intros W_line l Hord.
  induction Hord as [ | x | x y rest Hxy Hrest IH ].
  - simpl. constructor.
  - simpl. constructor.
  - simpl. constructor.
    + apply reverse_inverts_precedence. exact Hxy.
    + exact IH.
Qed.

(** Theorem 8: Total occupied bounding span between the first and last item
    is identical between normal and reverse layouts.
    Note: In reverse layout, the last item [last_it] becomes the leftmost
    item, and [first_it] becomes the rightmost item. *)
Theorem reverse_preserves_bounding_span :
  forall (W_line : Z) (first_it last_it : FlexItem),
  bounding_span (reverse_item W_line last_it) (reverse_item W_line first_it) =
  bounding_span first_it last_it.
Proof.
  intros W_line [xf wf] [xl wl].
  unfold bounding_span, item_start, item_end, reverse_item, reverse_coord; simpl.
  lia.
Qed.

(** Theorem 9: Total measure (sum of item sizes) is invariant under reversal. *)
Theorem reverse_preserves_total_measure : forall (W_line : Z) (l : list FlexItem),
  total_item_measure (map (reverse_item W_line) l) = total_item_measure l.
Proof.
  intros W_line l.
  induction l as [ | it rest IH ]; simpl.
  - reflexivity.
  - rewrite IH. reflexivity.
Qed.
```