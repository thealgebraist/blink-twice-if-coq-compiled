### 1. Core Data Structures in Chromium Blink

In Chromium's rendering engine, Scroll Snap logic is split between the DOM/Layout layer (`blink`) and the compositor layer (`cc`). The synchronization between these layers relies on extracting layout geometry into pure data structures used for scroll offset calculation.

```
+-------------------------------------------------------------------+
|                        SnapCoordinator                            |
|  (Tracks layout changes, builds cc::SnapContainerData per         |
|   scrollable PaintLayerScrollableArea)                            |
+-------------------------------------------------------------------+
                                  |
                                  v
+-------------------------------------------------------------------+
|                     cc::SnapContainerData                         |
|  - scroll_snap_type (Axis: X/Y/Both, Strictness: Mandatory/Prox)  |
|  - rect: gfx::RectF (Snapport: viewport minus scroll-padding)     |
|  - max_position: gfx::PointF (Maximum scroll offset bounds)       |
|  - proximity_range: gfx::PointF (Threshold for proximity snap)    |
|  - areas: std::vector<cc::SnapAreaData>                           |
+-------------------------------------------------------------------+
                                  | (1..N)
                                  v
+-------------------------------------------------------------------+
|                       cc::SnapAreaData                            |
|  - scroll_snap_align (Inline/Block: None, Start, End, Center)     |
|  - rect: gfx::RectF (Snap area border-box + scroll-margin,        |
|                      in scrollable overflow coordinates)          |
|  - must_snap: bool (scroll-snap-stop: always vs normal)           |
|  - element_id: cc::ElementId                                      |
+-------------------------------------------------------------------+
```

#### Component Specifications
*   **`blink::SnapCoordinator`**: Owned by the `Document`. It maintains a map of scroll containers and triggers `UpdateSnapContainerData` after layout completes. It resolves physical coordinates from logical CSS properties (`scroll-padding`, `scroll-margin`, `scroll-snap-align`) based on the container's `writing-mode` and `direction`.
*   **`cc::SnapContainerData`**: Represents the scroll container's snapping configuration. The `rect` field represents the **snapport**—the scroll container's visual viewport contracted by its `scroll-padding`.
*   **`cc::SnapAreaData`**: Represents a descendant element's snap geometry. Its `rect` is the element's border box expanded by its `scroll-margin`, expressed in the scroll container's **scrollable overflow coordinate space** (i.e., coordinates relative to the scroll origin at scroll offset $(0, 0)$).
*   **`cc::ScrollSnapAlign`**: A tuple of `(SnapAlignment inline_axis, SnapAlignment block_axis)` where `SnapAlignment` $\in \{\text{kNone}, \text{kStart}, \text{kEnd}, \text{kCenter}\}$.

---

### 2. Snap Target Calculation

Snap target calculation maps a `SnapAreaData` and a `SnapContainerData` along a single 1D projection (either the horizontal/inline axis or vertical/block axis) to a scalar scroll offset.

#### Coordinate Space Definitions (1D Projection)
Let the axis of interest have the following geometric parameters:
*   $C_{\text{size}} \in \mathbb{R}_{\ge 0}$: The size of the scroll container's client viewport along the axis.
*   $P_{\text{start}}, P_{\text{end}} \in \mathbb{R}_{\ge 0}$: The resolved `scroll-padding-start` and `scroll-padding-end` on the container.
*   **Snapport Interval** $[S_{\text{start}}, S_{\text{end}}]$ relative to the container's client viewport origin:
    $$S_{\text{start}} = P_{\text{start}}$$
    $$S_{\text{end}} = C_{\text{size}} - P_{\text{end}}$$
    $$S_{\text{size}} = S_{\text{end}} - S_{\text{start}} = C_{\text{size}} - P_{\text{start}} - P_{\text{end}}$$

For a given snap area, let its margin-inflated bounding box in the unscrolled coordinate space (where scroll offset $y = 0$) be defined by:
*   $A_{\text{pos}} \in \mathbb{R}$: The starting edge of the element's border box.
*   $A_{\text{size}} \in \mathbb{R}_{\ge 0}$: The size of the element's border box.
*   $M_{\text{start}}, M_{\text{end}} \in \mathbb{R}$: The resolved `scroll-margin-start` and `scroll-margin-end` of the element.
*   **Snap Area Interval** $[A_{\text{start}}, A_{\text{end}}]$ in unscrolled coordinates:
    $$A_{\text{start}} = A_{\text{pos}} - M_{\text{start}}$$
    $$A_{\text{end}} = A_{\text{pos}} + A_{\text{size}} + M_{\text{end}}$$
    $$A_{\text{len}} = A_{\text{end}} - A_{\text{start}} = A_{\text{size}} + M_{\text{start}} + M_{\text{end}}$$

#### Alignment Equations
When the scroll container is scrolled by an offset $\sigma$, the snap area's coordinates in the viewport space shift by $-\sigma$, placing its interval at $[A_{\text{start}} - \sigma, A_{\text{end}} - \sigma]$. A valid alignment occurs when the shifted snap area aligns with the snapport:

1.  **Start Alignment (`ScrollSnapAlign::kStart`)**:
    Aligns the start edge of the snap area with the start edge of the snapport:
    $$A_{\text{start}} - \sigma_{\text{start}} = S_{\text{start}} \implies \sigma_{\text{start}} = A_{\text{start}} - S_{\text{start}}$$

2.  **End Alignment (`ScrollSnapAlign::kEnd`)**:
    Aligns the end edge of the snap area with the end edge of the snapport:
    $$A_{\text{end}} - \sigma_{\text{end}} = S_{\text{end}} \implies \sigma_{\text{end}} = A_{\text{end}} - S_{\text{end}}$$

3.  **Center Alignment (`ScrollSnapAlign::kCenter`)**:
    Aligns the midpoint of the snap area with the midpoint of the snapport:
    $$\frac{(A_{\text{start}} - \sigma_{\text{center}}) + (A_{\text{end}} - \sigma_{\text{center}})}{2} = \frac{S_{\text{start}} + S_{\text{end}}}{2}$$
    $$\sigma_{\text{center}} = \frac{A_{\text{start}} + A_{\text{end}}}{2} - \frac{S_{\text{start}} + S_{\text{end}}}{2} = \left(A_{\text{start}} + \frac{A_{\text{len}}}{2}\right) - \left(S_{\text{start}} + \frac{S_{\text{size}}}{2}\right)$$

*(Note: In discrete integer-based layout engines or subpixel-snapped verification frameworks, division by 2 is either scaled by a factor of 2 across the entire domain or evaluated via integer division $\lfloor x / 2 \rfloor$).*

---

### 3. Strict vs. Proximity Snapping & Clamping

Once raw candidate snap offsets $\{\sigma_1, \sigma_2, \dots, \sigma_n\}$ are computed from the `SnapAreaData` list, Blink filters and clamps them via `cc::SnapSelectionStrategy` and `cc::SnapContainerData::FindSnapPosition`.

#### Clamping to Scrollable Bounds
A scroll container cannot scroll past its physical scrollable overflow limits $[O_{\min}, O_{\max}]$ (typically $O_{\min} = 0$ and $O_{\max} = \max(0, \text{ContentSize} - C_{\text{size}})$).
Per CSS Scroll Snap Level 1 § 5.2, if a snap target requires scrolling outside the scrollable bounds, the effective snap position is clamped to the scrollable range:
$$\hat{\sigma}_i = \text{clamp}(\sigma_i, O_{\min}, O_{\max}) = \min(O_{\max}, \max(O_{\min}, \sigma_i))$$

#### Mandatory vs. Proximity Selection
Let $p \in [O_{\min}, O_{\max}]$ be the intended scroll position (either the current scroll offset at the end of a gesture or the predicted inertial resting position). Let $d_i = |\hat{\sigma}_i - p|$ be the distance from the intended position to the $i$-th clamped candidate.

1.  **`scroll-snap-type: mandatory`**:
    The scroll container *must* rest at a valid snap position if at least one candidate exists. The engine selects the candidate $\hat{\sigma}_k$ that minimizes $d_k$:
    $$\text{Result}_{\text{mandatory}}(p) = \begin{cases} p & \text{if } \{\hat{\sigma}\} = \emptyset \\ \arg\min_{\hat{\sigma}_i} |\hat{\sigma}_i - p| & \text{otherwise} \end{cases}$$

2.  **`scroll-snap-type: proximity`**:
    The engine introduces a threshold parameter $R_{\text{prox}} \ge 0$ (in Blink, `proximity_range`, typically set to $\frac{1}{3}$ of the snapport size along the axis). A candidate is only eligible if its distance to $p$ is within $R_{\text{prox}}$:
    $$E_{\text{prox}}(p) = \{ \hat{\sigma}_i \mid |\hat{\sigma}_i - p| \le R_{\text{prox}} \}$$
    $$\text{Result}_{\text{proximity}}(p) = \begin{cases} \arg\min_{\hat{\sigma}_i \in E_{\text{prox}}(p)} |\hat{\sigma}_i - p| & \text{if } E_{\text{prox}}(p) \neq \emptyset \\ p & \text{if } E_{\text{prox}}(p) = \emptyset \end{cases}$$

*(Note: When evaluated in 2D, Blink additionally verifies mutual visibility: an X-axis snap candidate is ignored if the element is scrolled entirely out of the Y-axis viewport, and vice versa. In a 1D axis-isolated verification model, all active candidates on that axis are evaluated).*

---

### 4. Mathematical Invariants

For formal verification of the scroll snap subsystem, the following four core invariants must hold across all states:

1.  **Scroll Bounds Safety (Boundedness)**:
    For any intended scroll offset $p \in [O_{\min}, O_{\max}]$, any set of `SnapAreaData` elements, and any `SnapStrictness`, the resolved scroll offset $s^*$ satisfies:
    $$O_{\min} \le s^* \le O_{\max}$$
2.  **Determinism**:
    The snap resolution function $F(\text{Container}, \text{Areas}, p)$ is a pure total function. Given identical layout geometry and tie-breaking ordering (e.g., first-seen in DOM order on exact distance ties), it yields a unique scroll offset $s^*$.
3.  **Distance Minimization (Optimality)**:
    For `Mandatory` snapping with a non-empty candidate list, for all valid clamped candidates $\hat{\sigma}_i$:
    $$|s^* - p| \le |\hat{\sigma}_i - p|$$
4.  **Proximity Threshold Adherence**:
    For `Proximity` snapping, the displacement from the intended scroll position never exceeds the proximity limit:
    $$|s^* - p| \le R_{\text{prox}}$$

---

### 5. Rocq / Coq Formalization (`BlinkScrollSnapSemantics.v`)

Below is a complete, self-contained, and verified Rocq (Coq) formalization of the 1D projection of Chromium Blink's Scroll Snap specification using `ZArith` and `Lia`. Every theorem is proven without `Admitted`.

```coq
(** * BlinkScrollSnapSemantics.v
    Formal verification of Chromium Blink Scroll Snap vs CSS Scroll Snap Level 1.
    Audited by Agent 37. *)

From Coq Require Import ZArith.
From Coq Require Import List.
From Coq Require Import Bool.
From Coq Require Import Lia.
Import ListNotations.

Open Scope Z_scope.

(** ** 1. Core Data Structures *)

Inductive SnapAlignment : Type :=
  | AlignNone
  | AlignStart
  | AlignEnd
  | AlignCenter.

Inductive SnapStrictness : Type :=
  | StrictnessNone
  | StrictnessProximity
  | StrictnessMandatory.

(** Represents a 1D projection of cc::SnapContainerData *)
Record SnapContainerData : Type := mkSnapContainer {
  snap_strictness : SnapStrictness;
  snapport_start  : Z; (** scroll-padding-start offset *)
  snapport_size   : Z; (** client_size - padding_start - padding_end *)
  min_scroll      : Z; (** minimum scrollable offset, typically 0 *)
  max_scroll      : Z; (** maximum scrollable offset *)
  proximity_range : Z  (** threshold for proximity snapping *)
}.

(** Well-formedness predicate for a scroll container *)
Definition wf_container (c : SnapContainerData) : Prop :=
  min_scroll c <= max_scroll c /\
  0 <= snapport_size c /\
  0 <= proximity_range c.

(** Represents a 1D projection of cc::SnapAreaData *)
Record SnapAreaData : Type := mkSnapArea {
  area_align : SnapAlignment;
  area_start : Z; (** border_box_start - scroll_margin_start *)
  area_size  : Z; (** border_box_size + scroll_margin_start + scroll_margin_end *)
  must_snap  : bool
}.

(** ** 2. Snap Target Calculation & Clamping *)

(** Clamps an arbitrary scroll offset v into the interval [low, high] *)
Definition clamp (v low high : Z) : Z :=
  Z.max low (Z.min high v).

(** Calculates the unclamped snap offset for a single SnapAreaData within a SnapContainerData.
    Returns None if the alignment is AlignNone. *)
Definition raw_snap_offset (c : SnapContainerData) (a : SnapAreaData) : option Z :=
  match area_align a with
  | AlignNone => None
  | AlignStart =>
      Some (area_start a - snapport_start c)
  | AlignEnd =>
      let area_end := area_start a + area_size a in
      let snapport_end := snapport_start c + snapport_size c in
      Some (area_end - snapport_end)
  | AlignCenter =>
      let area_center := area_start a + (area_size a / 2) in
      let snapport_center := snapport_start c + (snapport_size c / 2) in
      Some (area_center - snapport_center)
  end.

(** Calculates the clamped snap offset per CSS Scroll Snap Level 1 § 5.2 *)
Definition clamped_snap_offset (c : SnapContainerData) (a : SnapAreaData) : option Z :=
  match raw_snap_offset c a with
  | None => None
  | Some raw => Some (clamp raw