**Agent 279: Audit Report – Chromium Blink Paint Offset Propagation**

### 1. Propagation Mechanics
In Chromium's Blink rendering engine (specifically within `PaintPropertyTreeBuilder` and `FragmentPaintPropertyTreeBuilder`), the **Paint Offset** represents the 2D translation of a `LayoutObject` from the origin of its current transform space (the nearest ancestor that creates a paint offset translation node). 

When traversing the layout tree downward without crossing a transform boundary, the paint offset is propagated additively from parent to child:
$$\text{offset\_accum}(\text{parent}, \text{child}) = (p_x + c_x, p_y + c_y)$$
where $(p_x, p_y)$ is the accumulated paint offset of the parent in the current transform space, and $(c_x, c_y)$ is the local offset of the child relative to the parent's border box.

### 2. Core Invariants
1. **Root/Reset Identity**: At the root of the tree, or immediately beneath a layout object that establishes a new transform space (e.g., via CSS `transform`, `will-change: transform`, or fixed positioning), the initial paint offset is reset to the identity offset $(0, 0)$. Propagating from a reset boundary yields the child's local offset unchanged.
2. **Associativity**: Grouping of sub-tree layout offsets does not affect the final resolved paint offset in the backing transform space. Formally, flattening an intermediate wrapper container preserves the exact subpixel coordinates:
   $$\text{accum}(\text{accum}(A, B), C) = \text{accum}(A, \text{accum}(B, C))$$
3. **Commutativity**: Because paint offset propagation is purely a 2D vector translation without scaling or rotation (which are pushed to separate `TransformPaintPropertyNode` instances), the vector addition itself commutes:
   $$\text{accum}(A, B) = \text{accum}(B, A)$$

---

### 3. Formal Verification (`BlinkPaintOffsetPropagationSemantics.v`)

Below is the complete, self-contained Rocq/Coq formalization of the paint offset propagation semantics, including multi-level tree traversal invariants, with **0 admits**.

```coq
(** * BlinkPaintOffsetPropagationSemantics.v
    Agent 279: Formal Audit of Chromium Blink Paint Offset Propagation.
    Contains 0 admits. *)

Require Import Coq.ZArith.ZArith.
Require Import Coq.Lists.List.
Require Import Coq.Micromega.Lia.

Import ListNotations.
Open Scope Z_scope.

(** ** 1. Data Types and Definitions *)

(** In Blink, LayoutUnit is a fixed-point representation (typically 1/64th of a pixel).
    We model the underlying fixed-point integer values using exact integers (Z). *)
Record PaintOffset : Type := mkOffset {
  px : Z;
  py : Z
}.

(** The root offset (or transform-boundary reset offset) is (0, 0). *)
Definition root_offset : PaintOffset := mkOffset 0 0.

(** Paint offset accumulation: offset_accum(parent, child) = (px + cx, py + cy). *)
Definition offset_accum (parent child : PaintOffset) : PaintOffset :=
  mkOffset (px parent + px child) (py parent + py child).

(** Multi-step propagation down a chain of LayoutObjects within the same transform space. *)
Definition propagate_chain (base : PaintOffset) (chain : list PaintOffset) : PaintOffset :=
  fold_left offset_accum chain base.

(** ** 2. Structural Equality Helper *)

Lemma paint_offset_eq : forall (a b : PaintOffset),
  px a = px b -> py a = py b -> a = b.
Proof.
  intros [x1 y1] [x2 y2] Hx Hy.
  simpl in *.
  subst.
  reflexivity.
Qed.

(** ** 3. Core Algebraic Invariants *)

(** Invariant 2a: Left Identity - Propagating from the root offset yields the child offset. *)
Theorem offset_accum_root_left : forall (c : PaintOffset),
  offset_accum root_offset c = c.
Proof.
  intros [cx cy].
  unfold offset_accum, root_offset.
  simpl.
  apply paint_offset_eq; simpl; lia.
Qed.

(** Invariant 2b: Right Identity - A child with a (0,0) local offset preserves the parent offset. *)
Theorem offset_accum_root_right : forall (p : PaintOffset),
  offset_accum p root_offset = p.
Proof.
  intros [px0 py0].
  unfold offset_accum, root_offset.
  simpl.
  apply paint_offset_eq; simpl; lia.
Qed.

(** Invariant 2c: Commutativity - Offset composition is commutative. *)
Theorem offset_accum_comm : forall (a b : PaintOffset),
  offset_accum a b = offset_accum b a.
Proof.
  intros [ax ay] [bx by0].
  unfold offset_accum.
  simpl.
  apply paint_offset_eq; simpl; lia.
Qed.

(** Invariant 2d: Associativity - Offset composition is associative. *)
Theorem offset_accum_assoc : forall (a b c : PaintOffset),
  offset_accum (offset_accum a b) c = offset_accum a (offset_accum b c).
Proof.
  intros [ax ay] [bx by0] [cx cy].
  unfold offset_accum.
  simpl.
  apply paint_offset_eq; simpl; lia.
Qed.

(** ** 4. Tree Traversal & Container Flattening Theorems *)

(** Propagating an empty chain of descendants leaves the base offset unchanged. *)
Theorem propagate_chain_nil : forall (base : PaintOffset),
  propagate_chain base [] = base.
Proof.
  intros base.
  reflexivity.
Qed.

(** Generalized base-shift lemma for fold_left over offset_accum. *)
Lemma propagate_chain_shift_base : forall (chain : list PaintOffset) (a b : PaintOffset),
  propagate_chain (offset_accum a b) chain = offset_accum a (propagate_chain b chain).
Proof.
  induction chain as [| h t IH]; intros a b.
  - simpl. reflexivity.
  - simpl.
    rewrite <- offset_accum_assoc.
    apply IH.
Qed.

(** Subtree Composition Invariant: 
    Propagating down two concatenated layout chains is equivalent to propagating 
    down the first chain, and using that result as the parent base for the second chain. *)
Theorem propagate_chain_app : forall (c1 c2 : list PaintOffset) (base : PaintOffset),
  propagate_chain base (c1 ++ c2) = propagate_chain (propagate_chain base c1) c2.
Proof.
  intros c1 c2 base.
  unfold propagate_chain.
  rewrite fold_left_app.
  reflexivity.
Qed.

(** Container Flattening Invariant:
    Computing a subtree's relative offset from root_offset and then adding it to a 
    parent base is identical to propagating directly from the parent base. *)
Theorem subtree_relativization_correct : forall (chain : list PaintOffset) (base : PaintOffset),
  propagate_chain base chain = offset_accum base (propagate_chain root_offset chain).
Proof.
  intros chain base.
  rewrite <- propagate_chain_shift_base.
  rewrite offset_accum_root_right.
  reflexivity.
Qed.
```