# Formal Verification Report: Blink `requestAnimationFrame` Pre-Paint Execution Order

**Target Component:** `third_party/blink/renderer/core/dom/scripted_animation_controller.cc`  
**Normative Specification:** WHATWG HTML Standard §8.1.7.2 (Update the rendering)  
**Formal Theory Target:** `BlinkRequestAnimationFramePrePaintSemantics.v`  
**Core Invariant:** $\forall f \in \text{Frames}, \quad \text{step}(\text{rAF}, f) < \text{step}(\text{Style}, f) < \text{step}(\text{Layout}, f) < \text{step}(\text{Paint}, f)$

---

## 1. Normative Specification Analysis (WHATWG HTML Standard §8.1)

In the WHATWG HTML Standard, the event loop processing model (§8.1.7.2) strictly governs when `requestAnimationFrame` callbacks are executed relative to the rendering pipeline. Within a single turn of the event loop, if a browsing context is deemed to have a rendering opportunity, the user agent executes the **"Update the rendering"** sub-algorithm:

1. **Timestamp Generation (Step 8):** Let `now` be the current high-resolution time for each fully active `Document` in `docs`.
2. **Animation Frame Callbacks (Step 13):** For each fully active `Document` in `docs`, run the animation frame callbacks for that `Document`, passing in `now` as the timestamp.
   * *Note:* The specification mandates snapshot semantics. Only callbacks registered prior to entering the callback invocation loop execute in the current frame; callbacks queued *during* the execution of a callback are deferred to the subsequent frame ($f + 1$).
3. **Style, Layout, and Paint (Step 15):** "For each fully active `Document` in `docs`, update the rendering or user interface of that `Document` and its browsing context to reflect the current state."
   * By reference to the CSSOM View, CSS Cascade, and CSS Display specifications, "updating the rendering" requires resolving computed styles, computing box geometry (Layout), and generating display lists for rasterization/compositing (Paint/PrePaint).

### Architectural Consequence
Because `requestAnimationFrame` (Step 13) strictly precedes the UI/Rendering update (Step 15), mutations to the DOM or CSSOM performed inside an animation frame callback are guaranteed to be absorbed into the same frame's Style Recalculation, Layout, and Paint phases without inducing intra-frame layout thrashing or visual tearing (assuming the callback itself does not synchronously query layout properties before mutating styles).

---

## 2. Chromium Blink Implementation & Invariants

In Chromium's Blink rendering engine, the main thread rendering pipeline is orchestrated by the compositor (`cc::ProxyMain::BeginMainFrame`) calling into `WebFrameWidgetImpl::BeginMainFrame` and subsequently `PageAnimator::ServiceScriptedAnimations` and `LocalFrameView::UpdateLifecyclePhases`.

### 2.1 `ScriptedAnimationController` Mechanics
The file `third_party/blink/renderer/core/dom/scripted_animation_controller.cc` implements the per-Document queue for `requestAnimationFrame` callbacks:

```cpp
void ScriptedAnimationController::ServiceScriptedAnimations(
    base::TimeTicks monotonic_time_now) {
  if (! ExecutionContext() || ExecutionContext()->IsContextDestroyed())
    return;
  
  // 1. Snapshot the current callback queue to prevent infinite loops
  //    when callbacks re-register themselves via requestAnimationFrame().
  callback_collection_.ExecuteFrameCallbacks(monotonic_time_now,
                                             legacy_high_res_now_ms);
}
```

Inside `FrameRequestCallbackCollection::ExecuteFrameCallbacks`:
1. The active `callbacks_` vector is swapped or copied into a local `callbacks_to_invoke_` list.
2. Any call to `window.requestAnimationFrame()` during this execution appends to `callbacks_`, which is now isolated for frame $f + 1$.
3. After each callback invocation, a V8 microtask checkpoint (`Microtask::PerformCheckpoint`) is executed.

### 2.2 The Grand Unified Lifecycle Pipeline (`DocumentLifecycle`)
The overarching frame coordinator in `WebFrameWidgetImpl` executes the following exact sequence during `BeginMainFrame`:

1. **`PageAnimator::ServiceScriptedAnimations`**: Dispatches to `ScriptedAnimationController::ServiceScriptedAnimations`. At this point, the `DocumentLifecycle::LifecycleState` is typically `kVisualUpdatePending` (or `kStyleClean` / `kLayoutClean` from the prior frame, which drops to `kVisualUpdatePending` as soon as the rAF callback mutates DOM/Style).
2. **`WebFrameWidgetImpl::UpdateLifecycle(WebLifecycleUpdate::kAll, ...)`**: Transitions the `DocumentLifecycle` state machine through its strictly ordered monotonic phases via `LocalFrameView::UpdateLifecyclePhasesInternal`:
   * **`UpdateStyleAndLayoutTree()`**: Transitions state through `kInStyleRecalc` $\to$ `kStyleClean`.
   * **`UpdateStyleAndLayout()`**: Transitions state through `kInPerformLayout` $\to$ `kLayoutClean`.
   * **`RunCompositingInputsLifecyclePhase()` / `RunPrePaintLifecyclePhase()`**: Transitions state to `kPrePaintClean`.
   * **`RunPaintLifecyclePhase()`**: Generates `cc::DisplayItemList` artifacts and transitions state to `kPaintClean`.

### 2.3 State Machine Invariant
Blink enforces this ordering at runtime via `DCHECK` assertions in `document_lifecycle.cc` (`DocumentLifecycle::CanAdvanceTo`). A transition backwards within the rendering update phase is prohibited unless triggered by script execution (which is legally bounded to happen *before* `UpdateLifecyclePhases` begins, except for synchronous `ResizeObserver` loops which precede Paint).

---

## 3. Formal Specification in Rocq / Coq

Below is the complete, self-contained formalization of Blink's pre-paint execution pipeline (`BlinkRequestAnimationFramePrePaintSemantics.v`). It models the `ScriptedAnimationController` snapshot queue, the `DocumentLifecycle` state machine, discrete time-step execution traces, and proves the strict chronological ordering property:
$$\text{raf\_step} < \text{style\_recalc\_step} < \text{layout\_step} < \text{paint\_step}$$

```coq
(** * BlinkRequestAnimationFramePrePaintSemantics.v
    Formal verification of Chromium Blink's requestAnimationFrame (rAF)
    execution order relative to the DocumentLifecycle rendering pipeline.
    
    Target: third_party/blink/renderer/core/dom/scripted_animation_controller.cc
    Specification: WHATWG HTML Standard §8.1.7.2 (Update the rendering)
*)

From Coq Require Import ZArith.
From Coq Require Import Lia.
From Coq Require Import Bool.
From Coq Require Import List.
Import ListNotations.

Open Scope Z_scope.

(** ** 1. Pipeline Stage Definitions *)

(** Represents the discrete stages of a single BeginMainFrame execution turn
    in Blink's main thread pipeline. *)
Inductive PipelineStage : Type :=
  | Stage_Idle            (* Frame awaiting BeginMainFrame *)
  | Stage_rAF             (* ScriptedAnimationController::ServiceScriptedAnimations *)
  | Stage_StyleRecalc     (* Document::UpdateStyleAndLayoutTree *)
  | Stage_Layout          (* LocalFrameView::UpdateLayout *)
  | Stage_PrePaint        (* PrePaintTreeWalk::Walk *)
  | Stage_Paint           (* LocalFrameView::PaintTree *)
  | Stage_Commit.         (* LayerTreeHost::CommitComplete *)

(** Maps each pipeline stage to its canonical chronological ordinal within a frame. *)
Definition stage_rank (s : PipelineStage) : Z :=
  match s with
  | Stage_Idle        => 0
  | Stage_rAF         => 1
  | Stage_StyleRecalc => 2
  | Stage_Layout      => 3
  | Stage_PrePaint    => 4
  | Stage_Paint       => 5
  | Stage_Commit      => 6
  end.

(** Decidable equality for PipelineStage. *)
Definition stage_eqb (s1 s2 : PipelineStage) : bool :=
  Z.eqb (stage_rank s1) (stage_rank s2).

Lemma stage_eqb_eq : forall s1 s2,
  stage_eqb s1 s2 = true <-> s1 = s2.
Proof.
  intros s1 s2; unfold stage_eqb; split; intro H.
  - apply Z.eqb_eq in H.
    destruct s1, s2; simpl in H; try reflexivity; discriminate.
  - subst; apply Z.eqb_refl.
Qed.

(** ** 2. ScriptedAnimationController State & Snapshot Semantics *)

(** A callback identifier coupled with the DOM/Style dirtying effect it produces. *)
Record rAFCallback : Type := mkCallback {
  cb_id : Z;
  cb_mutates_style : bool;
  cb_spawns_next_raf : bool
}.

(** Models FrameRequestCallbackCollection inside ScriptedAnimationController. *)
Record ControllerState : Type := mkController {
  pending_callbacks : list rAFCallback;    (* callbacks_ registered for next service *)
  executing_snapshot : list rAFCallback;   (* callbacks_to_invoke_ active in current frame *)
  next_cb_id : Z
}.

(** Models the DocumentLifecycle and dirty bits of blink::Document. *)
Record DocumentState : Type := mkDocument {
  frame_index : Z;
  current_stage : PipelineStage;
  step_counter : Z;
  style_dirty : bool;
  layout_dirty : bool;
  paint_dirty : bool;
  controller : ControllerState
}.

(** Snapshot operation: moves pending_callbacks into executing_snapshot,
    clearing pending_callbacks so newly registered callbacks wait for the next frame. *)
Definition snapshot_callbacks (c : ControllerState) : ControllerState :=
  mkController [] (pending_callbacks c) (next_cb_id c).

(** Executes a single rAF callback from the snapshot. If it spawns a follow-up rAF,
    that callback is appended to pending_callbacks (for frame + 1). *)
Definition execute_one_callback (cb : rAFCallback) (doc : DocumentState) : DocumentState :=
  let c := controller doc in
  let new_pending :=
    if cb_spawns_next_raf cb then
      pending_callbacks c ++ [mkCallback (next_cb_id c) (cb_mutates_style cb) false]
    else
      pending_callbacks c
  in
  let new_id := if cb_spawns_next_raf cb then (next_cb_id c) + 1 else next_cb_id c in
  let new_ctrl := mkController new_pending ( List.tl (executing_snapshot c) ) new_id in
  let dirty := orb (style_dirty doc) (cb_mutates_style cb) in
  mkDocument
    (frame_index doc)
    Stage_rAF
    (step_counter doc + 1)
    dirty
    (orb (layout_dirty doc) dirty)
    (orb (paint_dirty doc) dirty)
    new_ctrl.

(** Recursively drains the snapshotted callback queue. *)
Fixpoint drain_snapshot (cbs : list rAFCallback) (doc : DocumentState) : DocumentState :=
  match cbs with
  | [] => doc
  | cb :: rest => drain_snapshot rest (execute_one_callback cb doc)
  end.

(** ** 3. Lifecycle Transitions (BeginMainFrame Step Function) *)

(** Transition 1: Idle -> rAF (ServiceScriptedAnimations) *)
Definition transition_to_raf (doc : DocumentState) : DocumentState :=
  let snap_ctrl := snapshot_callbacks (controller doc) in
  let doc_init := mkDocument
                    (frame_index doc)
                    Stage_rAF
                    (step_counter doc + 1)
                    (style_dirty doc)
                    (layout_dirty doc)
                    (paint_dirty doc)
                    snap_ctrl in
  drain_snapshot (executing_snapshot snap_ctrl) doc_init.

(** Transition 2: rAF -> StyleRecalc (UpdateStyleAndLayoutTree) *)
Definition transition_to_style (doc : DocumentState) : DocumentState :=
  mkDocument
    (frame_index doc)
    Stage_StyleRecalc
    (step_counter doc + 1)
    false (* Style is now clean *)
    (orb (layout_dirty doc) (style_dirty doc))
    (orb (paint_dirty doc) (style_dirty doc))
    (controller doc).

(** Transition 3: StyleRecalc -> Layout (UpdateLayout) *)
Definition transition_to_layout (doc : DocumentState) : DocumentState :=
  mkDocument
    (frame_index doc)
    Stage_Layout
    (step_counter doc + 1)
    (style_dirty doc)
    false (* Layout is now clean *)
    (orb (paint_dirty doc) (layout_dirty doc))
    (controller doc).

(** Transition 4: Layout -> PrePaint (RunPrePaintLifecyclePhase) *)
Definition transition_to_prepaint (doc : DocumentState) : DocumentState :=
  mkDocument
    (frame_index doc)
    Stage_PrePaint
    (step_counter doc + 1)
    (style_dirty doc)
    (layout_dirty doc)
    (paint_dirty doc)
    (controller doc).

(** Transition 5: PrePaint -> Paint (RunPaintLifecyclePhase) *)
Definition transition_to_paint (doc : DocumentState) : DocumentState :=
  mkDocument
    (frame_index doc)
    Stage_Paint
    (step_counter doc + 1)
    (style_dirty doc)
    (layout_dirty doc)
    false (* Paint is now clean *)
    (controller doc).

(** Transition 6: Paint -> Commit *)
Definition transition_to_commit (doc : DocumentState) : DocumentState :=
  mkDocument
    (frame_index doc)
    Stage_Commit
    (step_counter doc + 1)
    (style_dirty doc)
    (layout_dirty doc)
    (paint_dirty doc)
    (controller doc).

(** ** 4. Frame Execution Trace Record *)

(** Captures the exact step counter timestamps at each critical pipeline stage
    during the execution of a single frame. *)
Record FrameTrace : Type := mkFrameTrace {
  initial_doc       : DocumentState;
  after_raf_doc     : DocumentState;
  after_style_doc   : DocumentState;
  after_layout_doc  : DocumentState;
  after_prepaint_doc: DocumentState;
  after_paint_doc   : DocumentState;
  after_commit_doc  : DocumentState;

  raf_entry_step    : Z;
  raf_exit_step     : Z;
  style_recalc_step : Z;
  layout_step       : Z;
  prepaint_step     : Z;
  paint_step        : Z
}.

(** Executes a complete BeginMainFrame lifecycle turn and records the trace. *)
Definition run_begin_main_frame (doc : DocumentState) : FrameTrace :=
  let d_raf      := transition_to_raf doc in
  let d_style    := transition_to_style d_raf in
  