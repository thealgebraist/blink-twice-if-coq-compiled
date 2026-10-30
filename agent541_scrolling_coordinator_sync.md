# Formal Verification of Chromium Blink `ScrollingCoordinator` Main-Thread to Compositor Synchronization

**Target Artifact**: `BlinkScrollingCoordinatorSyncSemantics.v`  
**Chromium Subsystem**: `third_party/blink/renderer/core/page/scrolling/scrolling_coordinator.cc`  
**Specification Reference**: Blink Scrolling Architecture §2 (Scroll Tree & Offset Synchronization), CSSOM View Module §6, HTML Living Standard §8.1.7.2 (Event Loop Processing Model)  
**Primary Invariant**: $\forall s \in \text{ScrollNodes},\ \text{commit}(s) \implies \text{compositor\_scroll\_offset}(s) = \text{main\_thread\_scroll\_offset}(s)$

---

## 1. Exact Normative Specification Requirements

The synchronization of scroll offsets between the Blink main thread and the Chromium compositor thread (`cc`) sits at the intersection of the HTML Event Loop rendering pipeline, the CSSOM View specification, and the internal Blink CompositeAfterPaint (CAP) / Scroll Unification architecture.

### 1.1 HTML Living Standard §8.1.7.2 (Update the Rendering)
In the WHATWG HTML Living Standard, step 14 of the Event Loop processing model ("Update the rendering") mandates a deterministic sequence of operations before a frame is presented to the display compositor:
1. Run the resize steps, scroll steps, and media query steps.
2. Run CSS animations and send events.
3. Run the fullscreen steps.
4. Run the animation frame callbacks (`requestAnimationFrame`).
5. **Update the layout and rendering** of all `Document` objects, flushing pending style and layout dirty bits.

During this phase, JavaScript execution (including WebAssembly modules invoked via JS bindings, `AnimationWorklet` stateful mutators, and `ScrollTimeline` evaluations) can programmatically mutate scroll offsets via `Element.prototype.scrollTo`, `window.scrollBy`, or `Element.prototype.scrollTop`.

### 1.2 CSSOM View Module §6 (Scrolling)
The W3C CSSOM View specification requires that programmatic scroll mutations take effect either immediately (when `scroll-behavior: auto`) or initiate an asynchronous smooth scroll transition (`scroll-behavior: smooth`). When a synchronous programmatic scroll occurs on the main thread:
* The layout box's `ScrollableArea` updates its internal offset representation.
* Any subsequent layout queries within the same turn of the event loop must observe the newly clamped scroll offset.
* Upon committing the frame to the compositor, the visual viewport and all composited sub-scrollers must reflect the exact main-thread scroll state, reconciled with any concurrent compositor-thread user input deltas ($cc \to \text{main}$ deltas).

### 1.3 Blink Scrolling Architecture §2 (Scroll Unification & Property Trees)
Under Blink's **Scroll Unification** and **CompositeAfterPaint (CAP)** architecture:
1. **Property Tree Authority**: The compositor thread (`cc::LayerTreeHostImpl`) is the authoritative source of truth for gesture-driven scrolling, while the main thread (`blink::LocalFrameView`, `blink::PaintLayerScrollableArea`) is the authoritative source for layout geometry (scroll bounds, container bounds) and programmatic scroll mutations (`scrollTo`).
2. **Delta Reconciliation Equation**: During `BeginMainFrame`, the compositor sends a `CompositorCommitData` packet containing `scroll_deltas` ($\Delta_{cc}$) accumulated on the active tree since the last commit. The main thread applies $\Delta_{cc}$ to its current base offset $O_{\text{base}}$. If main-thread JavaScript subsequently executes a programmatic scroll to $O_{\text{prog}}$, it overrides the accumulated offset and sets a `clobber_active_value` flag on the `cc::ScrollNode` / `cc::TransformNode`.
3. **Commit Synchronization**: At the end of the `DocumentLifecycle::kPaintClean` phase, `ScrollingCoordinator` and `PaintArtifactCompositor` push updated scroll offsets to the pending `cc::PropertyTrees` (`cc::ScrollTree` and `cc::TransformTree`). When `LayerTreeHost::Commit` completes, the compositor's synced property value (`cc::SyncedScrollOffset`) resolves the main-thread offset and active tree delta such that, in the absence of concurrent untracked active-tree mutations during commit or when clobbered, the effective compositor offset equals the committed main-thread offset.

---

## 2. Blink Implementation Details and Invariants

In Chromium's codebase (`third_party/blink/renderer/core/page/scrolling/scrolling_coordinator.cc` and its post-CAP successors `paint_property_tree_builder.cc` and `paint_artifact_compositor.cc`), scroll synchronization is governed by strict lifecycle invariants.

### 2.1 Lifecycle & Execution Pipeline in `scrolling_coordinator.cc`

```cpp
// Conceptual structure reflecting third_party/blink/renderer/core/page/scrolling/scrolling_coordinator.cc
// and cc/trees/property_tree.cc synchronization mechanics.

void ScrollingCoordinator::UpdateAfterPaint(LocalFrameView* frame_view) {
  DCHECK_EQ(frame_view->GetFrame().GetDocument()->Lifecycle().GetState(),
            DocumentLifecycle::kPaintClean);
  
  // Iterate over all scrollable areas or dirty scroll paint property nodes.
  for (PaintLayerScrollableArea* area : frame_view->ScrollableAreas()) {
    if (!area->ScrollsOverflow())
      continue;
      
    // Extract the clamped main-thread scroll offset.
    gfx::PointF main_offset = area->ScrollPosition();
    
    // Push to cc::ScrollTree / cc::TransformTree via PaintArtifactCompositor
    UpdateCompositorScrollOffset(area->GetScrollElementId(), main_offset,
                                 area->WasProgrammaticallyScrolled());
  }
}
```

### 2.2 Core Implementation Invariants

1. **Lifecycle Phase Invariant (`kPaintClean` Precondition)**:
   `ScrollingCoordinator` methods that write to `cc` data structures assert `DocumentLifecycle::GetState() >= DocumentLifecycle::kCompositingInputsClean` or `kPaintClean`. No JavaScript, WebAssembly, or Layout mutation can occur between `UpdateAfterPaint` and the `cc::LayerTreeHost` commit barrier.
2. **Scroll Bounds Clamping Invariant**:
   For any `ScrollableArea`, let $C \in \mathbb{Z}_{\ge 0}$ be the container dimension and $S \in \mathbb{Z}_{\ge 0}$ be the scroll contents dimension. The maximum scroll offset is $M = \max(0, S - C)$. Every main-thread offset $O_{\text{main}}$ is strictly clamped to $[0, M]$ prior to property tree generation:
   $$0 \le O_{\text{main}} \le \max(0, S - C)$$
3. **`cc::SyncedProperty` Resolution Invariant**:
   In `cc/base/synced_property.h`, the compositor tracks scroll offsets using a 3-tuple $(O_{\text{base}}, \Delta_{\text{main}}, \Delta_{\text{active}})$ and a boolean `clobber_active_value`:
   * During `BeginMainFrame`, $\Delta_{\text{reflected}} = \Delta_{\text{active}}$ is sent to main. Main updates its internal offset to $O_{\text{main}} = \text{clamp}(O_{\text{base}} + \Delta_{\text{reflected}}, 0, M)$.
   * If JS/Wasm executes a programmatic scroll $O_{\text{prog}}$, main sets $O_{\text{main}} = \text{clamp}(O_{\text{prog}}, 0, M)$ and sets `clobber_active_value = true`.
   * During `Commit` (which blocks the compositor thread in single-commit/synchronous commit semantics or pushes to the pending tree), `PushMainToPending` updates $O_{\text{base}} \leftarrow O_{\text{main}}$, clears $\Delta_{\text{reflected}}$, and if `clobber_active_value` is true (or when $\Delta_{\text{active}}$ since `BeginMainFrame` is $0$), sets $\Delta_{\text{active}} \leftarrow 0$.
   * Consequently, immediately after commit activation, the effective compositor offset $O_{cc} = O_{\text{base}} + \Delta_{\text{active}}$ satisfies:
     $$O_{cc} = O_{\text{main}}$$

---

## 3. Formal Specification in Rocq / Coq

Below is the complete, self-contained formalization of the `ScrollingCoordinator` synchronization state machine in Rocq (Coq). It models the document lifecycle states, scroll geometry clamping, `cc::SyncedScrollOffset` delta reconciliation, programmatic clobbering, and the commit barrier.

### 3.1 Verification Environment and Imports

```coq
(** * BlinkScrollingCoordinatorSyncSemantics.v
    Formal verification of Chromium Blink's ScrollingCoordinator
    main-thread to compositor scroll offset synchronization. *)

From Coq Require Import ZArith.
From Coq Require Import Bool.
From Coq Require Import List.
From Coq Require Import Lia.
Import ListNotations.

Open Scope Z_scope.
```

### 3.2 Data Types and Architectural State Definitions

```coq
(** ** 1. Document Lifecycle States
    Models blink::DocumentLifecycle::LifecycleState *)
Inductive LifecycleState : Type :=
  | kVisualUpdatePending
  | kInStyleRecalc
  | kStyleClean
  | kInLayout
  | kLayoutClean
  | kInPrePaint
  | kPrePaintClean
  | kInPaint
  | kPaintClean
  | kCommitComplete.

(** Boolean equality for LifecycleState *)
Definition lifecycle_eqb (s1 s2 : LifecycleState) : bool :=
  match s1, s2 with
  | kVisualUpdatePending, kVisualUpdatePending => true
  | kInStyleRecalc, kInStyleRecalc => true
  | kStyleClean, kStyleClean => true
  | kInLayout, kInLayout => true
  | kLayoutClean, kLayoutClean => true
  | kInPrePaint, kInPrePaint => true
  | kPrePaintClean, kPrePaintClean => true
  | kInPaint, kInPaint => true
  | kPaintClean, kPaintClean => true
  | kCommitComplete, kCommitComplete => true
  | _, _ => false
  end.

(** ** 2. Scroll Geometry and Clamping
    Models blink::ScrollableArea::MaximumScrollOffset and ClampScrollOffset *)
Record ScrollGeometry : Type := mkGeometry {
  container_size : Z;
  contents_size  : Z;
}.

Definition max_scroll_offset (g : ScrollGeometry) : Z :=
  Z.max 0 (contents_size g - container_size g).

Definition clamp_offset (g : ScrollGeometry) (offset : Z) : Z :=
  Z.min (Z.max 0 offset) (max_scroll_offset g).

(** Predicate stating an offset is valid within a given geometry *)
Definition valid_offset (g : ScrollGeometry) (offset : Z) : Prop :=
  0 <= offset /\ offset <= max_scroll_offset g.

(** ** 3. Main-Thread ScrollableArea State
    Models blink::PaintLayerScrollableArea & ScrollPaintPropertyNode *)
Record MainScrollNode : Type := mkMainNode {
  node_id          : nat;
  geometry         : ScrollGeometry;
  main_offset      : Z;
  clobber_active   : bool; (* True if programmatic scroll occurred this frame *)
  dirty_for_commit : bool; (* True if main offset or geometry mutated *)
}.

(** ** 4. Compositor SyncedScrollOffset State
    Models cc::SyncedProperty<cc::AdditionGroup<gfx::PointF>> in cc::ScrollTree *)
Record CompositorScrollNode : Type := mkCompNode {
  comp_node_id   : nat;
  base_offset    : Z; (* Last committed main-thread offset *)
  reflected_delta: Z; (* Delta sent to main thread during BeginMainFrame *)
  unreported_delta: Z;(* Concurrent active-tree delta accrued during main frame *)
}.

(** The effective scroll offset rendered by the compositor (CurrentOffset) *)
Definition compositor_effective_offset (c : CompositorScrollNode) : Z :=
  base_offset c + reflected_delta c + unreported_delta c.

(** ** 5. Unified ScrollingCoordinator & Pipeline State *)
Record ScrollSyncState : Type := mkSyncState {
  lifecycle : LifecycleState;
  main_node : MainScrollNode;
  comp_node : CompositorScrollNode;
}.
```

### 3.3 State Transitions (Operational Semantics)

```coq
(** ** 6. Pipeline Transitions *)

(** Step 1: BeginMainFrame (cc -> Blink)
    Compositor packages active deltas as reflected_delta and sends to main.
    Main thread applies reflected_delta and clamps to current geometry. *)
Definition begin_main_frame (st : ScrollSyncState) : ScrollSyncState :=
  let m := main_node st in
  let c := comp_node st in
  let total_cc_delta := reflected_delta c + unreported_delta c in
  let new_main_off := clamp_offset (geometry m) (main_offset m + total_cc_delta) in
  mkSyncState
    kVisualUpdatePending
    (mkMainNode
      (node_id m)
      (geometry m)
      new_main_off
      false
      (negb (Z.eqb new_main_off (main_offset m))))
    (mkCompNode
      (comp_node_id c)
      (base_offset c)
      total_cc_delta
      0).

(** Step 2: Main-Thread Layout Update
    Updates scroll geometry (e.g. DOM resize) and re-clamps main_offset. *)
Definition update_layout (new_geom : ScrollGeometry) (st : ScrollSyncState) : ScrollSyncState :=
  let m := main_node st in
  let clamped := clamp_offset new_geom (main_offset m) in
  mkSyncState
    kLayoutClean
    (mkMainNode
      (node_id m)
      new_geom
      clamped
      (clobber_active m)
      true)
    (comp_node st).

(** Step 3: Main-Thread Programmatic Scroll (JS / Wasm / Worklet scrollTo)
    Overrides main_offset, clamps to layout bounds, sets clobber_active = true. *)
Definition programmatic_scroll (target_offset : Z) (st : ScrollSyncState) : ScrollSyncState :=
  let m := main_node st in
  let clamped := clamp_offset (geometry m) target_offset in
  mkSyncState
    (lifecycle st)
    (mkMainNode
      (node_id m)
      (geometry m)
      clamped
      true
      true)
    (comp_node st).

(** Step 4: Advance to PrePaint and PaintClean *)
Definition advance_to_paint_clean (st : ScrollSyncState) : ScrollSyncState :=
  mkSyncState
    kPaintClean
    (main_node st)
    (comp_node st).

(** Step 5: ScrollingCoordinator::UpdateAfterPaint & LayerTreeHost::Commit
    Requires lifecycle == kPaintClean.
    Pushes main_offset to comp_node.base_offset, clears reflected_delta.
    If clobber_active is true, zeroes out any unreported_delta. *)
Definition scrolling_coordinator_commit (st : ScrollSyncState) : ScrollSyncState :=
  if lifecycle_eqb