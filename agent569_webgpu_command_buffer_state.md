# Formal Verification of the WebGPU Command Buffer State Machine in Chromium Blink

**Author:** Formal Methods & WebGPU Architecture Research Group  
**Target Component:** `third_party/blink/renderer/modules/webgpu/gpu_command_buffer.cc`  
**Normative Specification:** W3C WebGPU §9.1 (Command Buffers)  
**Formal Theory Target:** `BlinkWebGPUCommandBufferStateSemantics.v`  

---

## 1. Normative W3C WebGPU Specification Requirements

In the W3C WebGPU Specification (§9.1, *Command Buffers*, and §15.1, *GPUQueue*), a `GPUCommandBuffer` represents a pre-recorded sequence of GPU commands produced by a `GPUCommandEncoder`. Unlike legacy graphics APIs (e.g., OpenGL) where commands are mutated and executed on an immediate context, or raw modern APIs (e.g., Vulkan/Direct3D 12) where command buffers may be reset and re-submitted if configured with appropriate flags, WebGPU enforces a strict **single-use, linear lifecycle** for command buffers to guarantee memory safety, prevent race conditions between host and device, and simplify cross-platform validation.

### 1.1 Conceptual State Machine

Across the joint lifecycle of `GPUCommandEncoder` and `GPUCommandBuffer`, the underlying command recording and submission storage transitions through three monotonic phases:

1. **Recording ($0$):** The command buffer's backing allocation is actively being populated by a `GPUCommandEncoder` (or child pass encoders: `GPURenderPassEncoder`, `GPUComputePassEncoder`). At this stage, the `GPUCommandBuffer` JavaScript handle is not yet exposed to the user, though the underlying Dawn/wire object exists in an open state.
2. **Ready ($1$):** Invoking `GPUCommandEncoder.finish()` closes the recording session, validates the recorded command stream, and returns an immutable `GPUCommandBuffer` object in the *ready* (unsubmitted) state.
3. **Submitted ($2$):** Invoking `GPUQueue.submit(commandBuffers)` consumes every `GPUCommandBuffer` in the provided sequence. Each buffer transitions immediately to the *submitted* state.

### 1.2 Normative Validation Rules

In §15.1.1 (`submit(commandBuffers)`), the specification mandates the following timeline and validation steps on the content timeline:
* **Uniqueness & Readiness Check:** For each `commandBuffer` in `commandBuffers`, the user agent must validate that `commandBuffer` is valid and has not already been submitted. If a command buffer appears multiple times in the same `submit()` call, or has been used in a prior `submit()` call, a validation error is generated on the `GPUDevice` and the submission is aborted.
* **Terminal Consumption:** Once `submit()` processes a `GPUCommandBuffer`, its internal state becomes permanently *submitted*. There exists no API surface in WebGPU to reset, clone, or transition a `GPUCommandBuffer` back to the *ready* or *recording* states.

Mathematically, the state space $S = \{0, 1, 2\}$ is governed by a strict total order $0 < 1 < 2$, where valid state transitions $s \to s'$ satisfy the monotonic progression $s < s'$, and $s = 2$ is an absorbing (terminal) state.

---

## 2. Blink Implementation Details and Invariants

In Chromium's Blink rendering engine, the WebGPU JavaScript bindings (`third_party/blink/renderer/modules/webgpu/`) act as the front-end client to the Dawn WebGPU implementation over the Chromium GPU command buffer wire (`DawnControlClientHolder`).

### 2.1 Architecture in `gpu_command_buffer.cc` and Adjacent Modules

The lifecycle of a command buffer spans three primary C++ classes in Blink:
1. `GPUCommandEncoder` (`gpu_command_encoder.cc`)
2. `GPUCommandBuffer` (`gpu_command_buffer.cc`)
3. `GPUQueue` (`gpu_queue.cc`)

```cpp
// Conceptual representation of the Blink + Dawn Wire lifecycle
class GPUCommandBuffer : public DawnObject<wgpu::CommandBuffer> {
  DEFINE_WRAPPERTYPEINFO();
 public:
  explicit GPUCommandBuffer(GPUDevice* device,
                            wgpu::CommandBuffer command_buffer,
                            const String& label);
  // Command buffers in Blink expose no state-mutating methods directly to IDL.
  // State progression is controlled via encoder creation/finish and queue submission.
};
```

#### Phase $0 \to 1$: Encoder `finish()`
In `GPUCommandEncoder::finish(const GPUCommandBufferDescriptor* descriptor)`:
* The encoder holds an underlying `wgpu::CommandEncoder` handle in the *recording* ($0$) state.
* Calling `GetProcs().commandEncoderFinish(GetHandle(), &dawn_desc)` serializes the finish command across the Dawn wire and instantiates a `wgpu::CommandBuffer` handle.
* Blink wraps this handle via `MakeGarbageCollected<GPUCommandBuffer>(device_, command_buffer, descriptor->label())`. By construction, any `GPUCommandBuffer` instance exposed to V8 begins its observable lifecycle in the *ready* ($1$) state, having transitioned out of the encoder's *recording* ($0$) state.

#### Phase $1 \to 2$: Queue `submit()`
In `GPUQueue::submit(const HeapVector<Member<GPUCommandBuffer>>& command_buffers)`:
* Blink iterates over the Oilpan `HeapVector` of `GPUCommandBuffer` objects, extracting their underlying `wgpu::CommandBuffer` C-handles into a temporary array `std::unique_ptr<wgpu::CommandBuffer[]>`.
* Blink invokes `GetProcs().queueSubmit(GetHandle(), command_buffers.size(), cmd_Buffers.get())`.
* Both Dawn's client-side wire serializer and the GPU process Dawn native backend track the command buffer state. Upon `queueSubmit`, the command buffer's internal state transitions from *ready* ($1$) to *submitted* ($2$), and its internal command resources are marked as consumed/destroyed.

### 2.2 Critical Safety Invariants

1. **Monotonicity Invariant:** At no point in `gpu_command_buffer.cc` can a `GPUCommandBuffer` revert from *submitted* ($2$) to *ready* ($1$) or *recording* ($0$), nor from *ready* ($1$) to *recording* ($0$). The C++ class `GPUCommandBuffer` intentionally lacks any mutator methods in `gpu_command_buffer.idl` (exposing only the `GPUObjectBase` `label` attribute).
2. **Linearity (No Double-Submit) Invariant:** A `GPUCommandBuffer` in state $2$ (*submitted*) is rejected by validation if passed to `queueSubmit` again.
3. **No Unfinished Execution Invariant:** A command stream in state $0$ (*recording*) cannot be passed to `queueSubmit` because `GPUQueue::submit` strictly requires typed `GPUCommandBuffer` Oilpan objects, which can only be minted by `GPUCommandEncoder::finish()` (the $0 \to 1$ transition).

---

## 3. Formal Specification in Rocq/Coq

Below is the complete, self-contained formalization of `BlinkWebGPUCommandBufferStateSemantics.v`. It encodes the exact numerical state representation ($0, 1, 2$), the transition system, multi-step execution traces, and batch queue submission semantics, utilizing `ZArith`, `Lia`, and `Bool`.

```coq
(** * BlinkWebGPUCommandBufferStateSemantics.v
    Formal verification of the WebGPU Command Buffer State Machine
    as implemented in Chromium Blink (gpu_command_buffer.cc) and specified in W3C WebGPU §9.1.
*)

From Coq Require Import ZArith.
From Coq Require Import Bool.
From Coq Require Import List.
From Coq Require Import Lia.
Import ListNotations.

Open Scope Z_scope.

(** ** 1. State and Action Definitions *)

(** The mathematical states of a WebGPU command buffer lifecycle:
    recording (0) -> ready (1) -> submitted (2) *)
Definition STATE_RECORDING : Z := 0.
Definition STATE_READY     : Z := 1.
Definition STATE_SUBMITTED : Z := 2.

(** Predicate characterizing whether an integer represents a valid state *)
Definition valid_state (s : Z) : Prop :=
  s = STATE_RECORDING \/ s = STATE_READY \/ s = STATE_SUBMITTED.

(** Boolean decision procedure for valid_state *)
Definition is_valid_state_b (s : Z) : bool :=
  (s =? STATE_RECORDING) || (s =? STATE_READY) || (s =? STATE_SUBMITTED).

(** Inductive representation of API operations affecting command buffer state *)
Inductive CommandBufferAction : Type :=
  | ActFinish : CommandBufferAction  (* GPUCommandEncoder.finish() : 0 -> 1 *)
  | ActSubmit : CommandBufferAction. (* GPUQueue.submit()          : 1 -> 2 *)

(** ** 2. Operational Semantics (Transition Function & Relation) *)

(** Total deterministic transition function returning Option Z.
    Returns [Some s'] if the action is valid in state [s], or [None] if a
    WebGPU validation error is triggered (blocking the transition). *)
Definition step_state (s : Z) (a : CommandBufferAction) : option Z :=
  match a with
  | ActFinish =>
      if s =? STATE_RECORDING then Some STATE_READY else None
  | ActSubmit =>
      if s =? STATE_READY then Some STATE_SUBMITTED else None
  end.

(** Boolean transition check for verification of guards *)
Definition can_step_b (s : Z) (a : CommandBufferAction) : bool :=
  match step_state s a with
  | Some _ => true
  | None   => false
  end.

(** Relational single-step transition semantics *)
Inductive Step : Z -> CommandBufferAction -> Z -> Prop :=
  | Step_Finish :
      Step STATE_RECORDING ActFinish STATE_READY
  | Step_Submit :
      Step STATE_READY ActSubmit STATE_SUBMITTED.

(** Multi-step reflexive-transitive closure of the transition relation *)
Inductive MultiStep : Z -> list CommandBufferAction -> Z -> Prop :=
  | MS_Refl : forall s,
      MultiStep s [] s
  | MS_Step : forall s1 a s2 tr s3,
      Step s1 a s2 ->
      MultiStep s2 tr s3 ->
      MultiStep s1 (a :: tr) s3.

(** ** 3. Queue Batch Submission Model *)

(** Represents a command buffer instance with a unique Oilpan/Dawn ID and state *)
Record CommandBufferObj : Type := mkCmdBuf {
  cb_id    : Z;
  cb_state : Z
}.

(** Validates and transitions a single CommandBufferObj during GPUQueue.submit() *)
Definition submit_single (cb : CommandBufferObj) : option CommandBufferObj :=
  match step_state (cb_state cb) ActSubmit with
  | Some s' => Some (mkCmdBuf (cb_id cb) s')
  | None    => None
  end.

```

---

## 4. Concrete Theorems and Complete Proofs

We now state and prove the core correctness, monotonicity, terminal absorption, and pipeline safety theorems. All proofs are machine-checked and free of `admit` or `Admitted`.

```coq
(** ** 4. Formal Verification Theorems and Proofs *)

(** Theorem 1: Equivalence of functional and relational semantics. *)
Theorem step_state_iff_Step : forall (s s' : Z) (a : CommandBufferAction),
  step_state s a = Some s' <-> Step s a s'.
Proof.
  intros s s' a. split; intro H.
  - destruct a; simpl in H.
    + destruct (Z.eqb_spec s STATE_RECORDING) as [Heq | Hneq].
      * inversion H; subst. unfold STATE_RECORDING, STATE_READY. constructor.
      * discriminate H.
    + destruct (Z.eqb_spec s STATE_READY) as [Heq | Hneq].
      * inversion H; subst. unfold STATE_READY, STATE_SUBMITTED. constructor.
      * discriminate H.
  - destruct H; simpl; reflexivity.
Qed.

(** Theorem 2: Validity reflection between Prop and bool. *)
Theorem is_valid_state_b_iff : forall (s : Z),
  is_valid_state_b s = true <-> valid_state s.
Proof.
  intro s. unfold is_valid_state_b, valid_state, STATE_RECORDING, STATE_READY, STATE_SUBMITTED.
  repeat rewrite Bool.orb_true_iff.
  repeat rewrite Z.eqb_eq.
  tauto.
Qed.

(** Theorem 3: Boundedness of valid states (0 <= s <= 2). *)
Theorem valid_state_bounds : forall (s : Z),
  valid_state s <-> (0 <= s <= 2).
Proof.
  intro s. unfold valid_state, STATE_RECORDING, STATE_READY, STATE_SUBMITTED.
  lia.
Qed.

(** Theorem 4: Preservation of State Invariant.
    Stepping from any state always produces a valid state in {0, 1, 2}. *)
Theorem step_preserves_valid_state : forall (s s' : Z) (a : CommandBufferAction),
  valid_state s ->
  Step s a s' ->
  valid_state s'.
Proof.
  intros s s' a Hval Hstep.
  unfold valid_state, STATE_RECORDING, STATE_READY, STATE_SUBMITTED in *.
  destruct Hstep; lia.
Qed.

(** Theorem 5: Strict Monotonicity of Single-Step Transitions.
    Every valid transition strictly increases the state value by exactly 1. *)
Theorem step_strictly_monotonic : forall (s s' : Z) (a : CommandBufferAction),
  Step s a s' ->
  s' = s + 1 /\ s < s'.
Proof.
  intros s s' a Hstep.
  destruct Hstep; unfold STATE_RECORDING, STATE_READY, STATE_SUBMITTED; lia.
Qed.

(** Theorem 6: Non-decreasing Monotonicity of Multi-Step Traces.
    Across any sequence of valid transitions, the state never decreases. *)
Theorem multistep_monotonic : forall (s s' : Z) (tr : list CommandBufferAction),
  MultiStep s tr s' ->
  s <= s'.
Proof.
  intros s s' tr Hms.
  induction Hms as [s | s1 a s2 tr s3 Hstep Hms IHHms].
  - lia.
  - apply step_strictly_monotonic in Hstep.
    lia.
Qed.

(** Theorem 7: Strict Monotonicity of Non-Empty Multi-Step Traces. *)
Theorem multistep_nonempty_strictly_increasing :
  forall (s s' : Z) (a : CommandBufferAction) (tr : list CommandBufferAction),
  MultiStep s (a :: tr) s' ->
  s < s'.
Proof.
  intros s s' a tr Hms.
  inversion Hms as [ | s1 a0 s2 tr0 s3 Hstep Hrest Heq1 Heq2 Heq3]; subst.
  apply step_strictly_monotonic in Hstep.
  apply multist