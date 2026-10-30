### 1. Core Data Structures in Blink Filter Operations

In Chromium Blink (`third_party/blink/renderer/core/style/` and `platform/graphics/`), CSS filter effects are lowered from `CSSValue` lists into a platform-independent representation used to compute visual/ink overflow outsets during layout and pre-paint phases.

#### `Outsets` (`gfx::Outsets` / `LayoutRectOutsets`)
Represents non-negative directional expansion around a bounding box in layout or pixel units:
```cpp
struct Outsets {
  int top = 0;
  int right = 0;
  int bottom = 0;
  int left = 0;
};
```

#### `FilterOperation` Hierarchy (`FilterOperation.h`)
Blink models individual filter functions as subclasses of `FilterOperation`:
*   **`FilterOperation`**: Abstract base class tagged with `OperationType` (`kBlur`, `kDropShadow`, `kReference`, `kGrayscale`, etc.). Color-matrix operations (`brightness`, `contrast`, `grayscale`, `sepia`, `hue-rotate`, `invert`, `opacity`, `saturate`) do not displace pixels and have zero outsets.
*   **`BlurFilterOperation`**: Holds a single `Length std_deviation_` ($\sigma \ge 0$). Resolved to a `float` pixel radius during paint/outset calculation.
*   **`DropShadowFilterOperation`**: Wraps a `ShadowData` struct containing:
    *   `gfx::PointF location_` ($\Delta x, \Delta y$ offset in CSS pixels).
    *   `float blur_` ($\sigma \ge 0$, standard deviation).
    *   `Color color_`.
*   **`FilterOperations`**: A wrapper around `HeapVector<Member<FilterOperation>> operations_` representing an ordered pipeline $F = [f_1, f_2, \dots, f_n]$ applied sequentially from left to right.

---

### 2. Ink Overflow Expansion: W3C Spec vs. Blink Skia Lowering

#### W3C Filter Effects Module Level 1
Under W3C Filter Effects Level 1 (§ 13.1 `feGaussianBlur` & § 11 `Filter Region`), a Gaussian blur with standard deviation $\sigma$ has an infinite impulse response:
$$G_\sigma(x, y) = \frac{1}{2\pi\sigma^2} e^{-\frac{x^2+y^2}{2\sigma^2}}$$
For non-trivial $\sigma \ge 2$, the specification mandates or suggests approximating the Gaussian kernel using three successive passes of a box filter of width $d$:
$$d = \left\lfloor \sigma \cdot \frac{3\sqrt{2\pi}}{4} + 0.5 \right\rfloor$$

#### Blink / Skia Implementation (`feGaussianBlur` & `SkBlurMask`)
Blink delegates filter outset computation to `FilterOperation::MapRect` and `cc::FilterOperations::MapRect`. Rather than using the raw box-filter width $d$ as the total outset, Blink computes the maximum extent of the 3-pass box convolution (or direct truncated Gaussian kernel support) where kernel weights remain non-zero in 8-bit/float color channels.

In `skia/ext/` and `cc/paint/filter_operations.cc` (`SpreadForStdDeviation`):
1.  **Gaussian Blur (`kBlur`)**:
    Given standard deviation $\sigma \ge 0$, the pixel spread radius $R(\sigma)$ is bounded by $3\sigma$:
    $$R(\sigma) = \lceil 3 \cdot \sigma \rceil$$
    *(Note: While a single box pass has radius $\approx \frac{1}{2} \sigma \frac{3\sqrt{2\pi}}{4} \approx 0.94\sigma$, three convolved passes expand the support radius to $3 \times 0.94\sigma \approx 2.82\sigma$, which Blink/Skia conservatively bounds by $\lceil 3\sigma \rceil$ to prevent clipping of anti-aliased filter fringes).*
    The resulting outsets are isotropic:
    $$\text{Outset}_{\text{blur}}(\sigma) = \big( T: R(\sigma),\; R: R(\sigma),\; B: R(\sigma),\; L: R(\sigma) \big)$$

2.  **Drop Shadow (`kDropShadow`)**:
    A drop shadow composites the original source graphic with an offset, blurred alpha mask of the source. For offset $(\Delta x, \Delta y) \in \mathbb{Z}^2$ and blur $\sigma \ge 0$:
    *   The shadow's bounding box shifts by $(\Delta x, \Delta y)$ and expands by $R(\sigma)$ in all four directions.
    *   Because `feDropShadow` merges the shadow with the *original* unshifted graphic (`feMerge`), the final ink overflow must enclose both the original bounds $(0,0,0,0)$ and the shifted shadow bounds:
    $$\begin{aligned}
    T &= \max(0, R(\sigma) - \Delta y) \\
    R &= \max(0, R(\sigma) + \Delta x) \\
    B &= \max(0, R(\sigma) + \Delta y) \\
    L &= \max(0, R(\sigma) - \Delta x)
    \end{aligned}$$
    *(Convention: $+x$ is Right, $+y$ is Down/Bottom).*

---

### 3. Filter Outset Accumulation Across a Filter Chain

In CSS Filter Effects, `filter: f_1 f_2 ... f_n` forms a functional composition $f_n \circ \dots \circ f_2 \circ f_1$.

In Blink (`cc::FilterOperations::MapRect`), outsets are computed by sequentially mapping an initial bounding rectangle $B_0$ through each operation in the list:
$$B_k = \text{MapRect}(f_k, B_{k-1})$$

When expressed purely in terms of `Outsets` $O = (T, R, B, L) \in \mathbb{N}^4$ relative to the origin box:
1.  **Sequential Composition ($\oplus$)**: Each filter operation $f_k$ takes the already-expanded ink bounds from $f_{1\dots k-1}$ and expands them further. Because `drop-shadow` unions its shifted output with its *input* (which is the output of $f_{k-1}$), and `blur` expands its input symmetrically, the effective outset of applying operation $f$ after existing outsets $O_{\text{prev}}$ is component-wise addition of the clamped operation outset:
    $$\text{Outset}(f) = (T_f, R_f, B_f, L_f) \in \mathbb{N}^4$$
    $$O_{\text{next}} = O_{\text{prev}} + \text{Outset}(f)$$
2.  **Union of Parallel Filter Branches ($\sqcup$)**: For SVG reference filters (`feMerge`, `feComposite`) or bounding-box unions during damage tracking, two outset quads $O_1, O_2$ combine via component-wise maximum:
    $$O_1 \sqcup O_2 = \big( \max(T_1, T_2),\; \max(R_1, R_2),\; \max(B_1, B_2),\; \max(L_1, L_2) \big)$$

---

### 4. Mathematical Invariants

1.  **Non-Negativity**: $\forall F,\; \text{Outsets}(F) = (T, R, B, L) \implies T \ge 0 \land R \ge 0 \land B \ge 0 \land L \ge 0$. A CSS filter chain never shrinks the ink overflow rect used for paint invalidation (clipping/erosion is ignored or conservatively bounded by the original box).
2.  **Monotonicity in $\sigma$**: For both `Blur` and `DropShadow`, if $\sigma_1 \le \sigma_2$, then $\text{Outset}(\sigma_1) \preceq \text{Outset}(\sigma_2)$ component-wise.
3.  **Chain Monotonicity (Prefix Sub-bound)**: Appending a filter operation $f$ to a pipeline $F$ never reduces the outsets: $\text{Outsets}(F) \preceq \text{Outsets}(F \mathbin{+\!+} [f])$.
4.  **Union Associativity, Commutativity, and Idempotence**: $(\mathbb{N}^4, \sqcup, \mathbf{0})$ forms a bounded join-semilattice.
5.  **Determinism & Homomorphism**: Sequential filter outset accumulation is a monoid homomorphism from $(\text{list FilterOp}, \mathbin{+\!+}, [])$ to $(\mathbb{N}^4, +, \mathbf{0})$.

---

### 5. Rocq / Coq Formalization (`BlinkFilterOutsetSemantics.v`)

The following standalone script compiles cleanly in Coq/Rocq (8.16+ / 9.0) using standard library arithmetic (`ZArith`, `Lia`).

```coq
(** * BlinkFilterOutsetSemantics.v
    Formal verification of Chromium Blink CSS Filter Outsets
    vs. W3C Filter Effects Module Level 1.
    Agent 43 Audit Artifact. *)

From Coq Require Import ZArith.
From Coq Require Import List.
From Coq Require Import Lia.
Import ListNotations.
Open Scope Z_scope.

(** ** 1. Core Data Structures *)

(** Directional pixel outsets (Top, Right, Bottom, Left). *)
Record Outsets : Type := mkOutsets {
  outset_top    : Z;
  outset_right  : Z;
  outset_bottom : Z;
  outset_left   : Z
}.

Definition zero_outsets : Outsets :=
  mkOutsets 0 0 0 0.

(** Well-formedness: Ink overflow outsets are non-negative. *)
Definition outsets_nonneg (o : Outsets) : Prop :=
  0 <= outset_top o /\
  0 <= outset_right o /\
  0 <= outset_bottom o /\
  0 <= outset_left o.

(** Component-wise partial order on Outsets. *)
Definition outsets_le (o1 o2 : Outsets) : Prop :=
  outset_top o1 <= outset_top o2 /\
  outset_right o1 <= outset_right o2 /\
  outset_bottom o1 <= outset_bottom o2 /\
  outset_left o1 <= outset_left o2.

(** Component-wise union (join) of two Outsets. *)
Definition outsets_union (o1 o2 : Outsets) : Outsets :=
  mkOutsets
    (Z.max (outset_top o1) (outset_top o2))
    (Z.max (outset_right o1) (outset_right o2))
    (Z.max (outset_bottom o1) (outset_bottom o2))
    (Z.max (outset_left o1) (outset_left o2)).

(** Sequential accumulation (Minkowski sum of bounding box expansions). *)
Definition outsets_add (o1 o2 : Outsets) : Outsets :=
  mkOutsets
    (outset_top o1 + outset_top o2)
    (outset_right o1 + outset_right o2)
    (outset_bottom o1 + outset_bottom o2)
    (outset_left o1 + outset_left o2).

(** Blink FilterOperation AST.
    Note: Blur std_deviation (sigma) is modeled as a non-negative integer
    (or fixed-point unit) alongside a ceiling spread function. *)
Inductive FilterOperation : Type :=
  | FOp_ColorMatrix : FilterOperation (* grayscale, sepia, brightness, etc. *)
  | FOp_Blur        : Z -> FilterOperation (* sigma *)
  | FOp_DropShadow  : Z -> Z -> Z -> FilterOperation. (* dx, dy, sigma *)

Definition FilterOperations := list FilterOperation.

(** ** 2. Ink Overflow Expansion Semantics *)

(** Blink/Skia spread calculation: R(sigma) = 3 * max(0, sigma).
    (In fixed-point or integer pixel radii, ceil(3 * sigma) is monotonic). *)
Definition blur_spread (sigma : Z) : Z :=
  3 * Z.max 0 sigma.

(** Single FilterOperation Outset evaluation. *)
Definition eval_filter_op (op : FilterOperation) : Outsets :=
  match op with
  | FOp_ColorMatrix => zero_outsets
  | FOp_Blur sigma =>
      let r := blur_spread sigma in
      mkOutsets r r r r
  | FOp_DropShadow dx dy sigma =>
      let r := blur_spread sigma in
      mkOutsets
        (Z.max 0 (r - dy))
        (Z.max 0 (r + dx))
        (Z.max 0 (r + dy))
        (Z.max 0 (r - dx))
  end.

(** ** 3. Filter Chain Outset Accumulation *)

Fixpoint eval_filter_chain (ops : FilterOperations) : Outsets :=
  match ops with
  | [] => zero_outsets
  | op :: rest => outsets_add (eval_filter_op op) (eval_filter_chain rest)
  end.

(** Parallel branch union across a list of filter outset results (e.g. feMerge). *)
Fixpoint union_filter_outsets (os : list Outsets) : Outsets :=
  match os with
  | [] => zero_outsets
  | o :: rest => outsets_union o (union_filter_outsets rest)
  end.

(** ** 4. Mathematical Invariants & Proofs *)

Lemma blur_spread_nonneg : forall sigma : Z,
  0 <= blur_spread sigma.
Proof.
  intros sigma. unfold blur_spread. lia.
Qed.

Lemma blur_spread_monotonic : forall s1 s2 : Z,
  s1 <= s2 -> blur_spread s1 <= blur_spread s2.
Proof.
  intros s1 s2 Hle. unfold blur_spread. lia.
Qed.

(** Invariant 1: Every individual filter operation produces non-negative outsets. *)
Theorem eval_filter_op_nonneg : forall op : FilterOperation,
  outsets_nonneg (eval_filter_op op).
Proof.
  intros [ | sigma | dx dy sigma]; unfold eval_filter_op, outsets_nonneg, zero_outsets; simpl.
  - lia.
  - pose proof (blur_spread_nonneg sigma). lia.
  - lia.
Qed.

Lemma outsets_add_nonneg : forall o1 o2 : Outsets,
  outsets_nonneg o1 -> outsets_nonneg o2 -> outsets_nonneg (outsets_add o1 o2).
Proof.
  intros [t1 r1 b1 l1] [t2 r2 b2 l2] H1 H2.
  unfold outsets_nonneg, outsets_add in *; simpl in *. lia.
Qed.

(** Invariant 2: Any chain of FilterOperations yields non-negative outsets. *)
Theorem eval_filter_chain_nonneg : forall ops :