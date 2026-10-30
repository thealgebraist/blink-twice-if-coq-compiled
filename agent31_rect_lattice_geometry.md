### 1. Core Data Structures in Blink Rect Geometry

Chromium Blink's layout engine relies on fixed-point 2D geometry (`LayoutUnit`, 1/64th of a CSS pixel, backed by a 32-bit saturating signed integer) to represent physical and writing-mode-relative layout spaces.

#### Coordinate & Dimension Primitives
*   **`PhysicalOffset` / `LogicalOffset`**: Represents a 2D coordinate vector $(x, y)$ or $(\text{inline\_offset}, \text{block\_offset})$ relative to an origin.
    *   *Representation*: `{ LayoutUnit left, LayoutUnit top }` (for Physical) or `{ LayoutUnit inline_offset, LayoutUnit block_offset }` (for Logical).
*   **`PhysicalSize` / `LogicalSize`**: Represents 2D extents $(w, h)$ or $(\text{inline\_size}, \text{block\_size})$.
    *   *Representation*: `{ LayoutUnit width, LayoutUnit height }` or `{ LayoutUnit inline_size, LayoutUnit block_size }`.

#### Rectangular Structures
*   **`PhysicalRect`**: Represents an axis-aligned bounding box in the physical coordinate space of the screen/page.
    *   *Representation*: Composed of `PhysicalOffset offset` and `PhysicalSize size`.
    *   *Derived Edges*:
        *   $X_{\min} = \text{offset.left}$
        *   $Y_{\min} = \text{offset.top}$
        *   $X_{\max} = \text{offset.left} \oplus \text{size.width}$ (where $\oplus$ denotes saturating addition)
        *   $Y_{\max} = \text{offset.top} \oplus \text{size.height}$
*   **`LogicalRect`**: Represents an axis-aligned bounding box in the flow-relative coordinate space dictated by the CSS `writing-mode` and `direction` properties.
    *   *Representation*: Composed of `LogicalOffset offset` and `LogicalSize size`.
    *   *Isomorphism*: Under any fixed writing-mode transformation matrix $M$, `LogicalRect` and `PhysicalRect` are isomorphic across all lattice operations (Intersect, Unite).

---

### 2. 2D Rect Operations

Let a rectangle $R$ be defined by the tuple $(x, y, w, h)$. In geometric space (ignoring saturation temporarily), $R$ represents the half-open interval product $[x, x+w) \times [y, y+h)$.

#### `IsEmpty(R)`
A rectangle is considered empty if it covers zero or negative area:
$$\text{IsEmpty}(R) \iff (R.w \le 0) \lor (R.h \le 0)$$

#### `Intersect(A, B)` (Meet Semi-Lattice $\sqcap$)
Computes the maximal rectangle contained within both $A$ and $B$.
1.  **Edge Calculation**:
    *   $x' = \max(A.x, B.x)$
    *   $y' = \max(A.y, B.y)$
    *   $r' = \min(A.x \oplus A.w, B.x \oplus B.w)$
    *   $b' = \min(A.y \oplus A.h, B.y \oplus B.h)$
2.  **Dimension Extraction**:
    *   $w' = r' \ominus x'$ (where $\ominus$ denotes saturating subtraction)
    *   $h' = b' \ominus y'$
3.  **Canonicalization (Non-overlapping clamp)**:
    *   If $w' \le 0 \lor h' \le 0$ (or if $\text{IsEmpty}(A) \lor \text{IsEmpty}(B)$), Blink zeroes the structure or normalizes dimensions to zero: $w' = \max(0, w')$, $h' = \max(0, h')$. In `gfx::Rect` / `PhysicalRect`, if the intersection is empty, the result is canonically $(0, 0, 0, 0)$ (or retains the point with $0 \times 0$ size depending on whether `Intersect` or `InclusiveIntersect` is invoked). For pure lattice semantics, all empty rects belong to the equivalence class $\bot$.

#### `Unite(A, B)` (Join Semi-Lattice $\sqcup$, Minimal Bounding Box)
Computes the minimal axis-aligned bounding rectangle containing both $A$ and $B$.
1.  **Empty Identity Short-circuit**:
    *   If $\text{IsEmpty}(A)$, return $B$.
    *   If $\text{IsEmpty}(B)$, return $A$.
2.  **Edge Calculation**:
    *   $x' = \min(A.x, B.x)$
    *   $y' = \min(A.y, B.y)$
    *   $r' = \max(A.x \oplus A.w, B.x \oplus B.w)$
    *   $b' = \max(A.y \oplus A.h, B.y \oplus B.h)$
3.  **Dimension Extraction**:
    *   $w' = r' \ominus x'$
    *   $h' = b' \ominus y'$
4.  **Result**: $(x', y', w', h')$.

*Note*: Blink also provides `UniteEvenIfEmpty(A, B)`, which bypasses step 1 and includes the degenerate point $(x,y)$ of an empty rectangle in the bounding calculation.

#### `Contains(A, B)`
Determines if $B$ is a subset of $A$ ($B \sqsubseteq A$).
*   In Blink:
    $$\text{Contains}(A, B) \iff \neg\text{IsEmpty}(B) \land \neg\text{IsEmpty}(A) \land (A.x \le B.x) \land (A.y \le B.y) \land (A.x \oplus A.w \ge B.x \oplus B.w) \land (A.y \oplus A.h \ge B.y \oplus B.h)$$
    *(Note: While set theory dictates $\emptyset \subseteq A$, Blink's `PhysicalRect::Contains` returns `false` if the target rect is empty or varies by overload; however, in lattice theory, $\bot \sqsubseteq A$ is universally true).*

#### `InclusiveIntersects(A, B)`
Determines if $A$ and $B$ share at least one boundary point (closed interval intersection $[x, x+w] \times [y, y+h]$), even if the intersection area is zero (e.g., touching edges or zero-size rects).
$$\text{InclusiveIntersects}(A, B) \iff (A.x \le B.x \oplus B.w) \land (A.x \oplus A.w \ge B.x) \land (A.y \le B.y \oplus B.h) \land (A.y \oplus A.h \ge B.y)$$
(Assuming valid non-negative widths and heights; if $w < 0$, it returns false).

---

### 3. Empty Rect Behavior & Saturation Semantics

#### Empty Rectangles ($\bot$ Equivalence Class)
In 2D geometry specifications (CSSOM View, Geometry Interfaces), a rectangle with $w \le 0$ or $h \le 0$ has no area. In Blink:
*   Any rectangle with $w \le 0 \lor h \le 0$ satisfies `IsEmpty() == true`.
*   Because an empty rectangle still retains `offset` coordinates in memory (e.g., `(10, 20, 0, 0)` vs `(0, 0, 0, 0)`), strict structural equality (`operator==`) distinguishes them, even though geometrically they both represent the empty set $\emptyset$.
*   In `Unite(A, B)`, if $A$ is `(10, 20, 0, 0)` and $B$ is `(50, 50, 10, 10)`, `A.Unite(B)` completely discards $A$'s offset and yields `(50, 50, 10, 10)`. If both $A$ and $B$ are empty, `A.Unite(B)` preserves $A$'s representation (or returns no-op). Thus, lattice laws hold **up to equivalence of empty rectangles** ($\equiv_\bot$).

#### Saturation During Rectangular Bounding
Blink's `LayoutUnit` clamps values to $[-\text{kMax}, \text{kMax}]$ ($[-2^{31}, 2^{31}-1]$ raw integer representation).
1.  **Right/Bottom Edge Overflow**: Computing $X_{\max} = x \oplus w$ saturates at `LayoutUnit::Max()`. If $x = \text{Max} - 10$ and $w = 50$, $X_{\max} = \text{Max}$. The effective width of the represented half-open interval shrinks to $10$.
2.  **Span Overflow in `Unite`**: When uniting two distant rectangles, e.g., $A = (-\text{Max}, 0, 10, 10)$ and $B = (\text{Max} - 10, 0, 10, 10)$:
    *   $x' = -\text{Max}$
    *   $r' = \text{Max}$
    *   $w' = r' \ominus x' = \text{Max} \ominus (-\text{Max}) = \text{Max}$ (due to saturation).
    *   Consequently, the new right edge of the united rectangle is $x' \oplus w' = (-\text{Max}) \oplus \text{Max} = 0 \neq \text{Max}$.
    *   **Audit Finding**: Under extreme saturation, converting from offset-size $(x, w)$ to min-max edges $(x, r)$ and back to $(x, r \ominus x)$ is **lossy**. The lattice invariants (associativity and absorption) hold strictly over the *Endpoint Interval Domain* $[X_{\min}, X_{\max}] \times [Y_{\min}, Y_{\max}]$, and hold over the *Offset-Size Domain* if and only if coordinates are bounded within $[\text{Min}/2, \text{Max}/2]$ (Blink's `NearlyMax()` guard range).

---

### 4. Mathematical Invariants (Bounded Lattice Structure)

When modeled in the canonical endpoint domain (or offset-size domain within non-saturating bounds, quotiented by the empty rect relation $\equiv_\bot$ where all empty rects map to $\bot$):

1.  **Commutativity**:
    *   $A \sqcap B \equiv_\bot B \sqcap A$
    *   $A \sqcup B \equiv_\bot B \sqcup A$
2.  **Associativity**:
    *   $(A \sqcap B) \sqcap C \equiv_\bot A \sqcap (B \sqcap C)$
    *   $(A \sqcup B) \sqcup C \equiv_\bot A \sqcup (B \sqcup C)$
3.  **Idempotence**:
    *   $A \sqcap A \equiv_\bot A$
    *   $A \sqcup A \equiv_\bot A$
4.  **Absorption Laws**:
    *   $A \sqcap (A \sqcup B) \equiv_\bot A$
    *   $A \sqcup (A \sqcap B) \equiv_\bot A$

*(Note: While $(R, \sqcap, \sqcup)$ forms a lattice, it is **not** a distributive lattice because the union of two disjoint rectangles gets expanded into their minimal bounding box, which may intersect a third rectangle that neither original rectangle intersected).*

---

### 5. Formal Verification in Rocq / Coq (`BlinkRectLatticeSemantics.v`)

The following complete, self-contained Rocq (Coq) formalization defines Blink's 2D rectangles, the equivalence relation over empty rectangles, the exact `Intersect` and `Unite` operations, and proves the full suite of algebraic lattice invariants including the absorption law.

```coq
(** * BlinkRectLatticeSemantics.v
    Formalization of Chromium Blink 2D Rect Operations and Lattice Invariants.
    Agent 31 Audit Artifact. *)

From Coq Require Import ZArith.
From Coq Require Import Bool.
From Coq Require Import Psatz. (* For lia tactic *)
Open Scope Z_scope.

(** ** 1. Core Geometry Primitives *)

Record PhysicalOffset : Type := mkOffset {
  left : Z;
  top  : Z
}.

Record PhysicalSize : Type := mkSize {
  width  : Z;
  height : Z
}.

Record PhysicalRect : Type := mkRect {
  offset : PhysicalOffset;
  size   : PhysicalSize
}.

(** Helper accessors and edge projections *)
Definition X (r : PhysicalRect) : Z := r.(offset).(left).
Definition Y (r : PhysicalRect) : Z := r.(offset).(top).
Definition W (r : PhysicalRect) : Z := r.(size).(width).
Definition H (r : PhysicalRect) : Z := r.(size).(height).

Definition Right (r : PhysicalRect) : Z := X r + W r.
Definition Bottom (r : PhysicalRect) : Z := Y r + H r.

(** ** 2. Empty Rect Semantics and Equivalence *)

Definition is_empty (r : PhysicalRect) : bool :=
  (W r <=? 0) || (H r <=? 0).

Definition EmptyRect : PhysicalRect :=
  mkRect (mkOffset 0 0) (mkSize 0 0).

(** Two rectangles are geometrically equivalent (rect_eq) if they are both
    empty, or if they are both non-empty and have identical coordinates. *)
Definition rect_eq (a b : PhysicalRect) : Prop :=
  (is_empty a = true /\ is_empty b = true) \/
  (is_empty a = false /\ is_empty b = false /\
   X a = X b /\ Y a = Y b /\ W a = W b /\ H a = H b).

Infix "===" := rect_eq (at level 70, no associativity).

Lemma is_empty_spec : forall r,
  is_empty r = true <-> (W r <= 0 \/ H r <= 0).
Proof.
  intros r. unfold is_empty.
  rewrite orb_true_iff, !Z.leb_le. reflexivity.
Qed.

Lemma not_empty_spec : forall r,
  is_empty r = false <-> (W r > 0 /\ H r > 0).
Proof.
  intros r. unfold is_empty.
  rewrite orb_false_iff, !Z.leb_gt. lia.
Qed.

(** Equivalence relation proofs for rect_eq *)
Lemma rect_eq_refl : forall a, a === a.
Proof.
  intros a. unfold rect_eq.
  destruct (is_empty a); [left | right]; auto 10.
Qed.

Lemma rect_eq_sym : forall a b, a === b -> b === a.
Proof.
  intros a b [[Ha Hb] | [Ha [Hb [Hx [Hy [Hw Hh]]]]]];
  [left | right]; auto 10.
Qed.

Lemma rect_eq_trans : forall a b c, a === b -> b === c ->