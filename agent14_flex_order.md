### 1. Core Data Structures in Blink Flex Child Ordering

In Chromium’s Blink LayoutNG engine, the CSS Flexible Box Layout Level 1 §5.4 (`order` property) is realized before flex line construction and main-axis space distribution. The separation of concerns between the DOM tree (document order) and layout calculation (flex order) is governed by the following core structures located primarily within `third_party/blink/renderer/core/layout/flex/`:

#### `LayoutInputNode` / `BlockNode`
Represents a generalized layout box input to a LayoutNG algorithm. During flex child collection, the parent `FlexLayoutAlgorithm` iterates over its immediate DOM children via `LayoutInputNode::NextSibling()`. At this stage, nodes are strictly in **DOM / Box-Tree Order**.

#### `FlexChildIterator`
Defined in `flex_child_iterator.h` and `flex_child_iterator.cc`, this structure acts as the translation layer between the raw box-tree sibling traversal and the `order`-modified layout sequence.
* **Internal Representation**: Contains a `HeapVector<Entry>` (or `Vector<Entry>`), where each `Entry` is a lightweight struct:
  ```cpp
  struct Entry {
    BlockNode child;
    int order;
    // Note: original_index is either stored explicitly when using non-stable sort
    // or implicitly preserved by the vector index when using std::stable_sort.
  };
  ```
* **Role**: Upon construction (`FlexChildIterator(const BlockNode container)`), it walks all in-flow and out-of-flow children of the flex container, queries `child.Style().Order()`, populates the internal vector, and sorts it if more than one distinct `order` value is observed.

#### `order` Property Integer
Extracted via `ComputedStyle::Order()`, which returns a signed 32-bit C++ `int` (`int32_t`). 
* **W3C Spec Value**: `<integer>`, initial value `0`.
* **Blink Representation**: Clamped during CSS parsing/computation to the target platform's signed 32-bit integer bounds ($[-2^{31}, 2^{31}-1]$, i.e., `INT_MIN` to `INT_MAX`).

#### `FlexItem` (`NGFlexItem`)
Once `FlexChildIterator` yields sorted `BlockNode` instances, `FlexLayoutAlgorithm::ConstructAndAppendFlexItems()` filters out out-of-flow (`position: absolute` / `fixed`) children and constructs `FlexItem` objects for in-flow children. These are appended to the `FlexLineBuilder` / `Vector<FlexItem>` in the exact sequence emitted by `FlexChildIterator`. Thus, all subsequent §9 Flex Layout Algorithm phases (line breaking, flexible length resolution, cross-axis alignment) operate natively on the `order`-permuted sequence without needing to re-query `Style().Order()`.

---

### 2. Sorting Algorithm and Lexicographical Tuple Semantics

According to W3C CSS Flexbox §5.4:
> *"Flex items are, by default, displayed and laid out in the same order as they appear in the source document. The `order` property may be used to change this ordering... A flex container lays out its content in order-modified document order, starting from the lowest numbered ordinal group and going up. Items with the same ordinal group are laid out in the order they appear in the source document."*

#### Blink's Sorting Realization
During `FlexChildIterator` initialization:
1. **Collection & Fast-Path Detection**: As children $c_0, c_1, \dots, c_{n-1}$ are collected in document order, Blink tracks whether all children share the same `order` value (typically `0`). If `is_all_same_order` holds true, the sorting step is bypassed entirely ($O(n)$ collection, $O(1)$ sort overhead).
2. **Lexicographical Key Formulation**: Each child $i \in \{0, \dots, n-1\}$ is assigned a conceptual tuple:
   $$K_i = (\text{order}_i, i) \in \mathbb{Z}_{32} \times \mathbb{N}$$
   where $\text{order}_i = \text{Style}(c_i).\text{Order}()$ and $i$ is the 0-based document-order index.
3. **Algorithm**: Blink invokes `std::stable_sort` on the `children_` vector using a comparator targeting only the `order` field:
   ```cpp
   std::stable_sort(children_.begin(), children_.end(),
                    [](const Entry& a, const Entry& b) {
                      return a.order < b.order;
                    });
   ```
   *(Note: In earlier revisions or specialized vector implementations where `std::sort` was used instead of `std::stable_sort`, `Entry` explicitly stored `wtf_size_t original_index` and compared `a.order != b.order ? a.order < b.order : a.original_index < b.original_index`.)*

Mathematically, both `std::stable_sort` on $\text{order}$ and `std::sort` on $(\text{order}, \text{original\_index})$ define the exact same strict weak ordering (which is in fact a **strict total order** because the document indices $i$ are strictly unique):
$$K_a \prec K_b \iff (\text{order}_a < \text{order}_b) \lor (\text{order}_a = \text{order}_b \land \text{index}_a < \text{index}_b)$$

---

### 3. Iterator Traversal Semantics During Flex Line Generation

Once `FlexChildIterator` finishes construction, its state consists of the immutable sorted array `children_[0 ... n-1]` and an internal cursor `position_ = 0`.

1. **Traversal API**: The algorithm consumes items via `BlockNode NextChild()`. Each call returns `children_[position_++].child` until `position_ == children_.size()`, after which it returns `BlockNode(nullptr)`.
2. **Interaction with Out-of-Flow (OOF) Boxes**: 
   * W3C §5.4 states: *"Absolutely-positioned children of a flex container are treated as having `order: 0` for the purpose of determining their painting order..."*, and §4 states they do not participate in flex layout.
   * However, in Blink, `FlexChildIterator` collects **all** immediate children (including OOF) and sorts them before OOF filtering occurs in `FlexLayoutAlgorithm`. Because OOF children do not generate `FlexItem` structs, their position in `FlexChildIterator` does not affect the relative order of in-flow `FlexItem`s (removing elements from a sorted sequence preserves the sortedness and stability of the remaining subsequence).
3. **Flex Line Generation (§9.3)**: `FlexLayoutAlgorithm` iterates linearly through `FlexChildIterator`. As each in-flow `FlexItem` is constructed, its hypothetical main size is computed. When `wrap` is enabled (`flex-wrap: wrap` or `wrap-reverse`), line-breaking decisions occur greedily on the `FlexChildIterator` stream. Thus, items in lower ordinal groups are placed on earlier flex lines (or earlier along the main-start to main-end axis within the same line).

---

### 4. Mathematical Invariants, Edge Cases, and Audit Gaps

#### Formal Invariants
Let $L_{in} = [x_0, x_1, \dots, x_{n-1}]$ be the input list of children in document order, where each item $x_k$ has a unique document index $\text{id}(x_k) = k$ and an order property $\text{ord}(x_k) \in \mathbb{Z}$. Let $L_{out} = [y_0, y_1, \dots, y_{m-1}]$ be the output sequence produced by `FlexChildIterator`.

1. **Invariant 1: Permutation Preservation (Bijection / Conservation of Items)**
   $L_{out}$ is a permutation of $L_{in}$. Consequently, $m = n$, every input node is visited **at least once** (completeness) and **at most once** (uniqueness/no duplication).
2. **Invariant 2: Monotonicity of `order`**
   For all $0 \le p < q < n$, $\text{ord}(y_p) \le \text{ord}(y_q)$.
3. **Invariant 3: Relative Document Order Stability**
   For all $0 \le p < q < n$, if $\text{ord}(y_p) = \text{ord}(y_q)$, then $\text{id}(y_p) < \text{id}(y_q)$.
4. **Combined Invariant (Strict Lexicographical Monotonicity)**
   Invariants 2 and 3 combine with the uniqueness of $\text{id}$ in $L_{in}$ to form a single strict invariant:
   $$\forall p, q \in \{0, \dots, n-1\}, \quad p < q \implies (\text{ord}(y_p) < \text{ord}(y_q)) \lor (\text{ord}(y_p) = \text{ord}(y_q) \land \text{id}(y_p) < \text{id}(y_q))$$

#### Edge Cases & Audit Gaps (Blink vs. W3C §5.4)

| Edge Case / Aspect | W3C CSS Flexbox §5.4 Specification | Chromium Blink Behavior | Audit Status / Gap Analysis |
| :--- | :--- | :--- | :--- |
| **Extreme Integer Bounds** | `<integer>` is theoretically unbounded in mathematical CSS grammar, though CSS Values & Units Level 4 mandates support up to at least $\pm 2^{30}-1$. | Clamped to `std::numeric_limits<int>::min()` ($-2147483648$) and `max()` ($2147483647$) during CSS value parsing. Subtracting `a.order - b.order` in a naive comparator would overflow, but Blink uses `<` (`a.order < b.order`), which is immune to signed integer overflow. | **Compliant (Safe)**: Direct `<` comparison avoids UB overflow on `INT_MIN` vs `INT_MAX`. Values exceeding 32-bit signed integers collapse into the same saturating ordinal group and fall back to document order. |
| **Out-of-Flow (OOF) Painting Order** | §5.4: *"Absolutely-positioned children of a flex container are treated as having `order: 0` for the purpose of determining their painting order."* | `PaintLayerStackingNode` / `BoxFragmentBuilder` handles painting order separately from `FlexChildIterator`. In `FlexChildIterator`, OOF nodes still read their actual `Style().Order()`, which dictates the order in which OOF placeholders are added to the builder. | **Subtle Architectural Nuance**: While `FlexItem` layout ignores OOF nodes, adding OOF candidates to `BoxFragmentBuilder` in `order`-modified sequence rather than treating their `order` as `0` can affect fragment tree sibling order if not normalized during paint-order sorting. |
| **`display: contents` Subtrees** | Children of a `display: contents` element within a flex container become flex items themselves; their document order is determined by a pre-order depth-first traversal of the flattened box tree. | Blink’s box construction (`LayoutTreeBuilderForElement`) flattens `display: contents` into the sibling chain of the `LayoutFlexibleBox` before `FlexChildIterator` runs. | **Compliant**: `NextSibling()` naturally yields the pre-order flattened sequence, so `original_index` accurately reflects flattened document order. |
| **Pseudo-elements (`::before`, `::after`)** | Generated content in a flex container acts as flex items with initial `order: 0`, positioned at the start and end of the document order respectively. | Included in `LayoutInputNode::FirstChild()` and `NextSibling()` as standard layout boxes; participate uniformly in `FlexChildIterator`. | **Compliant**. |
| **Accessibility / Tab Order Gap** | §5.4.1 explicitly mandates that `order` **must not** affect sequential navigation order (`tabindex`) or speech order. | Blink’s `FocusController` and Accessibility (`AXObjectCache`) traverse the DOM tree (`NodeTraversal`), not `FlexChildIterator`. | **Compliant**. |

---

### 5. Rocq / Coq Formalization (`BlinkFlexOrderSemantics.v`)

Below is a complete, self-contained Rocq (Coq) formalization defining the data structures, the specification of W3C §5.4, a model of Blink's stable insertion/merge sort on `(order, original_index)`, and the machine-checked proofs of **Permutation Preservation**, **Strict Lexicographical Monotonicity**, **Stability**, and **Uniqueness of the Resulting Sequence**.

```coq
(** * BlinkFlexOrderSemantics.v
    Formal verification of Chromium Blink's FlexChildIterator sorting semantics
    against W3C CSS Flexible Box Layout Module Level 1, Section 5.4. *)

From Coq Require Import List.
From Coq Require Import ZArith.
From Coq Require Import Arith.
From Coq Require Import Permutation.
From Coq Require Import Sorted.
From Coq Require Import Lia.
Import ListNotations.

Open Scope Z_scope.

(** ** 1. Core Data Structures *)

(** A raw layout node coming from the DOM / Box tree before indexing. *)
Record RawLayoutNode : Type := mkRawNode {
  node_payload : nat;     (** Opaque identifier for the LayoutInputNode *)
  node_order   : Z        (** CSS 'order' property (32-bit signed int in Blink) *)
}.

(** An entry inside Blink's FlexChildIterator vector, annotated with its
    0-based document-order index. *)
Record FlexChildEntry : Type := mkEntry {
  entry_node  : RawLayoutNode;
  entry_order : Z;
  orig_index  : nat
}.

(** ** 2. Lexicographical Ordering Relation (W3C §5.4 + Blink Comparator) *)

(** Strict lexicographical order on (entry_order, orig_index). *)
Definition flex_lt (a b : FlexChildEntry) : Prop :=
  (entry_order a < entry_order b)%Z \/
  (entry_order a = entry_order b /\ (orig_index a < orig_index b)%nat).

(** Decidable boolean comparator used by Blink's sorting routine. *)
Definition flex_leb (a b : FlexChildEntry) : bool :=
  if Z.ltb (entry_order a) (entry_order b) then true
  else if Z.eqb (entry_order a) (entry_order b) then Nat.leb (orig_index a) (orig_index b)
  else false.

Lemma flex_leb_true_iff : forall a b,
  flex_leb a b = true <->
  (entry_order a < entry_order b)%Z \/
  (entry_order a = entry_order b /\ (orig_index a <= orig_index b)%nat).
Proof.
  intros a b. unfold flex_leb.
  destruct (Z.ltb_spec (entry_order a) (entry_order b)) as [Hlt | Hge].
  - split; [intros _; left; exact Hlt | intros _; reflexivity].
  - destruct (Z.eqb_spec (entry_order a) (entry_order b)) as [Heq | Hneq].
    + rewrite Nat.leb_le. split.
      * intros Hle. right. split; assumption.
      * intros [Hlt | [_