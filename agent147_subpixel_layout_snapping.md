### 1. LayoutUnit Fixed-Point Representation vs. CSS Values 3 §5.1

Per **CSS Values and Units Module Level 3 §5.1**, length values are theoretically real numbers, though user agents must approximate them with finite precision. Chromium’s Blink layout engine implements this approximation using `LayoutUnit`, a 32-bit signed fixed-point representation configured as **26.6** (`kFixedPointDenominator = 64`, `kLayoutUnitFractionalBits = 6`). 

* **Representation**: A `LayoutUnit` $x$ is backed by an integer $x_{raw} \in [-2^{31}, 2^{31}-1]$, representing the physical CSS pixel value $\frac{x_{raw}}{64}$. The resolution (quantum) is $\epsilon = \frac{1}{64} = 0.015625\text{ px}$.
* **Snapping Functions**: Blink maps subpixel `LayoutUnit` values to integer device/CSS pixels via three primary operations (operating on $x_{raw}$):
  * **`Floor()`**: $\lfloor \frac{x_{raw}}{64} \rfloor = \text{ x\_raw } \gg 6$ (arithmetic shift right, rounding toward $-\infty$).
  * **`Ceil()`**: $\lceil \frac{x_{raw}}{64} \rceil = \lfloor \frac{x_{raw} + 63}{64} \rfloor$.
  * **`Round()`**: Rounds to the nearest integer, resolving halfway cases ($\pm 0.5\text{ px}$, or $x_{raw} \equiv 32 \pmod{64}$) toward $+\infty$ (up):
    $$\text{Round}(x_{raw}) = \left\lfloor \frac{x_{raw} + 32}{64} \right\rfloor$$

---

### 2. Pixel Snapping of Borders/Coordinates & Error Bounds

During the Paint and Compositing phases, Blink snaps layout coordinates and box dimensions to integer pixel boundaries to prevent anti-aliasing blur on sharp edges (e.g., `SnapSizeToPixel`).

* **Coordinate Snapping**: Given a `LayoutUnit` coordinate with raw value $x$, its snapped integer pixel coordinate is:
  $$\text{snap}(x) = \text{Round}(x) = \left\lfloor \frac{x + 32}{64} \right\rfloor$$
  When projected back into the `LayoutUnit` domain, the snapped value is $64 \cdot \text{snap}(x)$.
* **Size/Border Snapping (`SnapSizeToPixel`)**: To prevent gaps between adjacent boxes, the width/size $w$ starting at offset $x$ is snapped as:
  $$\text{snap\_size}(w, x) = \text{snap}(x + w) - \text{snap}(x) = \left\lfloor \frac{x + w + 32}{64} \right\rfloor - \left\lfloor \frac{x + 32}{64} \right\rfloor$$
* **Snapping Error Bound**: By Euclidean division, let $x + 32 = 64q + r$ where $q = \text{snap}(x)$ and $0 \le r < 64$. Rearranging gives:
  $$x - 64 \cdot \text{snap}(x) = r - 32$$
  Since $0 \le r \le 63$, the quantization error in `LayoutUnit` quanta is bounded by:
  $$-32 \le x - 64 \cdot \text{snap}(x) \le 31 \implies |x - 64 \cdot \text{snap}(x)| \le 32$$
  In CSS pixel units, the maximum absolute snapping error is $\frac{32}{64} = 0.5\text{ px}$.

---

### 3. Formal Invariants

1. **Non-Negativity Preservation**: For any non-negative `LayoutUnit` $x \ge 0$, $x + 32 \ge 32 > 0$, hence $\text{snap}(x) = \lfloor \frac{x+32}{64} \rfloor \ge 0$.
2. **Idempotence on Integer Pixel Boundaries**: If $x$ already lies on an integer pixel boundary ($x = 64k$ for $k \in \mathbb{Z}$), then $\text{snap}(64k) = \lfloor \frac{64k + 32}{64} \rfloor = k + \lfloor \frac{32}{64} \rfloor = k$. Projecting back to `LayoutUnit` yields $64 \cdot \text{snap}(64 \cdot \text{snap}(x)) = 64 \cdot \text{snap}(x)$.
3. **Approximate Additivity (Triangle-like Inequality)**: Because independent snapping of two segments can accumulate two half-pixel rounding errors in the same direction, strict subadditivity does not hold ($\text{snap}(32 + 32) = 1 \le \text{snap}(32) + \text{snap}(32) = 2$, while $\text{snap}(31 + 31) = 1 > \text{snap}(31) + \text{snap}(31) = 0$). However, the discrepancy is strictly bounded by $1\text{ px}$:
   $$|\text{snap}(x + y) - (\text{snap}(x) + \text{snap}(y))| \le 1$$

---

### 4. Rocq / Coq Formalization (`BlinkSubpixelLayoutSnappingSemantics.v`)

```coq
(** * BlinkSubpixelLayoutSnappingSemantics.v
    Formal verification of Chromium Blink LayoutUnit (26.6 fixed-point)
    subpixel snapping semantics vs CSS Values and Units Level 3 §5.1. *)

From Coq Require Import ZArith Psatz.
Open Scope Z_scope.

(** ** 1. Representation & Snapping Definitions *)

Definition kFixedPointDenominator : Z := 64.
Definition kHalfPixel : Z := 32.

(** LayoutUnit is represented by its raw underlying integer value. *)
Definition LayoutUnit := Z.

(** Floor: rounds toward -infinity *)
Definition lu_floor (x : LayoutUnit) : Z :=
  x / kFixedPointDenominator.

(** Ceil: rounds toward +infinity *)
Definition lu_ceil (x : LayoutUnit) : Z :=
  (x + (kFixedPointDenominator - 1)) / kFixedPointDenominator.

(** Round / Snap: rounds to nearest integer, ties (+32/64) toward +infinity *)
Definition snap (x : LayoutUnit) : Z :=
  (x + kHalfPixel) / kFixedPointDenominator.

(** Convert an integer pixel coordinate back to LayoutUnit domain *)
Definition from_pixel (p : Z) : LayoutUnit :=
  kFixedPointDenominator * p.

(** SnapSizeToPixel: snaps width [w] relative to starting offset [x] *)
Definition snap_size (w x : LayoutUnit) : Z :=
  snap (x + w) - snap x.

(** ** 2. Error Bounds *)

Theorem snap_error_asymmetric : forall (x : LayoutUnit),
  -32 <= x - from_pixel (snap x) <= 31.
Proof.
  intros x.
  unfold from_pixel, snap, kFixedPointDenominator, kHalfPixel.
  pose proof (Z.div_mod (x + 32) 64) as Hdiv.
  pose proof (Z_mod_lt (x + 32) 64) as Hmod.
  lia.
Qed.

Theorem snap_error_bound : forall (x : LayoutUnit),
  Z.abs (x - from_pixel (snap x)) <= 32.
Proof.
  intros x.
  pose proof (snap_error_asymmetric x) as H.
  lia.
Qed.

(** ** 3. Core Invariants *)

(** Invariant 3.1: Non-negativity for non-negative inputs *)
Theorem snap_nonneg : forall (x : LayoutUnit),
  0 <= x -> 0 <= snap x.
Proof.
  intros x Hx.
  unfold snap, kFixedPointDenominator, kHalfPixel.
  apply Z.div_pos; lia.
Qed.

(** Invariant 3.2: Exactness & Idempotence on integer pixel boundaries *)
Theorem snap_exact_on_pixel : forall (k : Z),
  snap (from_pixel k) = k.
Proof.
  intros k.
  unfold snap, from_pixel, kFixedPointDenominator, kHalfPixel.
  replace (64 * k + 32) with (k * 64 + 32) by lia.
  rewrite Z.div_add_l by lia.
  simpl. lia.
Qed.

Theorem snap_idempotent : forall (x : LayoutUnit),
  snap (from_pixel (snap x)) = snap x.
Proof.
  intros x.
  apply snap_exact_on_pixel.
Qed.

(** Invariant 3.3: Monotonicity *)
Theorem snap_monotonic : forall (x y : LayoutUnit),
  x <= y -> snap x <= snap y.
Proof.
  intros x y Hxy.
  unfold snap, kFixedPointDenominator, kHalfPixel.
  apply Z.div_le_mono; lia.
Qed.

(** Invariant 3.4: Subadditivity / Triangle Inequality Defect Bound
    |snap(x + y) - (snap(x) + snap(y))| <= 1 *)
Theorem snap_add_defect_bound : forall (x y : LayoutUnit),
  Z.abs (snap (x + y) - (snap x + snap y)) <= 1.
Proof.
  intros x y.
  unfold snap, kFixedPointDenominator, kHalfPixel.
  pose proof (Z.div_mod (x + 32) 64) as Hdx.
  pose proof (Z_mod_lt (x + 32) 64) as Hmx.
  pose proof (Z.div_mod (y + 32) 64) as Hdy.
  pose proof (Z_mod_lt (y + 32) 64) as Hmy.
  pose proof (Z.div_mod (x + y + 32) 64) as Hdxy.
  pose proof (Z_mod_lt (x + y + 32) 64) as Hmxy.
  lia.
Qed.

(** Invariant 3.5: Triangle inequality for snapped magnitudes *)
Theorem snap_triangle_inequality : forall (x y : LayoutUnit),
  Z.abs (snap (x + y)) <= Z.abs (snap x) + Z.abs (snap y) + 1.
Proof.
  intros x y.
  pose proof (snap_add_defect_bound x y) as H.
  lia.
Qed.

(** Invariant 3.6: Telescope property of SnapSizeToPixel (Adjacent Boxes)
    Guarantees zero-gap layout between adjacent sibling boxes. *)
Theorem snap_size_telescope : forall (x w1 w2 : LayoutUnit),
  snap_size w1 x + snap_size w2 (x + w1) = snap_size (w1 + w2) x.
Proof.
  intros x w1 w2.
  unfold snap_size.
  replace (x + w1 + w2) with (x + (w1 + w2)) by lia.
  lia.
Qed.
```