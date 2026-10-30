# Formal Verification Report: WebGPU Device Loss State Terminal Irreversibility in Chromium Blink

**Formal Theory Target:** `BlinkWebGPUDeviceLossTerminalSemantics.v`  
**Chromium Component:** `third_party/blink/renderer/modules/webgpu/gpu_device.cc`  
**W3C Specification:** WebGPU §5.1 (`GPUDevice` and Device Loss)  
**Mathematical Property:** $\text{device\_lost}(st) \iff (st = 1)$; terminal absorption $\forall st', (st = 1 \land st \to st') \implies st' = 1$.

---

## 1. Normative W3C WebGPU Specification Requirements

In the W3C WebGPU Specification (§5.1 *GPUDevice*), a `GPUDevice` encapsulates a logical connection to an underlying physical or virtual graphics adapter (`GPUAdapter`). Because GPU hardware executes asynchronously in a separate process (and physical execution domain) from the user agent’s JavaScript runtime, the underlying device can become unavailable at any point due to hardware removal, driver resets (TDR), resource exhaustion, or explicit destruction via `device.destroy()`.

### 1.1 Normative State Machine Invariants
The specification mandates strict lifecycle semantics regarding device loss:
1. **Internal State Representation:** Each `GPUDevice` maintains an internal `[[lost_promise]]` slot (exposed via `device.lost`) and a boolean/state indicator tracking whether the device is operational or lost.
2. **Irreversibility (Terminal State):** Once a `GPUDevice` enters the lost state, it **must never** transition back to an active or valid state. There is no recovery mechanism on an existing `GPUDevice` instance; applications must request a new `GPUAdapter` and `GPUDevice` to resume rendering.
3. **Promise Resolution Monotonicity:** The `[[lost_promise]]` is a single-assignment promise. Once resolved with a `GPUDeviceLostInfo` object (specifying reason `"unknown"` or `"destroyed"`), its state is permanently settled.
4. **Operational Absorbing Semantics:** Any subsequent commands, buffer mappings, texture creations, or queue submissions issued to a lost `GPUDevice` must either become no-ops or fail gracefully without re-initializing the underlying Dawn/WebGPU wire client or reviving the device state.

---

## 2. Chromium Blink Implementation Analysis

In Chromium’s multi-process architecture, WebGPU is split between the **Blink Renderer Process** (`third_party/blink/renderer/modules/webgpu/`) and the **GPU Process** (which hosts the Dawn native backend). Communication occurs over the Dawn Wire protocol serialized via Mojo IPC.

### 2.1 Architecture in `gpu_device.cc`
In `third_party/blink/renderer/modules/webgpu/gpu_device.cc` (and its header `gpu_device.h`), `GPUDevice` inherits from `ScriptWrappable`, `ExecutionContextClient`, and `DawnObject<WGPUDevice>`. The device loss lifecycle is governed by the following mechanisms:

```cpp
// Conceptual excerpt of critical state pathways in gpu_device.cc / gpu_device.h
class GPUDevice final : public ScriptWrappable,
                        public DawnObject<WGPUDevice>,
                        public ExecutionContextLifecycleObserver {
  // ...
 private:
  Member<LostProperty> lost_property_;
  bool destroyed_ = false;
  // Dawn wire client callback registrations
};
```

### 2.2 State Transition Pathways
There are three primary execution paths in `gpu_device.cc` that interact with the device loss state:

1. **Asynchronous Wire/Backend Loss (`OnDeviceLostError`):**
   When the GPU process detects a hardware reset, context loss, or Dawn wire disconnection, it invokes the registered C-callback forwarded to `GPUDevice::OnDeviceLostError(WGPUDeviceLostReason reason, const char* message)`.
   - Inside `OnDeviceLostError`, Blink checks the state of `lost_property_` (an instance of `ScriptPromiseProperty<GPUDeviceLostInfo, IDLUndefined>`).
   - If `lost_property_->GetState() == LostProperty::kPending`, it transitions the property to `kResolved` by invoking `lost_property_->Resolve(device_lost_info)`.
   - Because `ScriptPromiseProperty` enforces state machine monotonicity (`kPending` $\to$ `kResolved`), subsequent invocations of `OnDeviceLostError` are guarded and ignored.

2. **Explicit Destruction (`GPUDevice::destroy`):**
   When JavaScript calls `device.destroy(script_state)`:
   - Blink sets `destroyed_ = true;`.
   - It unmaps all active `GPUBuffer` instances tracked in `track_for_destroy_` to prevent dangling shared memory pointers.
   - It invokes `GetProcs().deviceDestroy(GetHandle())` across the Dawn wire.
   - The Dawn wire immediately synthesizes or triggers the device lost callback with `WGPUDeviceLostReason_Destroyed`, driving `lost_property_` to `kResolved`.

3. **Execution Context Destruction (`GPUDevice::ContextDestroyed`):**
   When the Blink `ExecutionContext` (e.g., `LocalDOMWindow` or `WorkerGlobalScope`) is torn down, `ContextDestroyed()` clears the callbacks and ensures the Dawn handle is released without reviving the JS-visible state.

### 2.3 Formal Abstraction of the Blink State Machine
In our formal model, we abstract the composite state of `GPUDevice` (combining `lost_property_->GetState()` and `destroyed_`) into an integer state $st \in \mathbb{Z}$:
* $st = 0$: **Active / Operational** (`lost_property_->GetState() == kPending` and valid Dawn handle).
* $st = 1$: **Lost / Terminal** (`lost_property_->GetState() == kResolved` or context/device destroyed).

All state transitions in `gpu_device.cc` are modeled as discrete actions $a \in \text{Action}$. Every action handler in `gpu_device.cc` either preserves $st = 0$ (normal API validation/execution) or transitions $st \mapsto 1$. Critically, no method in `GPUDevice` assigns `kPending` to `lost_property_` after construction, nor does any method re-bind `WGPUDevice` after `deviceDestroy`.

---

## 3. Formal Specification in Rocq (Coq)

Below is the complete, self-contained formalization of the `BlinkWebGPUDeviceLossTerminalSemantics.v` theory. It encodes the state space using `Z` (from `ZArith`) as specified by the target mathematical property `device_lost(st) = (st =? 1)`, defines the operational semantics of `gpu_device.cc`, and proves multi-step terminal irreversibility.

```coq
(**
 * Formal Theory Target: BlinkWebGPUDeviceLossTerminalSemantics.v
 * Chromium Source: third_party/blink/renderer/modules/webgpu/gpu_device.cc
 * Specification: W3C WebGPU §5.1
 * Mathematical Property: device_lost(st) = (st =? 1); once lost, device cannot
 *                        transition back to active.
 *)

From Coq Require Import ZArith.
From Coq Require Import Bool.
From Coq Require Import Lia.
From Coq Require Import List.
Import ListNotations.

Open Scope Z_scope.

Section BlinkWebGPUDeviceLossSemantics.

  (** * 1. State Space and Core Predicates *)

  (** State representation:
      0 represents an Active / Operational GPUDevice (kPending).
      1 represents a Lost / Destroyed GPUDevice (kResolved). *)
  Definition DeviceState : Type := Z.

  Definition STATE_ACTIVE : DeviceState := 0.
  Definition STATE_LOST   : DeviceState := 1.

  (** Well-formedness invariant for the device state register in Blink. *)
  Definition valid_state (st : DeviceState) : Prop :=
    st = STATE_ACTIVE \/ st = STATE_LOST.

  (** Exact mathematical property required: device_lost(st) = (st =? 1) *)
  Definition device_lost (st : DeviceState) : bool :=
    st =? 1.

  (** Dual predicate for active device status. *)
  Definition device_active (st : DeviceState) : bool :=
    st =? 0.

  (** * 2. Blink GPUDevice Actions and Operational Semantics *)

  (** Enumeration of all external stimuli and internal callbacks affecting
      GPUDevice state in third_party/blink/renderer/modules/webgpu/gpu_device.cc *)
  Inductive DeviceAction : Type :=
    | ActRegularOperation      (* e.g., createBuffer, createTexture, queue.submit *)
    | ActExplicitDestroy       (* GPUDevice::destroy() called from JS *)
    | ActDeviceLostCallback    (* GPUDevice::OnDeviceLostError() from Dawn wire *)
    | ActWireDisconnect        (* Mojo IPC / Dawn wire fatal channel error *)
    | ActContextDestroyed.     (* ExecutionContextLifecycleObserver::ContextDestroyed() *)

  (** Deterministic transition function modeling the C++ implementation in gpu_device.cc.
      Notice how LostProperty::Resolve() and destroyed_ flags act as a one-way latch. *)
  Definition step_device (st : DeviceState) (act : DeviceAction) : DeviceState :=
    if device_lost st then
      STATE_LOST
    else
      match act with
      | ActRegularOperation   => STATE_ACTIVE
      | ActExplicitDestroy    => STATE_LOST
      | ActDeviceLostCallback => STATE_LOST
      | ActWireDisconnect     => STATE_LOST
      | ActContextDestroyed   => STATE_LOST
      end.

  (** Multi-step execution trace over a sequence of actions. *)
  Fixpoint run_trace (st : DeviceState) (trace : list DeviceAction) : DeviceState :=
    match trace with
    | [] => st
    | act :: rest => run_trace (step_device st act) rest
    end.

  (** Relational single-step transition semantics (for Kripke/LTS verification). *)
  Inductive StepRel : DeviceState -> DeviceAction -> DeviceState -> Prop :=
    | Step_Active_Regular :
        StepRel STATE_ACTIVE ActRegularOperation STATE_ACTIVE
    | Step_Active_Destroy :
        StepRel STATE_ACTIVE ActExplicitDestroy STATE_LOST
    | Step_Active_Callback :
        StepRel STATE_ACTIVE ActDeviceLostCallback STATE_LOST
    | Step_Active_Disconnect :
        StepRel STATE_ACTIVE ActWireDisconnect STATE_LOST
    | Step_Active_Context :
        StepRel STATE_ACTIVE ActContextDestroyed STATE_LOST
    | Step_Lost_Absorbing : forall act,
        StepRel STATE_LOST act STATE_LOST.

  (** Reflexive-transitive closure of StepRel over action traces. *)
  Inductive MultiStepRel : DeviceState -> list DeviceAction -> DeviceState -> Prop :=
    | Multi_Refl : forall st,
        MultiStepRel st [] st
    | Multi_Step : forall st1 act st2 trace st3,
        StepRel st1 act st2 ->
        MultiStepRel st2 trace st3 ->
        MultiStepRel st1 (act :: trace) st3.

  (** * 3. Resource Safety Model (Dawn Wire & Buffer Unmapping Guard) *)

  (** In gpu_device.cc, hardware command submission is only permitted if the
      device is not lost. This models the safety gate preventing UAF/IPC faults. *)
  Definition can_dispatch_to_dawn_wire (st : DeviceState) : bool :=
    negb (device_lost st).

  (** * 4. Formal Theorems and Admitted-Free Proofs *)

  (** Lemma 1: Characterization of the device_lost boolean predicate. *)
  Theorem device_lost_iff : forall (st : DeviceState),
    device_lost st = true <-> st = 1.
  Proof.
    intros st.
    unfold device_lost.
    rewrite Z.eqb_eq.
    reflexivity.
  Qed.

  (** Lemma 2: Characterization of the negation of device_lost. *)
  Theorem device_not_lost_iff : forall (st : DeviceState),
    device_lost st = false <-> st <> 1.
  Proof.
    intros st.
    unfold device_lost.
    rewrite Z.eqb_neq.
    reflexivity.
  Qed.

  (** Lemma 3: Mutual exclusion of active and lost states for valid states. *)
  Theorem valid_state_dichotomy : forall (st : DeviceState),
    valid_state st ->
    (device_active st = true /\ device_lost st = false) \/
    (device_active st = false /\ device_lost st = true).
  Proof.
    intros st Hvalid.
    unfold valid_state, STATE_ACTIVE, STATE_LOST in Hvalid.
    unfold device_active, device_lost.
    destruct Hvalid as [H0 | H1]; subst st.
    - left. split; reflexivity.
    - right. split; reflexivity.
  Qed.

  (** Theorem 1: State Validity Invariant Preservation.
      Any transition from a valid state yields a valid state. *)
  Theorem step_preserves_valid_state : forall (st : DeviceState) (act : DeviceAction),
    valid_state st ->
    valid_state (step_device st act).
  Proof.
    intros st act Hvalid.
    unfold step_device.
    destruct (device_lost st) eqn:Hlost.
    - right. reflexivity.
    - destruct act; unfold valid_state;
      try (left; reflexivity);
      try (right; reflexivity).
  Qed.

  (** Theorem 2: Equivalence of Functional and Relational Semantics on Valid States. *)
  Theorem step_functional_relational_equiv :
    forall (st st' : DeviceState) (act : DeviceAction),
      valid_state st ->
      (step_device st act = st' <-> StepRel st act st').
  Proof.
    intros st st' act Hvalid.
    split; intros H.
    - subst st'.
      unfold valid_state, STATE_ACTIVE, STATE_LOST in Hvalid.
      destruct Hvalid as [H0 | H1]; subst st; unfold step_device, device_lost; simpl.
      + destruct act; constructor.
      + constructor.
    - inversion H; subst; unfold step_device, device_lost, STATE_ACTIVE, STATE_LOST; simpl;
      reflexivity.
  Qed.

  (** Theorem 3: Single-Step Terminal Irreversibility (Core Requirement).
      Once device_lost(st) = true, after any single action, device_lost remains true. *)
  Theorem device_loss_single_step_irreversible :
    forall (st : DeviceState) (act : DeviceAction),
      device_lost st = true ->
      device_lost (step_device st act) = true.
  Proof.
    intros st act Hlost.
    unfold step_device.
    rewrite Hlost.
    unfold device_lost, STATE_LOST.
     reflexivity.
  Qed.

  (** Theorem 4: State-Value Terminal Absorption.
      Expressed directly over Z arithmetic: st = 1 -> step_device st act = 1. *)
  Theorem device_loss_absorbing_Z :
    forall (st : DeviceState) (act : DeviceAction),
      st = 1 ->
      step_device st act = 1.
  Proof.
    intros st act Hst.
    subst st