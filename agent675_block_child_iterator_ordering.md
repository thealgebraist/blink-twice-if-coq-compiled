# Formal Verification Research Report: Block Child Iterator Sequencing and Block-End Margin Strut Propagation in Chromium Blink

**Agent ID:** 675  
**Specialization:** W3C/WHATWG Layout Rules (Block, Inline, Flexbox) in Chromium Blink  
**Target Source:** `third_party/blink/renderer/core/layout/block_child_iterator.cc`  
**Specification:** CSS 2.1 §8.3.1 (Collapsing Margins) & CSS Fragmentation Module Level 3  
**Formal Theory Target:** `BlinkBlockChildIteratorOrderingSemantics.v`  

---

## 1. Normative W3C Specification Requirements

In a CSS Block Formatting Context (BFC), block-level boxes are laid out vertically one after another, beginning at the top of a containing block (CSS 2.1 §9.4.1). The vertical distance between two sibling boxes is determined by their adjoining vertical margins, which collapse into a single margin strut according to the rules in **CSS 2.1 §8.3.1 (Collapsing margins)**:

1. **Adjoining Margins:** Two vertical margins are adjoining if and only if no non-empty content, padding, or border areas, or clearance separate them, and both belong to in-flow block-level boxes participating in the same BFC.
2. **Collapsed Margin Calculation (The Margin Strut):**
   - When two or more margins collapse, the resulting margin width is the maximum of the collapsing margins' widths if all are positive:
     $$M_{\text{pos}} = \max(\{m_i \mid m_i \ge 0\} \cup \{0\})$$
   - If any of the margins are negative, their maximum magnitude (most negative value) is subtracted from the maximum positive margin:
     $$M_{\text{neg}} = \min(\{m_i \mid m_i \le 0\} \cup \{0\})$$
   - The total collapsed margin resolved by the strut is:
     $$M_{\text{collapsed}} = M_{\text{pos}} + M_{\text{neg}}$$
3. **Self-Collapsing Boxes:** A block box with zero computed `min-height`, zero `height` (or `auto` height with no in-flow children), zero top/bottom borders, and zero top/bottom padding is *self-collapsing*. Its own top and bottom margins are adjoining and collapse together with the preceding and succeeding sibling margins without resolving the margin strut into a physical BFC offset delta.
4. **Block Progression Invariant:** For any sequence of in-flow block-level children $0, 1, \dots, n$, let $\text{cursor\_y}(n)$ denote the resolved BFC block-offset immediately preceding the margin evaluation of child $n$ (or the BFC block-offset at the border-box block-end of the last non-empty child). When child $n$ is non-self-collapsing, the BFC block-offset advances according to:
   $$\text{cursor\_y}(n+1) = \text{cursor\_y}(n) + \text{collapsed\_margin}(n) + \text{height}(n)$$
   where $\text{collapsed\_margin}(n)$ is the resolution of the incoming margin strut merged with child $n$'s block-start margin, and $\text{height}(n) > 0$ is the border-box block size of child $n$. Following this resolution, a new margin strut is initialized with child $n$'s block-end margin and propagated to child $n+1$.

---

## 2. Blink Implementation Details and Invariants

In Chromium Blink’s LayoutNG architecture, block child traversal and margin strut propagation are decoupled into `BlockChildIterator` (`third_party/blink/renderer/core/layout/block_child_iterator.cc`) and `BlockLayoutAlgorithm` (`third_party/blink/renderer/core/layout/block_layout_algorithm.cc`).

### 2.1 `BlockChildIterator::NextChild()` Sequencing
`BlockChildIterator` iterates over the children of a `BlockNode`, taking into account prior fragmentation breaks (`BlockBreakToken`):
- **Unfragmented Traversal:** When no incoming `BlockBreakToken` exists, the iterator starts at `first_child_` and advances linearly along the sibling linked list via `LayoutInputNode::NextSibling()`.
- **Fragmented Resumption:** When an incoming `BlockBreakToken` contains child break tokens, `BlockChildIterator` yields each broken child alongside its specific `ChildBreakToken` before advancing to the first unvisited sibling following the last broken child (unless `HasSeenAllChildren()` is set on the parent break token).
- **Sequencing Invariant:** Every in-flow block child in a fragmentainer is yielded in strict document tree order, forming a finite, deterministic stream of `Entry(LayoutInputNode, const BlockBreakToken*)` pairs.

### 2.2 `MarginStrut` and `PreviousInflowPosition` Propagation
During the `BlockLayoutAlgorithm::Layout` loop driven by `BlockChildIterator::NextChild()`, Blink maintains the layout state across iterations using `PreviousInflowPosition`:
```cpp
struct PreviousInflowPosition {
  LayoutUnit bfc_block_offset;
  LayoutUnit logical_block_offset;
  MarginStrut margin_strut;
  bool self_collapsing_child_had_clearance;
};
```
For each child $n$ yielded by `BlockChildIterator`:
1. **Strut Append:** The child's block-start margin $m_{\text{start}}(n)$ is appended to the incoming `margin_strut`:
   ```cpp
   margin_strut.Append(margins.block_start, is_quirky);
   ```
   Internally, `MarginStrut::Append` updates `positive_margin = std::max(positive_margin, value)` for `value >= 0` and `negative_margin = std::min(negative_margin, value)` for `value < 0`.
2. **Non-Empty (Solid) Child Resolution:** If the child is not self-collapsing, the BFC block-offset resolves the strut:
   ```cpp
   LayoutUnit child_bfc_offset = previous_inflow_position.bfc_block_offset + margin_strut.Sum();
   ```
   After laying out the child with border-box block-size `height(n)`, `ComputeInflowPosition` computes the state for child $n+1$:
   ```cpp
   LayoutUnit new_bfc_block_offset = child_bfc_offset + fragment.BlockSize();
   MarginStrut end_margin_strut;
   end_margin_strut.Append(margins.block_end, is_quirky);
   ```
   This directly implements the recurrence:
   $$\text{cursor\_y}(n+1) = \text{cursor\_y}(n) + \text{collapsed\_margin}(n) + \text{height}(n)$$
3. **Self-Collapsing Child Propagation:** If child $n$ is self-collapsing ($\text{height}(n) = 0$ and self-collapsing flag holds), `bfc_block_offset` does *not* advance ($\text{cursor\_y}(n+1) = \text{cursor\_y}(n)$, meaning the effective resolved margin at step $n$ is $0$), and `margins.block_end` is appended directly onto the active `margin_strut`, propagating the accumulated extremes forward to child $n+1$.

---

## 3. Formal Specification in Rocq/Coq

Below is the complete, self-contained formalization of `BlinkBlockChildIteratorOrderingSemantics.v`. It models `MarginStrut`, `BlockChildIterator` state transitions, `PreviousInflowPosition` updates, and proves the exact mathematical recurrence and W3C CSS 2.1 §8.3.1 margin collapsing invariants.

```coq
(* ========================================================================== *)
(* Formal Theory Target: BlinkBlockChildIteratorOrderingSemantics.v           *)
(* Topic: Block child iterator sequencing & block-end margin strut propagation*)
(* Chromium Source: third_party/blink/renderer/core/layout/                   *)
(*                  block_child_iterator.cc                                   *)
(* Specification: CSS 2.1 §8.3.1 BFC Margin Collapsing Chain                  *)
(* ========================================================================== *)

From Coq Require Import ZArith.
From Coq Require Import Lia.
From Coq Require Import Bool.
From Coq Require Import List.
Import ListNotations.

Open Scope Z_scope.

(* -------------------------------------------------------------------------- *)
(* 1. MarginStrut Formalization (CSS 2.1 §8.3.1 & Blink MarginStrut)          *)
(* -------------------------------------------------------------------------- *)

Record MarginStrut : Type := mkMarginStrut {
  pos_margin : Z;
  neg_margin : Z
}.

Definition empty_strut : MarginStrut :=
  mkMarginStrut 0 0.

Definition strut_wf (s : MarginStrut) : Prop :=
  0 <= pos_margin s /\ neg_margin s <= 0.

Definition strut_append (s : MarginStrut) (m : Z) : MarginStrut :=
  if Z.leb 0 m then
    mkMarginStrut (Z.max (pos_margin s) m) (neg_margin s)
  else
    mkMarginStrut (pos_margin s) (Z.min (neg_margin s) m).

Definition strut_sum (s : MarginStrut) : Z :=
  pos_margin s + neg_margin s.

(* -------------------------------------------------------------------------- *)
(* 2. Block Child Box & Iterator State (block_child_iterator.cc)              *)
(* -------------------------------------------------------------------------- *)

Record BlockChild : Type := mkBlockChild {
  child_id          : nat;
  margin_start      : Z;
  margin_end        : Z;
  border_box_height : Z;
  is_self_collapsing: bool
}.

(* Well-formedness of a BlockChild according to CSS 2.1 §8.3.1:
   - Border-box height is always non-negative.
   - A self-collapsing box must have zero border-box height. *)
Definition child_wf (c : BlockChild) : Prop :=
  0 <= border_box_height c /\
  (is_self_collapsing c = true -> border_box_height c = 0).

(* BlockChildIterator state modeling sequential traversal over siblings *)
Record IteratorState : Type := mkIteratorState {
  remaining_children : list BlockChild;
  visited_count      : nat
}.

Definition iterator_init (children : list BlockChild) : IteratorState :=
  mkIteratorState children 0%nat.

Definition next_child (st : IteratorState) : option (BlockChild * IteratorState) :=
  match remaining_children st with
  | [] => None
  | c :: cs => Some (c, mkIteratorState cs (S (visited_count st)))
  end.

(* -------------------------------------------------------------------------- *)
(* 3. BFC Layout State & Step Semantics (PreviousInflowPosition)              *)
(* -------------------------------------------------------------------------- *)

Record LayoutState : Type := mkLayoutState {
  cursor_y      : Z;
  current_strut : MarginStrut
}.

(* Effective collapsed margin resolved at step for child c given incoming strut s.
   - For non-self-collapsing children, the incoming strut is merged with
     margin_start and resolved into BFC offset delta.
   - For self-collapsing children, the strut is not resolved into cursor_y yet
     (effective delta is 0), and instead accumulates into current_strut. *)
Definition collapsed_margin_for_child (s : MarginStrut) (c : BlockChild) : Z :=
  let s_start := strut_append s (margin_start c) in
  if is_self_collapsing c then 0
  else strut_sum s_start.

(* Next margin strut propagated out of child c (block-end margin strut propagation) *)
Definition next_strut_for_child (s : MarginStrut) (c : BlockChild) : MarginStrut :=
  let s_start := strut_append s (margin_start c) in
  if is_self_collapsing c then
    strut_append s_start (margin_end c)
  else
    strut_append empty_strut (margin_end c).

(* Single layout step corresponding to Blink's BlockLayoutAlgorithm::HandleInflow *)
Definition layout_step (st : LayoutState) (c : BlockChild) : LayoutState :=
  let s_start := strut_append (current_strut st) (margin_start c) in
  if is_self_collapsing c then
    mkLayoutState
      (cursor_y st)
      (strut_append s_start (margin_end c))
  else
    let resolved_margin := strut_sum s_start in
    let next_y := cursor_y st + resolved_margin + border_box_height c in
    let next_s := strut_append empty_strut (margin_end c) in
    mkLayoutState next_y next_s.

(* Multi-step execution driven by BlockChildIterator *)
Fixpoint run_iterator_layout (it : IteratorState) (st : LayoutState)
  : list LayoutState :=
  match next_child it with
  | None => [st]
  | Some (c, it') => st :: run_iterator_layout it' (layout_step st c)
  end.

(* Direct state accessor at child index n *)
Fixpoint state_at (children : list BlockChild) (init_st : LayoutState) (n : nat)
  : LayoutState :=
  match n, children with
  | O, _ => init_st
  | S n', [] => init_st
  | S n', c :: cs => state_at cs (layout_step init_st c) n'
  end.

(* Accessor for cursor_y(n) *)
Definition cursor_y_at (children : list BlockChild) (init_st : LayoutState) (n : nat) : Z :=
  cursor_y (state_at children init_st n).

(* Accessor for collapsed_margin(n) *)
Definition collapsed_margin_at (children : list BlockChild) (init_st : LayoutState) (n : nat) : Z :=
  match nth_error children n with
  | None => 0
  | Some c => collapsed_margin_for_child (current_strut (state_at children init_st n)) c
  end.

(* Accessor for height(n) *)
Definition height_at (children : list BlockChild) (n : nat) : Z :=
  match nth_error children n with
  | None => 0
  | Some c => border_box_height c
  end.

(* ========================================================================== *)
(* 4. Concrete Theorems and Complete Proofs                                   *)
(* ========================================================================== *)

(* Theorem 1: MarginStrut Well-Formedness Preservation *)
Theorem strut_append_preserves_wf :
  forall (s : MarginStrut) (m : Z),
    strut_wf s ->
    strut_wf (strut_append s m).
Proof.
  intros [p n] m [Hp Hn].
  unfold strut_append, strut_wf; simpl in *.
  destruct (Z.leb 0 m) eqn:Hleb.
  - apply Z.leb_le in Hleb.
    simpl. split; [lia | exact Hn].
  -