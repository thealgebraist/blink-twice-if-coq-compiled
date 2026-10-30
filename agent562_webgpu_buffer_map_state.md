# Formal Verification of the Chromium Blink WebGPU Buffer Mapping State Machine

**Target Implementation:** `third_party/blink/renderer/modules/webgpu/gpu_buffer.cc`  
**Normative Specification:** W3C WebGPU §6.2.1 (GPUBufferMapState and Buffer Mapping)  
**Formal Theory Module:** `BlinkWebGPUBufferMapStateSemantics.v`  
**Mathematical Property:** Buffer mapping state transitions across `unmapped` ($0$), `pending` ($1$), and `mapped` ($2$); unconditional idempotency and state reset of `unmap()` to `unmapped` ($0$).

---

## 1. Normative W3C WebGPU Specification Requirements

In the W3C WebGPU Specification (§6.2 *GPUBuffer* and §6.2.1 *Buffer Mapping*), a `GPUBuffer` represents a block of memory that can be used in GPU operations. Because memory may reside in GPU-local VRAM or shared host-visible system RAM, CPU access to a `GPUBuffer` is mediated by an explicit, asynchronous ownership-transfer state machine.

### 1.1 Content-Timeline `[[mapState]]`
Every `GPUBuffer` internal slot includes a content-timeline state variable `[[mapState]]` of enumeration type `GPUBufferMapState`:
```webidl
enum GPUBufferMapState {
    "unmapped",
    "pending",
    "mapped"
};
```

### 1.2 Normative State Transition Rules
The specification mandates the following state transitions on the content timeline:

1. **Buffer Creation (`createBuffer`):**
   * If `descriptor.mappedAtCreation == true`, the buffer is initialized with `[[mapState]] = "mapped"`.
   * If `descriptor.mappedAtCreation == false`, the buffer is initialized with `[[mapState]] = "unmapped"`.

2. **Asynchronous Mapping Request (`mapAsync(mode, offset, size)`):**
   * **Precondition:** `[[mapState]]` must be `"unmapped"`. If `[[mapState]]` is `"pending"` or `"mapped"`, a `OperationError` (or validation error on the device timeline) is triggered, and the state transition is rejected.
   * **Immediate Effect (Content Timeline):** `[[mapState]]` transitions synchronously to `"pending"`, and `[[pending_map]]` is assigned the newly created `Promise`.

3. **Asynchronous Mapping Resolution (Callback on Content Timeline):**
   * **Precondition:** `[[mapState]]` is `"pending"` (if `unmap()` or `destroy()` was called while the request was in flight on the device timeline, `[[mapState]]` was already reset to `"unmapped"`, aborting resolution).
   * **Effect:** If the underlying device validation succeeds, `[[mapState]]` transitions from `"pending"` to `"mapped"`. If device validation fails (e.g., invalid usage flags or out-of-bounds range), `[[mapState]]` transitions from `"pending"` back to `"unmapped"`.

4. **Unmapping (`unmap()`):**
   * **Precondition:** None on `[[mapState]]` regarding state transitions (though detaching array buffers only occurs if `"mapped"`, and rejecting `[[pending_map]]` with `AbortError` occurs if `"pending"`).
   * **Effect:** `[[mapState]]` unconditionally transitions to `"unmapped"`.

5. **Destruction (`destroy()`):**
   * **Effect:** Invokes the unmapping steps, unconditionally setting `[[mapState]]` to `"unmapped"`.

---

## 2. Chromium Blink Implementation Analysis

In Chromium's multi-process architecture, Blink (the renderer process) executes JavaScript on the **Content Timeline**, while the GPU Process (via Dawn, the native WebGPU implementation) executes commands on the **Device Timeline** over the Wire (IPC command buffer).

### 2.1 Source Architecture in `gpu_buffer.cc`
In `third_party/blink/renderer/modules/webgpu/gpu_buffer.cc` (and its header `gpu_buffer.h`), Blink delegates the canonical state tracking of the content-timeline `mapState` to the Dawn Wire Client (`wgpu::Buffer`), while maintaining synchronized wrapper invariants for JavaScript ArrayBuffer detachment (`mapped_array_buffers_`) and pending promise resolution (`map_async_resolver_`).

```cpp
// Conceptual representation of Blink's GPUBuffer state management in gpu_buffer.cc
V8GPUBufferMapState GPUBuffer::mapState() const {
  return FromDawnEnum(GetHandle().GetMapState());
}
```

Dawn's Wire Client (`dawn/src/dawn/wire/client/Buffer.cpp`) and Blink's `GPUBuffer` enforce the exact 3-state encoding:
* `wgpu::BufferMapState::Unmapped` $\leftrightarrow 0$
* `wgpu::BufferMapState::Pending` $\leftrightarrow 1$
* `wgpu::BufferMapState::Mapped` $\leftrightarrow 2$

### 2.2 Critical Implementation Invariants
1. **Synchronous `Pending` Transition in `mapAsync`:**
   When `GPUBuffer::mapAsync` is invoked in Blink, `GetHandle().MapAsync(...)` is called. On the Dawn Wire Client, if the buffer is currently `Unmapped`, its internal state immediately transitions to `Pending` *before* the IPC command is flushed to the GPU process. If it is not `Unmapped`, the request is rejected without mutating the current state.

2. **In-Flight Cancellation via `unmap()`:**
   When `GPUBuffer::unmap(ScriptState* script_state, ExceptionState& exception_state)` is called:
   * Blink detaches all `DOMArrayBuffer` views associated with the mapping (`ResetMappingState`).
   * If `map_async_resolver_` is active (state is `Pending`), Blink rejects the pending promise immediately with an `AbortError` DOMException.
   * `GetHandle().Unmap()` is invoked, which synchronously resets the client-side `MapState` to `Unmapped` ($0$), regardless of whether the previous state was `Unmapped` ($0$), `Pending` ($1$), or `Mapped` ($2$).

3. **Mutual Exclusion of CPU and GPU Access:**
   A buffer may only yield a valid `getMappedRange()` pointer to JavaScript when `mapState == Mapped` ($2$). Conversely, the GPU command encoder rejects any submission referencing a buffer whose state is not `Unmapped` ($0$). Thus, the state machine guarantees memory safety and data-race freedom across the IPC boundary.

---

## 3. Formal Specification in Rocq / Coq

Below is the self-contained, formal mechanized theory `BlinkWebGPUBufferMapStateSemantics.v`. It models the buffer mapping state space both as an algebraic inductive type and via its exact numerical encoding in $\mathbb{Z}$ ($0, 1, 2$), defining the complete operational semantics of `create`, `mapAsync`, `onMapAsyncResolved`, `getMappedRange`, `unmap`, and `destroy`.

```coq
(** * BlinkWebGPUBufferMapStateSemantics.v
    Formal Verification of the Chromium Blink WebGPU Buffer Mapping State Machine
    Target: third_party/blink/renderer/modules/webgpu/gpu_buffer.cc
    Specification: W3C WebGPU §6.2.1
*)

From Coq Require Import ZArith.
From Coq Require Import Bool.
From Coq Require Import List.
From Coq Require Import Lia.
Import ListNotations.

Open Scope Z_scope.

(** ** 1. State Space Representation and Numerical Encoding *)

(** Algebraic representation of GPUBufferMapState (WebGPU §6.2.1) *)
Inductive MapState : Type :=
  | Unmapped : MapState
  | Pending  : MapState
  | Mapped   : MapState.

(** Decidable equality on MapState *)
Definition map_state_eqb (s1 s2 : MapState) : bool :=
  match s1, s2 with
  | Unmapped, Unmapped => true
  | Pending,  Pending  => true
  | Mapped,   Mapped   => true
  | _,        _        => false
  end.

(** Numerical encoding: unmapped(0), pending(1), mapped(2) *)
Definition encode_state (s : MapState) : Z :=
  match s with
  | Unmapped => 0
  | Pending  => 1
  | Mapped   => 2
  end.

(** Partial decoding from Z to MapState *)
Definition decode_state (z : Z) : option MapState :=
  if Z.eqb z 0 then Some Unmapped
  else if Z.eqb z 1 then Some Pending
  else if Z.eqb z 2 then Some Mapped
  else None.

(** Predicate characterizing valid numerical map state encodings *)
Definition valid_state_code (z : Z) : Prop :=
  0 <= z <= 2.

(** ** 2. Extended Buffer Mapping Model in Blink *)

(** Models the content-timeline state of a Blink GPUBuffer instance *)
Record BlinkGPUBuffer : Type := mkBuffer {
  buf_state_code     : Z;    (** Numerical mapState: 0, 1, or 2 *)
  buf_has_pending_op : bool; (** True iff map_async_resolver_ is active *)
  buf_has_mapped_mem : bool  (** True iff JS ArrayBuffer views are attached *)
}.

(** Well-formedness invariant of Blink's GPUBuffer wrapper *)
Definition well_formed_buffer (b : BlinkGPUBuffer) : Prop :=
  valid_state_code (buf_state_code b) /\
  (buf_state_code b = 0 <-> (buf_has_pending_op b = false /\ buf_has_mapped_mem b = false)) /\
  (buf_state_code b = 1 <-> (buf_has_pending_op b = true  /\ buf_has_mapped_mem b = false)) /\
  (buf_state_code b = 2 <-> (buf_has_pending_op b = false /\ buf_has_mapped_mem b = true)).

(** ** 3. Pure State Transition Functions (Z-encoded) *)

(** Transition for GPUBuffer creation: mappedAtCreation -> 2, else 0 *)
Definition transition_create (mapped_at_creation : bool) : Z :=
  if mapped_at_creation then 2 else 0.

(** Transition for GPUBuffer::mapAsync initiation on Content Timeline.
    Only transitions 0 -> 1. Otherwise, state remains unchanged (request rejected). *)
Definition transition_map_async (s : Z) : Z :=
  if Z.eqb s 0 then 1 else s.

(** Transition for asynchronous callback resolution (OnMapAsyncCallback).
    Only takes effect if still in Pending (1) state.
    If success = true, transitions 1 -> 2.
    If success = false, transitions 1 -> 0.
    If not in state 1 (e.g., unmapped while in flight), state is unchanged. *)
Definition transition_map_resolve (s : Z) (success : bool) : Z :=
  if Z.eqb s 1 then
    (if success then 2 else 0)
  else
    s.

(** Transition for GPUBuffer::unmap().
    Unconditionally resets the map state to unmapped (0). *)
Definition transition_unmap (s : Z) : Z := 0.

(** Transition for GPUBuffer::destroy().
    Invokes unmap semantics, resetting map state to unmapped (0). *)
Definition transition_destroy (s : Z) : Z :=
  transition_unmap s.

(** ** 4. Blink GPUBuffer Record Transitions *)

Definition buffer_create (mapped_at_creation : bool) : BlinkGPUBuffer :=
  if mapped_at_creation then
    mkBuffer 2 false true
  else
    mkBuffer 0 false false.

Definition buffer_map_async (b : BlinkGPUBuffer) : BlinkGPUBuffer :=
  if Z.eqb (buf_state_code b) 0 then
    mkBuffer 1 true false
  else
    b.

Definition buffer_map_resolve (b : BlinkGPUBuffer) (success : bool) : BlinkGPUBuffer :=
  if Z.eqb (buf_state_code b) 1 then
    if success then
      mkBuffer 2 false true
    else
      mkBuffer 0 false false
  else
    b.

Definition buffer_unmap (b : BlinkGPUBuffer) : BlinkGPUBuffer :=
  mkBuffer (transition_unmap (buf_state_code b)) false false.

Definition buffer_destroy (b : BlinkGPUBuffer) : BlinkGPUBuffer :=
  buffer_unmap b.

(** ** 5. Action Trace Semantics *)

Inductive BufferAction : Type :=
  | ActMapAsync   : BufferAction
  | ActMapResolve : bool -> BufferAction
  | ActUnmap      : BufferAction
  | ActDestroy    : BufferAction.

Definition step_state (s : Z) (a : BufferAction) : Z :=
  match a with
  | ActMapAsync        => transition_map_async s
  | ActMapResolve succ => transition_map_resolve s succ
  | ActUnmap           => transition_unmap s
  | ActDestroy         => transition_destroy s
  end.

Definition step_buffer (b : BlinkGPUBuffer) (a : BufferAction) : BlinkGPUBuffer :=
  match a with
  | ActMapAsync        => buffer_map_async b
  | ActMapResolve succ => buffer_map_resolve b succ
  | ActUnmap           => buffer_unmap b
  | ActDestroy         => buffer_destroy b
  end.

Fixpoint run_state_trace (s : Z) (trace : list BufferAction) : Z :=
  match trace with
  | []      => s
  | a :: tr => run_state_trace (step_state s a) tr
  end.

Fixpoint run_buffer_trace (b : BlinkGPUBuffer) (trace : list BufferAction) : BlinkGPUBuffer :=
  match trace with
  | []      => b
  | a :: tr => run_buffer_trace (step_buffer b a) tr
  end.

(** ** 6. GPU Pipeline Safety Predicates *)

(** CPU access via getMappedRange() is permitted iff state is Mapped (2) *)
Definition cpu_access_permitted (b : BlinkGPUBuffer) : bool :=
  Z.eqb (buf_state_code b) 2.

(** GPU queue submission referencing the buffer is permitted iff state is Unmapped (0) *)
Definition gpu_submit_permitted (b : BlinkGPUBuffer) : bool :=
  Z.eqb (buf_state_code b) 0.
```

---

## 4. Concrete Theorems and Mechanized Proofs

This section continues the Coq script with complete, self-contained, admitted-free proofs verifying the mathematical properties of the state machine, encoding bijections, trace invariants, `unmap` reset guarantees, and CPU/GPU mutual exclusion.

```coq
(** ** 7. Formal Verification Theorems and Proofs *)

(** Theorem 1: Bijection and bounds of the numerical state encoding. *)
Theorem encode_state_bounds : forall (s : MapState),
  valid_state_code (encode_state s).
Proof.
  intros s.
  destruct s; unfold valid_state_