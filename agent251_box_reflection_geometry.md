### Audit Report: Agent 251 — Chromium Blink Box Reflection Geometry

#### 1. Reflection Geometry Details (Direction: Below)
In Chromium Blink (`LayoutBoxModelObject` and `PaintLayer` reflection geometry calculation), a box reflection is defined by a direction (above, below, left, right) and a scalar offset. 

For a `kReflectionBelow` operation:
* Let the layout box have vertical position $y_{\text{box}}$ and height $h_{\text{box}}$. The bottom edge of the box is at $B = y_{\text{box}} + h_{\text{box}}$.
* Given an offset $o$ (`offset`), the axis of reflection lies horizontally at $A = B + \frac{o}{2} = y_{\text{box}} + h_{\text{box}} + \frac{o}{2}$.
* A point $y$ is reflected across axis $A$ via the isometric point-reflection mapping $R_{\text{pt}}(y) = 2A - y = 2(y_{\text{box}} + h_{\text{box}}) + o - y$.
* When reflecting a sub-element or the box content itself (which has origin $y_{\text{orig}}$ and height $h_{\text{box}}$), its original vertical interval is $[y_{\text{orig}}, y_{\text{orig}} + h_{\text{box}}]$. Under orientation-reversing reflection, the new top edge ($y_{\text{reflect}}$) is the image of the original bottom edge ($y_{\text{orig}} + h_{\text{box}}$):
  $$y_{\text{reflect}} = 2(y_{\text{box}} + h_{\text{box}}) + \text{offset} - (y_{\text{orig}} + h_{\text{box}})$$
  The new bottom edge is the image of the original top edge ($y_{\text{orig}}$):
  $$y_{\text{reflect\_bottom}} = 2(y_{\text{box}} + h_{\text{box}}) + \text{offset} - y_{\text{orig}}$$

#### 2. Geometric Invariants
1. **Height Preservation**: The vertical span (height) of the reflected bounding box is invariant under the reflection transformation: $y_{\text{reflect\_bottom}} - y_{\text{reflect}} = h_{\text{box}}$.
2. **Isometry**: The point reflection transformation preserves distances between any two points $y_1, y_2 \in \mathbb{Z}$: $|R_{\text{pt}}(y_1) - R_{\text{pt}}(y_2)| = |y_1 - y_2|$.
3. **Involution**: Reflecting a point or a bounding box twice across the same reflection axis yields the exact original geometry.

---

#### 3. Formal Verification (`BlinkBoxReflectionGeometrySemantics.v`)

The following Rocq/Coq specification formalizes the `kReflectionBelow` geometry over integer layout units (`Z`), proving height preservation, involutivity, and isometry with 0 admits.

```coq
(** * BlinkBoxReflectionGeometrySemantics.v
    Formal Audit by Agent 251: Chromium Blink Box Reflection Geometry *)

From Coq Require Import ZArith.
From Coq Require Import Lia.

Open Scope Z_scope.

Section BlinkReflectionGeometry.

  (** ** 1. Definitions *)

  (** Point reflection across the horizontal reflection axis for a 'below' reflection.
      The axis is located at (y_box + h_box) + offset / 2.
      Thus, 2 * Axis = 2 * (y_box + h_box) + offset. *)
  Definition reflect_point_below (y_box h_box offset y : Z) : Z :=
    2 * (y_box + h_box) + offset - y.

  (** Bounding box top-edge reflection for 'below' reflection.
      The new top edge is the reflection of the original bottom edge (y_orig + h_box). *)
  Definition y_reflect_below (y_box h_box offset y_orig : Z) : Z :=
    2 * (y_box + h_box) + offset - (y_orig + h_box).

  (** Bounding box bottom-edge reflection for 'below' reflection.
      The new bottom edge is the reflection of the original top edge (y_orig). *)
  Definition y_reflect_below_bottom (y_box h_box offset y_orig : Z) : Z :=
    2 * (y_box + h_box) + offset - y_orig.

  (** ** 2. Consistency & Structural Lemmas *)

  (** Verify that the box top-edge reflection formula matches the point reflection
      of the original box's bottom edge. *)
  Lemma y_reflect_below_is_point_reflection :
    forall y_box h_box offset y_orig : Z,
      y_reflect_below y_box h_box offset y_orig =
      reflect_point_below y_box h_box offset (y_orig + h_box).
  Proof.
    intros y_box h_box offset y_orig.
    unfold y_reflect_below, reflect_point_below.
    reflexivity.
  Qed.

  (** Verify that the box bottom-edge reflection formula matches the point reflection
      of the original box's top edge. *)
  Lemma y_reflect_below_bottom_is_point_reflection :
    forall y_box h_box offset y_orig : Z,
      y_reflect_below_bottom y_box h_box offset y_orig =
      reflect_point_below y_box h_box offset y_orig.
  Proof.
    intros y_box h_box offset y_orig.
    unfold y_reflect_below_bottom, reflect_point_below.
    reflexivity.
  Qed.

  (** ** 3. Primary Invariants *)

  (** Invariant 1: Reflection preserves the height of the reflected content.
      The distance between the reflected bottom edge and reflected top edge
      is strictly equal to the original height (h_box). *)
  Theorem reflection_preserves_height :
    forall y_box h_box offset y_orig : Z,
      y_reflect_below_bottom y_box h_box offset y_orig -
      y_reflect_below y_box h_box offset y_orig = h_box.
  Proof.
    intros y_box h_box offset y_orig.
    unfold y_reflect_below_bottom, y_reflect_below.
    lia.
  Qed.

  (** Invariant 2a: Reflection is an orientation-reversing isometry (signed distance). *)
  Lemma reflection_negates_signed_distance :
    forall y_box h_box offset y1 y2 : Z,
      reflect_point_below y_box h_box offset y1 -
      reflect_point_below y_box h_box offset y2 = - (y1 - y2).
  Proof.
    intros y_box h_box offset y1 y2.
    unfold reflect_point_below.
    lia.
  Qed.

  (** Invariant 2b: Reflection is isometric (preserves absolute distance between points). *)
  Theorem reflection_is_isometric :
    forall y_box h_box offset y1 y2 : Z,
      Z.abs (reflect_point_below y_box h_box offset y1 -
             reflect_point_below y_box h_box offset y2) =
      Z.abs (y1 - y2).
  Proof.
    intros y_box h_box offset y1 y2.
    unfold reflect_point_below.
    lia.
  Qed.

  (** Invariant 3a: Point reflection is an involution. *)
  Theorem reflect_point_below_involutive :
    forall y_box h_box offset y : Z,
      reflect_point_below y_box h_box offset
        (reflect_point_below y_box h_box offset y) = y.
  Proof.
    intros y_box h_box offset y.
    unfold reflect_point_below.
    lia.
  Qed.

  (** Invariant 3b: Box top-edge reflection is an involution. *)
  Theorem y_reflect_below_involutive :
    forall y_box h_box offset y_orig : Z,
      y_reflect_below y_box h_box offset
        (y_reflect_below y_box h_box offset y_orig) = y_orig.
  Proof.
    intros y_box h_box offset y_orig.
    unfold y_reflect_below.
    lia.
  Qed.

  (** Invariant 4: Self-reflection gap.
      When reflecting the box itself (y_orig = y_box), the distance between the 
      original bottom edge (y_box + h_box) and the reflected top edge is exactly 'offset'. *)
  Theorem self_reflection_gap_is_offset :
    forall y_box h_box offset : Z,
      y_reflect_below y_box h_box offset y_box - (y_box + h_box) = offset.
  Proof.
    intros y_box h_box offset.
    unfold y_reflect_below.
    lia.
  Qed.

End BlinkReflectionGeometry.
```