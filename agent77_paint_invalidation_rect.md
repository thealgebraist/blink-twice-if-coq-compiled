### 1. Core Data Structures in Blink Paint Invalidation

In Chromium’s Blink engine (specifically under the CompositeAfterPaint architecture), paint invalidation is the phase in the document lifecycle that maps layout mutations and style changes into damaged regions on a composited backing surface (such as a `cc::PictureLayer`).

*   **`PaintInvalidator`**: The stateless coordinator that executes during the `PrePaint` lifecycle phase (`PrePaintTreeWalk`). It traverses the `LayoutObject` and `FragmentData` trees, comparing previous geometry and paint properties against current states to emit invalidation rects and DisplayItemClient invalidation flags.
*   **`PaintInvalidatorContext`**: The traversal state passed down the layout tree during `PrePaintTreeWalk`. It maintains:
    *   `old_visual_rect` and `old_paint_offset`: The previous frame's geometry cached on the `FragmentData`.
    *   `tree_builder_context`: Pointers to the current nodes in the **Paint Property Tree** (`TransformPaintPropertyNode`, `ClipPaintPropertyNode`, `EffectPaintPropertyNode`, `ScrollPaintPropertyNode`).
    *   `painting_layer`: The enclosing `PaintLayer` that serves as the invalidation container or composited backing grouping.
*   **`VisualRectMapping` (`GeometryMapper`)**: In modern Blink, visual rect mapping is handled by `GeometryMapper`, which utilizes the Paint Property Trees to compute visual rects. It caches and resolves transformations and clips between an arbitrary local `PropertyTreeState` and an ancestor (invalidation container) `PropertyTreeState` via `FloatClipRect` and `TransformationMatrix`.

---

### 2. Invalidation Rect Accumulation

To invalidate a region on a composited layer, a `LayoutObject`'s local bounding box (the *local visual rect*, $R_{\text{local}}$) must be mapped into the coordinate space of its backing invalidation container ($S_{\text{target}}$).

During `PrePaint`, `GeometryMapper::LocalToAncestorVisualRect` transforms $R_{\text{local}}$ from its local property tree state $S_{\text{local}} = (T_{\text{local}}, C_{\text{local}}, E_{\text{local}})$ to $S_{\text{target}} = (T_{\text{target}}, C_{\text{target}}, E_{\text{target}})$ by walking up the property trees toward the Lowest Common Ancestor (LCA):

1.  **Paint Offset Application**: The object's local rect is first offset by its `PaintOffset` (accumulated subpixel layout offset from its paint offset root).
2.  **Transform Node Mapping ($T$)**: As the rect moves from $T_i$ to its parent $T_{\text{parent}}$, the 2D/3D affine or perspective transformation matrix $M_i$ is applied. Because axis-aligned bounding boxes (AABBs) do not stay axis-aligned under rotation or skew, the transformed quad is re-enclosed in an AABB:
    $$R' = \text{BoundingBox}(M_i \cdot \text{Corners}(R))$$
3.  **Scroll Node Mapping ($S$)**: Scroll translations are represented as specialized `TransformPaintPropertyNode`s containing a 2D translation offset $(- \Delta x_{\text{scroll}}, - \Delta y_{\text{scroll}})$.
4.  **Clip Node Mapping ($C$)**: When crossing a `ClipPaintPropertyNode` (e.g., `overflow: hidden`, CSS `clip-path`), the visual rect is intersected with the clip rect $R_{\text{clip}}$ (which itself is first mapped into the intermediate coordinate space):
    $$R'' = R' \cap R_{\text{clip}}$$
5.  **Effect Node Mapping ($E$)**: If an `EffectPaintPropertyNode` contains pixel-moving filters (e.g., `filter: blur(5px)` or `drop-shadow`), the visual rect is expanded (outset) by the filter's kernel bounds before further ancestor clips and transforms are applied.

---

### 3. Invalidation Union

When an element mutates (moves, resizes, or changes style), the rasterizer must repaint **both** the pixels the element *used to* occupy (to clear them and restore the background) and the pixels the element *now* occupies (to draw the new state).

*   **Incremental Invalidation**: If only the geometry changes slightly or incremental invalidation is possible, Blink computes the difference (e.g., right/bottom strips).
*   **Full Paint Invalidation**: In the general case, the total damaged region $R_{\text{damage}}$ emitted to the raster invalidator (`PaintController` / `RasterInvalidator`) is the Axis-Aligned Bounding Box (AABB) union of the previous frame's visual rect ($R_{\text{old}}$) and the current frame's visual rect ($R_{\text{new}}$), both expressed in the coordinate space of the invalidation container:
    $$R_{\text{damage}} = R_{\text{old}} \cup_{\text{AABB}} R_{\text{new}}$$

If either $R_{\text{old}}$ or $R_{\text{new}}$ is empty (zero width or height), the union operation acts as an identity element, returning the non-empty rect (to avoid expanding the bounding box to $(0,0)$ if the empty rect is located at the origin).

---

### 4. Mathematical Invariants

Let a valid rectangle $R$ be defined by $(x, y, w, h) \in \mathbb{Z}^4$ (representing Blink's `IntRect` or snapped `PhysicalRect`). A rectangle is **well-formed** if $w \ge 0 \land h \ge 0$. A rectangle is **empty** if $w \le 0 \lor h \le 0$.

1.  **Non-Negativity (Well-Formedness)**: For any input rectangle, normalization (or valid construction) ensures $w \ge 0$ and $h \ge 0$. All property tree operations (translations, intersections, AABB unions, outsets) preserve non-negativity.
2.  **Containment**: For any point $p = (p_x, p_y) \in \mathbb{Z}^2$, define $p \in R \iff x \le p_x < x + w \land y \le p_y < y + h$. The bounding box union $R_1 \cup_{\text{AABB}} R_2$ satisfies:
    $$\forall p, \quad (p \in R_1 \lor p \in R_2) \implies p \in (R_1 \cup_{\text{AABB}} R_2)$$
    *(Note: The converse does not hold because AABB union includes the convex hull's dead space between disjoint rects).*
3.  **Commutativity**: Up to empty-rectangle canonicalization, the union of the old and new visual rects is independent of operand order:
    $$R_{\text{old}} \cup_{\text{AABB}} R_{\text{new}} = R_{\text{new}} \cup_{\text{AABB}} R_{\text{old}}$$
4.  **Associativity**: Accumulating damage across multiple sub-fragments or layout phases is independent of grouping:
    $$(R_1 \cup_{\text{AABB}} R_2) \cup_{\text{AABB}} R_3 = R_1 \cup_{\text{AABB}} (R_2 \cup_{\text{AABB}} R_3)$$

---

### 5. Rocq / Coq Formalization (`BlinkPaintInvalidationRectSemantics.v`)

Below is the complete, self-contained Rocq (Coq) formalization proving the non-negativity, containment, commutativity, and associativity invariants of Blink's paint invalidation geometry and property tree mappings.

```coq
(** * BlinkPaintInvalidationRectSemantics.v
    Formal verification of Chromium Blink Paint Invalidation Rect Semantics,
    Property Tree VisualRectMapping, and AABB Union Invariants. *)

From Coq Require Import ZArith.
From Coq Require Import Lia.
From Coq Require Import List.
Import ListNotations.

Open Scope Z_scope.

(** ** 1. Core Geometry Data Structures *)

(** Represents a discrete Axis-Aligned Bounding Box (e.g., Blink's IntRect / PhysicalRect).
    To ensure canonical representation of empty rects (so union is strictly commutative
    and associative without equivalence classes), we use an explicit inductive type. *)
Inductive VisualRect : Type :=
  | EmptyRect : VisualRect
  | Box (x1 y1 x2 y2 : Z) : VisualRect. (* Represents [x1, x2) x [y1, y2) *)

(** Smart constructor from (x, y, width, height) matching Blink's LayoutRect/IntRect *)
Definition mk_rect (x y w h : Z) : VisualRect :=
  if (w <=? 0) || (h <=? 0) then EmptyRect
  else Box x y (x + w) (y + h).

(** Width and height extractors *)
Definition width (r : VisualRect) : Z :=
  match r with
  | EmptyRect => 0
  | Box x1 _ x2 _ => Z.max 0 (x2 - x1)
  end.

Definition height (r : VisualRect) : Z :=
  match r with
  | EmptyRect => 0
  | Box _ y1 _ y2 => Z.max 0 (y2 - y1)
  end.

(** Well-formedness invariant: non-empty boxes have strictly positive dimensions *)
Definition wf_rect (r : VisualRect) : Prop :=
  match r with
  | EmptyRect => True
  | Box x1 y1 x2 y2 => x1 < x2 /\ y1 < y2
  end.

(** Point containment semantics: half-open interval [x1, x2) x [y1, y2) *)
Definition in_rect (px py : Z) (r : VisualRect) : Prop :=
  match r with
  | EmptyRect => False
  | Box x1 y1 x2 y2 => x1 <= px < x2 /\ y1 <= py < y2
  end.

(** ** 2. Invalidation Operations: Intersection (Clip) and Union (Damage) *)

(** Clip intersection (used by ClipPaintPropertyNode) *)
Definition rect_intersect (r1 r2 : VisualRect) : VisualRect :=
  match r1, r2 with
  | EmptyRect, _ => EmptyRect
  | _, EmptyRect => EmptyRect
  | Box ax1 ay1 ax2 ay2, Box bx1 by1 bx2 by2 =>
      let nx1 := Z.max ax1 bx1 in
      let ny1 := Z.max ay1 by1 in
      let nx2 := Z.min ax2 bx2 in
      let ny2 := Z.min ay2 by2 in
      if (nx2 <=? nx1) || (ny2 <=? ny1) then EmptyRect
      else Box nx1 ny1 nx2 ny2
  end.

(** Bounding box union (used by PaintInvalidator to combine old_visual_rect and new_visual_rect) *)
Definition rect_union (r1 r2 : VisualRect) : VisualRect :=
  match r1, r2 with
  | EmptyRect, r => r
  | r, EmptyRect => r
  | Box ax1 ay1 ax2 ay2, Box bx1 by1 bx2 by2 =>
      Box (Z.min ax1 bx1) (Z.min ay1 by1) (Z.max ax2 bx2) (Z.max ay2 by2)
  end.

(** ** 3. Paint Property Tree & VisualRectMapping (GeometryMapper) *)

Inductive PaintPropertyNode : Type :=
  | TransformTranslation (dx dy : Z)           (* 2D translation / PaintOffset *)
  | ScrollTranslation (sx sy : Z)              (* ScrollPaintPropertyNode offset *)
  | ClipNode (clip_rect : VisualRect)          (* ClipPaintPropertyNode *)
  | EffectOutset (outset : Z).                 (* EffectPaintPropertyNode blur/shadow *)

Definition apply_node (node : PaintPropertyNode) (r : VisualRect) : VisualRect :=
  match node, r with
  | _, EmptyRect => EmptyRect
  | TransformTranslation dx dy, Box x1 y1 x2 y2 =>
      Box (x1 + dx) (y1 + dy) (x2 + dx) (y2 + dy)
  | ScrollTranslation sx sy, Box x1 y1 x2 y2 =>
      Box (x1 - sx) (y1 - sy) (x2 - sx) (y2 - sy)
  | ClipNode clip, _ =>
      rect_intersect r clip
  | EffectOutset d, Box x1 y1 x2 y2 =>
      let out := Z.max 0 d in
      Box (x1 - out) (y1 - out) (x2 + out) (y2 + out)
  end.

(** Maps a local layout rect through a chain of PaintPropertyNodes to the backing space *)
Fixpoint map_to_backing (chain : list PaintPropertyNode) (local_rect : VisualRect) : VisualRect :=
  match chain with
  | [] => local_rect
  | node :: rest => map_to_backing rest (apply_node node local_rect)
  end.

(** Core PaintInvalidator damage computation *)
Definition compute_invalidation_rect
  (old_chain new_chain : list PaintPropertyNode)
  (old_local new_local : VisualRect) : VisualRect :=
  let old_visual := map_to_backing old_chain old_local in
  let new_visual := map_to_backing new_chain new_local in
  rect_union old_visual new_visual.

(** ** 4. Formal Proofs of Mathematical Invariants *)

(** *** Invariant 1: Non-Negativity & Well-Formedness Preservation *)

Theorem width_nonneg : forall r, 0 <= width r.
Proof.
  intros [|x1 y1 x2 y2]; simpl; lia.
Qed.

Theorem height_nonneg : forall r, 0 <= height r.
Proof.
  intros [|x1 y1 x2 y2]; simpl; lia.
Qed.

Theorem mk_rect_wf : forall x y w h, wf_rect (mk_rect x y w h).
Proof.
  intros x y w h. unfold mk_rect.
  destruct ((w <=? 0) || (h <=? 0)) eqn:E.
  - simpl. exact I.
  - apply Bool.orb_false_iff in E. destruct E as [Ew Eh].
    apply Z.leb_gt in Ew. apply Z.leb_gt in Eh.
    simpl. lia.
Qed.

Lemma intersect_wf : forall r1 r2, wf_rect r1 -> wf_rect r2 -> wf_rect (rect_intersect r1 r2).
Proof.
  intros [|ax1 ay1 ax2 ay2] [|bx1 by1 bx2 by2] H1 H2; simpl in *; auto.
  destruct ((Z.min ax2 bx2 <=? Z.max ax1 bx1) || (Z.min ay2 by2 <=? Z.max ay1 by1)) eqn:E.
  - simpl. exact I.
  - apply Bool.orb_false_iff in E. destruct E as [Ex Ey].
    apply Z.leb_gt in Ex. apply Z.leb_gt in Ey.
    simpl. lia.
Qed.

Lemma union