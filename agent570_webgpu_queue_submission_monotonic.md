# Formal Verification of WebGPU Queue Submission Monotonicity in Chromium Blink

**Author**: Formal Methods & WebGPU Graphics Pipeline Research Group  
**Target Artifact**: `third_party/blink/renderer/modules/webgpu/gpu_queue.cc`  
**Specification Reference**: W3C WebGPU §13.1 (`GPUQueue`)  
**Formal Theory Target**: `BlinkWebGPUQueueSubmissionMonotonicitySemantics.v`  
**Primary Mathematical Property**: $\forall n \in \mathbb{N}, \text{submission\_id}(n + 1) > \text{submission\_id}(n)$ (Strict Monotonicity)

---

## 1. Normative W3C WebGPU Specification Requirements

Section 13.1 of the W3C WebGPU Specification defines the `GPUQueue` interface, which serves as the primary abstraction for submitting command buffers, writing buffer/texture data, and synchronizing device-timeline execution with the content timeline.

### 1.1 Queue Timeline and Execution Ordering
The normative specification mandates that all operations dispatched on a `GPUQueue`—specifically `submit(sequence<GPUCommandBuffer> commandBuffers)` and `onSubmittedWorkDone()`—must execute in a deterministic, strictly ordered sequence:

1. **`submit(commandBuffers)` (§13.1.1)**: Schedules the execution of the provided command buffers on the GPU queue timeline. Every invocation of `submit` represents a discrete atomic advancement of the queue's execution state.
2. **`onSubmittedWorkDone()` (§13.1.2)**: Returns a `Promise<undefined>` that resolves when all work submitted to the queue prior to the `onSubmittedWorkDone()` call has completed execution on the device timeline.

### 1.2 Implicit Monotonicity Requirement
While the W3C specification expresses queue progression via abstract queue-timeline ordering steps, any conforming browser architecture that bridges an asynchronous JavaScript content process (Blink) with an out-of-process GPU command decoder (Dawn/WebGPU via Chromium IPC) must reify this abstract timeline into concrete, totally ordered **submission identifiers** or **serials** (often referred to as `ExecutionSerial` or fence values).

For `onSubmittedWorkDone()` and resource Hazard Tracking (such as `GPUBuffer.mapAsync` awaiting queue completion) to uphold the normative W3C memory visibility and ordering guarantees:
* Every queue submission event $e_n$ must be assigned a unique identifier $S(n) \in \mathbb{Z}_{\ge 0}$.
* The assignment function $S : \mathbb{N} \to \mathbb{Z}$ must be **strictly monotonically increasing**:
  $$\forall n, m \in \mathbb{N}, \quad n < m \implies S(n) < S(m)$$
* Non-advancing queries (e.g., querying the current fence state when no new work was queued, or handling empty/failed validation states depending on whether the wire protocol advances the serial) must never cause the tracked submission serial to regress.

---

## 2. Chromium Blink Implementation Analysis

In Chromium, the WebGPU frontend is implemented in `third_party/blink/renderer/modules/webgpu/`. The `GPUQueue` class (`gpu_queue.cc` and `gpu_queue.h`) acts as the Blink wrapper around the Dawn Wire client handle (`wgpu::Queue`).

### 2.1 Architecture of `gpu_queue.cc`
When JavaScript invokes `queue.submit(commandBuffers)`, control enters `GPUQueue::submit(ScriptState* script_state, const HeapVector<Member<GPUCommandBuffer>>& command_buffers, ExceptionState& exception_state)` in `third_party/blink/renderer/modules/webgpu/gpu_queue.cc`.

The execution flow proceeds through the following critical phases:

1. **Dawn Wire Serialization**: Blink converts the `HeapVector<Member<GPUCommandBuffer>>` into a raw array of `wgpu::CommandBuffer` handles and invokes `GetProcs().queueSubmit(GetHandle(), ...)`, or uses the C++ wrapper `GetHandle().Submit(count, commands.data())`.
2. **Client-Side Serial Tracking & Fence Signaling**: To manage resource lifetimes (e.g., external texture destruction, buffer unmapping callbacks, and `onSubmittedWorkDone` resolution) without synchronous round-trips to the GPU process, the Blink/Dawn client layer maintains a monotonically increasing submission counter/serial.
3. **Monotonic State Transitions**:
   Let $\sigma_n$ represent the state of `GPUQueue` after $n$ submission transitions. The internal state tracks:
   * `last_submitted_serial` (or equivalent internal submission index $S_n \in \mathbb{Z}$).
   * `completed_serial` ($C_n \in \mathbb{Z}$), updated asynchronously via IPC callbacks from the GPU process when Dawn signals fence completion.

### 2.2 Implementation Invariants in `gpu_queue.cc`
To ensure memory safety (preventing Use-After-Free of shared memory transfer buffers and Dawn objects) and specification compliance, `gpu_queue.cc` and its underlying Dawn wire client enforce the following invariants:

* **Invariant I1 (Strict Step Progression)**: Every valid `Submit` dispatch increments the internal submission serial by a strictly positive delta $\Delta \ge 1$ (canonically $\Delta = 1$):
  $$S_{n+1} = S_n + 1$$
* **Invariant I2 (Positivity / Lower Bound)**: The initial submission serial $S_0$ is initialized to $0$, ensuring that all active submission serials satisfy $S_n \ge 0$, and after at least one submission ($n \ge 1$), $S_n \ge 1$.
* **Invariant I3 (Completion Causality)**: The completed work serial $C_n$ reported by the GPU process cannot exceed the most recently issued submission serial $S_n$, nor can it regress:
  $$0 \le C_n \le S_n \quad \text{and} \quad C_n \le C_{n+1}$$
* **Invariant I4 (Total Ordering of `onSubmittedWorkDone`)**: When `onSubmittedWorkDone()` is invoked at state $\sigma_n$, a callback is registered with target serial $T = S_n$. Because $S_{n+1} > S_n$, any subsequent submission $n+1$ receives serial $S_{n+1} > T$, guaranteeing that the promise resolves precisely upon completion of submission $n$ without being blocked by or prematurely triggered by submission $n+1$.

---

## 3. Formal Specification in Rocq/Coq

Below is the formalization of the Blink WebGPU Queue submission state machine, operational semantics, and monotonicity invariants. It is structured to be completely self-contained and verifiable in standard Rocq/Coq using `ZArith`, `Lia`, `List`, and `Bool`.

### 3.1 Formal Theory: `BlinkWebGPUQueueSubmissionMonotonicitySemantics.v`

```coq
(** * BlinkWebGPUQueueSubmissionMonotonicitySemantics.v
    Formal Verification of WebGPU Queue Submission Timestamp/Serial Monotonicity
    in Chromium Blink (third_party/blink/renderer/modules/webgpu/gpu_queue.cc)
    Specification: W3C WebGPU §13.1 (GPUQueue)
*)

From Coq Require Import ZArith.
From Coq Require Import Bool.
From Coq Require Import List.
From Coq Require Import Lia.
Import ListNotations.

Open Scope Z_scope.

(** ** 1. Core Domain Types and Queue State Representation *)

(** A SubmissionID (or ExecutionSerial) is modeled over the integers Z
    to allow reasoning about arithmetic bounds, deltas, and ordering via Lia. *)
Definition SubmissionID := Z.

(** CommandBufferStatus represents the validation state of a GPUCommandBuffer
    passed to GPUQueue::submit(). *)
Inductive CommandBufferState : Type :=
  | CBValid : CommandBufferState
  | CBInvalid : CommandBufferState.

(** A SubmitPayload is a list of command buffers passed to GPUQueue::submit(). *)
Definition SubmitPayload := list CommandBufferState.

(** GPUQueueState models the relevant state of blink::GPUQueue and its
    underlying Dawn wire client serial tracker. *)
Record GPUQueueState : Type := mkQueueState {
  (** The submission ID of the most recently dispatched queue submission. *)
  last_submitted_id : SubmissionID;
  (** The submission ID most recently confirmed completed by the GPU process. *)
  completed_id : SubmissionID;
  (** The discrete count of submissions executed on this queue timeline. *)
  submission_step : nat
}.

(** Initial state of a newly created GPUQueue upon GPUDevice initialization. *)
Definition init_queue_state : GPUQueueState := {|
  last_submitted_id := 0;
  completed_id := 0;
  submission_step := 0%nat
|}.

(** ** 2. Functional Model of Submission ID Generation *)

(** In Blink/Dawn, each submission event on the queue timeline advances the
    submission serial by a strictly positive step (canonically 1, or a bounded
    positive offset d > 0). First, we define the canonical deterministic mapping
    submission_id(n) for the n-th submission step. *)
Fixpoint submission_id (n : nat) : SubmissionID :=
  match n with
  | O => 0
  | S n' => submission_id n' + 1
  end.

(** Generalized submission transition function that advances a given SubmissionID
    by a positive work quantum (delta >= 1), modeling both standard single-step
    serial increments and batched internal Dawn wire serial increments. *)
Definition next_submission_id (current : SubmissionID) (delta : Z) : SubmissionID :=
  if Z.leb 1 delta then current + delta else current + 1.

(** Validation predicate for command buffer sequences in GPUQueue::submit(). *)
Definition is_cb_valid (cb : CommandBufferState) : bool :=
  match cb with
  | CBValid => true
  | CBInvalid => false
  end.

Definition validate_submit_payload (payload : SubmitPayload) : bool :=
  forallb is_cb_valid payload.

(** ** 3. Operational Semantics of GPUQueue::submit() *)

(** In Blink's GPUQueue::submit (gpu_queue.cc), every invocation of submit()
    dispatches the command buffers over the Dawn wire and advances the queue's
    submission serial. Even if validation fails in the GPU process, the wire
    submission serial itself advances monotonically on the queue timeline. *)
Definition exec_submit (st : GPUQueueState) (delta : Z) : GPUQueueState := {|
  last_submitted_id := next_submission_id (last_submitted_id st) delta;
  completed_id := completed_id st;
  submission_step := S (submission_step st)
|}.

(** Canonical single-step submit transition (delta = 1). *)
Definition exec_submit_canonical (st : GPUQueueState) : GPUQueueState :=
  exec_submit st 1.

(** N-step canonical execution trace starting from an initial state. *)
Fixpoint run_n_submits (n : nat) : GPUQueueState :=
  match n with
  | O => init_queue_state
  | S n' => exec_submit_canonical (run_n_submits n')
  end.

(** ** 4. Asynchronous Completion Semantics (onSubmittedWorkDone) *)

(** Models the GPU process signaling fence completion up to [new_completed].
    Blink/Dawn enforces that completion serials must be within [completed_id, last_submitted_id]. *)
Definition update_completed_work (st : GPUQueueState) (new_completed : SubmissionID) : GPUQueueState :=
  if andb (Z.leb (completed_id st) new_completed)
          (Z.leb new_completed (last_submitted_id st))
  then {|
    last_submitted_id := last_submitted_id st;
    completed_id := new_completed;
    submission_step := submission_step st
  |}
  else st.

(** Boolean checker for whether a promise registered at [target_id] via
    onSubmittedWorkDone() is resolved in state [st]. *)
Definition is_work_done (st : GPUQueueState) (target_id : SubmissionID) : bool :=
  Z.leb target_id (completed_id st).

(** ** 5. Well-Formedness and Safety Predicates *)

(** A GPUQueueState is well-formed (valid) if:
    1. All serials are non-negative.
    2. The completed serial never exceeds the last submitted serial.
    3. The last submitted serial is at least the number of submission steps. *)
Definition queue_state_wf (st : GPUQueueState) : Prop :=
  0 <= completed_id st /\
  completed_id st <= last_submitted_id st /\
  Z.of_nat (submission_step st) <= last_submitted_id st.

(** Relational trace transition combining submissions and completion callbacks. *)
Inductive QueueAction : Type :=
  | ActSubmit (delta : Z)
  | ActComplete (serial : SubmissionID).

Definition step_queue (st : GPUQueueState) (act : QueueAction) : GPUQueueState :=
  match act with
  | ActSubmit d => exec_submit st d
  | ActComplete s => update_completed_work st s
  end.

Fixpoint exec_trace (st : GPUQueueState) (trace : list QueueAction) : GPUQueueState :=
  match trace with
  | [] => st
  | act :: rest => exec_trace (step_queue st act) rest
  end.
```

---

## 4. Concrete Theorems and Complete Mechanized Proofs

We now state and prove the core mathematical theorems verifying strict monotonicity, algebraic closed-form equivalence, state invariant preservation, and `onSubmittedWorkDone` fence causality. Every proof is complete and free of `admit` or `Admitted`.

```coq
(** ** 6. Formal Theorems and Mechanized Proofs *)

(** *** Theorem 1: Closed-form equivalence of [submission_id]
    Proves that the recursive definition [submission_id n] equals [Z.of_nat n]. *)
Lemma submission_id_closed_form : forall (n : nat),
  submission_id n = Z.of_nat n.
Proof.
  induction n as [| n' IH].
  - simpl. reflexivity.
  - simpl. rewrite IH. lia.
Qed.

(** *** Theorem 2: Primary Mathematical Property — Strict Step Monotonicity
    Directly proves the specification requirement:
    submission_id(n + 1) > submission_id(n). *)
Theorem submission_id_strictly_monotonic_step : forall (n : nat),
  submission_id (n + 1)%nat > submission_id n.
Proof.
  intros n.
  repeat rewrite submission_id_closed_form.
  lia.
Qed.

(** Equivalent formulation using successor [S n]. *)
Theorem submission_id_strictly_monotonic_succ : forall (n : nat),
  submission_id (S n) > submission_id n.
Proof.
  intros n.
  simpl.
  lia.
Qed.

(** *** Theorem 3: Global Strict Monotonicity Across Arbitrary Steps
    For any two submission indices n and m, if n < m, then
    submission_id(n) < submission_id(m). *)
Theorem submission_id_strictly_monotonic_global : forall (n m : nat),
  (n < m)%nat -> submission_id n < submission_id m.
Proof.