**Audit Report: Agent 303**
**Target:** Chromium Blink SVG Marker Orientation (`auto-start-reverse` semantics)
**Artifact:** `BlinkSVGMarkerOrientationSemantics.v`

---

### 1. Start Marker Angle Specification
According to the SVG2 Specification (and implemented in Chromium Blink's `SVGMarkerOrientType` and `LayoutSVGResourceMarker`), the `orient` attribute on a `<marker>` element accepts the value `auto-start-reverse`. 

* **Standard `auto` behavior:** The marker is oriented such that its positive x-axis points in the direction of the path at the vertex where it is placed.
* **`auto-start-reverse` behavior:** If the marker is positioned at the **start** vertex of a path (`kStartMarker`), the computed orientation angle is reversed by adding $180^\circ$ modulo $360^\circ$:
  $$\theta_{\text{final}} = (\theta_{\text{path}} + 180) \bmod 360$$
  For **mid** (`kMidMarker`) and **end** (`kEndMarker`) vertices, the orientation remains identical to `auto`:
  $$\theta_{\text{final}} = \theta_{\text{path}} \bmod 360$$

---

### 2. Core Invariants
1. **Involution of Reversal:** Reversing an angle twice must yield the original normalized angle.
   $$(( \theta + 180 ) \bmod 360 + 180) \bmod 360 = (\theta + 180 + 180) \bmod 360 = \theta \bmod 360$$
2. **Range Normalization:** All computed marker orientations must strictly fall within the canonical interval $[0, 360)$.
3. **Non-Start Equivalence:** For non-start vertices, `auto-start-reverse` is observationally equivalent to `auto`.

---

### 3. Rocq / Coq Formalization (`BlinkSVGMarkerOrientationSemantics.v`)

The following formalization is verified to compile with **0 admits** in standard Coq/Rocq using the `ZArith` library.

```coq
(** * BlinkSVGMarkerOrientationSemantics.v
    Formal Audit by Agent 303: Chromium Blink SVG Marker Orientation *)

Require Import Coq.ZArith.ZArith.
Require Import Coq.micromega.Lia.

Open Scope Z_scope.

(** ** 1. Data Types and Domain Definitions *)

(** Represents the vertex position along the SVG path.
    Corresponds to Blink's SVGMarkerPositionType. *)
Inductive MarkerPosition : Type :=
  | StartMarker
  | MidMarker
  | EndMarker.

(** Represents the 'orient' attribute of an SVG <marker> element.
    Corresponds to Blink's SVGMarkerOrientType. *)
Inductive MarkerOrient : Type :=
  | OrientFixed (angle : Z)
  | OrientAuto
  | OrientAutoStartReverse.

(** Canonical normalization of angles into the [0, 360) degree range. *)
Definition normalize_angle (angle : Z) : Z :=
  angle mod 360.

(** Reverses a given angle by 180 degrees within the [0, 360) space. *)
Definition reverse_angle (angle : Z) : Z :=
  normalize_angle (angle + 180).

(** Computes the final orientation angle of a marker given its orient rule,
    its position on the path, and the path's tangent angle at that vertex. *)
Definition compute_marker_angle
  (orient : MarkerOrient)
  (pos : MarkerPosition)
  (path_angle : Z) : Z :=
  match orient with
  | OrientFixed fixed_angle => normalize_angle fixed_angle
  | OrientAuto => normalize_angle path_angle
  | OrientAutoStartReverse =>
      match pos with
      | StartMarker => reverse_angle path_angle
      | MidMarker | EndMarker => normalize_angle path_angle
      end
  end.

(** ** 2. Semantic Invariants and Theorems *)

(** Invariant 1 (Raw Double Reversal):
    Adding 180 degrees twice modulo 360 returns the original normalized angle. *)
Theorem raw_double_reverse_id : forall (angle : Z),
  (angle + 180 + 180) mod 360 = angle mod 360.
Proof.
  intros angle.
  replace (angle + 180 + 180) with (angle + 1 * 360) by lia.
  apply Z.mod_add.
  lia.
Qed.

(** Invariant 2 (Functional Involution):
    Applying [reverse_angle] twice is equivalent to a single normalization. *)
Theorem reverse_angle_involution : forall (angle : Z),
  reverse_angle (reverse_angle angle) = normalize_angle angle.
Proof.
  intros angle.
  unfold reverse_angle, normalize_angle.
  rewrite Zplus_mod_idemp_l.
  apply raw_double_reverse_id.
Qed.

(** Invariant 3 (Canonical Angle Bounds):
    Any angle computed by [compute_marker_angle] strictly resides in [0, 360). *)
Theorem compute_marker_angle_bounds :
  forall (orient : MarkerOrient) (pos : MarkerPosition) (path_angle : Z),
  0 <= compute_marker_angle orient pos path_angle < 360.
Proof.
  intros orient pos path_angle.
   assert (H360 : 360 > 0) by lia.
  destruct orient as [fixed_angle | | ]; simpl.
  - unfold normalize_angle. apply Z_mod_lt. exact H360.
  - unfold normalize_angle. apply Z_mod_lt. exact H360.
  - destruct pos; unfold reverse_angle, normalize_angle; apply Z_mod_lt; exact H360.
Qed.

(** Invariant 4 (Start Marker Reversal Correctness):
    Under [OrientAutoStartReverse], a [StartMarker] is oriented exactly 180 degrees
    opposite to what [OrientAuto] would produce, modulo 360. *)
Theorem auto_start_reverse_shifts_start_by_180 : forall (path_angle : Z),
  compute_marker_angle OrientAutoStartReverse StartMarker path_angle =
  normalize_angle (compute_marker_angle OrientAuto StartMarker path_angle + 180).
Proof.
  intros path_angle.
  simpl.
  unfold reverse_angle, normalize_angle.
  symmetry.
  apply Zplus_mod_idemp_l.
Qed.

(** Invariant 5 (Non-Start Equivalence):
    For [MidMarker] and [EndMarker], [OrientAutoStartReverse] behaves identically
    to [OrientAuto]. *)
Theorem auto_start_reverse_non_start_equiv :
  forall (pos : MarkerPosition) (path_angle : Z),
  pos <> StartMarker ->
  compute_marker_angle OrientAutoStartReverse pos path_angle =
  compute_marker_angle OrientAuto pos path_angle.
Proof.
  intros pos path_angle Hnot_start.
  destruct pos; simpl.
  - contradiction.
  - reflexivity.
  - reflexivity.
Qed.
```