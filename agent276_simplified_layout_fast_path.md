### 1. Simplified Layout Fast Path Architecture

In Chromium’s Blink rendering engine (specifically within LayoutNG), the **Simplified Layout Fast Path** (`NGSimplifiedLayoutAlgorithm`) optimizes the layout phase when a container experiences a change that does not affect the intrinsic geometry of its in-flow children. Typical triggers include parent block-size adjustments, out-of-flow (OOF) descendant modifications, or dynamic CSS property updates that preserve formatting context constraints.

When a layout pass is invoked on a `LayoutObject`:
1. **Cache Inspection**: The engine inspects the existing `NGLayoutResult` stored on the node and its direct children.
2. **Precondition Verification**: Blink checks if the node `NeedsSimplifiedLayoutOnly()`. This requires that the available inline-size passed down via `NGConstraintSpace` has not changed in a way that invalidates line breaking or child sizing, and that no in-flow child has the `NeedsLayout()` dirty bit set.
3. **Execution (Fast Path)**: Instead of invoking the full layout algorithm (e.g., `NGBlockLayoutAlgorithm`) which recursively invokes `Layout()` on every child, `NGSimplifiedLayoutAlgorithm` clones the previous `NGPhysicalBoxFragment`. It iterates over the existing child fragments, copies their cached physical dimensions, updates their relative offsets if the container's border/padding or alignment shifted, and recalculates the container's final block-size and layout overflow.

---

### 2. Core Soundness Invariants

For the simplified layout pass to be sound, its output must be observationally equivalent to a full recursive layout pass. This relies on three strict invariants:

* **Invariant 1 (Clean Subtree Guarantee)**: For any node $N$ entering simplified layout, for all in-flow children $C \in \text{Children}(N)$, $C.\text{NeedsLayout}() = \text{false}$. Furthermore, the cached layout result $C.\text{CachedFragment}$ must exist and be valid.
* **Invariant 2 (Constraint Space Stability)**: The incoming `NGConstraintSpace` must be layout-compatible with the cached constraint space used to generate the previous fragment of $N$. Specifically, the available inline-size allocated to in-flow children must remain constant, ensuring that child intrinsic dimensions (both inline and block) do not mutate.
* **Invariant 3 (Observational Equivalence)**: Under Invariants 1 and 2, the physical fragment tree produced by `SimplifiedLayout` (containing computed $X, Y$ coordinates and $W, H$ dimensions) is bitwise identical to the physical fragment tree produced by `FullLayout`.

---

### 3. Formal Verification in Rocq (Coq)

The following file `BlinkSimplifiedLayoutFastPathSemantics.v` formalizes the layout tree, the dirty-bit invalidation state, the full recursive layout pass, and the simplified layout fast path. It proves with zero admits that when the structural invariants hold, the simplified layout yields identical physical coordinates and dimensions to the full layout pass.

```coq
(* File: BlinkSimplifiedLayoutFastPathSemantics.v *)
(* Agent 276: Chromium Blink Simplified Layout Fast Path Audit *)

Require Import Coq.Lists.List.
Require Import Coq.Arith.Arith.
Require Import Coq.Bool.Bool.
Import ListNotations.

(* ========================================================================== *)
(* 1. Core Data Structures & Geometry                                         *)
(* ========================================================================== *)

(* Physical dimensions of a layout box *)
Record Dimensions : Type := mkDim {
  width : nat;
  height : nat
}.

(* Physical coordinates relative to parent fragment *)
Record Offset : Type := mkOffset {
  x : nat;
  y : nat
}.

(* NGConstraintSpace: Input constraints passed down from parent *)
Record ConstraintSpace : Type := mkSpace {
  available_width : nat
}.

(* NGPhysicalBoxFragment: Immutable output of a layout pass *)
Inductive PhysicalFragment : Type :=
| mkFragment : Dimensions -> list (Offset * PhysicalFragment) -> PhysicalFragment.

(* LayoutBox: Mutable DOM/Layout tree node with caching and dirty bits *)
Inductive LayoutBox : Type :=
| mkBox :
    nat ->                         (* Intrinsic Content Height *)
    nat ->                         (* Padding/Border Box Offset *)
    bool ->                        (* Bit: self_needs_full_layout *)
    option PhysicalFragment ->     (* Cached NGLayoutResult *)
    list LayoutBox ->              (* In-flow Children *)
    LayoutBox.

(* Accessors for PhysicalFragment *)
Definition frag_dims (f : PhysicalFragment) : Dimensions :=
  match f with mkFragment d _ => d end.

Definition frag_children (f : PhysicalFragment) : list (Offset * PhysicalFragment) :=
  match f with mkFragment _ c => c end.

(* Accessors for LayoutBox *)
Definition box_intrinsic_height (b : LayoutBox) : nat :=
  match b with mkBox h _ _ _ _ => h end.

Definition box_padding (b : LayoutBox) : nat :=
  match b with mkBox _ p _ _ _ => p end.

Definition box_needs_full_layout (b : LayoutBox) : bool :=
  match b with mkBox _ _ n _ _ => n end.

Definition box_cached_frag (b : LayoutBox) : option PhysicalFragment :=
  match b with mkBox _ _ _ c _ => c end.

Definition box_children (b : LayoutBox) : list LayoutBox :=
  match b with mkBox _ _ _ _ ch => ch end.

(* ========================================================================== *)
(* 2. Layout Algorithms (Full vs. Simplified)                                 *)
(* ========================================================================== *)

(* Helper: Stacks child fragments vertically (Block Formatting Context) *)
Fixpoint layout_children_flow (padding : nat) (current_y : nat) (frags : list PhysicalFragment) 
  : list (Offset * PhysicalFragment) * nat :=
  match frags with
  | [] => ([], current_y)
  | f :: rest =>
      let child_offset := mkOffset padding current_y in
      let next_y := current_y + height (frag_dims f) in
      let (rest_placed, final_y) := layout_children_flow padding next_y rest in
      ((child_offset, f) :: rest_placed, final_y)
  end.

(* NGBlockLayoutAlgorithm: Full Recursive Layout Pass *)
Fixpoint full_layout (space : ConstraintSpace) (b : LayoutBox) : PhysicalFragment :=
  match b with
  | mkBox intr_h pad _ _ children =>
      let child_space := mkSpace (available_width space - (2 * pad)) in
      let child_frags := map (full_layout child_space) children in
      let (placed_children, content_h) := layout_children_flow pad pad child_frags in
      let total_h := intr_h + content_h + pad in
      mkFragment (mkDim (available_width space) total_h) placed_children
  end.

(* Extracts cached fragment if child is clean; falls back to full layout if dirty *)
Definition extract_or_layout_child (child_space : ConstraintSpace) (c : LayoutBox) : PhysicalFragment :=
  if box_needs_full_layout c then
    full_layout child_space c
  else
    match box_cached_frag c with
    | Some frag => frag
    | None => full_layout child_space c
    end.

(* NGSimplifiedLayoutAlgorithm: Skips recursion on clean children with valid cache *)
Definition simplified_layout (space : ConstraintSpace) (b : LayoutBox) : PhysicalFragment :=
  match b with
  | mkBox intr_h pad _ _ children =>
      let child_space := mkSpace (available_width space - (2 * pad)) in
      let child_frags := map (extract_or_layout_child child_space) children in
      let (placed_children, content_h) := layout_children_flow pad pad child_frags in
      let total_h := intr_h + content_h + pad in
      mkFragment (mkDim (available_width space) total_h) placed_children
  end.

(* Top-level Layout Entry Point Dispatcher *)
Definition perform_layout (space : ConstraintSpace) (b : LayoutBox) : PhysicalFragment :=
  if box_needs_full_layout b then
    full_layout space b
  else
    simplified_layout space b.

(* ========================================================================== *)
(* 3. Soundness Invariants & Preconditions                                    *)
(* ========================================================================== *)

(* Invariant: A child box is un-invalidated and its cache matches the constraint space *)
Definition child_cache_valid (child_space : ConstraintSpace) (c : LayoutBox) : Prop :=
  box_needs_full_layout c = false /\
  box_cached_frag c = Some (full_layout child_space c).

(* Invariant: All in-flow children of a box satisfy the cache validity condition *)
Definition all_children_valid (space : ConstraintSpace) (b : LayoutBox) : Prop :=
  let child_space := mkSpace (available_width space - (2 * box_padding b)) in
  Forall (child_cache_valid child_space) (box_children b).

(* ========================================================================== *)
(* 4. Theorems & Proofs (0 Admits)                                            *)
(* ========================================================================== *)

(* Lemma 1: Under valid cache invariants, extracting the cached fragment is 
   identically equal to running a full recursive layout pass on the child. *)
Lemma extract_or_layout_child_sound :
  forall (cs : ConstraintSpace) (c : LayoutBox),
    child_cache_valid cs c ->
    extract_or_layout_child cs c = full_layout cs c.
Proof.
  intros cs c [Hclean Hcache].
  unfold extract_or_layout_child.
  rewrite Hclean.
  rewrite Hcache.
  reflexivity.
Qed.

(* Lemma 2: Mapping the simplified extraction over a list of valid children 
   produces the exact same fragment list as mapping the full layout pass. *)
Lemma map_extract_or_layout_sound :
  forall (cs : ConstraintSpace) (children : list LayoutBox),
    Forall (child_cache_valid cs) children ->
    map (extract_or_layout_child cs) children = map (full_layout cs) children.
Proof.
  intros cs children Hforall.
  induction Hforall as [| c rest Hvalid Hrest IH].
  - reflexivity.
  - simpl.
    rewrite (extract_or_layout_child_sound cs c Hvalid).
    rewrite IH.
    reflexivity.
Qed.

(* Theorem 1: Simplified Layout Fast Path Soundness.
   If all children of a box have valid caches for the current constraint space,
   simplified_layout produces output coordinates and dimensions identical to full_layout. *)
Theorem simplified_layout_matches_full_layout :
  forall (space : ConstraintSpace) (b : LayoutBox),
    all_children_valid space b ->
    simplified_layout space b = full_layout space b.
Proof.
  intros space b Hvalid.
  destruct b as [intr_h pad needs_full cache children].
  unfold all_children_valid in Hvalid.
  simpl in Hvalid.
  simpl.
  pose (child_space := mkSpace (available_width space - (2 * pad))).
  fold child_space.
  fold child_space in Hvalid.
  rewrite (map_extract_or_layout_sound child_space children Hvalid).
  reflexivity.
Qed.

(* Theorem 2: Top-level Dispatcher Correctness.
   Regardless of whether the container itself takes the fast path or full path,
   as long as the children invariants hold when the container is clean, 
   perform_layout is observationally indistinguishable from full_layout. *)
Theorem perform_layout_soundness :
  forall (space : ConstraintSpace) (b : LayoutBox),
    (box_needs_full_layout b = false -> all_children_valid space b) ->
    perform_layout space b = full_layout space b.
Proof.
  intros space b Hinv.
  unfold perform_layout.
  destruct (box_needs_full_layout b) eqn:Hneeds.
  - reflexivity.
  - apply simplified_layout_matches_full_layout.
    apply Hinv.
    reflexivity.
Qed.
```