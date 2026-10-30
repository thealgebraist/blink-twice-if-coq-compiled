### 1. Core Data Structures in Blink Keyframe Animation

In Chromium Blink (`third_party/blink/renderer/core/animation/`), keyframe interpolation bridges CSS Animations Level 1 and CSS Transitions Level 1 through a unified Web Animations model:

*   **`KeyframeEffectModelBase` / `KeyframeEffectModel`**: Holds the sorted vector of `Keyframe` objects (`KeyframeVector`), grouped by CSS property into `PropertySpecificKeyframeGroup` instances. It resolves implicit offsets (0% and 100%) and manages composite operations (`Replace`, `Add`, `Accumulate`).
*   **`Keyframe` & `PropertySpecificKeyframe`**: Represents an individual animation state at a normalized offset $o \in [0, 1]$. Each keyframe stores its `offset` (`std::optional<double>`), a per-keyframe `TimingFunction` (`scoped_refptr<TimingFunction>`), and property values wrapped as `InterpolationValue` (made of an `InterpolableValue` and a `NonInterpolableValue`).
*   **`CubicBezierTimingFunction`**: Implements `TimingFunction` (`ui/gfx/geometry/cubic_bezier.h` and `blink/renderer/platform/animation/timing_function.h`). Stores control points $P_1 = (x_1, y_1)$ and $P_2 = (x_2, y_2)$ where $x_1, x_2 \in [0, 1]$ and $y_1, y_2 \in \mathbb{R}$, with fixed endpoints $P_0 = (0,0)$ and $P_3 = (1,1)$.
*   **`InterpolationTime` / Progress (`double`)**: Represents the transformed iteration progress $t \in [0, 1]$ (or outside $[0, 1]$ if an outer effect timing function overshoots) passed into `GetActiveInterpolations()`.

---

### 2. Keyframe Interval Discovery

Given a sorted sequence of property-specific keyframes $K = \langle k_0, k_1, \dots, k_{n-1} \rangle$ with offsets $0 = o_0 \le o_1 \le \dots \le o_{n-1} = 1$ and overall normalized progress $t \in [0, 1]$:

1.  **Boundary & Duplicate Offset Rules (CSS Animations 1 §3.6 / Web Animations 1 §4.3.3)**:
    *   If $t < o_0$ (or $t = 0$ with multiple keyframes at $o_0 = 0$), the active interval is the first segment or a zero-width point interval $[k_0, k_0]$.
    *   If $t \ge o_{n-1}$, the active interval is bounded by the final keyframes reaching $o_{n-1} = 1$.
    *   For $t \in (0, 1)$, Blink locates the largest index $i \in \{0, \dots, n-2\}$ such that $o_i \le t$ and $o_{i+1} > t$ (or $o_i \le t \le o_{i+1}$ at boundaries).

---

### 3. Local Progress Parameter Calculation

Once the enclosing interval $[k_i, k_{i+1}]$ is selected with offsets $o_i$ and $o_{i+1}$:

$$\alpha = \begin{cases} 
1.0 & \text{if } o_{i+1} = o_i \text{ and } t \ge o_{i+1} \\
0.0 & \text{if } o_{i+1} = o_i \text{ and } t < o_i \\
\dfrac{t - o_i}{o_{i+1} - o_i} & \text{if } o_{i+1} > o_i 
\end{cases}$$

For strictly increasing offsets ($o_i < o_{i+1}$) and $t \in [o_i, o_{i+1}]$, we have $\alpha \in [0, 1]$.

---

### 4. Cubic-Bézier Evaluation & Linear Interpolation (`lerp`)

#### Parametric Cubic-Bézier Curve
With $P_0 = (0,0)$, $P_1 = (x_1, y_1)$, $P_2 = (x_2, y_2)$, $P_3 = (1,1)$ and curve parameter $u \in [0, 1]$:

$$B_x(u) = 3(1-u)^2 u x_1 + 3(1-u) u^2 x_2 + u^3$$
$$B_y(u) = 3(1-u)^2 u y_1 + 3(1-u) u^2 y_2 + u^3$$

To evaluate the timing function at local progress $\alpha \in [0, 1]$, Blink solves $B_x(u) = \alpha$ for $u \in [0, 1]$ (using Newton-Raphson with bisection fallback in `gfx::CubicBezier::SolveCurveX`, since $x_1, x_2 \in [0, 1]$ guarantees $B_x'(u) \ge 0$ and monotonicity on $[0, 1]$), and outputs transformed progress:

$$p = B_y(B_x^{-1}(\alpha))$$

#### Linear Interpolation (`InterpolableNumber::ScaleAndAdd`)
In Blink (`InterpolableNumber::Interpolate`), given start value $v_{\text{start}}$, end value $v_{\text{end}}$, and eased progress $p$:

$$\text{lerp}(v_{\text{start}}, v_{\text{end}}, p) = v_{\text{start}} \cdot (1 - p) + v_{\text{end}} \cdot p = v_{\text{start}} + p \cdot (v_{\text{end}} - v_{\text{start}})$$

*(Note: Blink explicitly checks `if (progress == 0) return a; if (progress == 1) return b;` to prevent floating-point drift at endpoints).*

---

### 5. Mathematical Invariants

1.  **Boundary Preservation**: $B_x(0) = 0, B_y(0) = 0$ and $B_x(1) = 1, B_y(1) = 1$. Similarly, $\text{lerp}(a, b, 0) = a$ and $\text{lerp}(a, b, 1) = b$.
2.  **`lerp` Convexity (Boundedness)**: For any $a, b \in \mathbb{R}$ and $p \in [0, 1]$ (e.g., when $y_1, y_2 \in [0, 1]$), $\min(a, b) \le \text{lerp}(a, b, p) \le \max(a, b)$.
3.  **Determinism**: Interval selection, $\alpha$ computation, $B(u)$, and $\text{lerp}$ are total, deterministic functions of their inputs.

---

### 6. Rocq / Coq Formalization (`BlinkKeyframeInterpolationSemantics.v`)

```coq
(** * BlinkKeyframeInterpolationSemantics.v
    Formal verification of Chromium Blink Keyframe Interpolation
    against CSS Animations 1 & CSS Transitions 1. *)

From Coq Require Import Reals Lra List.
Import ListNotations.
Open Scope R_scope.

(** ** 1. Core Data Structures *)

Record CubicBezier := mkBezier {
  x1 : R;
  y1 : R;
  x2 : R;
  y2 : R;
  x1_bounds : 0 <= x1 <= 1;
  x2_bounds : 0 <= x2 <= 1
}.

Inductive TimingFunction :=
  | LinearTiming : TimingFunction
  | BezierTiming : CubicBezier -> TimingFunction.

Record Keyframe := mkKeyframe {
  kf_offset : R;
  kf_value  : R;
  kf_timing : TimingFunction;
  kf_offset_bounds : 0 <= kf_offset <= 1
}.

(** ** 2. Cubic-Bezier & Linear Interpolation Definitions *)

Definition bezier_coord (c1 c2 u : R) : R :=
  3 * (1 - u) * (1 - u) * u * c1 +
  3 * (1 - u) * u * u * c2 +
  u * u * u.

Definition bezier_x (cb : CubicBezier) (u : R) : R :=
  bezier_coord (x1 cb) (x2 cb) u.

Definition bezier_y (cb : CubicBezier) (u : R) : R :=
  bezier_coord (y1 cb) (y2 cb) u.

Definition lerp (v_start v_end p : R) : R :=
  v_start * (1 - p) + v_end * p.

(** ** 3. Local Progress & Interval Discovery *)

Definition local_progress (t o_i o_next : R) : R :=
  if Rle_dec o_next o_i then
    if Rle_dec o_next t then 1 else 0
  else
    (t - o_i) / (o_next - o_i).

(** Find the active keyframe pair enclosing normalized progress t *)
Fixpoint find_interval (kfs : list Keyframe) (t : R) : option (Keyframe * Keyframe) :=
  match kfs with
  | [] => None
  | [_] => None
  | k1 :: ((k2 :: rest) as tail) =>
      match rest with
      | [] => Some (k1, k2)
      | _  => if Rle_dec t (kf_offset k2)
              then Some (k1, k2)
              else find_interval tail t
      end
  end.

(** ** 4. Mathematical Invariant Theorems *)

(** Invariant 5.1a: Cubic-Bezier Boundary at u = 0 *)
Theorem bezier_coord_0 : forall c1 c2 : R,
  bezier_coord c1 c2 0 = 0.
Proof.
  intros c1 c2. unfold bezier_coord. lra.
Qed.

(** Invariant 5.1b: Cubic-Bezier Boundary at u = 1 *)
Theorem bezier_coord_1 : forall c1 c2 : R,
  bezier_coord c1 c2 1 = 1.
Proof.
  intros c1 c2. unfold bezier_coord. lra.
Qed.

Theorem bezier_endpoints : forall cb : CubicBezier,
  bezier_x cb 0 = 0 /\ bezier_y cb 0 = 0 /\
  bezier_x cb 1 = 1 /\ bezier_y cb 1 = 1.
Proof.
  intro cb. unfold bezier_x, bezier_y.
  repeat split; (apply bezier_coord_0 || apply bezier_coord_1).
Qed.

(** Invariant 5.2: Local progress bounds for t in [o_i, o_next] with o_i < o_next *)
Theorem local_progress_bounds : forall t o_i o_next : R,
  o_i < o_next ->
  o_i <= t <= o_next ->
  0 <= local_progress t o_i o_next <= 1.
Proof.
  intros t o_i o_next Hlt [Hge Hle].
  unfold local_progress.
  destruct (Rle_dec o_next o_i) as [Hbad | Hgood].
  - lra.
  - split.
    + unfold Rdiv. apply Rmult_le_pos; [lra |].
      left. apply Rinv_0_lt_compat. lra.
    + apply Rle_div_l; lra.
Qed.

(** Invariant 5.3: Lerp Boundary Values *)
Theorem lerp_boundaries : forall a b : R,
  lerp a b 0 = a /\ lerp a b 1 = b.
Proof.
  intros a b. unfold lerp. split; lra.
Qed.

(** Invariant 5.4: Lerp Convexity (Result in [min(a,b), max(a,b)] for p in [0,1]) *)
Theorem lerp_convexity : forall a b p : R,
  0 <= p <= 1 ->
  Rmin a b <= lerp a b p <= Rmax a b.
Proof.
  intros a b p [Hp0 Hp1].
  unfold lerp, Rmin, Rmax.
  destruct (Rle_dec a b) as [Hab | Hba].
  - split.
    + assert (H : 0 <= p * (b - a)) by (apply Rmult_le_pos; lra). lra.
    + assert (H : 0 <= (1 - p) * (b - a)) by (apply Rmult_le_pos; lra). lra.
  - split.
    + assert (H : 0 <= (1 - p) * (a - b)) by (apply Rmult_le_pos; lra). lra.
    + assert (H : 0 <= p * (a - b)) by (apply Rmult_le_pos; lra). lra.
Qed.

(** Invariant 5.5: Cubic-Bezier Y-Convexity when control points y1, y2 in [0, 1] *)
Theorem bezier_y_in_unit_interval : forall (cb : CubicBezier) (u : R),
  0 <= y1 cb <= 1 ->
  0 <= y2 cb <= 1 ->
  0 <= u <= 1 ->
  0 <= bezier_y cb u <= 1.
Proof.
  intros cb u [Hy1_0 Hy1_1] [Hy2_0 Hy2_1] [Hu0 Hu1].
  unfold bezier_y, bezier_coord.
  assert (H1u : 0 <= (1 - u) * (1 - u) * u).
  { apply Rmult_le_pos; [apply Rmult_le_pos |]; lra. }
  assert (H2u : 0 <= (1 - u) * u * u).
  { apply Rmult_le_pos; [apply Rmult_le_pos |]; lra. }
  assert (H3u : 0 <= u * u * u).
  { apply Rmult_le_pos; [apply Rmult_le_pos |]; lra. }
  split.
  - assert (T1 : 0 <= 3 * ((1 - u) * (1 - u) * u) * y1 cb) by (apply Rmult_le_pos; lra).
    assert (T2 : 0 <= 3 * ((1 - u) * u * u) * y2 cb) by (apply Rmult_le_pos; lra).
    lra.
  - assert (T1 : 3 * ((1 - u) * (1 - u) * u) * y1 cb <= 3 * ((1 - u) * (1 - u) * u) * 1)
      by (apply Rmult_le