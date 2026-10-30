### 1. Core Data Structures in Blink Scroll Timeline Evaluation

In Chromium Blink (`third_party/blink/renderer/core/animation/`), the evaluation of scroll-driven timelines relies on the following structures:

*   **`ScrollTimeline` (`scroll_timeline.h/.cc`)**: Inherits from `AnimationTimeline`. It manages the relationship between a scroll container (` resolve_source_`), the scroll orientation (`ScrollAxis`: `kBlock`, `kInline`, `kX`, `kY`), and the cached `TimelineState`.
*   **`ScrollSnapshotTimeline` (`scroll_snapshot_timeline.h/.cc`)**: The base class handling state snapshotting once per animation frame (`ServiceAnimations`). It stores `TimelineState`, which encapsulates:
    *   `phase`: `TimelinePhase` (`kInactive`, `kActive`, `kBefore`, `kAfter`).
    *   `current_time`: `std::optional<AnimationTimeDelta>` representing normalized progress scaled by an internal duration (typically `100s` for percentage-based scroll timelines).
    *   `scroll_offsets`: `std::optional<ScrollOffsets>`.
*   **`ScrollOffsets` (`cc/animation/scroll_timeline.h`)**: A struct containing `double start_offset` ($S_{\text{start}}$) and `double end_offset` ($S_{\text{end}}$), representing the resolved pixel boundaries of the scroll range.
*   **`TimelineRange` (`timeline_range.h`)**: Represents the mapping of named timeline ranges (primarily used in `ViewTimeline`, a subclass of `ScrollTimeline`, e.g., `cover`, `contain`, `entry`, `exit`) into fractional offsets $[r_{\text{start}}, r_{\text{end}}] \subseteq [0, 1]$ relative to the overall `ScrollOffsets`.
*   **`ScrollTimelineOffset` (`scroll_timeline_offset.h`)**: Represents individual start/end offset boundaries resolved from CSS `<length-percentage>` values into layout pixels against the scroll container's scrollable overflow area.

---

### 2. Progress Computation

According to CSS Scroll-driven Animations 1 §3 (and implemented in `ScrollSnapshotTimeline::ComputeTimelineState`), the progress $\tau$ of a `ScrollTimeline` is determined by mapping the current scroll offset $S$ within the effective scroll range $[S_{\text{start}}, S_{\text{end}}]$.

For a standard `ScrollTimeline`:
*   $S_{\text{start}} = 0$
*   $S_{\text{end}} = \text{max\_scroll\_offset} = \text{scroll\_size} - \text{client\_size}$

When $S_{\text{start}} < S_{\text{end}}$, the unclamped normalized progress $\tau_{\text{raw}} \in \mathbb{R}$ is computed via the linear interpolation inverse:
$$\tau_{\text{raw}}(S) = \frac{S - S_{\text{start}}}{S_{\text{end}} - S_{\text{start}}}$$

In Blink, this fractional progress is converted into an `AnimationTimeDelta` by multiplying $\tau_{\text{raw}}$ by a fixed maximum timeline duration $D_{\max}$ (defined as `100s`, mapping $[0, 1]$ to $[0\%, 100\%]$):
$$\text{CurrentTime}(S) = \tau_{\text{raw}}(S) \times D_{\max}$$

---

### 3. Edge Case Handling

1.  **Zero or Negative Scroll Range ($S_{\text{start}} \ge S_{\text{end}}$)**:
    *   **CSS Spec §3.2**: If the scroll container does not overflow its scrollport (or $S_{\text{end}} \le S_{\text{start}}$), the scroll range is zero/degenerate, and the timeline is **inactive**.
    *   **Blink Implementation**: In `ScrollTimeline::CalculateOffsets`, if the scrollable overflow range is $\le 0$, `CalculateOffsets` returns `std::nullopt`. Consequently, `ComputeTimelineState` sets `phase = TimelinePhase::kInactive` and `current_time = std::nullopt`.
2.  **Non-Scrollable / Detached Source**:
    *   If the `resolved_source_` layout box is null, not a scroll container (`!IsScrollContainer()`), or display-locked, the timeline is immediately marked `kInactive` with no current time.
3.  **Out-of-Bounds Scroll Offsets ($S < S_{\text{start}}$ or $S > S_{\text{end}}$)**:
    *   **Elastic Overscroll (e.g., macOS / iOS)**: $S$ can temporarily fall outside $[S_{\text{start}}, S_{\text{end}}]$. The timeline itself does *not* clamp $\tau_{\text{raw}}$ at the `TimelineState` level; `current_time` can be $< 0\%$ or $> 100\%$.
    *   **Animation Effect Clamping / Fill Mode**: When an `AnimationEffect` samples the timeline (`AnimationEffect::UpdateInheritedTime`), it transitions into the `kBefore` phase ($\tau < 0$) or `kAfter` phase ($\tau > 1$). Depending on the CSS `animation-fill-mode` (`none`, `forwards`, `backwards`, `both`), the active progress applied to keyframes is clamped to $[0, 1]$ or evaluates to `null`. For effective active progress auditing within the scroll range, $S$ is bounded to $[S_{\text{start}}, S_{\text{end}}]$, yielding $\tau \in [0, 1]$.

---

### 4. Mathematical Invariants

For any active scroll timeline where $S_{\text{start}} < S_{\text{end}}$ and clamped scroll offset $S \in [S_{\text{start}}, S_{\text{end}}]$:

1.  **Monotonicity**: For any two scroll offsets $S_1, S_2$, if $S_1 \le S_2$, then $\tau(S_1) \le \tau(S_2)$.
2.  **Boundary Exactness**: $\tau(S_{\text{start}}) = 0$ and $\tau(S_{\text{end}}) = 1$.
3.  **Progress Containment**: For all $S \in [S_{\text{start}}, S_{\text{end}}]$, $0 \le \tau(S) \le 1$.
4.  **Degeneracy Inactivity**: Whenever $S_{\text{start}} \ge S_{\text{end}}$, the timeline state evaluates strictly to `Inactive`.

---

### 5. Rocq / Coq Formalization (`BlinkScrollTimelineProgressSemantics.v`)

```coq
(** * BlinkScrollTimelineProgressSemantics.v
    Formalization of Chromium Blink ScrollTimeline Progress vs CSS Scroll-driven Animations 1 §3. *)

From Coq Require Import Reals Lra.
Open Scope R_scope.

(** ** 1. Core Data Structures *)

Inductive ScrollAxis : Type :=
  | AxisBlock
  | AxisInline
  | AxisX
  | AxisY.

Inductive TimelinePhase : Type :=
  | PhaseInactive
  | PhaseBefore
  | PhaseActive
  | PhaseAfter.

Record ScrollOffsets : Type := mkScrollOffsets {
  start_offset : R;
  end_offset   : R
}.

Record TimelineRange : Type := mkTimelineRange {
  range_start : R;
  range_end   : R
}.

Inductive TimelineProgress : Type :=
  | InactiveProgress : TimelineProgress
  | ActiveProgress   : TimelinePhase -> R -> TimelineProgress.

(** ** 2. Clamping and Progress Computation *)

Definition clamp (x low high : R) : R :=
  Rmax low (Rmin high x).

Definition determine_phase (s s_start s_end : R) : TimelinePhase :=
  if Rlt_dec s s_start then PhaseBefore
  else if Rgt_dec s s_end then PhaseAfter
  else PhaseActive.

(** Unclamped raw progress computation matching ScrollSnapshotTimeline::ComputeTimelineState *)
Definition compute_raw_progress (offsets : option ScrollOffsets) (s : R) : TimelineProgress :=
  match offsets with
  | None => InactiveProgress
  | Some o =>
      let s_start := start_offset o in
      let s_end   := end_offset o in
      if Rlt_dec s_start s_end then
        let tau := (s - s_start) / (s_end - s_start) in
        ActiveProgress (determine_phase s s_start s_end) tau
      else
        InactiveProgress
  end.

(** Clamped progress computation in [0, 1] for active scroll range auditing *)
Definition compute_clamped_progress (offsets : option ScrollOffsets) (s : R) : TimelineProgress :=
  match offsets with
  | None => InactiveProgress
  | Some o =>
      let s_start := start_offset o in
      let s_end   := end_offset o in
      if Rlt_dec s_start s_end then
        let s_clamped := clamp s s_start s_end in
        let tau := (s_clamped - s_start) / (s_end - s_start) in
        ActiveProgress PhaseActive tau
      else
        InactiveProgress
  end.

(** ** 3. Mathematical Invariants and Proofs *)

(** Helper lemma for division monotonicity with positive denominator *)
Lemma Rdiv_le_compat_pos : forall a b c : R,
  0 < c -> a <= b -> a / c <= b / c.
Proof.
  intros a b c Hc Hab.
  unfold Rdiv.
  apply Rmult_le_compat_r.
  - left. apply Rinv_0_lt_compat; exact Hc.
  - exact Hab.
Qed.

(** Helper lemmas for clamp *)
Lemma clamp_bounds : forall x low high : R,
  low <= high -> low <= clamp x low high <= high.
Proof.
  intros x low high Hle.
  unfold clamp, Rmax, Rmin.
  destruct (Rle_dec high x); destruct (Rle_dec low (if Rle_dec high x then high else x)); lra.
Qed.

Lemma clamp_monotonic : forall x1 x2 low high : R,
  x1 <= x2 -> clamp x1 low high <= clamp x2 low high.
Proof.
  intros x1 x2 low high Hle.
  unfold clamp, Rmax, Rmin.
  destruct (Rle_dec high x1); destruct (Rle_dec high x2);
  destruct (Rle_dec low high); destruct (Rle_dec low x1); destruct (Rle_dec low x2); lra.
Qed.

Lemma clamp_id : forall x low high : R,
  low <= x <= high -> clamp x low high = x.
Proof.
  intros x low high [Hlow Hhigh].
  unfold clamp, Rmax, Rmin.
  destruct (Rle_dec high x); destruct (Rle_dec low x); destruct (Rle_dec low high); lra.
Qed.

(** *** Edge Case 1: Zero or Negative Scroll Range yields Inactive *)
Theorem zero_or_negative_range_inactive : forall o s,
  end_offset o <= start_offset o ->
  compute_raw_progress (Some o) s = InactiveProgress /\
  compute_clamped_progress (Some o) s = InactiveProgress.
Proof.
  intros o s Hdeg.
  unfold compute_raw_progress, compute_clamped_progress.
  destruct (Rlt_dec (start_offset o) (end_offset o)); [lra | auto].
Qed.

(** *** Invariant 1: Boundary Exactness tau(S_start) = 0 and tau(S_end) = 1 *)
Theorem boundary_start_zero : forall o,
  start_offset o < end_offset o ->
  compute_raw_progress (Some o) (start_offset o) = ActiveProgress PhaseActive 0.
Proof.
  intros o Hlt.
  unfold compute_raw_progress, determine_phase.
  destruct (Rlt_dec (start_offset o) (end_offset o)) as [H | H]; [| lra].
  destruct (Rlt_dec (start_offset o) (start_offset o)) as [H1 | H1]; [lra |].
  destruct (Rgt_dec (start_offset o) (end_offset o)) as [H2 | H2]; [lra |].
  f_equal.
  unfold Rdiv.
  replace (start_offset o - start_offset o) with 0 by lra.
  lra.
Qed.

Theorem boundary_end_one : forall o,
  start_offset o < end_offset o ->
  compute_raw_progress (Some o) (end_offset o) = ActiveProgress PhaseActive 1.
Proof.
  intros o Hlt.
  unfold compute_raw_progress, determine_phase.
  destruct (Rlt_dec (start_offset o) (end_offset o)) as [H | H]; [| lra].
  destruct (Rlt_dec (end_offset o) (start_offset o)) as [H1 | H1]; [lra |].
  destruct (Rgt_dec (end_offset o) (end_offset o)) as [H2 | H2]; [lra |].
  f_equal.
  apply Rinv_r.
  lra.
Qed.

(** *** Invariant 2: Progress Containment in [0, 1] *)
Theorem clamped_progress_contained : forall o s phase tau,
  compute_clamped_progress (Some o) s = ActiveProgress phase tau ->
  0 <= tau <= 1.
Proof.
  intros o s phase tau Heq.
  unfold compute_clamped_progress in Heq.
  destruct (Rlt_dec (start_offset o) (end_offset o)) as [Hlt | Hge]; [| discriminate].
  inversion Heq; subst; clear Heq.
  assert (Hbounds : start_offset o <= clamp s (start_offset o) (end_offset o) <= end_offset o).
  { apply clamp_bounds; lra. }
  destruct Hbounds as [Hlow Hhigh].
  split.
  - replace 0 with (0 / (end_offset o - start_offset o)) by (unfold Rdiv; lra).
    apply Rdiv_le_compat_pos; lra.
  - replace 1 with ((end_offset o - start_offset o) / (end_offset o - start_offset o)).
    + apply Rdiv_le_compat_pos; lra.
    + apply Rinv_r; lra.
Qed.

(** *** Invariant 3: Monotonic Mapping from Scroll Offset to Progress *)
Theorem raw_progress_monotonic : forall o s1 s2 p1 p2 tau1 tau2,
  s1 <= s2 ->
  compute_raw_progress (Some o) s1 = ActiveProgress p1 tau1 ->
  compute_raw_progress (Some o) s2 = ActiveProgress p2 tau2 ->
  tau1 <= tau2.
Proof.
  intros o s1 s2 p1 p2 tau1 tau2 Hs H1 H2.
  unfold compute_