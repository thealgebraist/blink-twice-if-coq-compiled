# Formal Verification Report: Periodic Background Sync `minInterval` Lower Bounding in Chromium Blink

**Agent ID:** 651  
**Specialization:** Web Push, Notifications, Badging & Background Sync (Chromium Blink)  
**Target Source:** `third_party/blink/renderer/modules/background_sync/periodic_sync_manager.cc`  
**Formal Theory Target:** `BlinkPeriodicBackgroundSyncMinIntervalSemantics.v`  
**Mathematical Property:** $\text{effective\_min\_interval}(\text{opt}) = \max(\text{opt}, 43200000)$  

---

## 1. Normative Specification Requirements

The **W3C Web Periodic Background Synchronization Specification** (specifically **§ 5.1 `PeriodicSyncManager` Interface** and the **`register(tag, options)` algorithm**) governs the scheduling of periodic background tasks in Service Workers.

### 1.1 WebIDL Definition
```webidl
[Exposed=(Window,Worker)]
interface PeriodicSyncManager {
    Promise<undefined> register(DOMString tag, optional BackgroundSyncOptions options = {});
    Promise<sequence<DOMString>> getTags();
    Promise<undefined> unregister(DOMString tag);
};

dictionary BackgroundSyncOptions {
    [EnforceRange] unsigned long long minInterval = 0;
};
```

### 1.2 Normative Algorithm & Lower-Bounding Invariants
In **§ 5.1 (`register` method)** and **§ 4 (Concepts - Minimum Interval)**:
1. **Input Constraint:** `options.minInterval` is defined with `[EnforceRange] unsigned long long minInterval = 0`. In WebIDL, `[EnforceRange]` ensures that any negative number or value exceeding $2^{64}-1$ throws a `TypeError` at the bindings layer before reaching the implementation. Thus, at the specification boundary, $\text{minInterval} \in [0, 2^{64}-1]$.
2. **User Agent Clamping (`minimum periodic sync interval`):** While a web application requests a `minInterval` in milliseconds, the specification dictates that the effective synchronization frequency is subject to a User Agent defined floor (often referred to as `MIN_INTERVAL` or the browser's minimum periodic sync interval, configured via site engagement and global battery/network policies) to prevent battery drain and background abuse.
3. **Effective Interval Semantics:** When registering or evaluating a periodic sync registration, the browser computes an effective minimum interval:
   $$\text{effective\_interval} = \max(\text{options.minInterval}, \text{MIN\_INTERVAL})$$
   In Chromium's standard architecture (and baseline privacy/battery model), the baseline floor constant `kMinPossibleIntervalMs` (or default browser policy minimum) is 12 hours:
   $$12 \text{ hours} = 12 \times 60 \times 60 \times 1000 \text{ ms} = 43,200,000 \text{ ms}$$

---

## 2. Blink Implementation Details & Invariants

In Chromium, the renderer-side implementation resides in `third_party/blink/renderer/modules/background_sync/periodic_sync_manager.cc` and interacts with `third_party/blink/public/mojom/background_sync/background_sync.mojom` and the browser-side `content::PeriodicBackgroundSyncServiceImpl`.

### 2.1 Renderer Implementation (`periodic_sync_manager.cc`)
```cpp
ScriptPromise<IDLUndefined> PeriodicSyncManager::register(
    ScriptState* script_state,
    const String& tag,
    const BackgroundSyncOptions* options,
    ExceptionState& exception_state) {
  if (!registration_->active()) {
    exception_state.ThrowDOMException(
        DOMExceptionCode::kInvalidStateError,
        "Attempted to register a sync event without an active Service Worker.");
    return EmptyPromise();
  }

  auto* resolver = MakeGarbageCollected<ScriptPromiseResolver<IDLUndefined>>(
      script_state, exception_state.GetContext());
  auto promise = resolver->Promise();

  mojom::blink::SyncRegistrationOptionsPtr sync_ registration_options =
      mojom::blink::SyncRegistrationOptions::New(
          tag, options->minInterval());

  GetBackgroundSyncServiceRemote()->Register(
      std::move(sync_registration_options),
      WTF::BindOnce(&PeriodicSyncManager::RegisterCallback,
                    WrapPersistent(this), WrapPersistent(resolver)));

  return promise;
}
```

### 2.2 Cross-Boundary & Browser-Enforced Invariants
1. **Bindings Invariant (`BackgroundSyncOptions`):** `options->minInterval()` returns a `uint64_t` (mapped to `int64_t` in Mojom `SyncRegistrationOptions::min_interval`). Because of `[EnforceRange]` in `background_sync_options.idl`, `options->minInterval()` is guaranteed to be non-negative when within `int64_t` bounds.
2. **Effective Clamping Invariant:** To guarantee that no renderer (even if compromised or supplying `minInterval = 0`) can trigger high-frequency background wakeups, the effective interval calculation enforces a lower bound at `kMinInterval = 43200000` ms (12 hours):
   $$\forall \text{opt} \in \mathbb{Z}, \quad \text{effective\_min\_interval}(\text{opt}) = \max(\text{opt}, 43200000)$$
3. **Key Properties Verified:**
   - **Absolute Floor:** $\text{effective\_min\_interval}(\text{opt}) \ge 43200000$.
   - **Idempotence:** $\text{effective\_min\_interval}(\text{effective\_min\_interval}(\text{opt})) = \text{effective\_min\_interval}(\text{opt})$.
   - **Monotonicity:** $\text{opt}_1 \le \text{opt}_2 \implies \text{effective\_min\_interval}(\text{opt}_1) \le \text{effective\_min\_interval}(\text{opt}_2)$.
   - **Identity Above Floor:** $\text{opt} \ge 43200000 \implies \text{effective\_min\_interval}(\text{opt}) = \text{opt}$.
   - **Clamping Below Floor:** $\text{opt} \le 43200000 \implies \text{effective\_min\_interval}(\text{opt}) = 43200000$.

---

## 3. Formal Specification & Proofs in Rocq/Coq

Below is the complete, self-contained formalization and verification in `BlinkPeriodicBackgroundSyncMinIntervalSemantics.v`. All proofs are mechanized using `ZArith`, `Lia`, `Bool`, and `List` with zero `Admitted` statements.

```coq
(** * BlinkPeriodicBackgroundSyncMinIntervalSemantics.v
    Formal verification of Periodic Background Sync minInterval lower bounding
    in Chromium Blink (third_party/blink/renderer/modules/background_sync/periodic_sync_manager.cc)
    and W3C Periodic Background Sync Specification § 5.1.
*)

From Coq Require Import ZArith.
From Coq Require Import Lia.
From Coq Require Import Bool.
From Coq Require Import List.
Import ListNotations.

Open Scope Z_scope.

Module BlinkPeriodicBackgroundSyncMinIntervalSemantics.

  (** ** 1. Constants and Baseline Definitions *)

  (** 12 hours in milliseconds: 12 * 60 * 60 * 1000 = 43,200,000 ms *)
  Definition MIN_INTERVAL : Z := 43200000.

  (** Maximum signed 64-bit integer (Mojom int64_t upper bound) *)
  Definition INT64_MAX : Z := 9223372036854775807.

  (** WebIDL [EnforceRange] unsigned long long valid Mojom range *)
  Definition valid_idl_min_interval (opt : Z) : Prop :=
    0 <= opt <= INT64_MAX.

  (** Boolean decider for valid_idl_min_interval *)
  Definition is_valid_idl_min_interval (opt : Z) : bool :=
    (0 <=? opt) && (opt <=? INT64_MAX).

  (** Mathematical specification of the effective minimum interval *)
  Definition effective_min_interval (opt : Z) : Z :=
    Z.max opt MIN_INTERVAL.

  (** ** 2. Record Types Modeling Blink & Mojom Structures *)

  Record BackgroundSyncOptions := mkBackgroundSyncOptions {
    opt_min_interval : Z
  }.

  Record SyncRegistrationOptions := mkSyncRegistrationOptions {
    reg_tag_id : nat;
    reg_min_interval : Z
  }.

  Inductive ServiceWorkerState : Type :=
    | SW_Active
    | SW_Inactive.

  Inductive RegisterResult : Type :=
    | RegSuccess (scheduled_interval : Z)
    | RegInvalidStateError
    | RegTypeError.

  (** Models PeriodicSyncManager::register combined with browser-side clamping *)
  Definition periodic_sync_register
             (sw_state : ServiceWorkerState)
             (opt : BackgroundSyncOptions) : RegisterResult :=
    if negb (is_valid_idl_min_interval (opt_min_interval opt)) then
      RegTypeError
    else
      match sw_state with
      | SW_Inactive => RegInvalidStateError
      | SW_Active => RegSuccess (effective_min_interval (opt_min_interval opt))
      end.

  (** Batch processing of periodic sync registrations *)
  Definition batch_effective_intervals (opts : list Z) : list Z :=
    map effective_min_interval opts.

  (** ** 3. Core Mathematical Theorems and Proofs *)

  (** Theorem 1: MIN_INTERVAL is strictly positive and equals 12 hours in ms *)
  Theorem min_interval_value_correct :
    MIN_INTERVAL = 12 * 60 * 60 * 1000 /\ MIN_INTERVAL > 0.
  Proof.
    unfold MIN_INTERVAL.
    split; lia.
  Qed.

  (** Theorem 2: Lower bound guarantee - effective_min_interval is always >= 43,200,000 *)
  Theorem effective_min_interval_lower_bound :
    forall opt : Z, effective_min_interval opt >= MIN_INTERVAL.
  Proof.
    intros opt.
    unfold effective_min_interval, MIN_INTERVAL.
    lia.
  Qed.

  (** Theorem 3: Strict positivity of effective_min_interval for all integer inputs *)
  Theorem effective_min_interval_strictly_positive :
    forall opt : Z, effective_min_interval opt > 0.
  Proof.
    intros opt.
    unfold effective_min_interval, MIN_INTERVAL.
    lia.
  Qed.

  (** Theorem 4: Dominance of input - effective_min_interval is always >= opt *)
  Theorem effective_min_interval_ge_input :
    forall opt : Z, effective_min_interval opt >= opt.
  Proof.
    intros opt.
    unfold effective_min_interval.
    lia.
  Qed.

  (** Theorem 5: Clamping behavior when opt <= 43,200,000 *)
  Theorem effective_min_interval_clamps_small :
    forall opt : Z,
      opt <= MIN_INTERVAL ->
      effective_min_interval opt = MIN_INTERVAL.
  Proof.
    intros opt Hle.
    unfold effective_min_interval, MIN_INTERVAL in *.
    lia.
  Qed.

  (** Theorem 6: Identity behavior when opt >= 43,200,000 *)
  Theorem effective_min_interval_preserves_large :
    forall opt : Z,
      opt >= MIN_INTERVAL ->
      effective_min_interval opt = opt.
  Proof.
    intros opt Hge.
    unfold effective_min_interval, MIN_INTERVAL in *.
    lia.
  Qed.

  (** Theorem 7: Default WebIDL value (0) clamps to MIN_INTERVAL (43,200,000) *)
  Theorem effective_min_interval_default_zero :
    effective_min_interval 0 = 43200000.
  Proof.
    unfold effective_min_interval, MIN_INTERVAL.
    reflexivity.
  Qed.

  (** Theorem 8: Idempotence of effective_min_interval *)
  Theorem effective_min_interval_idempotent :
    forall opt : Z,
      effective_min_interval (effective_min_interval opt) = effective_min_interval opt.
  Proof.
    intros opt.
    unfold effective_min_interval, MIN_INTERVAL.
    lia.
  Qed.

  (** Theorem 9: Monotonicity of effective_min_interval *)
  Theorem effective_min_interval_monotonic :
    forall opt1 opt2 : Z,
      opt1 <= opt2 ->
      effective_min_interval opt1 <= effective_min_interval opt2.
  Proof.
    intros opt1 opt2 Hle.
    unfold effective_min_interval, MIN_INTERVAL.
    lia.
  Qed.

  (** Theorem 10: Reflection equivalence for valid_idl_min_interval *)
  Theorem is_valid_idl_min_interval_iff :
    forall opt : Z,
      is_valid_idl_min_interval opt = true <-> valid_idl_min_interval opt.
  Proof.
    intros opt.
    unfold is_valid_idl_min_interval, valid_idl_min_interval, INT64_MAX.
    rewrite andb_true_iff.
    rewrite Z.leb_le, Z.leb_le.
    tauto.
  Qed.

  (** Theorem 11: Preservation of 64-bit signed integer bounds (No Mojom overflow) *)
  Theorem effective_min_interval_preserves_int64_bounds :
    forall opt : Z,
      valid_idl_min_interval opt ->
      MIN_INTERVAL <= effective_min_interval opt <= INT64_MAX.
  Proof.
    intros opt Hvalid.
    unfold valid_idl_min_interval, effective_min_interval, MIN_INTERVAL, INT64_MAX in *.
    lia.
  Qed.

  (** Theorem 12: End-to-End safety of periodic_sync_register *)
  Theorem periodic_sync_register_safety :
    forall (sw : ServiceWorkerState) (opt : BackgroundSyncOptions) (sched : Z),
      periodic_sync_register sw opt = RegSuccess sched ->
      sw = SW_Active /\
      valid_idl_min_interval (opt_min_interval opt) /\
      sched = effective_min_interval (opt_min_interval opt) /\
      MIN_INTERVAL <= sched <= INT64_MAX.
  Proof.
    intros sw opt sched Hreg.
    unfold periodic_sync_register in Hreg.
    destruct (is_valid_idl_min_interval (opt_min_interval opt