# Formal Verification Report: Blink Background Tab Timer Minimum Interval Clamping

## 1. Normative Specification Analysis

### 1.1 WHATWG HTML Standard §8.6 (Timers)
According to the WHATWG HTML Standard §8.6 (*Timers*), specifically within the ** timer initialization steps** executed by `setTimeout()` and `setInterval()`:

1. **Step 8**: Let $timeout$ be the second method argument, or 0 if omitted, converted to an IDL `long`. If $timeout < 0$, then set $timeout$ to 0.
2. **Step 9**: If the currently running task is a task that was created by this algorithm, then let $nesting\_level$ be the task's timer nesting level. Otherwise, let $nesting\_level$ be 0.
3. **Step 10**: If $nesting\_level > 5$, and $timeout < 4$, then set $timeout$ to 4.
4. **Step 11 (Implementation-Defined Throttling)**: *"Optionally, wait a further implementation-defined length of time."* 
   - Note: The specification explicitly adds normative guidance stating that user agents are encouraged to throttle timers in background pages, hidden `iframe`s, or out-of-view elements to conserve battery and CPU resources.

### 1.2 Page Visibility API Integration
The normative trigger for background throttling is governed by the Document's **visibility state** (HTML Standard §7.5 / Page Visibility Level 2):
- When a top-level browsing context's active document has its visibility state transition to `"hidden"` (i.e., `Page::IsPageVisible() == false`), the user agent engages background timer throttling.
- The canonical de-facto standard across Chromium (Blink), Gecko, and WebKit for standard unaligned background throttling is a minimum clamping floor of **1000 milliseconds (1 Hz)**.

---

## 2. Blink Implementation & Architectural Invariants

### 2.1 Source Analysis: `third_party/blink/renderer/core/frame/dom_timer.cc`
In Chromium's Blink rendering engine, `DOMTimer` manages standard JavaScript scheduled timers (`setTimeout` and `setInterval`). The interaction between `DOMTimer` and the Blink Scheduler (`FrameSchedulerImpl` and `DOMTimerCoordinator`) enforces a strict multi-tiered clamping pipeline:

```cpp
// Conceptual representation of third_party/blink/renderer/core/frame/dom_timer.cc
// and scheduler/main_thread/frame_scheduler_impl.cc integration.

constexpr base::TimeDelta kMaxHighResolutionTimerNestingLevel = 5;
constexpr base::TimeDelta kMinimumInterval = base::Milliseconds(4);
constexpr base::TimeDelta kBackgroundThrottlingMinimumInterval = base::Milliseconds(1000);

base::TimeDelta DOMTimer::CalculateEffectiveInterval(
    base::TimeDelta requested_interval,
    int nesting_level,
    bool is_page_visible) {
  // 1. Non-negativity enforcement
  base::TimeDelta interval = std::max(base::TimeDelta(), requested_interval);

  // 2. HTML Standard §8.6 Step 10: Nesting level > 5 clamps to 4ms
  if (nesting_level > kMaxHighResolutionTimerNestingLevel &&
      interval < kMinimumInterval) {
    interval = kMinimumInterval;
  }

  // 3. Background Page Throttling (1000ms minimum clamp)
  // Enforced via DOMTimer / WebFrameScheduler when page visibility is hidden.
  if (!is_page_visible) {
    interval = std::max(interval, kBackgroundThrottlingMinimumInterval);
  }

  return interval;
}
```

### 2.2 Engine Pipeline & Worklet/WebAssembly Interactions
1. **Main Thread ExecutionContext (`LocalDOMWindow`)**: `DOMTimer` instances are bound to the `ExecutionContext` of the frame. When `Page::SetVisibilityState` dispatches a visibility change to `mojom::blink::PageVisibilityState::kHidden`, the `FrameSchedulerImpl` updates the `TaskQueue` throttling configuration.
2. **WebAssembly Concurrency**: When WebAssembly modules execute on the main thread and yield to the JS event loop via `setTimeout` (e.g., Emscripten's `emscripten_set_main_loop`), background clamping directly limits the Wasm tick rate to 1 Hz.
3. **Worklets (`AudioWorklet`, `PaintWorklet`, `AnimationWorklet`)**: Worklets operate on specialized `WorkletGlobalScope` contexts and do *not* expose `DOMTimer` (`setTimeout`/`setInterval` are excluded from `WorkletGlobalScope` IDL). However, main-thread coordinators communicating with worklets via `MessagePort` or `postMessage` triggered by `DOMTimer` are strictly bounded by this 1000ms invariant when the host document is backgrounded.

### 2.3 Formal Invariants
Let $I_{\text{req}} \in \mathbb{Z}_{\ge 0}$ be the non-negative requested timeout (in milliseconds), $N \in \mathbb{N}$ be the timer nesting level, and $V \in \{\mathsf{Visible}, \mathsf{Hidden}\}$ be the page visibility state.

The effective interval $I_{\text{eff}}$ satisfies:
1. **Foreground Base Clamping**:
   $$I_{\text{fg}}(I_{\text{req}}, N) = \begin{cases} \max(I_{\text{req}}, 4) & \text{if } N > 5 \\ \max(I_{\text{req}}, 0) & \text{otherwise} \end{cases}$$
2. **Background Clamping dominance**:
   $$V = \mathsf{Hidden} \implies I_{\text{eff}}(I_{\text{req}}, N, \mathsf{Hidden}) = \max(I_{\text{fg}}(I_{\text{req}}, N), 1000)$$
3. **Subsumption Invariant**: Because $1000 \ge 4 \ge 0$, for any non-negative $I_{\text{req}} \ge 0$ and any nesting level $N$, the background clamping dominates the nesting clamp:
   $$I_{\text{req}} \ge 0 \implies \max(I_{\text{fg}}(I_{\text{req}}, N), 1000) = \max(I_{\text{req}}, 1000)$$

---

## 3. Formal Specification in Rocq/Coq (`BlinkTimerBackgroundThrottlingSemantics.v`)

Below is the complete, self-contained, and admitted-free Rocq/Coq formalization of `BlinkTimerBackgroundThrottlingSemantics.v`.

```coq
(** * BlinkTimerBackgroundThrottlingSemantics.v
    Formalization of Chromium Blink's DOMTimer Background Minimum Interval Clamping
    Source: third_party/blink/renderer/core/frame/dom_timer.cc
    Specification: WHATWG HTML Standard §8.6 (Timers)
*)

From Coq Require Import ZArith.
From Coq Require Import Bool.
From Coq Require Import Lia.

Open Scope Z_scope.

(** ** 1. Architectural Types and Constants *)

Inductive PageVisibilityState : Type :=
  | PageVisible : PageVisibilityState
  | PageHidden  : PageVisibilityState.

Definition is_background (v : PageVisibilityState) : bool :=
  match v with
  | PageVisible => false
  | PageHidden  => true
  end.

(** Normative and Blink Constants (in milliseconds) *)
Definition kZeroInterval : Z := 0.
Definition kMinNestingInterval : Z := 4.
Definition kMaxTimerNestingLevel : Z := 5.
Definition kBackgroundMinInterval : Z := 1000.

(** Timer Configuration Record representing DOMTimer state at creation *)
Record TimerRequest : Type := mkTimerRequest {
  req_interval  : Z;
  nesting_level : Z;
  visibility    : PageVisibilityState
}.

(** ** 2. Blink DOMTimer Clamping Pipeline Semantics *)

(** Step 8: Clamp negative intervals to 0ms *)
Definition sanitize_interval (t : Z) : Z :=
  Z.max t kZeroInterval.

(** Step 10: Nesting level > 5 clamps minimum interval to 4ms *)
Definition apply_nesting_clamp (t : Z) (nesting : Z) : Z :=
  let t0 := sanitize_interval t in
  if Z.gtb nesting kMaxTimerNestingLevel then
    Z.max t0 kMinNestingInterval
  else
    t0.

(** Step 11 / Blink Background Throttling:
    When page is in background (PageHidden), clamp minimum interval to 1000ms. *)
Definition apply_background_clamp (t : Z) (vis : PageVisibilityState) : Z :=
  match vis with
  | PageVisible => t
  | PageHidden  => Z.max t kBackgroundMinInterval
  end.

(** Full DOMTimer Effective Interval Calculation *)
Definition compute_effective_interval (req : TimerRequest) : Z :=
  let fg_interval := apply_nesting_clamp (req_interval req) (nesting_level req) in
  apply_background_clamp fg_interval (visibility req).

(** Direct specification predicate for the target mathematical property *)
Definition background_clamping_spec (req_int eff_int : Z) : Prop :=
  eff_int = Z.max req_int 1000.
```

---

## 4. Concrete Theorems and Complete Proofs

```coq
(** ** 3. Formal Theorems and Proofs *)

(** Lemma 1: Sanitized interval is always non-negative. *)
Lemma sanitize_interval_nonneg : forall t : Z,
  0 <= sanitize_interval t.
Proof.
  intros t.
  unfold sanitize_interval, kZeroInterval.
  lia.
Qed.

(** Lemma 2: Foreground clamped interval is always non-negative and at least t. *)
Lemma nesting_clamp_bounds : forall t n : Z,
  0 <= apply_nesting_clamp t n /\ t <= apply_nesting_clamp t n.
Proof.
  intros t n.
  unfold apply_nesting_clamp, sanitize_interval, kZeroInterval,
         kMinNestingInterval, kMaxTimerNestingLevel.
  destruct (n >? 5) eqn:Hnest; lia.
Qed.

(** Lemma 3: Foreground nesting clamp (4ms) is strictly subsumed by the
    background minimum interval (1000ms). *)
Lemma background_subsumes_nesting_clamp : forall t n : Z,
  Z.max (apply_nesting_clamp t n) kBackgroundMinInterval =
  Z.max (sanitize_interval t) kBackgroundMinInterval.
Proof.
  intros t n.
  unfold apply_nesting_clamp, sanitize_interval, kZeroInterval,
         kMinNestingInterval, kMaxTimerNestingLevel, kBackgroundMinInterval.
  destruct (n >? 5) eqn:Hnest; lia.
Qed.

(** Theorem 1 (Primary Target Property):
    For any non-negative requested interval, when the page is in the background
    (PageHidden), the effective interval is exactly max(requested_interval, 1000),
    regardless of the timer nesting level. *)
Theorem background_timer_effective_interval_exact :
  forall (req : TimerRequest),
    visibility req = PageHidden ->
    0 <= req_interval req ->
    compute_effective_interval req = Z.max (req_interval req) 1000.
Proof.
  intros req Hvis Hnonneg.
  unfold compute_effective_interval, apply_background_clamp.
  rewrite Hvis.
  rewrite background_subsumes_nesting_clamp.
  unfold sanitize_interval, kZeroInterval, kBackgroundMinInterval.
  lia.
Qed.

(** Theorem 2 (Unconditional Lower Bound in Background):
    Even if the caller passes a negative requested_interval (e.g., setTimeout(fn, -50)),
    any background timer has an effective interval of at least 1000ms. *)
Theorem background_timer_minimum_1000ms :
  forall (req : TimerRequest),
    visibility req = PageHidden ->
    1000 <= compute_effective_interval req.
Proof.
  intros req Hvis.
  unfold compute_effective_interval, apply_background_clamp.
  rewrite Hvis.
  unfold kBackgroundMinInterval.
  lia.
Qed.

(** Theorem 3 (Background Monotonicity over Visibility Transition):
    Transitioning a page from PageVisible to PageHidden never decreases the
    effective timer interval. *)
Theorem visibility_transition_monotonic :
  forall (t n : Z),
    let req_vis := mkTimerRequest t n PageVisible in
    let req_hid := mkTimerRequest t n PageHidden in
    compute_effective_interval req_vis <= compute_effective_interval req_hid.
Proof.
  intros t n req_vis req_hid.
  unfold compute_effective_interval, apply_background_clamp, req_vis, req_hid.
  simpl.
  unfold kBackgroundMinInterval.
  lia.
Qed.

(** Theorem 4 (Interval Monotonicity):
    If requested_interval_1 <= requested_interval_2, then for identical
    nesting level and visibility state, effective_interval_1 <= effective_interval_2. *)
Theorem effective_interval_monotonic_in_request :
  forall (t1 t2 n : Z) (vis : PageVisibilityState),
    t1 <= t2 ->
    compute_effective_interval (mkTimerRequest t1 n vis) <=
    compute_effective_interval (mkTimerRequest t2 n vis).
Proof.
  intros t1 t2 n vis Hle.
  unfold compute_effective_interval, apply_background_clamp,
         apply_nesting_clamp, sanitize_interval,
         kZeroInterval, kMinNestingInterval, kMaxTimerNestingLevel,
         kBackgroundMinInterval.
  simpl.
  destruct vis; destruct (n >? 5); lia.
Qed.

(** Theorem 5 (Idempotence of Background Clamping):
    Applying the background clamp to an already-computed background effective
    interval is idempotent. *)
Theorem background_clamp_idempotent :
  forall (req : TimerRequest),
    visibility req = PageHidden ->
    apply_background_clamp (compute_effective_interval req) PageHidden =
    compute_effective_interval req.
Proof.
  intros req Hvis.
  unfold compute_effective_interval, apply_background_clamp.
  rewrite Hvis.
  unfold kBackgroundMinInterval.
  lia.
Qed.

(** Theorem 6 (Exact Equivalence with Specification Predicate):
    For all valid (non-negative) timer requests in a background tab,
    the implementation satisfies background_clamping_spec. *)
Corollary blink_dom_timer_satisfies_spec :
  forall (req : TimerRequest),
    is_background (visibility req) = true ->
    0 <= req_interval req ->
    background_clamping_spec (req_interval req) (compute_effective_interval req).
Proof.
  intros req Hbg Hnonneg.
  unfold background_clamping_spec.
  destruct (visibility req) eqn:Hvis.
  -