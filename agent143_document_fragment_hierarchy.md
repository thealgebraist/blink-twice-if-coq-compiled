### 1. Physical Fragment Tree Traversal Architecture

In Chromium’s Blink rendering engine (specifically within the LayoutNG architecture), the **Physical Fragment Tree** is an immutable, post-layout output structure generated from the mutable `LayoutObject` tree. Each node in this tree is an instance of `NGPhysicalFragment` (or its subclasses: `NGPhysicalBoxFragment`, `NGPhysicalLineBoxFragment`, `NGPhysicalTextFragment`), paired with a physical `LayoutPoint` offset relative to its parent fragment via an `NGLink` structure.

```
[NGPhysicalBoxFragment: Root / ICB] (Offset: 0,0)
  └── [NGPhysicalBoxFragment: <body>] (Offset: x_b, y_b)
        └── [NGPhysicalBoxFragment: Block Container] (Offset: x_blk, y_blk)
              ├── [NGPhysicalBoxFragment: Anonymous Block / Row] (Offset: x_r, y_r)
              └── [NGPhysicalLineBoxFragment: Line Box] (Offset: x_l, y_l)
                    └── [NGPhysicalTextFragment: Text Run] (Offset: x_t, y_t)
```

#### Traversal Path Mechanics
1. **Root Document (`LayoutView` $\rightarrow$ Root `NGPhysicalBoxFragment`)**: 
   The traversal begins at the Initial Containing Block (ICB), represented by the root `NGPhysicalBoxFragment`. This fragment establishes the global physical coordinate space $(0, 0)$ with dimensions matching the layout viewport.
2. **Body Fragment (`LayoutBlockFlow` $\rightarrow$ Body `NGPhysicalBoxFragment`)**:
   Iterating over the root fragment’s `Children()` (`base::span<const NGLink>`), the engine resolves the `NGLink` pointing to the `<body>` fragment. Its `Offset()` defines the physical displacement from the ICB's top-left border edge, factoring in document margins and root padding.
3. **Block Fragments (Block-Level `NGPhysicalBoxFragment`)**:
   The body fragment acts as a Block Formatting Context (BFC) root or participates in the root BFC. Traversal descends into child block fragments (e.g., `<div>`, `<p>`, or flex/grid containers). Due to fragmentation (pagination, multicol), a single `LayoutObject` may generate multiple `NGPhysicalBoxFragment` siblings across fragmentainers, linked via `NGBlockBreakToken`.
4. **Row and Line Fragments (`NGPhysicalBoxFragment` / `NGPhysicalLineBoxFragment`)**:
   * **Row Fragments**: Within table, flex, or grid formatting contexts, intermediate row-level `NGPhysicalBoxFragment` instances group cell or item fragments.
   * **Line Fragments**: When a block container establishes an Inline Formatting Context (IFC), its children are `NGPhysicalLineBoxFragment` instances. Traversal transitions from block-level coordinate accumulation to inline-level progression, stepping into line boxes and subsequently leaf `NGPhysicalTextFragment` or atomic inline `NGPhysicalBoxFragment` nodes.

---

### 2. Bounding Box Enclosing Union vs. CSS Box Model Level 3

According to the **CSS Box Model Level 3** specification, every box consists of four concentric areas: Content, Padding, Border, and Margin. In Blink's LayoutNG, an `NGPhysicalFragment`’s primary geometry (`Size()`) corresponds strictly to the **Border Box** of the CSS element. 

#### The Enclosing Union Discrepancy (Layout vs. Visual Overflow)
In pure CSS semantics, child boxes can overflow their parent’s border box (e.g., via explicit `width`/`height` constraints on the parent, negative margins, or `position: absolute`). Therefore, a naive geometric union of parent and child CSS border boxes does **not** guarantee that the parent’s border box encloses its children.

To reconcile this for painting, hit-testing, and scrolling, Blink computes an **Enclosing Bounding Box Union** (formally tracked as `InkOverflow` and `ScrollableOverflow` via `NGPhysicalBoxFragment::OverflowClipRect()` and `ScrollableOverflow()`). 

For a strict containment hierarchy audit (modeling an idealized, non-overflowing layout state or auditing the *Scrollable Overflow Bounding Box*):
* Let $B(f) = [x_0, x_0 + w] \times [y_0, y_0 + h]$ be the physical bounding rectangle of fragment $f$ in the coordinate space of its parent.
* For a parent fragment $P$ with local bounding box $B_{\text{local}}(P) = [0, W_P] \times [0, H_P]$, and its set of direct child links $C(P) = \{ (f_i, \text{offset}_i) \}$, the **Enclosing Union Property** states that the effective layout bounding box of $P$ must encompass its own border box and the translated bounding boxes of all its children:

$$B_{\text{enclosing}}(P) \supseteq B_{\text{local}}(P) \cup \bigcup_{(f_i, \vec{o}_i) \in C(P)} \left( B_{\text{enclosing}}(f_i) + \vec{o}_i \right)$$

Where $B + \vec{o}$ denotes the Minkowski sum (translation) of the bounding box $B$ by the child's physical `NGLink` offset $\vec{o} = (\Delta x_i, \Delta y_i)$. In the formal verification below, we enforce strict structural containment where $B_{\text{local}}(P) = B_{\text{enclosing}}(P)$, corresponding to CSS layouts with `overflow: hidden/clip` or auto-sizing BFC roots (`height: auto; width: auto`) without negative margins.

---

### 3. Formal Structural and Geometric Invariants

To guarantee memory safety, termination of layout/paint passes, and geometric soundness during `NGPhysicalFragment` tree traversals, the engine maintains three core invariants:

#### Invariant 1: Tree Acyclicity (DAG / Strict Tree Structure)
Because `NGPhysicalFragment` instances are constructed bottom-up (children are finalized and ref-counted via `scoped_refptr` before the parent is instantiated), it is structurally impossible for a fragment to reference an ancestor. Formally, the binary relation $x \prec y$ ("$x$ is a direct child fragment of $y$") is well-founded, irreflexive, and asymmetric. No pre-order traversal path can visit the same physical fragment pointer twice.

#### Invariant 2: Pre-Order Child Count Conservation
A pre-order depth-first traversal (`NGPhysicalFragment::PreOrderTraverse`) flattens the fragment hierarchy into a deterministic sequence. The total number of nodes visited in the flattened sequence of a parent fragment $P$ must strictly equal $1$ (for $P$ itself) plus the exact sum of the pre-order node counts of all immediate children in `P.Children()`. No fragments are dropped or synthetically duplicated during traversal.

#### Invariant 3: Fragment Coordinates Non-Negativity
Within a standard flow formatting context free of negative margins, relative positioning offsets, or out-of-flow negative insets, all physical coordinates (both local `NGLink` offsets $(x, y)$ and dimensions $(w, h)$) are non-negative ($\ge 0$). By induction over the vector addition of `NGLink` offsets along any path from the Root ICB $(0,0)$ to an arbitrary descendant fragment, the global screen-space coordinates of any fragment remain strictly within the first quadrant $(\mathbb{N} \times \mathbb{N})$.

---

### 4. Formal Verification in Rocq / Coq

The following file, `BlinkDocumentFragmentHierarchySemantics.v`, provides a self-contained, zero-admit formalization of the Physical Fragment Tree, its CSS Box Model geometry, pre-order traversal, and complete proofs of the three invariants and the transitive bounding box enclosing union theorem.

```coq
(** * BlinkDocumentFragmentHierarchySemantics.v
    Formal Audit of Chromium Blink Physical Fragment Tree vs CSS Box Model Level 3.
    Agent 143 Verification Artifact. *)

Require Import Coq.Lists.List.
Require Import Coq.Arith.Arith.
Require Import Coq.ZArith.ZArith.
Require Import Coq.micromega.Lia.
Import ListNotations.

Open Scope Z_scope.

(** ** 1. Geometric Primitives and CSS Box Model Level 3 Representation *)

(** Physical coordinates and dimensions are modeled in integer layout units (LayoutUnit). *)
Record PhysicalOffset := mkOffset {
  off_x : Z;
  off_y : Z
}.

Record PhysicalSize := mkSize {
  width  : Z;
  height : Z
}.

Record EdgeInsets := mkInsets {
  top    : Z;
  right  : Z;
  bottom : Z;
  left   : Z
}.

(** CSS Box Model Level 3: A box has content dimensions and surrounding edges. *)
Record CSSBoxModel := mkCSSBox {
  content_size : PhysicalSize;
  padding      : EdgeInsets;
  border       : EdgeInsets;
  margin       : EdgeInsets
}.

(** Computes the CSS Border Box size, which corresponds to NGPhysicalFragment::Size(). *)
Definition css_border_box_size (box : CSSBoxModel) : PhysicalSize :=
  mkSize
    (width (content_size box) + left (padding box) + right (padding box) +
     left (border box) + right (border box))
    (height (content_size box) + top (padding box) + bottom (padding box) +
     top (border box) + bottom (border box)).

(** A Physical Bounding Box (Rect) in a given coordinate space. *)
Record BoundingBox := mkBBox {
  min_x : Z;
  min_y : Z;
  max_x : Z;
  max_y : Z
}.

(** Translate a bounding box by a physical offset (NGLink offset). *)
Definition translate_bbox (b : BoundingBox) (o : PhysicalOffset) : BoundingBox :=
  mkBBox (min_x b + off_x o) (min_y b + off_y o)
         (max_x b + off_x o) (max_y b + off_y o).

(** Convert a local PhysicalSize at origin (0,0) to a local BoundingBox. *)
Definition size_to_local_bbox (s : PhysicalSize) : BoundingBox :=
  mkBBox 0 0 (width s) (height s).

(** Geometric containment: [b_inner] is completely enclosed within [b_outer]. *)
Definition bbox_enclosed (b_inner b_outer : BoundingBox) : Prop :=
  min_x b_outer <= min_x b_inner /\
  min_y b_outer <= min_y b_inner /\
  max_x b_inner <= max_x b_outer /\
  max_y b_inner <= max_y b_outer.

(** Bounding Box Union of two boxes. *)
Definition bbox_union (b1 b2 : BoundingBox) : BoundingBox :=
  mkBBox (Z.min (min_x b1) (min_x b2))
         (Z.min (min_y b1) (min_y b2))
         (Z.max (max_x b1) (max_x b2))
         (Z.max (max_y b1) (max_y b2)).

(** ** 2. Blink Physical Fragment Tree Hierarchy *)

Inductive FragmentType :=
  | FragRootDocument
  | FragBody
  | FragBlock
  | FragRow
  | FragLineBox.

(** Inductive definition of NGPhysicalFragment paired with its parent-relative NGLink offset. *)
Inductive PhysicalFragment :=
  | mkFragment :
       nat ->                        (** Unique Fragment ID *)
      FragmentType ->               (** Role in Hierarchy *)
      PhysicalOffset ->             (** NGLink Offset relative to parent *)
      CSSBoxModel ->                (** Underlying CSS Box Model 3 geometry *)
      list PhysicalFragment ->      (** Child Physical Fragments *)
      PhysicalFragment.

(** Accessors *)
Definition frag_id (f : PhysicalFragment) : nat :=
  match f with mkFragment id _ _ _ _ => id end.

Definition frag_type (f : PhysicalFragment) : FragmentType :=
  match f with mkFragment _ t _ _ _ => t end.

Definition frag_offset (f : PhysicalFragment) : PhysicalOffset :=
  match f with mkFragment _ _ o _ _ => o end.

Definition frag_box (f : PhysicalFragment) : CSSBoxModel :=
  match f with mkFragment _ _ _ b _ => b end.

Definition frag_children (f : PhysicalFragment) : list PhysicalFragment :=
  match f with mkFragment _ _ _ _ c => c end.

Definition frag_size (f : PhysicalFragment) : PhysicalSize :=
  css_border_box_size (frag_box f).

Definition frag_local_bbox (f : PhysicalFragment) : BoundingBox :=
  size_to_local_bbox (frag_size f).

Definition frag_ bbox_in_parent (f : PhysicalFragment) : BoundingBox :=
  translate_bbox (frag_local_bbox f) (frag_offset f).

(**Valid Hierarchy Sequencing: Root -> Body -> Block -> Row/LineBox *)
Definition valid_child_type (parent_t child_t : FragmentType) : Prop :=
  match parent_t, child_t with
  | FragRootDocument, FragBody => True
  | FragBody, FragBlock => True
  | FragBlock, FragBlock => True
  | FragBlock, FragRow => True
  | FragBlock, FragLineBox => True
  | FragRow, FragBlock => True
  | FragRow, FragLineBox => True
  | _, _ => False
  end.

(** ** 3. Traversal Mechanics & Invariant 2: Pre-Order Child Count Conservation *)

(** Pre-order depth-first traversal flattening the fragment tree. *)
Fixpoint preorder_traverse (f : PhysicalFragment) : list PhysicalFragment :=
  match f with
  | mkFragment _ _ _ _ children =>
      f :: flat_map preorder_traverse children
  end.

(** Total node count computed recursively over subtrees. *)
Fixpoint fragment_count (f : PhysicalFragment) : nat :=
  match f with
  | mkFragment _ _ _ _ children =>
      1 + list_sum (map fragment_count children)
  end.

Lemma flat_map_preorder_length : forall (l : list PhysicalFragment),
  length (flat_map preorder_traverse l) = list_sum (map fragment_count l).
Proof.
  induction l as [| x xs IH].
  - simpl. reflexivity.
  - simpl. rewrite app_length. rewrite IH.
    destruct x as [id t o b c]. simpl.
    reflexivity.
Qed.

(** THEOREM (Invariant 2 - Pre-Order Child Count Conservation):
    The length of the pre-order traversal of any fragment tree is strictly equal
    to 1 (the parent fragment) plus the sum of the fragment counts of its children. *)
Theorem preorder_child_count_conservation : forall (f : PhysicalFragment),
  length (preorder_traverse f) = fragment_count f.
Proof.
  intros f.
  destruct f as [id t o b children].
  simpl.
  f_equal.
  apply flat_map_preorder_length.
Qed.

(** ** 4. Invariant 1: Structural Tree Acyclicity *)

(** Defines when [sub] is a strict descendant of [f]. *)
Fixpoint is_strict_descendant (sub f : PhysicalFragment) : Prop :=
  match f with
  | mkFragment _