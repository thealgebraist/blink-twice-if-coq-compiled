# Formal Verification of TransformStream Pipe Throughput Conservation in Chromium Blink

**Formal Theory Target**: `BlinkStreamsTransformStreamConservationSemantics.v`  
**Chromium Component**: `third_party/blink/renderer/core/streams/transform_stream.cc`  
**Normative Specification**: WHATWG Streams Standard §5.2  
**Core Invariant**: $\text{chunks\_out} = \text{chunks\_in} - \text{queued}$ (for Identity Transform Streams)

---

## 1. Normative Specification Analysis (WHATWG Streams Standard §5.2)

The WHATWG Streams Standard defines a `TransformStream` as a pair of a `WritableStream` (the writable side) and a `ReadableStream` (the readable side) coupled through a shared internal controller (`TransformStreamDefaultController`). In §5.2 (*TransformStream* and *TransformStreamDefaultController* abstract operations), data movement across the transform boundary is governed by strict queueing and backpressure state machines.

### 1.1 Normative Abstract Operations

1. **`TransformStreamDefaultSinkWriteAlgorithm(chunk)` (§5.2.5.1)**:
   - Invoked when the writable side's `WritableStreamDefaultController` processes a chunk.
   - Delegates directly to `TransformStreamDefaultControllerPerformTransform(controller, chunk)`.

2. **`TransformStreamDefaultControllerPerformTransform(controller, chunk)` (§5.2.4.5)**:
   - Invokes the user-supplied `[[transformAlgorithm]]` with `chunk`.
   - For an **Identity Transform Stream** (or the default transform algorithm when `transform()` is omitted from the transformer dictionary, §5.2.2 Step 7), the default `transformAlgorithm` executes:
     $$\text{ Let } \textit{result} \text{ be } \text{TransformStreamDefaultControllerEnqueue}(\textit{controller}, \textit{chunk}).$$
   - If the operation throws, the stream transitions to an `errored` state via `TransformStreamError(stream, e)`. Otherwise, it returns a promise resolved with `undefined`.

3. **`TransformStreamDefaultControllerEnqueue(controller, chunk)` (§5.2.4.3)**:
   - Let `stream` be `controller.[[stream]]`.
   - Let `readableController` be `stream.[[readable]].[[controller]]`.
   - If `ReadableStreamDefaultControllerCanCloseOrEnqueue(readableController)` is `false`, throw a `TypeError` (violating state machine preconditions).
   - Call `ReadableStreamDefaultControllerEnqueue(readableController, chunk)`.
   - Compute backpressure: Let `backpressure` be `ReadableStreamDefaultControllerHasBackpressure(readableController)`.
   - If `backpressure` is not `stream.[[backpressure]]`, update `stream.[[backpressure]]` to `true` via `TransformStreamSetBackpressure(stream, true)`.

4. **`ReadableStreamDefaultControllerEnqueue(controller, chunk)` (§4.3.5.5)**:
   - If `ReadableStreamGetNumReadRequests(stream) > 0`, the chunk bypasses the internal queue and is immediately passed to `ReadableStreamFulfillReadRequest(stream, chunk, false)`. This increments the consumer's received chunk count ($\text{chunks\_out} \leftarrow \text{chunks\_out} + 1$) while leaving the queue size unchanged ($\text{queued} \leftarrow 0$).
   - If `ReadableStreamGetNumReadRequests(stream) == 0`, the chunk is appended to `controller.[[queue]]` via `EnqueueValueWithSize`. This leaves $\text{chunks\_out}$ unchanged and increments the internal queue occupancy ($\text{queued} \leftarrow \text{queued} + 1$).

5. **`ReadableStreamDefaultReaderRead(reader, readRequest)` (§4.4.4.4)**:
   - If `controller.[[queue]]` is non-empty (`queued > 0`), `DequeueValue(controller)` removes the head chunk ($\text{queued} \leftarrow \text{queued} - 1$) and immediately invokes `readRequest.chunkSteps(chunk)` ($\text{chunks\_out} \leftarrow \text{chunks\_out} + 1$).
   - If `controller.[[queue]]` is empty (`queued == 0`), the `readRequest` is appended to `reader.[[readRequests]]` ($\text{pending\_reads} \leftarrow \text{pending\_reads} + 1$).

### 1.2 Throughput Conservation Law
Across all non-error state transitions of an identity `TransformStream`, every chunk successfully processed by `TransformStreamDefaultSinkWriteAlgorithm` ($\text{chunks\_in}$) is either:
1. Immediately dispatched to a waiting reader ($\Delta \text{chunks\_out} = +1, \Delta \text{queued} = 0$), or
2. Retained in `readable.[[controller]].[[queue]]` ($\Delta \text{chunks\_out} = 0, \Delta \text{queued} = +1$), and subsequently drained by `ReadableStreamDefaultReaderRead` ($\Delta \text{chunks\_out} = +1, \Delta \text{queued} = -1$).

Thus, the global conservation invariant holds across all reachable states:
$$\text{chunks\_out} = \text{chunks\_in} - \text{queued} \iff \text{chunks\_in} = \text{chunks\_out} + \text{queued}$$

---

## 2. Chromium Blink Implementation Analysis

In Chromium's Blink engine, the Streams Standard is implemented in `third_party/blink/renderer/core/streams/`. Specifically, `transform_stream.cc` and its collaborators (`readable_stream_default_controller.cc`, `writable_stream_default_controller.cc`, `queue_with_sizes.cc`) implement the specification's abstract operations in C++ on top of Oilpan (Blink's garbage collector) and V8 promises.

### 2.1 Architecture in `transform_stream.cc`

1. **Identity Transform Algorithm (`DefaultTransformAlgorithm`)**:
   When a `TransformStream` is constructed without a custom `transform` method (or via `TransformStream::CreateIdentityTransformStream` used internally by `Response::body`, `CompressionStream` pass-throughs, and `ServiceWorker` synthetic responses), Blink instantiates a default `StreamStartAlgorithm` and `TransformStreamDefaultController::DefaultTransformAlgorithm`.
   ```cpp
   // Conceptual mapping from third_party/blink/renderer/core/streams/transform_stream.cc
   ScriptPromise<IDLUndefined> TransformStream::DefaultTransformAlgorithm(
       ScriptState* script_state,
       TransformStreamDefaultController* controller,
       v8::Local<v8::Value> chunk,
       ExceptionState& exception_state) {
     TransformStreamDefaultController::Enqueue(script_state, controller, chunk,
                                               exception_state);
     if (exception_state.HadException()) {
       return EmptyPromise();
     }
     return ToResolvedUndefinedPromise(script_state);
   }
   ```

2. **Enqueue and Queue Delegation (`TransformStreamDefaultController::Enqueue`)**:
   `TransformStreamDefaultController::Enqueue` retrieves `stream->readable_->GetController()` (a `ReadableStreamDefaultController*`) and invokes `ReadableStreamDefaultController::Enqueue(script_state, readable_controller, chunk, exception_state)`.
   Inside `ReadableStreamDefaultController::Enqueue`:
   - It checks `ReadableStream::GetNumReadRequests(stream) == 0`.
   - If `false` (there are pending reads in `reader->read_requests_`), it calls `ReadableStream::FulfillReadRequest(script_state, stream, chunk, false)`, popping from `read_requests_` (`HeapDeque<Member<ReadRequest>>`) and resolving the V8 Promise / invoking `ChunkSteps`.
   - If `true` (no pending reads), it calls `queue_->EnqueueValueWithSize(...)`, which pushes a `ValueWithSize` struct onto `QueueWithSizes::queue_` (`HeapDeque<ValueWithSize>`).

3. **Backpressure Synchronization (`TransformStream::SetBackpressure`)**:
   Blink maintains `bool backpressure_` and `Member<StreamPromiseResolver> backpressure_change_promise_` on `TransformStream`.
   - When `ReadableStreamDefaultController::HasBackpressure()` transitions to `true` (i.e., `queue_->TotalQueueSize() >= strategy_high_water_mark_`), `SetBackpressure` updates `backpressure_ = true`.
   - When the readable side drains via `ReadableStreamDefaultReader::Read` and `TotalQueueSize()` drops below the high water mark, `TransformStreamDefaultSourcePullAlgorithm` resolves `backpressure_change_promise_` and sets `backpressure_ = false`, unblocking `TransformStreamDefaultSinkWriteAlgorithm`.

### 2.2 Blink Implementation Invariants

To guarantee memory safety, absence of chunk loss, and throughput conservation in `transform_stream.cc`, Blink relies on four structural invariants:
- **Invariant B1 (Mutual Exclusion of Queue and Read Requests)**: In `ReadableStreamDefaultController`, `(queue_->IsEmpty()) || (GetNumReadRequests(stream) == 0)`. A stream cannot simultaneously hold buffered chunks in `QueueWithSizes` and have unfulfilled `ReadRequest` objects in `ReadableStreamDefaultReader::read_requests_`.
- **Invariant B2 (Non-Negative Queue Occupancy)**: The number of elements in `QueueWithSizes::queue_` is always $\ge 0$, bounded above by available heap memory and regulated by `strategy_high_water_mark_`.
- **Invariant B3 (Atomic Handoff in Identity Enqueue)**: In `DefaultTransformAlgorithm`, if `ReadableStreamDefaultController::CanCloseOrEnqueue` is true and `ValueWithSize` validation succeeds, the chunk is either added to `queue_` or passed to `FulfillReadRequest` synchronously within the same V8 microtask turn before returning the resolved promise to `WritableStreamDefaultController`.
- **Invariant B4 (Pipe Conservation)**: Across `ReadableStream::PipeTo` (`pipe_to_engine.cc`) connected to an identity `TransformStream`, the difference between chunks written to the sink and chunks read from the source equals the length of `QueueWithSizes::queue_`.

---

## 3. Formal Specification in Rocq/Coq

Below is the complete, self-contained formalization of `BlinkStreamsTransformStreamConservationSemantics.v`. It models the exact state machine of `third_party/blink/renderer/core/streams/transform_stream.cc` and `readable_stream_default_controller.cc`, including backpressure states, queue sizes, pending read requests, and multi-stage pipelines.

```coq
(** * BlinkStreamsTransformStreamConservationSemantics.v
    Formal Verification of TransformStream Pipe Throughput Conservation
    Target: third_party/blink/renderer/core/streams/transform_stream.cc
    Specification: WHATWG Streams Standard §5.2
*)

From Coq Require Import ZArith.
From Coq Require Import Lia.
From Coq Require Import Bool.
From Coq Require Import List.
Import ListNotations.

Open Scope Z_scope.

(** ** 1. Stream Lifecycle and Controller States *)

(** Represents the state of the underlying ReadableStream (§4.2) *)
Inductive ReadableState : Type :=
  | RReadable
  | RClosed
  | RErrored.

(** Represents the state of the underlying WritableStream (§3.2) *)
Inductive WritableState : Type :=
  | WWritable
  | WClosing
  | WClosed
  | WErrored.

(** Scheme for structural equality on stream states *)
Definition readable_state_eqb (s1 s2 : ReadableState) : bool :=
  match s1, s2 with
  | RReadable, RReadable => true
  | RClosed, RClosed => true
  | RErrored, RErrored => true
  | _, _ => false
  end.

Definition writable_state_eqb (s1 s2 : WritableState) : bool :=
  match s1, s2 with
  | WWritable, WWritable => true
  | WClosing, WClosing => true
  | WClosed, WClosed => true
  | WErrored, WErrored => true
  | _, _ => false
  end.

(** ** 2. TransformStream State Representation (transform_stream.cc) *)

(** Models the combined state of a Blink TransformStream, its
    TransformStreamDefaultController, and the paired ReadableStreamDefaultController.
    All counters are modeled in Z to seamlessly support algebraic conservation laws. *)
Record TransformStreamState : Type := mkTS {
  ts_chunks_in       : Z;            (** Total chunks accepted by DefaultSinkWriteAlgorithm *)
  ts_chunks_out      : Z;            (** Total chunks delivered to reader via ReadRequest *)
  ts_queued          : Z;            (** Current occupancy of QueueWithSizes (queue_) *)
  ts_pending_reads   : Z;            (** Length of reader->read_requests_ *)
  ts_high_water_mark : Z;            (** Readable side strategy_high_water_mark_ *)
  ts_backpressure    : bool;         (** TransformStream::backpressure_ *)
  ts_close_requested : bool;         (** ReadableStreamDefaultController::close_requested_ *)
  ts_readable_state  : ReadableState;(** stream->readable_->state_ *)
  ts_writable_state  : WritableState (** stream->writable_->state_ *)
}.

(** Initial state constructed by TransformStream::Create / InitInternal *)
Definition init_transform_stream (hwm : Z) : TransformStreamState :=
  mkTS 0 0 0 0 hwm true false RReadable WWritable.

(** ** 3. WHATWG Streams §4 & §5 Abstract Operations *)

(** §4.3.5.2 ReadableStreamDefaultControllerCanCloseOrEnqueue *)
Definition can_close_or_enqueue (s : TransformStreamState) : bool :=
  negb (ts_close_requested s) && readable_state_eqb (ts_readable_state s) RReadable.

(** §4.3.5.7 ReadableStreamDefaultControllerGetDesiredSize (for unit-sized chunks) *)
Definition get_desired_size (s : TransformStreamState) : Z :=
  (ts_high_water_mark s) - (ts_queued s).

(** §4.3.5.8 ReadableStreamDefaultControllerHasBackpressure *)
Definition has_backpressure (s : TransformStreamState) : bool :=
  Z.leb (get_desired_size s) 0.

(** §5.2.4.3 TransformStreamDefaultControllerEnqueue &
    §5.2.4.5 TransformStreamDefaultControllerPerformTransform (Identity)
    Models DefaultTransformAlgorithm in transform_stream.cc *)
Definition step_identity_write (s : TransformStreamState) : TransformStreamState :=
  if can_close_or_enqueue s then
    if Z.gtb (ts_pending_reads s) 0 then
      (* Fast-path: ReadableStream::GetNumReadRequests > 0 -> FulfillReadRequest *)
      mkTS (ts_chunks_in s + 1)
           (ts_chunks_out s + 1)
           (ts_queued s)
           (ts_pending_reads s - 1)
           (ts_high_water_mark s)
           (ts_backpressure s)
           (ts_close_requested s)
           (ts_readable_state s)
           (ts_writable_state s)
    else
      (* Queue-path: EnqueueValueWithSize into QueueWithSizes *)
      let new_queued := ts_queued s + 1 in
      let new_bp := Z.leb ((ts_high_water_mark s) - new_queued) 0 in
      mkTS (ts_chunks_in s