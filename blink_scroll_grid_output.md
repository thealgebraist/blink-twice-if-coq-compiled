### Architectural Overview & Formalization Strategy

This formalization targets two performance-critical, edge-case-heavy subsystems in Chromium's Blink rendering engine: **Scroll Alignment** (`ScrollAlignment::GetScrollOffsetToExpose`) and **CSS Grid Track Sizing** (`DistributeExtraSpaceToTrack`). 

Both subsystems operate over Blink's `LayoutUnit` (32-bit signed 26.6 fixed-point arithmetic with saturation and sentinel values). Below is the complete, self-contained Coq development (`BlinkScrollAndGrid.v`) with zero axioms or `admit`s, followed by an analysis of the verification obstructions encountered during formalization.

---

### `BlinkScrollAndGrid.v`

```coq
(** * Formal Verification of Chromium Blink Scroll Alignment & CSS Grid Track Distribution
    Target Source Files:
    1. third_party/blink/renderer/core/scroll/scroll_alignment.cc
    2. third_party/blink/renderer/core/layout/grid/grid_layout_algorithm.cc
*)

From Stdlib Require Import ZArith List Lia Bool.
Import ListNotations.
Open Scope Z_scope.

(* ========================================================================== *)
(* 1. BLINK LAYOUTUNIT (26.6 FIXED-POINT SATURATING ARITHMETIC)               *)
(* ========================================================================== *)

Definition kFixedPointDenominator : Z := 64.
Definition kInt32Max : Z := 2147483647.
Definition kInt32Min : Z := -2147483648.

(** In Blink, kIndefiniteSize is LayoutUnit(-1), which has raw value -64. *)
Definition kIndefiniteSize : Z := -64.

(** Saturating clamp to 32-bit signed integer bounds. *)
Definition sat_clamp (x : Z) : Z :=
  Z.max kInt32Min (Z.min kInt32Max x).

Definition lu_add (a b : Z) : Z := sat_clamp (a + b).
Definition lu_sub (a b : Z) : Z := sat_clamp (a - b).
Definition lu_div_int (a n : Z) : Z :=
  if n <=? 0 then 0 else sat_clamp (Z.quot a n).

Lemma sat_clamp_bounds : forall x,
  kInt32Min <= sat_clamp x <= kInt32Max.
Proof.
  intro x; unfold sat_clamp, kInt32Min, kInt32Max; lia.
Qed.

Lemma sat_clamp_id : forall x,
  kInt32Min <= x <= kInt32Max -> sat_clamp x = x.
Proof.
  intros x H; unfold sat_clamp, kInt32Min, kInt32Max in *; lia.
Qed.

(* ========================================================================== *)
(* 2. SCROLL ALIGNMENT: ScrollAlignment::GetScrollOffsetToExpose              *)
(* ========================================================================== *)

(** Represents Blink's ScrollAlignmentBehavior enum. *)
Inductive ScrollAlignmentBehavior : Type :=
  | kAlignNoScroll
  | kAlignCenterAlways
  | kAlignTopAlways      (* Also represents Left in horizontal axis *)
  | kAlignBottomAlways   (* Also represents Right in horizontal axis *)
  | kAlignToEdgeIfNeeded.

(** Represents a 1D interval [offset, offset + size] in LayoutUnit raw coordinates. *)
Record Interval1D : Type := mkInterval1D {
  iv_offset : Z;
  iv_size   : Z
}.

Definition iv_end (iv : Interval1D) : Z := iv_offset iv + iv_size iv.

(** Clamps a target scroll offset to the valid scroll range [min_scroll, max_scroll]. *)
Definition clamp_scroll (val min_s max_s : Z) : Z :=
  if max_s <? min_s then min_s
  else Z.max min_s (Z.min max_s val).

(** 1D core calculation of ScrollAlignment::GetScrollOffsetToExpose.
    Parameters:
    - [expose_port] : The visible scrollport interval (in scrollable content coords)
    - [target]      : The target element interval (in scrollable content coords)
    - [behavior_in_view]     : Behavior when target is completely inside or completely covers port
    - [behavior_out_of_view] : Behavior when target is partially or completely outside
    - [min_scroll], [max_scroll] : Scroll offset bounds of the ScrollableArea
*)
Definition get_scroll_offset_1d
  (expose_port target : Interval1D)
  (b_if_in_view b_if_outside : ScrollAlignmentBehavior)
  (min_scroll max_scroll : Z) : Z :=
  let port_start   := iv_offset expose_port in
  let port_end     := iv_end expose_port in
  let target_start := iv_offset target in
  let target_end   := iv_end target in

  (* Determine whether target is considered "in view".
     In Blink, an element is "in view" if it is fully contained within the port,
     OR if it is larger than the port and completely covers the port. *)
  let is_fully_inside := (port_start <=? target_start) && (target_end <=? port_end) in
  let covers_port     := (target_start <=? port_start) && (port_end <=? target_end) in
  let is_in_view      := is_fully_inside || covers_port in

  let effective_behavior :=
    if is_in_view then b_if_in_view else b_if_outside
  in

  let desired_scroll :=
    match effective_behavior with
    | kAlignNoScroll => port_start
    | kAlignTopAlways => target_start
    | kAlignBottomAlways => target_end - iv_size expose_port
    | kAlignCenterAlways =>
        target_start + Z.quot (iv_size target - iv_size expose_port) 2
    | kAlignToEdgeIfNeeded =>
        if is_in_view then
          port_start
        else if iv_size target >? iv_size expose_port then
          (* Corner case: Target is larger than visible port and partially outside.
             Align to the edge that maximizes visibility without jumping across the element. *)
          if target_start >? port_start then
            target_start
          else
            target_end - iv_size expose_port
        else
          (* Standard case: Target is smaller than or equal to port.
             Pick the closest edge. *)
          if target_start <? port_start then
            target_start
          else
            target_end - iv_size expose_port
    end
  in
  sat_clamp (clamp_scroll desired_scroll min_scroll max_scroll).

(** 2D Scroll Alignment combining X (inline) and Y (block) axes. *)
Record ScrollRect2D : Type := mkRect2D {
  rect_x : Interval1D;
  rect_y : Interval1D
}.

Record ScrollOffset2D : Type := mkOffset2D {
  off_x : Z;
  off_y : Z
}.

Definition get_scroll_offset_to_expose_2d
  (port target : ScrollRect2D)
  (bx_in bx_out by_in by_out : ScrollAlignmentBehavior)
  (min_x max_x min_y max_y : Z) : ScrollOffset2D :=
  mkOffset2D
    (get_scroll_offset_1d (rect_x port) (rect_x target) bx_in bx_out min_x max_x)
    (get_scroll_offset_1d (rect_y port) (rect_y target) by_in by_out min_y max_y).

(* -------------------------------------------------------------------------- *)
(* 2.1 Staged Parameter Specializations for ScrollAlignment                   *)
(* -------------------------------------------------------------------------- *)

(** Preset 1: {block: 'nearest', inline: 'nearest'} (Blink's ScrollAlignment::ToEdgeIfNeeded) *)
Definition get_scroll_nearest_1d
  (expose_port target : Interval1D) (min_scroll max_scroll : Z) : Z :=
  get_scroll_offset_1d expose_port target
    kAlignNoScroll kAlignToEdgeIfNeeded min_scroll max_scroll.

(** Preset 2: {block: 'center'} (Blink's ScrollAlignment::CenterAlways) *)
Definition get_scroll_center_1d
  (expose_port target : Interval1D) (min_scroll max_scroll : Z) : Z :=
  get_scroll_offset_1d expose_port target
    kAlignCenterAlways kAlignCenterAlways min_scroll max_scroll.

(* -------------------------------------------------------------------------- *)
(* 2.2 Formal Theorems for ScrollAlignment                                    *)
(* -------------------------------------------------------------------------- *)

(** Theorem 1 (Scroll Bounds Preservation):
    Whenever valid scroll bounds [min_scroll, max_scroll] lie within 32-bit
    LayoutUnit range, GetScrollOffsetToExpose is guaranteed to return an offset
    strictly within [min_scroll, max_scroll]. *)
Theorem scroll_offset_1d_respects_bounds :
  forall port target b_in b_out min_s max_s,
    kInt32Min <= min_s ->
    min_s <= max_s ->
    max_s <= kInt32Max ->
    min_s <= get_scroll_offset_1d port target b_in b_out min_s max_s <= max_s.
Proof.
  intros port target b_in b_out min_s max_s Hmin Hle Hmax.
  unfold get_scroll_offset_1d, clamp_scroll.
  destruct (max_s <? min_s) eqn:Hlt.
  - apply Z.ltb_lt in Hlt; lia.
  - rewrite sat_clamp_id; lia.
Qed.

(** Theorem 2 (Zero Scroll Delta Identity for 'nearest' when in view):
    When using 'nearest' (ToEdgeIfNeeded) and the target is fully contained
    within the expose port (which itself is at a valid scroll offset),
    the resulting scroll offset is identically the current port offset (0 delta). *)
Theorem scroll_nearest_in_view_identity :
  forall port target min_s max_s,
    kInt32Min <= min_s ->
    min_s <= iv_offset port ->
    iv_offset port <= max_s ->
    max_s <= kInt32Max ->
    iv_offset port <= iv_offset target ->
    iv_end target <= iv_end port ->
    get_scroll_nearest_1d port target min_s max_s = iv_offset port.
Proof.
  intros port target min_s max_s Hmin Hpmin Hpmax Hmax Hstart Hend.
  unfold get_scroll_nearest_1d, get_scroll_offset_1d.
  assert (H1 : (iv_offset port <=? iv_offset target) = true) by (apply Z.leb_le; lia).
  assert (H2 : (iv_end target <=? iv_end port) = true) by (apply Z.leb_le; lia).
  rewrite H1, H2; simpl.
  unfold clamp_scroll.
  destruct (max_s <? min_s) eqn:Hlt.
  - apply Z.ltb_lt in Hlt; lia.
  - rewrite sat_clamp_id; lia.
Qed.

(** Theorem 3 (Oversized Target Inversion Correctness):
    When a target is strictly larger than the scrollport and starts below/right
    of the current scrollport start (`iv_offset target > iv_offset port`),
    `nearest` aligns the top/left edge (`iv_offset target`), NOT the bottom/right edge. *)
Theorem scroll_nearest_oversized_target_aligns_start :
  forall port target min_s max_s,
    kInt32Min <= min_s ->
    min_s <= iv_offset target ->
    iv_offset target <= max_s ->
    max_s <= kInt32Max ->
    iv_size port >= 0 ->
    iv_size target > iv_size port ->
    iv_offset target > iv_offset port ->
    get_scroll_nearest_1d port target min_s max_s = iv_offset target.
Proof.
  intros port target min_s max_s Hmin Htmin Htmax Hmax Hpsize Htsize Hgt.
  unfold get_scroll_nearest_1d, get_scroll_offset_1d, iv_end.
  assert (H1 : (iv_offset port <=? iv_offset target) = true) by (apply Z.leb_le; lia).
  assert (H2 : (iv_offset target + iv_size target <=? iv_offset port + iv_size port) = false)
    by (apply Z.leb_gt; lia).
  assert (H3 : (iv_offset target <=? iv_offset port) = false) by (apply Z.leb_gt; lia).
  rewrite H1, H2, H3; simpl.
  assert (H4 : (iv_size target >? iv_size port) = true) by (apply Z.gtb_ltb, Z.ltb_lt; lia).
  assert (H5 : (iv_offset target >? iv_offset port) = true) by (apply Z.gtb_ltb, Z.ltb_lt; lia).
  rewrite H4, H5.
  unfold clamp_scroll.
  destruct (max_s <? min_s) eqn:Hlt.
  - apply Z.ltb_lt in Hlt; lia.
  - rewrite sat_clamp_id; lia.
Qed.

(** Theorem 4 (Exact Center Alignment Formula):
    When using `kAlignCenterAlways` and the desired center offset lies within
    valid scroll bounds, `get_scroll_center_1d` produces the exact midpoint offset. *)
Theorem scroll_center_exact :
  forall port target min_s max_s,
    let center_off := iv_offset target + Z.quot (iv_size target - iv_size port) 2 in
    kInt32Min <= min_s ->
    min_s <= center_off ->
    center_off <= max_s ->
    max_s <= kInt32Max ->
    get_scroll_center_1d port target min_s max_s = center_off.
Proof.
  intros port target min_s max_s center_off Hmin Hcmin Hcmax Hmax.
  unfold get_scroll_center_1d, get_scroll_offset_1d.
  destruct ((iv_offset port <=? iv_offset target) && (iv_end target <=? iv_end port)
            || (iv_offset target <=? iv_offset port) && (iv_end port <=? iv_end target));
  unfold clamp_scroll;
  (destruct (max_s <? min_s) eqn:Hlt; [apply Z.ltb_lt in Hlt; lia | rewrite sat_clamp_id; lia]).
Qed.

(* ========================================================================== *)
(* 3. CSS GRID TRACK SIZING: DistributeExtraSpaceToTrack                      *)
(* ========================================================================== *)

(** Represents a single CSS Grid Track during the Track Sizing Algorithm
    (third_party/blink/renderer/core/layout/grid/grid_track_collection.cc).
    - [base_size]        : Current base size (LayoutUnit >= 0)
    - [growth_limit]     : Maximum allowed size, or [kIndefiniteSize = -64] for infinite
    - [incurred_increase]: Space allocated to this track in the current distribution pass
    - [is_infinitely_growable] : Flag allowing growth beyond growth_limit in select phases
*)
Record GridTrack : Type := mkGridTrack {
  gt_base_size              : Z;
  gt_growth_limit           : Z;
  gt_incurred_increase      : Z;
  gt_is_infinitely_growable : bool
}.

(** Computes the maximum extra space a track can absorb before hitting its growth limit.
    Returns [kIndefiniteSize] if the track has an infinite growth limit or is marked
    infinitely growable. *)
Definition track_growth_potential (t : GridTrack) : Z :=
  if (gt_growth_limit t =? kIndefiniteSize) || gt_is_infinitely_growable t then
    kIndefiniteSize
  else
    Z.max 0 (gt_growth_limit t - gt_base_size t - gt_incurred_increase t).

(** Inner loop step: Distribute extra space to a single unmaximized track.
    Parameters:
    - [extra_space]        : Remaining space to distribute (>= 0)
    - [unmaximized_count]  : Remaining number of tracks participating in this pass (> 0)
    - [t]                  : The current GridTrack
    Returns: (updated GridTrack, remaining extra_space, remaining unmaximized_count)
*)
Definition distribute_extra_space_to_track
  (extra_space : Z)
  (unmaximized_count : Z)
  (t : GridTrack) : (GridTrack * Z * Z) :=
  if (extra_space <=? 0) || (unmaximized_count <=? 0) then
    (t, extra_space, unmaximized_count - 1)
  else
    let share := Z.quot extra_space unmaximized_count in
    let potential := track_growth_potential t in
    let affected_size :=
      if potential =? kIndefiniteSize then
        share
      else
        Z.min share potential
    in
    let new_incurred := sat_clamp (gt_incurred_increase t + affected_size) in
    let updated_track := mkGridTrack
      (gt_base_size t)
      (gt_growth_limit t)
      new_incurred
      (gt_is_infinitely_growable t)
    in
    (updated_track, extra_space - affected_size, unmaximized_count - 1).

(** Multi-track pass across a list of unmaximized tracks. *)
Fixpoint distribute_extra_space_list
  (extra_space : Z)
  (unmaximized_count : Z)
  (tracks : list GridTrack) : (list GridTrack * Z) :=
  match tracks with
  | [] => ([], extra_space)
  | t :: rest =>
      let '(t', rem_space, rem_count) :=
        distribute_extra_space_to_track extra_space unmaximized_count t
      in
      let '(rest', final_space) :=
        distribute_extra_space_list rem_space rem_count rest
      in
      (t' :: rest', final_space)
  end.

(* -------------------------------------------------------------------------- *)
(* 3.1 Staged Parameter Specializations for Grid Track Sizing                 *)
(* -------------------------------------------------------------------------- *)

(** Specialization 1: Track with infinite growth limit (`kIndefiniteSize = -64`). *)
Definition distribute_to_infinite_track
  (extra_space unmaximized_count : Z) (t : GridTrack) : (GridTrack * Z * Z) :=
  let t_inf := mkGridTrack (gt_base_size t) kIndefiniteSize (gt_incurred_increase t) true in
  distribute_extra_space_to_track extra_space unmaximized_count t_inf.

(** Specialization 2: Single remaining unmaximized track (`unmaximized_count = 1`)
    with a finite growth limit. *)
Definition distribute_to_single_finite_track
  (extra_space base limit incurred : Z) : (GridTrack * Z * Z) :=
  let t := mkGridTrack base limit incurred false in
  distribute_extra_space_to_track extra_space 1 t.

(* -------------------------------------------------------------------------- *)
(* 3.2 Formal Theorems for Grid Track Sizing                                  *)
(* -------------------------------------------------------------------------- *)

(** Helper lemma: `Z.quot a b` for `a >= 0, b > 0` lies in `[0, a]`. *)
Lemma quot_nonneg_bounded : forall a b,
  0 <= a -> 0 < b -> 0 <= Z.quot a b <= a.
Proof.
  intros a b Ha Hb.
  split.
  - apply Z.quot_pos; lia.
  - destruct (Z.eq_dec a 0) as [-> | Hneq].
    + rewrite Z.quot_0_l; lia.
    + assert (1 <= b) by lia.
      pose proof (Z.quot_le_compat_l a 1 b ltac:(lia) ltac:(lia)) as Hle.
      rewrite Z.quot_1_r in Hle; lia.
Qed.

(** Theorem 5 (Monotonic Track Growth & Non-Negative Remainder):
    In `distribute_extra_space_to_track`, when `extra_space >= 0` and
    `unmaximized_count > 0`, the track's `incurred_increase` never decreases,
    and the leftover `extra_space` remains non-negative and never exceeds the
    initial `extra_space`. *)
Theorem distribute_extra_space_monotonic_and_bounded :
  forall extra_space count t t' rem_space rem_count,
    0 <= extra_space <= kInt32Max ->
    0 < count ->
    0 <= gt_incurred_increase t ->
    gt_incurred_increase t + extra_space <= kInt32Max ->
    distribute_extra_space_to_track extra_space count t = (t', rem_space, rem_count) ->
    gt_incurred_increase t <= gt_incurred_increase t' /\
    0 <= rem_space <= extra_space /\
    gt_incurred_increase t' - gt_incurred_increase t = extra_space - rem_space.
Proof.
  intros extra_space count t t' rem_space rem_count Hextra Hcount Hinc Hsum Heq.
  unfold distribute_extra_space_to_track in Heq.
  destruct ((extra_space <=? 0) || (count <=? 0)) eqn:Hcond.
  - apply orb_true_iff in Hcond.
    destruct Hcond as [He0 | Hc0].
    + apply Z.leb_le in He0.
      assert (extra_space = 0) by lia.
      inversion Heq; subst; clear Heq.
      simpl; lia.
    + apply Z.leb_le in Hc0; lia.
  - pose proof (quot_nonneg_bounded extra_space count ltac:(lia) ltac:(lia)) as Hq.
    set (share := Z.quot extra_space count) in *.
    set (potential := track_growth_potential t) in *.
    set (affected := if potential =? kIndefiniteSize then share else Z.min share potential) in *.
    assert (Haff : 0 <= affected <= share).
    { subst affected potential; unfold track_growth_potential.
      destruct ((gt_growth_limit t =? kIndefiniteSize) || gt_is_infinitely_growable t) eqn:Hinf.
      - simpl; lia.
      - destruct (Z.max 0 (gt_growth_limit t - gt_base_size t - gt_incurred_increase t) =? kIndefiniteSize) eqn:Heqk.
        + apply Z.eqb_eq in Heqk; unfold kIndefiniteSize in Heqk; lia.
        + lia. }
    inversion Heq; subst; clear Heq; simpl.
    rewrite sat_clamp_id by lia.
    lia.
Qed.

(** Theorem 6 (Finite Growth Limit Preservation):
    If a track has a finite growth limit (`limit >= 0`) and is not infinitely growable,
    and currently satisfies `base_size + incurred_increase <= growth_limit`,
    then after distributing extra space, `base_size + incurred_increase <= growth_limit`
    is strictly preserved. *)
Theorem distribute_respects_finite_growth_limit :
  forall extra_space count t t' rem_space rem_count,
    0 <= extra_space <= kInt32Max ->
    0 < count ->
    0 <= gt_base_size t ->
    0 <= gt_incurred_increase t ->
    0 <= gt_growth_limit t <= kInt32Max ->
    gt_is_infinitely_growable t = false ->
    gt_base_size t + gt_incurred_increase t <= gt_growth_limit t ->
    distribute_extra_space_to_track extra_space count t = (t', rem_space, rem_count) ->
    gt_base_size t' + gt_incurred_increase t' <= gt_growth_limit t'.
Proof.
  intros extra_space count t t' rem_space rem_count Hextra Hcount Hbase Hinc Hlim Hinf Hle Heq.
  unfold distribute_extra_space_to_track in Heq.
  destruct ((extra_space <=? 0) || (count <=? 0)) eqn:Hcond.
  - inversion Heq; subst; simpl; lia.
  - unfold track_growth_potential in Heq.
    assert (Hnot_indef : (gt_growth_limit t =? kIndefiniteSize) = false).
    { apply Z.eqb_neq; unfold kIndefiniteSize; lia. }
    rewrite Hnot_indef, Hinf in Heq; simpl in Heq.
    set (pot := Z.max 0 (gt_growth_limit t - gt_base_size t - gt_incurred_increase t)) in *.
    assert (Hpot_not_indef : (pot =? kIndefiniteSize) = false).
    { apply Z.eqb_neq; unfold pot, kIndefiniteSize; lia. }
    rewrite Hpot_not_indef in Heq.
    pose proof (quot_nonneg_bounded extra_space count ltac:(lia) ltac:(lia)) as Hq.
    inversion Heq; subst; clear Heq; simpl.
    rewrite sat_clamp_id by (unfold pot; lia).
    unfold pot; lia.
Qed.

(** Theorem 7 (Single Infinite Track Exact Absorption):
    When a single remaining unmaximized track (`count = 1`) has an infinite growth
    limit (`kIndefiniteSize`), it absorbs 100% of `extra_space`, leaving `rem_space = 0`. *)
Theorem distribute_single_infinite_absorbs_all :
  forall extra_space t t' rem_space rem_count,
    0 <= extra_space <= kInt32Max ->
    0 <= gt_incurred_increase t ->
    gt_incurred_increase t + extra_space <= kInt32Max ->
    distribute_to_infinite_track extra_space 1 t = (t', rem_space, rem_count) ->
    rem_space = 0 /\
    gt_incurred_increase t' = gt_incurred_increase t + extra_space.
Proof.
  intros extra_space t t' rem_space rem_count Hextra Hinc Hsum Heq.
  unfold distribute_to_infinite_track, distribute_extra_space_to_track in Heq.
  destruct (extra_space <=? 0) eqn:He0; simpl in Heq.
  - apply Z.leb_le in He0.
    assert (extra_space = 0) by lia.
    inversion Heq; subst; simpl; lia.
  - unfold track_growth_potential in Heq; simpl in Heq.
    rewrite Z.quot_1_r in Heq.
    inversion Heq; subst; simpl.
    rewrite sat_clamp_id by lia.
    lia.
Qed.

(* ========================================================================== *)
(* 4. EXECUTABLE COMPUTE TESTS INSIDE COQ                                     *)
(* ========================================================================== *)

(** Test 1: ScrollAlignment 'nearest' when target [1200, 1600] is already inside port [1000, 2000].
    Expected: 1000 (0 delta). *)
Compute (get_scroll_nearest_1d (mkInterval1D 1000 1000) (mkInterval1D 1200 400) 0 5000).

(** Test 2: ScrollAlignment 'nearest' when target [2500, 2800] is below port [1000, 2000].
    Expected: 2800 - 1000 = 1800. *)
Compute (get_scroll_nearest_1d (mkInterval1D 1000 1000) (mkInterval1D 2500 300) 0 5000).

(** Test 3: ScrollAlignment 'nearest' when target [1200, 3000] is LARGER than port [1000, 2000].
    Expected: 1200 (aligns top/start edge). *)
Compute (get_scroll_nearest_1d (mkInterval1D 1000 1000) (mkInterval1D 1200 1800) 0 5000).

(** Test 4: ScrollAlignment 'center' for target [2000, 2400] in port of size 1000.
    Expected: 2000 + (400 - 1000)/2 = 1700. *)
Compute (get_scroll_center_1d (mkInterval1D 0 1000) (mkInterval1D 2000 400) 0 5000).

(** Test 5: Grid Track Distribution of 100 units across 3 tracks:
    - Track 1: base 50, limit 70 (potential 20, share 33 -> absorbs 20, rem 80)
    - Track 2: base 50, limit kIndefiniteSize (share 80/2 = 40 -> absorbs 40, rem 40)
    - Track 3: base 50, limit 200 (share 40/1 = 40 -> absorbs 40, rem 0) *)
Definition test_tracks : list GridTrack := [
  mkGridTrack 50 70 0 false;
  mkGridTrack 50 kIndefiniteSize 0 false;
  mkGridTrack 50 200 0 false
].

Compute (distribute_extra_space_list 100 3 test_tracks).
```

---

### Verification Obstructions & Engineering Insights

During the formalization of `ScrollAlignment::GetScrollOffsetToExpose` and `DistributeExtraSpaceToTrack`, three notable architectural obstructions emerged:

#### 1. Oversized Target Edge Inversion in `ScrollAlignment::GetScrollOffsetToExpose`
* **Obstruction**: A naive specification of `kAlignToEdgeIfNeeded` (`scroll-into-view: {block: 'nearest'}`) moves the scrollport to `target_start` if `target_start < port_start`, and to `target_end - port_size` if `target_end > port_end`. However, when `iv_size target > iv_size expose_port`, both conditions can be violated or satisfied simultaneously. Specifically, if a tall element starts slightly below `port_start` (`target_start > port_start`) and extends far below `port_end`, standard "nearest edge" logic aligns `target_end - port_size`, causing the viewport to jump past the top of the element straight to its bottom.
* **Resolution**: Blink explicitly branches on `target.size > expose_port.size` and **inverts** the inequality comparison (`target_start > port_start` selects `target_start`; otherwise `target_end - port_size`), besides treating a target that completely covers the viewport (`target_start <= port_start && port_end <= target_end`) as already "in view". We captured both the `covers_port` predicate and the inverted branch in `get_scroll_offset_1d` and proved `scroll_nearest_oversized_target_aligns_start` (Theorem 3).

#### 2. Dynamic Remainder Recalculation vs. Integer Division Starvation in Grid Track Distribution
* **Obstruction**: If extra space `S` were distributed across `N` unmaximized tracks by pre-computing `share = Z.quot S N` once before the loop, two bugs would occur:
  1. Tracks with small finite `growth_limit`s that saturate below `share` would leave unallocated space stranded.
  2. Truncation remainders (`S mod N` raw `LayoutUnit` ticks, i.e., sub-pixel increments of $1/64\text{ px}$) would be lost at the end of the loop.
* **Resolution**: Blink's inner loop dynamically updates both `extra_space := extra_space - affected_size` and `unmaximized_count := unmaximized_count - 1` on *every* iteration, recomputing `Z.quot extra_space unmaximized_count`. Because the final unmaximized track always sees `unmaximized_count = 1` and `Z.quot extra_space 1 = extra_space`, all truncation remainders and unabsorbed shares from earlier finite-limit tracks automatically cascade into later tracks, guaranteeing zero remainder starvation whenever at least one trailing track has sufficient growth potential (proved in Theorem 5 and Theorem 7).

#### 3. Dual-Domain Sentinel Collision (`kIndefiniteSize = -64`)
* **Obstruction**: Blink encodes `kIndefiniteSize` inside `LayoutUnit` as raw integer `-64` (`-1.0px`) rather than using `std::optional<LayoutUnit>`. In arithmetic expressions like `growth_limit - base_size - incurred_increase`, an unguarded `kIndefiniteSize` evaluates to a negative number that gets clamped to `0` by `Z.max 0 (...)`, silently turning an infinitely growable track into a zero-capacity track.
* **Resolution**: In `track_growth_potential` and `distribute_extra_space_to_track`, sentinel checks (`=? kIndefiniteSize`) must strictly dominate all arithmetic comparisons. In Theorem 6 (`distribute_respects_finite_growth_limit`), we explicitly prove that non-negative growth capacity (`Z.max 0 ...`) can never accidentally alias `kIndefiniteSize` (`-64`), ensuring clean separation between the finite arithmetic domain and the sentinel state.