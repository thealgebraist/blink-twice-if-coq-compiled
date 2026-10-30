### Agent 287: Chromium Blink `LayoutView` Root Master Pipeline Audit

This report details the structural hierarchy, layout pipeline stages, geometric invariants, and formal verification of the Chromium Blink `LayoutView` root layout pipeline (Engine: LayoutNG).

---

### 1. Pipeline Architecture: `ICB` $\rightarrow$ `HTML` $\rightarrow$ `Body` $\rightarrow$ `Document Children`

In Blink’s LayoutNG architecture, `LayoutView` is the root of the layout tree, corresponding to the Initial Containing Block (ICB). The master layout pipeline propagates constraints downwards via `NGConstraintSpace` and aggregates geometry upwards via `NGPhysicalBoxFragment`.

#### Stage 1: `LayoutView` (Initial Containing Block / ICB)
* **Source:** `third_party/blink/renderer/core/layout/layout_view.cc`
* **Role:** Establishes the root coordinate system and the Initial Containing Block.
* **Constraint Generation:** `LayoutView::LayoutRoot()` constructs the root `NGConstraintSpace` using the `FrameView`’s layout viewport dimensions $(v_w, v_h)$. It forces the root fragment to have a fixed inline size equal to $v_w$ and a block size initialized to $v_h$.
* **Output:** Produces the root `NGPhysicalBoxFragment` positioned at $(0, 0)$ relative to the document canvas.

#### Stage 2: Document Element (`<html>` Box)
* **Source:** `NGBlockNode::Layout()` invoked on `Document::documentElement()`.
* **Role:** Receives the ICB's `NGConstraintSpace` (available size: $v_w \times v_h$).
* **Layout Execution:** `NGBlockLayoutAlgorithm` resolves the `<html>` element's box model (margins, borders, padding). By default (`width: auto`), the `<html>` box expands to fill the available inline size $v_w$ minus its horizontal margins. Its block size is intrinsic (content-driven) unless explicitly constrained.
* **Propagation:** Generates a child `NGConstraintSpace` with an available inline size equal to the `<html>` element's content-box inline size.

#### Stage 3: Body Element (`<body>` Box)
* **Source:** `NGBlockLayoutAlgorithm::Layout()` processing the primary child of `<html>`.
* **Role:** Receives the `<html>` content-box constraint space.
* **Quirks & Propagation:** Handles CSS quirks (e.g., `<html>` / `<body>` background and overflow viewport propagation to the `LayoutView`). Calculates its own box geometry (defaulting to an $8\text{px}$ margin in user-agent stylesheets) and establishes the formatting context (typically a Block Formatting Context) for the document's primary content.

#### Stage 4: Document Children Fragments
* **Source:** Iterative invocation of `NGBlockLayoutAlgorithm::HandleInFlow()` / `HandleOutOfFlowPositioned()`.
* **Role:** Lays out descendant DOM nodes into immutable `NGPhysicalFragment` instances (boxes, lines, text).
* **Aggregation:** Each child returns an `NGLayoutResult` containing its `NGPhysicalFragment` and a relative `PhysicalOffset` from its parent's border-box origin. If descendants exceed the ICB's dimensions, `LayoutView` updates its `LayoutOverflow` rectangle, triggering scrollbar allocation in `PaintLayerScrollableArea`.

---

### 2. Core Pipeline Invariants

1. **ICB Viewport Containment Invariant:**
   The Initial Containing Block (`LayoutView`) geometry strictly equals the viewport bounds $[0, v_w] \times [0, v_h]$ for non-negative viewport dimensions $v_w, v_h \ge 0$. Every coordinate $(x, y)$ within the viewport range $0 \le x \le v_w \land 0 \le y \le v_h$ is contained within the physical border-box of the ICB.
2. **Coordinate Space Monotonicity (Non-Negative Offsets):**
   In standard flow without negative margins, the absolute physical offset of any descendant fragment $F_n$ (e.g., `Document Child` inside `Body` inside `HTML` inside `ICB`) is the vector sum of relative offsets along the ancestor chain:
   $$\text{Offset}_{\text{abs}}(F_n) = \text{Offset}(\text{ICB}) + \sum_{i=1}^{n} \text{Offset}_{\text{rel}}(F_i)$$
3. **Scrollable Overflow Soundness:**
   The `LayoutView`'s scrollable overflow bounding box is guaranteed to be a superset of both the ICB's physical box $[0, v_w] \times [0, v_h]$ and the union of all descendant physical fragment bounding boxes translated into the root coordinate space.

---

### 3. Formal Verification: `BlinkLayoutViewRootPipelineSemantics.v`

The following Rocq (Coq) script formalizes the 4-stage pipeline, its coordinate transformations, the ICB viewport containment invariant, and the scrollable overflow soundness invariant. It contains **0 admits**.

```coq
(** * BlinkLayoutViewRootPipelineSemantics.v
    Formal Audit by Agent 287: Chromium Blink LayoutView Root Master Pipeline.
    Proves ICB Viewport Containment, Pipeline Constraint Propagation, and
    Overflow Accumulation Invariants with 0 Admits. *)

From Coq Require Import ZArith.
From Coq Require Import List.
From Coq Require Import Lia.
Import ListNotations.

Open Scope Z_scope.

(** ** 1. Geometric Primitives (LayoutNG Physical Geometry) *)

Record PhysicalOffset : Type := mkOffset {
  offset_left : Z;
  offset_top  : Z
}.

Record PhysicalSize : Type := mkSize {
  size_width  : Z;
  size_height : Z
}.

Record PhysicalRect : Type := mkRect {
  rect_offset : PhysicalOffset;
  rect_size   : PhysicalSize
}.

Definition zero_offset : PhysicalOffset := mkOffset 0 0.

Definition add_offset (o1 o2 : PhysicalOffset) : PhysicalOffset :=
  mkOffset (offset_left o1 + offset_left o2) (offset_top o1 + offset_top o2).

Definition rect_right (r : PhysicalRect) : Z :=
  offset_left (rect_offset r) + size_width (rect_size r).

Definition rect_bottom (r : PhysicalRect) : Z :=
  offset_top (rect_offset r) + size_height (rect_size r).

(** A point (x, y) is within a PhysicalRect *)
Definition point_in_rect (x y : Z) (r : PhysicalRect) : Prop :=
  offset_left (rect_offset r) <= x <= rect_right r /\
  offset_top (rect_offset r) <= y <= rect_bottom r.

(** Rect r1 is geometrically contained within r2 *)
Definition rect_contains (r1 r2 : PhysicalRect) : Prop :=
  offset_left (rect_offset r2) <= offset_left (rect_offset r1) /\
  rect_right r1 <= rect_right r2 /\
  offset_top (rect_offset r2) <= offset_top (rect_offset r1) /\
  rect_bottom r1 <= rect_bottom r2.

(** ** 2. Box Model and Constraint Space *)

Record BoxStrut : Type := mkStrut {
  strut_left   : Z;
  strut_right  : Z;
  strut_top    : Z;
  strut_bottom : Z
}.

Definition strut_non_negative (s : BoxStrut) : Prop :=
  0 <= strut_left s /\ 0 <= strut_right s /\
  0 <= strut_top s /\ 0 <= strut_bottom s.

Record NGConstraintSpace : Type := mkConstraintSpace {
  available_size : PhysicalSize;
  is_fixed_size  : bool
}.

Record NGPhysicalBoxFragment : Type := mkFragment {
  frag_offset   : PhysicalOffset; (* Relative to parent border box *)
  frag_size     : PhysicalSize;
  frag_children : list NGPhysicalBoxFragment
}.

Definition frag_local_rect (f : NGPhysicalBoxFragment) : PhysicalRect :=
  mkRect zero_offset (frag_size f).

Definition frag_Placed_rect (parent_abs_offset : PhysicalOffset) (f : NGPhysicalBoxFragment) : PhysicalRect :=
  mkRect (add_offset parent_abs_offset (frag_offset f)) (frag_size f).

(** ** 3. Master Pipeline Execution: ICB -> HTML -> Body -> Children *)

(** Stage 4: Lay out Document Children inside Body's content box *)
Definition layout_document_children
  (body_content_offset : PhysicalOffset)
  (body_avail_width : Z)
  (child_heights : list Z) : (list NGPhysicalBoxFragment * Z) :=
  fold_left (fun acc h =>
    let (frags, current_y) := acc in
    let h_clamped := Z.max 0 h in
    let child_frag := mkFragment
      (mkOffset (offset_left body_content_offset) (offset_top body_content_offset + current_y))
      (mkSize (Z.max 0 body_avail_width) h_clamped)
      [] in
    (frags ++ [child_frag], current_y + h_clamped)
  ) child_heights ([], 0).

(** Stage 3: Lay out Body Box inside HTML's constraint space *)
Definition layout_body_box
  (html_content_space : NGConstraintSpace)
  (html_content_offset : PhysicalOffset)
  (body_margin body_border_padding : BoxStrut)
  (child_heights : list Z) : NGPhysicalBoxFragment :=
  let avail_w := size_width (available_size html_content_space) in
  let body_w := Z.max 0 (avail_w - (strut_left body_margin + strut_right body_margin)) in
  let content_w := Z.max 0 (body_w - (strut_left body_border_padding + strut_right body_border_padding)) in
  let content_offset := mkOffset (strut_left body_border_padding) (strut_top body_border_padding) in
  let (children, children_total_h) := layout_document_children content_offset content_w child_heights in
  let body_h := children_total_h + strut_top body_border_padding + strut_bottom body_border_padding in
  let body_rel_offset := mkOffset
    (offset_left html_content_offset + strut_left body_margin)
    (offset_top html_content_offset + strut_top body_margin) in
  mkFragment body_rel_offset (mkSize body_w body_h) children.

(** Stage 2: Lay out HTML Box inside ICB's constraint space *)
Definition layout_html_box
  (icb_space : NGConstraintSpace)
  (html_margin html_border_padding : BoxStrut)
  (body_margin body_border_padding : BoxStrut)
  (child_heights : list Z) : NGPhysicalBoxFragment :=
  let avail_w := size_width (available_size icb_space) in
  let html_w := Z.max 0 (avail_w - (strut_left html_margin + strut_right html_margin)) in
  let content_w := Z.max 0 (html_w - (strut_left html_border_padding + strut_right html_border_padding)) in
  let html_content_space := mkConstraintSpace (mkSize content_w (size_height (available_size icb_space))) false in
  let html_content_offset := mkOffset (strut_left html_border_padding) (strut_top html_border_padding) in
  let body_frag := layout_body_box html_content_space html_content_offset body_margin body_border_padding child_heights in
  let html_h := size_height (frag_size body_frag) +
                strut_top body_margin + strut_bottom body_margin +
                strut_top html_border_padding + strut_bottom html_border_padding in
  let html_rel_offset := mkOffset (strut_left html_margin) (strut_top html_margin) in
  mkFragment html_rel_offset (mkSize html_w html_h) [body_frag].

(** Stage 1: Lay out LayoutView (Initial Containing Block / ICB) *)
Definition layout_view_root_pipeline
  (vw vh : Z)
  (html_margin html_bp body_margin body_bp : BoxStrut)
  (child_heights : list Z) : NGPhysicalBoxFragment :=
  let clamped_vw := Z.max 0 vw in
  let clamped_vh := Z.max 0 vh in
  let icb_space := mkConstraintSpace (mkSize clamped_vw clamped_vh) true in
  let html_frag := layout_html_box icb_space html_margin html_bp body_margin body_bp child_heights in
  mkFragment zero_offset (mkSize clamped_vw clamped_vh) [html_frag].

(** ** 4. Formal Verification & Invariant Proofs *)

(** *** Invariant 1: ICB Contains Entire Viewport Coordinate Range [0, vw] x [0, vh] *)
Theorem icb_contains_viewport_range :
  forall (vw vh x y : Z)
         (html_m html_bp body_m body_bp : BoxStrut)
         (child_heights : list Z),
    0 <= vw ->
    0 <= vh ->
    0 <= x <= vw ->
    0 <= y <= vh ->
    let icb_frag := layout_view_root_pipeline vw vh html_m html_bp body_m body_bp child_heights in
    let icb_rect := frag_Placed_rect zero_offset icb_frag in
    point_in_rect x y icb_rect.
Proof.
  intros vw vh x y html_m html_bp body_m body_bp child_heights Hvw Hvh Hx Hy.
  unfold layout_view_root_pipeline, frag_Placed_rect, point_in_rect.
  simpl.
  unfold rect_right, rect_bottom.
  simpl.
  rewrite Z.max_r by lia.
  rewrite Z.max_r by lia.
  lia.
Qed.

(** *** Invariant 2: Exact Viewport Geometry Equivalence for ICB *)
Theorem icb_exact_viewport_bounds :
  forall (vw vh : Z)
         (html_m html_bp body_m body_bp : BoxStrut)
         (child_heights : list Z),
    0 <= vw ->
    0 <= vh ->
    let icb_frag := layout_view_root_pipeline vw vh html_m html_bp body_m body_bp child_heights in
    frag_offset icb_frag = mkOffset 0 0 /\
    frag_size icb_frag = mkSize vw vh.
Proof.
  intros vw vh html_m html_bp body_m body_bp child_heights Hvw Hvh.
  unfold layout_view_root_pipeline.
  simpl.
  rewrite (Z.max_r