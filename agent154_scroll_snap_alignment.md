### 1. Scroll Snap Data Structures

In Chromium's Blink engine (and delegated down to the compositor `cc`), CSS Scroll Snap (CSS Scroll Snap Module Level 1, §4 & §6) is orchestrated via the following architecture:

*   **`SnapCoordinator`** (`third_party/blink/renderer/core/page/scrolling/snap_coordinator.h`):
    Maintains the registry of scroll containers that have snap points or areas. During the post-layout phase (`SnapCoordinator::UpdateAllSnapContainerData`), it collects geometry from descendant `LayoutBox` instances and builds a `cc::SnapContainerData` structure for each scrollable area, transferring it to the compositor thread for deterministic, main-thread-independent snapping.
*   **`SnapContainerData`** (`cc/input/scroll_snap_data.h`):
    Represents the scroll container's **snapport** (the visual viewport of the scroll container reduced by `scroll-padding`). It holds:
    *   `scroll_snap_type`: Strictness (`kNone`, `kProximity`, `kMandatory`) and axis (`kX`, `kY`, `kBoth`, `kBlock`, `kInline`).
    *   `rect`: The bounding box of the snapport in the scrollable area's coordinate space.
    *   `max_position`: The maximum valid scroll offset ($\max(0, \text{content\_size} - \text{viewport\_size})$).
    *   `proximity_range`: The distance threshold within which `proximity` snapping triggers.
    *   `std::vector<SnapAreaData>`: The collection of registered snap areas inside this container.
*   **`SnapAreaData`** (`cc/input/scroll_snap_data.h`):
    Represents a descendant element's **snap area** (its border box expanded by `scroll-margin`, expressed in the scroll container's scrollable content coordinate space). It contains:
    *   `rect`: The `gfx::RectF` of the margin-adjusted snap area relative to the scroll container's origin at scroll offset $(0,0)$.
    *   `scroll_snap_align`: A pair of alignments (block and inline) taking values from `SnapAlignment`:
        *   `kNone`: No alignment on this axis.
        *   `kStart`: Align the start edge of the snap area with the start edge of the snapport.
        *   `kCenter`: Align the center of the snap area with the center of the snapport.
        *   `kEnd`: Align the end edge of the snap area with the end edge of the snapport.
    *   `must_snap`: Boolean representing `scroll-snap-stop: always` vs `normal`.

---

### 2. Target Scroll Offset Calculation

Per CSS Scroll Snap 1 §6.1 (*Scroll Snap Alignment*) and `cc::SnapContainerData::FindSnapPosition`, calculating the target scroll offset along a single 1D axis (e.g., horizontal axis X) proceeds as follows:

Let:
*   $C_{size}$ be the total scrollable content size (`scrollWidth`).
*   $V_{size}$ be the scroll container's visual viewport size (`clientWidth`).
*   $P_{start}, P_{end}$ be the `scroll-padding` offsets on the start and end edges.
*   The **snapport** interval at scroll offset $s=0$ is $[P_{start}, V_{size} - P_{end}]$, with size $S_{port} = (V_{size} - P_{end}) - P_{start}$.
*   $A_{pos}, A_{size}$ be the snap area's offset and size (already incorporating `scroll-margin`, where $A_{pos} = \text{box\_offset} - M_{start}$ and $A_{size} = \text{box\_size} + M_{start} + M_{end}$).

#### Unclamped Alignment Offset ($T_{raw}$)
When the container is scrolled by offset $s$, the snap area's coordinates in the viewport shift by $-s$. To align the snap area with the snapport:

1.  **Start Alignment (`kStart`)**:
    Align area start ($A_{pos} - s$) with snapport start ($P_{start}$):
    $$T_{raw} = A_{pos} - P_{start}$$

2.  **Center Alignment (`kCenter`)**:
    Align area center ($A_{pos} + \frac{A_{size}}{2} - s$) with snapport center ($P_{start} + \frac{S_{port}}{2}$):
    $$T_{raw} = \left(A_{pos} + \frac{A_{size}}{2}\right) - \left(P_{start} + \frac{S_{port}}{2}\right)$$

3.  **End Alignment (`kEnd`)**:
    Align area end ($A_{pos} + A_{size} - s$) with snapport end ($V_{size} - P_{end} = P_{start} + S_{port}$):
    $$T_{raw} = (A_{pos} + A_{size}) - (P_{start} + S_{port})$$

#### Scroll Bounds Clamping
Per CSS Scroll Snap 1 §4.1, a scroll snap position cannot force the container to scroll past its scrollable bounds. Let the maximum scroll offset be:
$$S_{max} = \max(0, C_{size} - V_{size})$$
The valid target scroll offset $T$ is clamped to $[0, S_{max}]$:
$$T = \min(S_{max}, \max(0, T_{raw}))$$

*(Note: In Blink's `cc/input/scroll_snap_data.cc`, candidate snap positions outside $[0, S_{max}]$ are either clamped during construction of the `SnapSearchResult` or filtered against `max_position_` so the final selected snap offset strictly resides within $[0, S_{max}]$).*

---

### 3. Invariants

1.  **Target Scroll Bounds Invariant**:
    For any scroll container with $C_{size} \ge 0$ and $V_{size} \ge 0$, any valid snap target offset $T$ returned by the snap algorithm satisfies:
    $$0 \le T \le \max(0, C_{size} - V_{size})$$
    If $C_{size} \ge V_{size}$, this simplifies to $0 \le T \le C_{size} - V_{size}$.

2.  **Proximity Threshold Determinism**:
    For a given intended scroll offset $s_{intended} \in [0, S_{max}]$, strictness mode (`Mandatory` or `Proximity`), proximity threshold $D_{prox} \ge 0$, and a finite list of snap areas:
    *   The selection of the winning snap offset $T_{final}$ is a pure, deterministic function.
    *    under `Proximity` strictness, if the minimum distance $\min_i |T_i - s_{intended}| > D_{prox}$, the container does not snap and deterministically settles at $s_{intended}$.

3.  **Alignment Geometric Exactness (Unclamped Interior)**:
    If $0 \le T_{raw} \le S_{max}$, the resulting scroll offset $T = T_{raw}$ places the specified feature (start, center, or end) of the snap area at the exact coordinate of the corresponding feature of the snapport.

---

### 4. Concrete Rocq / Coq Formalization

Below is the complete, self-contained formalization in `BlinkScrollSnapAlignmentSemantics.v` using exact rational/integer arithmetic (`Z`, representing subpixel layout units such as Blink's `LayoutUnit` or doubled coordinates to avoid division rounding in center alignment).

```coq
(** * BlinkScrollSnapAlignmentSemantics.v
    Formal audit of Chromium Blink Scroll Snap Alignment (cc::SnapContainerData)
    against CSS Scroll Snap Module Level 1 (§4 & §6). *)

From Coq Require Import ZArith.
From Coq Require Import List.
From Coq Require Import Lia.
Import ListNotations.
Open Scope Z_scope.

(** ** 1. Scroll Snap Data Structures *)

Inductive SnapAlignment : Type :=
  | AlignNone
  | AlignStart
  | AlignCenter
  | AlignEnd.

Inductive SnapStrictness : Type :=
  | StrictnessNone
  | StrictnessProximity
  | StrictnessMandatory.

(** A 1D SnapArea in the scrollable overflow coordinate space.
    To avoid rational division rounding during Center alignment, coordinates
    can be interpreted as 1/2-layout-units (or standard LayoutUnits where
    center uses integer division). Here we use exact Z arithmetic with
    doubled coordinates or explicit integer division2. We model standard
    integer division (Z.div 2) matching C++ integer/float midpoint behavior. *)
Record SnapArea1D : Type := mkSnapArea {
  area_pos   : Z; (* Margin-box start offset relative to scroll origin *)
  area_size  : Z; (* Margin-box length *)
  area_align : SnapAlignment
}.

(** A 1D SnapContainer (Snapport + Scroll Bounds + Strictness). *)
Record SnapContainer1D : Type := mkSnapContainer {
  content_width       : Z;
  viewport_width      : Z;
  padding_start       : Z;
  padding_end         : Z;
  strictness          : SnapStrictness;
  proximity_threshold : Z;
  snap_areas          : list SnapArea1D
}.

(** ** 2. Target Scroll Offset Calculation *)

(** Maximum scrollable offset: max(0, content_width - viewport_width) *)
Definition max_scroll_offset (c : SnapContainer1D) : Z :=
  Z.max 0 (content_width c - viewport_width c).

(** Snapport start and size relative to the visual viewport *)
Definition snapport_start (c : SnapContainer1D) : Z :=
  padding_start c.

Definition snapport_size (c : SnapContainer1D) : Z :=
  (viewport_width c - padding_end c) - padding_start c.

(** Clamp a value v into [low, high] *)
Definition clamp (v low high : Z) : Z :=
  Z.min high (Z.max low v).

(** Unclamped target scroll offset aligning the area with the snapport (§6.1) *)
Definition raw_snap_offset (c : SnapContainer1D) (a : SnapArea1D) : option Z :=
  let p_start := snapport_start c in
  let p_size  := snapport_size c in
  match area_align a with
  | AlignNone   => None
  | AlignStart  => Some (area_pos a - p_start)
  | AlignCenter => Some ((area_pos a + (area_size a / 2)) - (p_start + (p_size / 2)))
  | AlignEnd    => Some ((area_pos a + area_size a) - (p_start + p_size))
  end.

(** Clamped target scroll offset within [0, max_scroll_offset] (§4.1) *)
Definition target_snap_offset (c : SnapContainer1D) (a : SnapArea1D) : option Z :=
  match raw_snap_offset c a with
  | None => None
  | Some raw => Some (clamp raw 0 (max_scroll_offset c))
  end.

(** Extract all valid candidate snap positions from a container's snap areas *)
Fixpoint candidate_offsets (c : SnapContainer1D) (areas : list SnapArea1D) : list Z :=
  match areas with
  | [] => []
  | a :: rest =>
      match target_snap_offset c a with
      | Some pos => pos :: candidate_offsets c rest
      | None     => candidate_offsets c rest
      end
  end.

(** Find the candidate offset minimizing distance to intended_scroll.
    Tie-breaking is deterministic: first minimal candidate in layout order wins. *)
Fixpoint find_closest_candidate (intended : Z) (candidates : list Z) (best : option Z) : option Z :=
  match candidates with
  | [] => best
  | cand :: rest =>
      match best with
      | None => find_closest_candidate intended rest (Some cand)
      | Some b =>
          if Z.ltb (Z.abs (cand - intended)) (Z.abs (b - intended))
          then find_closest_candidate intended rest (Some cand)
          else find_closest_candidate intended rest (Some b)
      end
  end.

(** Full 1D Scroll Snap resolution given an intended scroll offset. *)
Definition resolve_scroll_snap (c : SnapContainer1D) (intended_scroll : Z) : Z :=
  let clamped_intended := clamp intended_scroll 0 (max_scroll_offset c) in
  let candidates := candidate_offsets c (snap_areas c) in
  match strictness c with
  | StrictnessNone => clamped_intended
  | StrictnessMandatory =>
      match find_closest_candidate clamped_intended candidates None with
      | Some snap_pos => snap_pos
      | None          => clamped_intended
      end
  | StrictnessProximity =>
      match find_closest_candidate clamped_intended candidates None with
      | Some snap_pos =>
          if Z.leb (Z.abs (snap_pos - clamped_intended)) (proximity_threshold c)
          then snap_pos
          else clamped_intended
      | None => clamped_intended
      end
  end.

(** ** 3. Invariants & Theorems *)

(** Lemma: clamp always bounds the value within [low, high] when low <= high. *)
Lemma clamp_bounds : forall v low high : Z,
  low <= high ->
  low <= clamp v low high <= high.
Proof.
  intros v low high Hle.
  unfold clamp.
  lia.
Qed.

(** Lemma: max_scroll_offset is always non-negative. *)
Lemma max_scroll_nonneg : forall c : SnapContainer1D,
  0 <= max_scroll_offset c.
Proof.
  intros c.
  unfold max_scroll_offset.
  lia.
Qed.

(** Theorem 1: Any single snap area's target scroll offset is bounded within
    [0, max_scroll_offset], and specifically [0, content_width - viewport_width]
    whenever content_width >= viewport_width. *)
Theorem target_snap_offset_bounded : forall (c : SnapContainer1D) (a : SnapArea1D) (t : Z),
  content_width c >= viewport_width c ->
  target_snap_offset c a = Some t ->
  0 <= t <= content_width c - viewport_width c.
Proof.
  intros c a t Hcw Htarget.
  unfold target_snap_offset in Htarget.
  destruct (raw_snap_offset c a) as [raw|] eqn:Hraw; [|discriminate].
  inversion Htarget; subst t; clear Htarget.
  assert (Hmax : max_scroll_offset c = content_width c - viewport_width c).
  { unfold max_scroll_offset. lia. }
  rewrite <- Hmax.
  apply clamp_bounds.
  apply max_scroll_nonneg.
Qed.

(** Lemma: Every element in candidate_offsets satisfies the scroll bounds. *)
Lemma candidate_offsets_bounded : forall (c : SnapContainer1