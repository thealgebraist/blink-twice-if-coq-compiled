# Formal Verification Report: `performance.now()` Monotonic Progression in Chromium Blink

**Formal Theory Target**: `BlinkPerformanceNowMonotonicitySemantics.v`  
**Chromium Source**: `third_party/blink/renderer/core/timing/performance.cc`  
**Specification**: W3C High Resolution Time Level 3, §4 (Monotonic Clock) & §5 (`Performance.now()`)  
**Mathematical Property**: $\forall t_1, t_2 \in \mathbb{T}, \quad t_2 \ge t_1 \implies \text{time\_now}(t_2) \ge \text{time\_now}(t_1)$

---

## 1. Normative Specification Requirements

### 1.1 W3C High Resolution Time (§4 & §5)
The W3C High Resolution Time specification defines the timing primitives that underpin scheduling, animation frames (`requestAnimationFrame`), WebAssembly execution profiling, and Audio/Paint Worklet synchronization across the Web Platform.

1. **Monotonic Clock (§4)**: 
   The specification mandates an abstract global monotonic clock alongside an environment settings object's isolated monotonic clock. The time values returned when reading the monotonic clock MUST be a sequence of `DOMHighResTimeStamp` values that are **monotonically non-decreasing** and not subject to system clock adjustments (e.g., NTP synchronization, leap seconds, or user-initiated wall-clock shifts).
   
2. **Coarsening and Side-Channel Mitigation (§4.3)**:
   To mitigate microarchitectural side-channel attacks (e.g., Spectre, meltdown, shared-cache timing attacks via `SharedArrayBuffer` and WebAssembly threads), the specification mandates an algorithm to *coarsen time*:
   - Given a raw timestamp $t$ and a cross-origin isolated capability boolean $c$:
   - If $c$ is true (`crossOriginIsolated === true`), the resolution granularity $\Delta$ is at least $5\text{ }\mu\text{s}$.
   - If $c$ is false, the resolution granularity $\Delta$ is at least $100\text{ }\mu\text{s}$.
   - Even when artificial jitter is applied on top of coarsening, the exposed timestamp sequence observed by any single execution thread/worklet MUST preserve non-decreasing monotonicity.

3. **`now()` Method (§5.2)**:
   The `now()` method must return the current relative high-resolution time from the environment settings object's `timeOrigin` to the current value of the monotonic clock, coarsened according to the execution context's cross-origin isolation capability. Formally, if call $C_1$ happens-before call $C_2$ within the same realm, `C1.return_value <= C2.return_value`.

---

## 2. Blink Implementation Details & Invariants

In Chromium's Blink rendering engine, `performance.now()` is implemented in `third_party/blink/renderer/core/timing/performance.cc` and assisted by `TimeClamper` in `third_party/blink/renderer/core/timing/time_clamper.cc`.

### 2.1 Execution Pipeline in `performance.cc`
```cpp
DOMHighResTimeStamp Performance::now() const {
  return MonotonicTimeToDOMHighResTimeStamp(tick_clock_->NowTicks());
}

DOMHighResTimeStamp Performance::MonotonicTimeToDOMHighResTimeStamp(
    base::TimeTicks time_origin,
    base::TimeTicks monotonic_time,
    bool allow_negative_value,
    bool cross_origin_isolated_capability) {
  if (monotonic_time.is_null() || time_origin.is_null())
    return 0.0;

  base::TimeDelta delta =
      ClampTimeResolution(monotonic_time, cross_origin_isolated_capability) -
      ClampTimeResolution(time_origin, cross_origin_isolated_capability);

  if (delta.is_negative() && !allow_negative_value)
    return 0.0;

  return delta.InMillisecondsF();
}
```

### 2.2 Core Engine Invariants
1. **Underlying OS Monotonicity (`base::TimeTicks`)**:
   `tick_clock_->NowTicks()` queries the platform's monotonic hardware/OS counter (`CLOCK_MONOTONIC` on POSIX/Linux/Android, `mach_absolute_time` on macOS/iOS, `QueryPerformanceCounter` on Windows). `base::TimeTicks` represents time in integer microseconds ($\mu\text{s}$) since an arbitrary platform epoch, guaranteeing $t_2 \ge t_1$ at the hardware/HAL boundary.
2. **Order-Preserving Quantization (`TimeClamper::ClampTimeResolution`)**:
   Before subtracting `time_origin`, Blink clamps both `monotonic_time` and `time_origin` independently to discrete buckets of size $\Delta \in \{5\text{ }\mu\text{s}, 100\text{ }\mu\text{s}\}$. Because clamping is implemented as a deterministic step function (using floor division and a deterministic pseudo-random per-bucket threshold that depends strictly on the bucket index), if $t_2 \ge t_1$, they either fall into the same bucket (and compare identically against the bucket's unique pseudo-random threshold) or $t_2$ falls into a strictly higher bucket.
3. **Zero-Floor Clamping (`!allow_negative_value`)**:
   For `performance.now()`, `allow_negative_value` is `false`. The function applies $\max(0, \text{clamped}(t) - \text{clamped}(t_0))$. Since $\max(0, \cdot)$ is monotonically increasing, composition with order-preserving quantization maintains non-decreasing monotonicity across the entire pipeline.

---

## 3. Formal Specification in Rocq / Coq

We construct the formal theory `BlinkPerformanceNowMonotonicitySemantics.v`. Time is modeled in discrete integer ticks (e.g., nanoseconds or microseconds in $\mathbb{Z}$), capturing `base::TimeTicks` and `base::TimeDelta` without floating-point rounding anomalies (which are order-preserving in IEEE 754 for positive range values).

### 3.1 Formal Definitions

* **`TimeTicks` ($\mathbb{Z}$)**: Represents `base::TimeTicks` internal microsecond values.
* **`Resolution` ($\mathbb{Z}$)**: The clamping granularity ($5\text{ }\mu\text{s}$ or $100\text{ }\mu\text{s}$).
* **`clamp_time` ($\mathbb{Z} \to \mathbb{Z} \to \mathbb{Z}$)**: Models `TimeClamper` quantization via Euclidean division `Z.div` and multiplication, alongside deterministic within-bucket threshold clamping.
* **`monotonic_to_dom_high_res`**: Models `Performance::MonotonicTimeToDOMHighResTimeStamp`.
* **`performance_now`**: Models `Performance::now()`.

---

## 4. Concrete Rocq / Coq Theory and Proofs

Below is the complete, self-contained, admitted-free Rocq/Coq module verifying the monotonicity invariants of Blink's `performance.now()`.

```coq
(** * BlinkPerformanceNowMonotonicitySemantics.v
    Formal verification of W3C High Resolution Time §4 and §5 in Chromium Blink:
    third_party/blink/renderer/core/timing/performance.cc *)

From Coq Require Import ZArith.
From Coq Require Import Bool.
From Coq Require Import Lia.

Open Scope Z_scope.

Section BlinkPerformanceNow.

  (** ** 1. Types and Constants *)

  (** [TimeTicks] models [base::TimeTicks] in integer microseconds. *)
  Definition TimeTicks := Z.

  (** [DOMHighResTimeStamp] models the exposed timestamp in discrete ticks. *)
  Definition DOMHighResTimeStamp := Z.

  (** Resolution constants matching Blink's [TimeClamper] in microseconds. *)
  Definition kFineResolution : Z := 5.
  Definition kCoarseResolution : Z := 100.

  (** Select resolution based on [cross_origin_isolated_capability]. *)
  Definition get_resolution (cross_origin_isolated : bool) : Z :=
    if cross_origin_isolated then kFineResolution else kCoarseResolution.

  Lemma get_resolution_pos : forall coi : bool,
    get_resolution coi > 0.
  Proof.
    intros [|]; unfold get_resolution, kFineResolution, kCoarseResolution; lia.
  Qed.

  (** ** 2. Time Clamping / Coarsening Semantics *)

  (** Abstract deterministic threshold function per bucket.
      In Blink's [TimeClamper], each bucket [b = t / res] has a deterministic
      pseudo-random offset [0 <= offset(b) < res]. If [t mod res >= offset(b)],
      the timestamp rounds up to the next bucket boundary [(b + 1) * res],
      otherwise it rounds down to [b * res]. *)
  Variable bucket_threshold : Z -> Z.
  Hypothesis bucket_threshold_bounds : forall (res b : Z),
    res > 0 -> 0 <= bucket_threshold b < res.

  (** Formal model of [TimeClamper::ClampTimeResolution] with jitter threshold. *)
  Definition clamp_time_with_jitter (t : TimeTicks) (res : Z) : TimeTicks :=
    let b := t / res in
    let rem := t mod res in
    if Z.geb rem (bucket_threshold b)
    then (b + 1) * res
    else b * res.

  (** Pure floor-based clamping (special case where threshold >= res). *)
  Definition clamp_time_floor (t : TimeTicks) (res : Z) : TimeTicks :=
    (t / res) * res.

  (** ** 3. Blink [MonotonicTimeToDOMHighResTimeStamp] and [performance.now()] *)

  (** Models [Performance::MonotonicTimeToDOMHighResTimeStamp].
      Note: Null checks are handled via option types or positive epoch invariants;
      here we model valid initialized clocks where [time_origin] and [monotonic_time]
      are active ticks. *)
  Definition monotonic_to_dom_high_res
    (time_origin : TimeTicks)
    (monotonic_time : TimeTicks)
    (allow_negative_value : bool)
    (cross_origin_isolated : bool) : DOMHighResTimeStamp :=
    let res := get_resolution cross_origin_isolated in
    let clamped_time := clamp_time_with_jitter monotonic_time res in
    let clamped_origin := clamp_time_with_jitter time_origin res in
    let delta := clamped_time - clamped_origin in
    if (delta <? 0) && negb allow_negative_value
    then 0
    else delta.

  (** Models [Performance::now()].
      In Blink, [performance.now()] invokes [MonotonicTimeToDOMHighResTimeStamp]
      with [allow_negative_value = false]. *)
  Definition performance_now
    (time_origin : TimeTicks)
    (coi : bool)
    (t : TimeTicks) : DOMHighResTimeStamp :=
    monotonic_to_dom_high_res time_origin t false coi.

  (** ** 4. Auxiliary Arithmetic Lemmas *)

  Lemma Z_div_monotone : forall t1 t2 res : Z,
    res > 0 ->
    t1 <= t2 ->
    t1 / res <= t2 / res.
  Proof.
    intros t1 t2 res Hres Hle.
    apply Z.div_le_mono; lia.
  Qed.

  Lemma Z_mod_same_bucket_monotone : forall t1 t2 res : Z,
    res > 0 ->
    t1 <= t2 ->
    t1 / res = t2 / res ->
    t1 mod res <= t2 mod res.
  Proof.
    intros t1 t2 res Hres Hle Hdiv.
    pose proof (Z.div_mod t1 res ltac:(lia)) as H1.
    pose proof (Z.div_mod t2 res ltac:(lia)) as H2.
    rewrite Hdiv in H1.
    lia.
  Qed.

  (** ** 5. Core Monotonicity Theorems *)

  (** Theorem 1: Floor clamping is monotonically non-decreasing. *)
  Theorem clamp_time_floor_monotonic : forall (t1 t2 res : Z),
    res > 0 ->
    t1 <= t2 ->
    clamp_time_floor t1 res <= clamp_time_floor t2 res.
  Proof.
    intros t1 t2 res Hres Hle.
    unfold clamp_time_floor.
    assert (Hdiv: t1 / res <= t2 / res) by (apply Z_div_monotone; lia).
    apply Z.mul_le_mono_nonneg_r; lia.
  Qed.

  (** Theorem 2: Blink's jitter-coarsened clamping [TimeClamper] is
      monotonically non-decreasing. *)
  Theorem clamp_time_with_jitter_monotonic : forall (t1 t2 res : Z),
    res > 0 ->
    t1 <= t2 ->
    clamp_time_with_jitter t1 res <= clamp_time_with_jitter t2 res.
  Proof.
    intros t1 t2 res Hres Hle.
    unfold clamp_time_with_jitter.
    assert (Hdiv: t1 / res <= t2 / res) by (apply Z_div_monotone; lia).
    destruct (Z.eq_dec (t1 / res) (t2 / res)) as [Heq | Hneq].
    - (* Case 1: t1 and t2 fall in the exact same resolution bucket *)
      assert (Hmod: t1 mod res <= t2 mod res).
      { apply Z_mod_same_bucket_monotone; assumption. }
      rewrite Heq in *.
      destruct (Z.geb (t1 mod res) (bucket_threshold (t2 / res))) eqn:E1;
      destruct (Z.geb (t2 mod res) (bucket_threshold (t2 / res))) eqn:E2.
      + lia.
      + rewrite Z.geb_le in E1.
        assert (Hlt: (t2 mod res >=? bucket_threshold (t2 / res)) = true).
        { apply Z.geb_le. lia. }
        congruence.
      + apply Z.mul_le_mono_nonneg_r; lia.
      + lia.
    - (* Case 2: t2 falls in a strictly greater resolution bucket than t1 *)
      assert (Hstrict: t1 / res + 1 <= t2 / res) by lia.
      destruct (Z.geb (t1 mod res) (bucket_threshold (t1 / res)));
      destruct (Z.geb (t2 mod res) (bucket_threshold (t2 / res)));
      apply Z.mul_le_mono_nonneg_r; lia.
  Qed.

  (** Theorem 3: [MonotonicTimeToDOMHighResTimeStamp] preserves monotonicity
      for any configuration of [allow_negative_value] and [cross_origin_isolated]. *)
  Theorem monotonic_to_dom_high_res_monotonic :
    forall (time_origin t1 t