# Formal Verification Report: WritableStream Backpressure Signaling in Chromium Blink

**Formal Theory Target**: `BlinkStreamsWritableStreamBackpressureSemantics.v`  
**Chromium Component**: `third_party/blink/renderer/core/streams/writable_stream_default_controller.cc`  
**Normative Specification**: WHATWG Streams Standard §4.2 (WritableStreamDefaultController) & §4.1 (WritableStream)  
**Mathematical Property**: $\text{desired\_size} = \text{high\_water\_mark} - \text{queue\_size} \implies (\text{backpressure} \iff \text{desired\_size} \le 0)$

---

## 1. Normative WHATWG Specification Requirements

The WHATWG Streams Standard governs how writable streams manage internal queues and communicate flow-control signals (backpressure) to underlying sinks and stream writers. Backpressure in a `WritableStream` is a cooperative signal calculated from the internal queue's total byte/chunk size relative to a configured queuing strategy's `highWaterMark`.

### 1.1 Internal Slots and State Machine
Per **WHATWG Streams §4.1.3** (`WritableStream`) and **§4.2.3** (`WritableStreamDefaultController`), the backpressure state is governed by the following internal slots:

* **`stream.[[state]]`**: One of `"writable"`, `"erroring"`, `"errored"`, or `"closed"`.
* **`stream.[[backpressure]]`**: A boolean initialized to `false`. It tracks the most recently communicated backpressure state on the stream.
* **`stream.[[inFlightWriteRequest]]`**: Either `undefined` or a Promise record representing the chunk currently being written to the underlying sink.
* **`controller.[[queue]]`**: A List of `(value, size)` tuples representing buffered write chunks and `"close"` sentinel records.
* **`controller.[[queueTotalSize]]`**: A real number $\ge 0$ representing the sum of sizes of all elements currently in `controller.[[queue]]`.
* **`controller.[[strategyHWM]]`**: A non-negative real number representing the high water mark configured during stream construction.
* **`controller.[[started]]`**: A boolean indicating whether the underlying sink's `start()` algorithm has resolved.

### 1.2 Abstract Operations
The specification defines exact algorithmic steps for computing and propagating backpressure:

1. **`WritableStreamDefaultControllerGetDesiredSize(controller)` (§4.2.4.4)**:
   $$\text{Return } \text{controller}.[[\text{strategyHWM}]] - \text{controller}.[[\text{queueTotalSize}]]$$

2. **`WritableStreamDefaultControllerGetBackpressure(controller)` (§4.2.4.12)**:
   * Let `desiredSize` be `! WritableStreamDefaultControllerGetDesiredSize(controller)`.
   * Return `true` if $\text{desiredSize} \le 0$, and `false` otherwise.

3. **`WritableStreamUpdateBackpressure(stream, backpressure)` (§4.1.4.14)**:
   * Assert: `stream.[[state]]` is `"writable"`.
   * Assert: `! WritableStreamCloseQueuedOrInFlight(stream)` is `false`.
   * Let `writer` be `stream.[[writer]]`.
   * If `writer` is not `undefined` and $\text{backpressure} \neq \text{stream}.[[\text{backpressure}]]$:
     * If `backpressure` is `true`, set `writer.[[readyPromise]]` to a new unresolved promise.
     * Otherwise (`backpressure` is `false`), resolve `writer.[[readyPromise]]` with `undefined`.
   * Set `stream.[[backpressure]]` to `backpressure`.

### 1.3 Normative Trigger Points
Backpressure recalculation occurs at three strict lifecycle transitions in `writable_stream_default_controller.cc`:
1. **Controller Start Completion** (`SetUp` / `startAlgorithm` resolution): When `controller.[[started]]` transitions to `true`, backpressure is evaluated against any chunks enqueued while `start()` was pending.
2. **Chunk Enqueue** (`WritableStreamDefaultControllerWrite`): Enqueuing a chunk with size $s \ge 0$ increments `[[queueTotalSize]]` by $s$. If the stream is `"writable"` and not closing, `WritableStreamUpdateBackpressure` is invoked with the newly computed `GetBackpressure(controller)`.
3. **Queue Advancement / Sink Completion** (`WritableStreamDefaultControllerAdvanceQueueIfNeeded` / `FinishInFlightWrite`): When an in-flight write completes and the next chunk is dequeued from `[[queue]]`, `[[queueTotalSize]]` decreases by $s$, and `WritableStreamUpdateBackpressure` is invoked to potentially relieve backpressure and resolve `writer.[[readyPromise]]`.

---

## 2. Chromium Blink Implementation Analysis

In Chromium's Blink rendering engine, the Streams Standard is implemented in C++ directly on top of V8 Oilpan garbage-collected objects (`ScriptWrappable` / `GarbageCollected`). 

### 2.1 Source Mapping (`writable_stream_default_controller.cc`)
In `third_party/blink/renderer/core/streams/writable_stream_default_controller.cc`, the controller delegates queue storage and size tracking to `QueueWithSizes` (`third_party/blink/renderer/core/streams/queue_with_sizes.h`).

```cpp
// third_party/blink/renderer/core/streams/writable_stream_default_controller.cc

double WritableStreamDefaultController::GetDesiredSize(
    const WritableStreamDefaultController* controller) {
  // https://streams.spec.whatwg.org/#writable-stream-default-controller-get-desired-size
  // 1. Return controller.[[strategyHWM]] - controller.[[queueTotalSize]].
  return controller->strategy_high_water_mark_ -
         controller->queue_->TotalSize();
}

bool WritableStreamDefaultController::GetBackpressure(
    const WritableStreamDefaultController* controller) {
  // https://streams.spec.whatwg.org/#writable-stream-default-controller-get-backpressure
  // 1. Let desiredSize be ! WritableStreamDefaultControllerGetDesiredSize(controller).
  double desired_size = GetDesiredSize(controller);
  // 2. Return desiredSize <= 0.
  return desired_size <= 0.0;
}
```

### 2.2 State Mutations and Invariants in Blink
1. **Queue Size Clamping (`QueueWithSizes::DequeueValue`)**:
   Floating-point arithmetic in IEEE-754 can introduce rounding drift when repeatedly adding and subtracting chunk sizes. In `QueueWithSizes`, Blink enforces a strict non-negativity invariant: when `queueTotalSize` is decremented upon dequeue, if the resulting value falls below $0$ (or if the queue becomes empty), `queueTotalSize` is clamped to `0.0`. In discrete integer/fixed-point verification domains ($\mathbb{Z}$), this corresponds to the structural invariant $0 \le \text{queue\_size}$ and $\text{queue} = \emptyset \implies \text{queue\_size} = 0$.
2. **Write Execution (`WritableStreamDefaultController::Write`)**:
   ```cpp
   void WritableStreamDefaultController::Write(
       ScriptState* script_state,
       WritableStreamDefaultController* controller,
       v8::Local<v8::Value> chunk,
       double chunk_size,
       ExceptionState& exception_state) {
     // ... EnqueueValueWithSize ...
     WritableStream* stream = controller->controlled_writable_stream_;
     if (!WritableStream::CloseQueuedOrInFlight(stream) &&
         stream->GetState() == WritableStream::kWritable) {
       bool backpressure = GetBackpressure(controller);
       WritableStream::UpdateBackpressure(script_state, stream, backpressure);
     }
     AdvanceQueueIfNeeded(script_state, controller);
   }
   ```
3. **Idempotence of `WritableStream::UpdateBackpressure`**:
   In `third_party/blink/renderer/core/streams/writable_stream.cc`, `UpdateBackpressure` checks `if (stream->has_backpressure_ != backpressure)` before mutating `writer->ReadyResolver()`. This guarantees that consecutive writes that both exceed `strategy_high_water_mark_` do not repeatedly allocate or orphan pending V8 promises.

---

## 3. Formal Specification in Rocq / Coq

We model the `WritableStream` and `WritableStreamDefaultController` state space in Rocq (Coq) using `ZArith` to represent discrete byte/chunk sizes (e.g., byte lengths in `FetchDataLoader` / `CacheStorage` / `TransformStream` pipelines).

### 3.1 Formal Definitions (`BlinkStreamsWritableStreamBackpressureSemantics.v`)

```coq
(** * BlinkStreamsWritableStreamBackpressureSemantics.v
    Formal verification of WHATWG Streams §4.2 WritableStreamDefaultController
    backpressure signaling as implemented in Chromium Blink:
    third_party/blink/renderer/core/streams/writable_stream_default_controller.cc *)

From Coq Require Import ZArith.
From Coq Require Import Bool.
From Coq Require Import List.
From Coq Require Import Lia.
Import ListNotations.

Open Scope Z_scope.

(** ** 1. Stream and Controller State Types *)

(** Stream lifecycle states per WHATWG Streams §4.1.3 *)
Inductive StreamState : Type :=
  | Writable
  | Erroring
  | Errored
  | Closed.

Scheme Equality for StreamState.

(** Abstract representation of a Writer's [[readyPromise]] state *)
Inductive PromiseState : Type :=
  | PromisePending
  | PromiseResolved
  | PromiseRejected.

Scheme Equality for PromiseState.

(** Queue records: either a WriteRecord with a validated non-negative chunk size,
    or a CloseRecord sentinel (which has size 0 in QueueWithSizes). *)
Inductive QueueEntry : Type :=
  | WriteChunk (chunk_size : Z)
  | CloseSentinel.

(** Compute the contribution of a QueueEntry to [[queueTotalSize]] *)
Definition entry_size (e : QueueEntry) : Z :=
  match e with
  | WriteChunk sz => sz
  | CloseSentinel => 0
  end.

(** Exact sum of sizes in the queue list *)
Fixpoint sum_queue_sizes (q : list QueueEntry) : Z :=
  match q with
  | [] => 0
  | e :: rest => entry_size e + sum_queue_sizes rest
  end.

(** Composite state of WritableStream and WritableStreamDefaultController *)
Record WritableStreamSystem : Type := mkSystem {
  stream_state : StreamState;
  stream_backpressure : bool;
  in_flight_write : bool;
  close_queued_or_in_flight : bool;
  has_writer : bool;
  writer_ready_promise : PromiseState;
  controller_started : bool;
  strategy_hwm : Z;
  queue : list QueueEntry;
  queue_total_size : Z
}.

(** ** 2. Specification Operations (WHATWG §4.1.4 & §4.2.4) *)

(** §4.2.4.4 WritableStreamDefaultControllerGetDesiredSize(controller) *)
Definition get_desired_size (sys : WritableStreamSystem) : Z :=
  sys.(strategy_hwm) - sys.(queue_total_size).

(** §4.2.4.12 WritableStreamDefaultControllerGetBackpressure(controller) *)
Definition get_backpressure (sys : WritableStreamSystem) : bool :=
  Z.leb (get_desired_size sys) 0.

(** Guard predicate: When is the stream eligible for backpressure updates?
    Per §4.2.4.7 step 5.a: !CloseQueuedOrInFlight(stream) && state == "writable" *)
Definition can_update_backpressure (sys : WritableStreamSystem) : bool :=
  andb (negb sys.(close_queued_or_in_flight))
       (StreamState_beq sys.(stream_state) Writable).

(** §4.1.4.14 WritableStreamUpdateBackpressure(stream, backpressure) *)
Definition update_backpressure (sys : WritableStreamSystem) (bp : bool) : WritableStreamSystem :=
  let new_promise :=
    if sys.(has_writer) then
      if Bool.eqb bp sys.(stream_backpressure) then
        sys.(writer_ready_promise)
      else if bp then
        PromisePending
      else
        PromiseResolved
    else
      sys.(writer_ready_promise)
  in
  mkSystem
    sys.(stream_state)
    bp
    sys.(in_flight_write)
    sys.(close_queued_or_in_flight)
    sys.(has_writer)
    new_promise
    sys.(controller_started)
    sys.(strategy_hwm)
    sys.(queue)
    sys.(queue_total_size).

(** QueueWithSizes::EnqueueValueWithSize *)
Definition enqueue_with_size (sys : WritableStreamSystem) (e : QueueEntry) : WritableStreamSystem :=
  let sz := entry_size e in
  mkSystem
    sys.(stream_state)
    sys.(stream_backpressure)
    sys.(in_flight_write)
    sys.(close_queued_or_in_flight)
    sys.(has_writer)
    sys.(writer_ready_promise)
    sys.(controller_started)
    sys.(strategy_hwm)
    (sys.(queue) ++ [e])
    (sys.(queue_total_size) + sz).

(** QueueWithSizes::DequeueValue (with Blink's >= 0 clamp) *)
Definition dequeue_value (sys : WritableStreamSystem) : WritableStreamSystem :=
  match sys.(queue) with
  | [] => sys
  | e :: rest =>
      let raw_new_size := sys.(queue_total_size) - entry_size e in
      let clamped_size := Z.max 0 raw_new_size in
      mkSystem
        sys.(stream_state)
        sys.(stream_backpressure)
        sys.(in_flight_write)
        sys.(close_queued_or_in_flight)
        sys.(has_writer)
        sys.(writer_ready_promise)
        sys.(controller_started)
        sys.(strategy_hwm)
        rest
        clamped_size
  end.

(** §4.2.4.7 WritableStreamDefaultControllerWrite(controller, chunk, chunkSize)
    (Modeling the synchronous enqueue and backpressure update phase prior to
     asynchronous sink completion) *)
Definition controller_write (sys : WritableStreamSystem) (chunk_size : Z) : WritableStreamSystem :=
  let sys1 := enqueue_with_size sys (WriteChunk chunk_size) in
  if can_update_backpressure sys1 then
    let bp := get_backpressure sys1 in
    update_backpressure sys1 bp
  else
    sys1.

(** Dequeue and update backpressure upon sink write completion *)
Definition controller_dequeue_and_update (sys : WritableStreamSystem) : WritableStreamSystem :=
  let sys1 := dequeue_value sys in
  if can_update_backpressure sys1 then
    let bp := get_backpressure sys1 in
    update_backpressure sys1 bp
  else
    sys1.

(** ** 3. Structural System Invariants *)

