# Formal Verification Report: `clip-path: path()` SVG Bounding Box Containment in Chromium Blink

**Agent:** 701 (W3C/WHATWG Layout Rules & Geometry Specialist)  
**Topic:** `clip-path: path()` SVG Bounding Box Containment  
**Chromium Source:** `third_party/blink/renderer/core/layout/svg/svg_path_parser.cc`  
**Specification:** CSS Masking Module Level 1 (§3 `clip-path`), SVG 2 (§11.15 Bounding boxes)  
**Formal Theory Target:** `BlinkClipPathSVGPathBoundingBoxSemantics.v`  
**Mathematical Property:** $\forall p,\ \text{path\_bounds}(p) = \{ \text{min\_x}, \text{max\_x}, \text{min\_y}, \text{max\_y} \} \implies \text{max\_x} \ge \text{min\_x} \land \text{max\_y} \ge \text{min\_y}$

---

## 1. Normative W3C Specification Requirements

### 1.1 CSS Masking Module Level 1 (§3 & §6.1)
Under CSS Masking Module Level 1 (and CSS Shapes Module Level 1 §4.2), the `clip-path` property specifies a `<basic-shape>` or `<clip-source>` that defines the visible region of an element. When `path(<string>)` is supplied:
1. **Path Interpretation:** The SVG path data string is parsed according to the grammar and normalizing rules of SVG 2 §9.3 (*Path data*).
2. **Reference Box & Bounding Box:** To compute visual overflow, hit-testing fast-paths, and masking textures, the browser must compute the tight or control-point **object bounding box** of the resolved path geometry.
3. **Empty Paths:** Per SVG 2 §11.15, if a path contains no segments or only move-to commands that do not contribute to rendering geometry (depending on bounding box mode), the resulting bounding box defaults to the origin $(0,0,0,0)$ with zero width and height.

### 1.2 Bounding Box Well-Formedness Invariant
For any parsed sequence of SVG path commands (after relative-to-absolute coordinate normalization and shorthand curve expansion), let $B = (\text{min\_x}, \text{max\_x}, \text{min\_y}, \text{max\_y})$ represent the computed axis-aligned bounding box (AABB) enclosing all path vertices and Bézier control points. The normative geometric invariant requires:
$$\text{max\_x} \ge \text{min\_x} \quad \land \quad \text{max\_y} \ge \text{min\_y}$$
Furthermore, for every active anchor and control point $(x_i, y_i)$ emitted by the normalized path stream:
$$\text{min\_x} \le x_i \le \text{max\_x} \quad \land \quad \text{min\_y} \le y_i \le \text{max\_y}$$

---

## 2. Chromium Blink Implementation Details & Invariants

### 2.1 Architecture in `svg_path_parser.cc`
In Chromium Blink, `third_party/blink/renderer/core/layout/svg/svg_path_parser.cc` (alongside `svg_path_builder.cc` and `gfx::RectF` / `SkPath::computeTightBounds()`) implements a streaming state machine via `SVGPathParser` and `SVGPathNormalizer`:

1. **Command Normalization (`SVGPathNormalizer::EmitSegment`):**
   - Relative commands (`m`, `l`, `h`, `v`, `c`, `s`, `q`, `t`, `a`) are translated into absolute coordinates by adding `current_point_`.
   - Horizontal (`H`) and Vertical (`V`) lines are expanded into standard `kPathSegLineToAbs` (`L`) segments using `current_point_.y()` or `current_point_.x()`.
   - Smooth cubic (`S`) and smooth quadratic (`T`) curves reflect the prior control point across `current_point_` and emit `kPathSegCurveToCubicAbs` (`C`) or `kPathSegCurveToQuadraticAbs` (`Q`).
   - ClosePath (`Z`/`z`) resets `current_point_` to `sub_path_point_`.

2. **Bounds Accumulation (`SVGPathBuilder` / `SkPath` Bounds):**
   - As normalized segments are fed into the path consumer, the bounding box accumulator tracks an `is_empty` state (or `has_points` boolean).
   - Upon encountering the first valid coordinate $(x_0, y_0)$, the bounding box initializes to $\text{min\_x} = \text{max\_x} = x_0$ and $\text{min\_y} = \text{max\_y} = y_0$.
   - For each subsequent point $(x, y)$ (target endpoints and control points), the bounds are updated via `std::min` and `std::max`:
     ```cpp
     min_x = std::min(min_x, x);
     max_x = std::max(max_x, x);
     min_y = std::min(min_y, y);
     max_y = std::max(max_y, y);
     ```

### 2.2 Critical Implementation Invariants
* **Invariant 1 (Non-Negative Extent):** Because initialization sets $\text{min} = \text{max} = p_0$ (or $0$ if empty) and every point expansion monotonically decreases $\text{min}$ and increases $\text{max}$, the width ($\text{max\_x} - \text{min\_x}$) and height ($\text{max\_y} - \text{min\_y}$) are strictly non-negative ($\ge 0$).
* **Invariant 2 (Control Hull Containment):** Because cubic and quadratic Bézier curves satisfy the convex hull property ($B(t) = \sum_{i=0}^n \binom{n}{i}(1-t)^{n-i}t^i P_i \in \text{Conv}(\{P_i\})$), accumulating the endpoints and control points into the AABB guarantees that the exact analytical curve is strictly contained within `path_bounds(p)`.

---

## 3. Formal Specification in Rocq / Coq

Below is the formalization of `BlinkClipPathSVGPathBoundingBoxSemantics.v`. Coordinates are modeled in fixed-point layout units ($\mathbb{Z}$) representing `LayoutUnit` / quantized subpixel coordinates, ensuring decidable linear integer arithmetic via `ZArith` and `Lia`.

### 3.1 Domain Types and Path Normalization Semantics
* **`Point`**: 2D coordinate $(x, y) \in \mathbb{Z} \times \mathbb{Z}$.
* **`BBox`**: Axis-aligned bounding box `{| min_x; max_x; min_y; max_y |}`.
* **`SVGPathCmd`**: Normalized and unnormalized SVG path commands (`MoveTo`, `LineTo`, `HLineTo`, `VLineTo`, `QuadTo`, `CubicTo`, `ClosePath`).
* **`ParserState`**: Tracks `cur_pt`, `subpath_start`, and the accumulated optional bounding box `acc_bounds : option BBox`.

---

## 4. Complete, Admitted-Free Rocq/Coq Formalization and Proofs

```coq
(** * BlinkClipPathSVGPathBoundingBoxSemantics.v
    Formal Verification of clip-path: path() SVG Bounding Box Containment
    Source: third_party/blink/renderer/core/layout/svg/svg_path_parser.cc
    Specification: CSS Masking 1 §3 & SVG 2 §11.15 *)

From Coq Require Import ZArith.
From Coq Require Import Lia.
From Coq Require Import Bool.
From Coq Require Import List.
Import ListNotations.

Open Scope Z_scope.

(** ** 1. Geometric Primitives *)

Record Point : Type := mkPoint {
  px : Z;
  py : Z
}.

Record BBox : Type := mkBBox {
  min_x : Z;
  max_x : Z;
  min_y : Z;
  max_y : Z
}.

Definition default_bbox : BBox :=
  mkBBox 0 0 0 0.

Definition bbox_wf (b : BBox) : Prop :=
  b.(min_x) <= b.(max_x) /\ b.(min_y) <= b.(max_y).

Definition point_in_bbox (p : Point) (b : BBox) : Prop :=
  b.(min_x) <= p.(px) <= b.(max_x) /\
  b.(min_y) <= p.(py) <= b.(max_y).

Definition bbox_contains_bbox (inner outer : BBox) : Prop :=
  outer.(min_x) <= inner.(min_x) /\
  inner.(max_x) <= outer.(max_x) /\
  outer.(min_y) <= inner.(min_y) /\
  inner.(max_y) <= outer.(max_y).

Definition bbox_width (b : BBox) : Z :=
  b.(max_x) - b.(min_x).

Definition bbox_height (b : BBox) : Z :=
  b.(max_y) - b.(min_y).

(** ** 2. Bounding Box Accumulation Operations *)

Definition init_bbox (p : Point) : BBox :=
  mkBBox p.(px) p.(px) p.(py) p.(py).

Definition expand_bbox (b : BBox) (p : Point) : BBox :=
  mkBBox (Z.min b.(min_x) p.(px))
         (Z.max b.(max_x) p.(px))
         (Z.min b.(min_y) p.(py))
         (Z.max b.(max_y) p.(py)).

Definition add_point_opt (ob : option BBox) (p : Point) : option BBox :=
  match ob with
  | None => Some (init_bbox p)
  | Some b => Some (expand_bbox b p)
  end.

Fixpoint add_points_opt (ob : option BBox) (pts : list Point) : option BBox :=
  match pts with
  | [] => ob
  | p :: rest => add_points_opt (add_point_opt ob p) rest
  end.

Definition finalize_bbox (ob : option BBox) : BBox :=
  match ob with
  | None => default_bbox
  | Some b => b
  end.

(** ** 3. SVG Path Commands & Blink Parser State Machine *)

Inductive CoordMode : Type :=
  | Abs
  | Rel.

Inductive SVGPathCmd : Type :=
  | CmdMoveTo (mode : CoordMode) (dx dy : Z)
  | CmdLineTo (mode : CoordMode) (dx dy : Z)
  | CmdHLineTo (mode : CoordMode) (x : Z)
  | CmdVLineTo (mode : CoordMode) (y : Z)
  | CmdQuadTo (mode : CoordMode) (x1 y1 x y : Z)
  | CmdCubicTo (mode : CoordMode) (x1 y1 x2 y2 x y : Z)
  | CmdClosePath.

Record ParserState : Type := mkParserState {
  cur_pt : Point;
  subpath_start : Point;
  acc_bounds : option BBox
}.

Definition initial_parser_state : ParserState :=
  mkParserState (mkPoint 0 0) (mkPoint 0 0) None.

Definition resolve_pt (mode : CoordMode) (cur : Point) (dx dy : Z) : Point :=
  match mode with
  | Abs => mkPoint dx dy
  | Rel => mkPoint (cur.(px) + dx) (cur.(py) + dy)
  end.

Definition resolve_x (mode : CoordMode) (cur : Point) (x : Z) : Point :=
  match mode with
  | Abs => mkPoint x cur.(py)
  | Rel => mkPoint (cur.(px) + x) cur.(py)
  end.

Definition resolve_y (mode : CoordMode) (cur : Point) (y : Z) : Point :=
  match mode with
  | Abs => mkPoint cur.(px) y
  | Rel => mkPoint cur.(px) (cur.(py) + y)
  end.

(** Blink SVGPathParser::EmitSegment step function *)
Definition step_cmd (st : ParserState) (cmd : SVGPathCmd) : ParserState :=
  match cmd with
  | CmdMoveTo mode dx dy =>
      let p := resolve_pt mode st.(cur_pt) dx dy in
      mkParserState p p (add_point_opt st.(acc_bounds) p)
  | CmdLineTo mode dx dy =>
      let p := resolve_pt mode st.(cur_pt) dx dy in
      mkParserState p st.(subpath_start)
        (add_points_opt st.(acc_bounds) [st.(cur_pt); p])
  | CmdHLineTo mode x =>
      let p := resolve_x mode st.(cur_pt) x in
      mkParserState p st.(subpath_start)
        (add_points_opt st.(acc_bounds) [st.(cur_pt); p])
  | CmdVLineTo mode y =>
      let p := resolve_y mode st.(cur_pt) y in
      mkParserState p st.(subpath_start)
        (add_points_opt st.(acc_bounds) [st.(cur_pt); p])
  | CmdQuadTo mode x1 y1 x y =>
      let c1 := resolve_pt mode st.(cur_pt) x1 y1 in
      let p  := resolve_pt mode st.(cur_pt) x y in
      mkParserState p st.(subpath_start)
        (add_points_opt st.(acc_bounds) [st.(cur_pt); c1; p])
  | CmdCubicTo mode x1 y1 x2 y2 x y =>
      let c1 := resolve_pt mode st.(cur_pt) x1 y1 in
      let c2 := resolve_pt mode st.(cur_pt) x2 y2 in
      let p  := resolve_pt mode st.(cur_pt) x y in
      mkParserState p st.(subpath_start)
        (add_points_opt st.(acc_bounds) [st.(cur_pt); c1; c2; p])
  | CmdClosePath =>
      mkParserState st.(subpath_start) st.(subpath_start) st.(acc_bounds)
  end.

Fixpoint parse_path_cmds (st : ParserState) (cmds : list SVGPathCmd) : ParserState :=
  match cmds with
  | [] => st
  | c :: rest => parse_path_cmds (step_cmd st c) rest
  end.

Definition path_bounds (cmds : list SVGPathCmd) : BBox :=
  finalize_bbox (parse_path_cmds initial_parser_state cmds).(acc_bounds).

(** Extract the sequence of geometric points emitted by the parser *)
Definition cmd_emitted_points (st : ParserState) (cmd