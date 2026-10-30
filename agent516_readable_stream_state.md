# Formal Verification Report: ReadableStream State Machine Terminal Invariants

**Target Theory**: `BlinkStreamsReadableStreamStateSemantics.v`  
**Chromium Component**: `third_party/blink/renderer/core/streams/readable_stream.cc`  
**Normative Specification**: WHATWG Streams Standard § 3.3 (General ReadableStream Abstract Operations)  
**Mathematical Property**: The `closed` and `errored` states of a `ReadableStream` are absorbing (terminal) states; no valid abstract operation or internal state transition can exit these states once entered.

---

## 1. Normative WHATWG Specification Requirements

According to the WHATWG Streams Standard (§ 3.1.3 Internal Slots and § 3.3 Abstract Operations), every `ReadableStream` instance possesses an internal `[[state]]` slot whose value is strictly drawn from the set $\{\text{"readable"}, \text{"closed"}, \text{"errored"}\}$.

Upon initialization via `InitializeReadableStream(stream)` (§ 3.3.2):
1. `Set stream.[[state]] to "readable".`
2. `Set stream.[[reader]] to undefined.`
3. `Set stream.[[storedError]] to undefined.`
4. `Set stream.[[disturbed]] to false.`

State transitions are governed exclusively by two primitive abstract operations:

### 1.1. ReadableStreamClose(stream) (§ 3.3.5)
The specification mandates the following exact steps:
1. `Assert: stream.[[state]] is "readable".`
2. `Set stream.[[state]] to "closed".`
3. `Let reader be stream.[[reader]].`
4. `If reader is undefined, return.`
5. `Resolve reader.[[closedPromise]] with undefined.`
6. `If reader implements ReadableStreamDefaultReader,readRequests flushing...`

### 1.2. ReadableStreamError(stream, e) (§ 3.3.6)
The specification mandates the following exact steps:
1. `Assert: stream.[[state]] is "readable".`
2. `Set stream.[[state]] to "errored".`
3. `Set stream.[[storedError]] to e.`
4. `Let reader be stream.[[reader]].`
5. `If reader is undefined, return.`
6. `Reject reader.[[closedPromise]] with e.`
7. `Perform readRequests / readIntoRequests rejection...`

**Normative Invariant**: Both transition operations carry the explicit precondition `Assert: stream.[[state]] is "readable"`. No abstract operation in the standard sets `[[state]]` to `"readable"`, nor does any operation transition `[[state]]` when `[[state]]` is `"closed"` or `"errored"`. Furthermore, higher-level controller operations (`ReadableStreamDefaultControllerClose`, `ReadableStreamDefaultControllerError`, `ReadableByteStreamControllerClose`, `ReadableByteStreamControllerError`) guard calls to `ReadableStreamClose` and `ReadableStreamError` by checking `ReadableStreamDefaultControllerCanCloseOrEnqueue` or explicitly checking `if (stream.[[state]] is not "readable") return`.

---

## 2. Chromium Blink Implementation Details & Invariants

In Chromium's Blink engine (`third_party/blink/renderer/core/streams/readable_stream.h` and `readable_stream.cc`), the internal state machine is implemented directly on the `blink::ReadableStream` GarbageCollected C++ class.

### 2.1. State Representation in C++
In `readable_stream.h`:
```cpp
class CORE_EXPORT ReadableStream : public ScriptWrappable {
  DEFINE_WRAPPERTYPEINFO();
 public:
  enum State : uint8_t { kReadable, kClosed, kErrored };
  // ...
 private:
  State state_ = kReadable;
  bool is_disturbed_ = false;
  Member<ReadableStreamGenericReader> reader_;
  Member<ReadableStreamController> readable_stream_controller_;
  TraceWrapperV8Reference<v8::Value> stored_error_;
};
```

### 2.2. Transition Enforcement in `readable_stream.cc`
In `third_party/blink/renderer/core/streams/readable_stream.cc`, the state mutations are strictly localized to `ReadableStream::Close` and `ReadableStream::Error`:

```cpp
void ReadableStream::Close(ScriptState* script_state, ReadableStream* stream) {
  // https://streams.spec.whatwg.org/# readable-stream-close
  // 1. Assert: stream.[[state]] is "readable".
  DCHECK_EQ(stream->state_, kReadable);

  // 2. Set stream.[[state]] to "closed".
  stream->state_ = kClosed;

  // 3. Let reader be stream.[[reader]].
  ReadableStreamGenericReader* reader = stream->reader_;

  // 4. If reader is undefined, return.
  if (!reader) {
    return;
  }
  // ... Promise resolution and request draining ...
}

void ReadableStream::Error(ScriptState* script_state,
                           ReadableStream* stream,
                           v8::Local<v8::Value> e) {
  // https://streams.spec.whatwg.org/#readable-stream-error
  // 1. Assert: stream.[[state]] is "readable".
  DCHECK_EQ(stream->state_, kReadable);

  // 2. Set stream.[[state]] to "errored".
  stream->state_ = kErrored;

  // 3. Set stream.[[storedError]] to e.
  stream->stored_error_.Reset(script_state->GetIsolate(), e);
  // ... Promise rejection and request draining ...
}
```

### 2.3. Controller Guard Rails
External JS callers and internal Blink networking consumers (`BodyStreamBuffer`, `FetchDataLoader`, `CacheStorage` blob readers, and `ServiceWorker` navigation preload streams) cannot invoke `ReadableStream::Close` or `ReadableStream::Error` directly without passing through controller guards or state predicates:
- `ReadableStreamDefaultController::CanCloseOrEnqueue(controller)` checks `!controller->close_requested_ && controller->controlled_readable_stream_->state_ == kReadable`.
- `ReadableStreamDefaultController::Error(script_state, controller, e)` explicitly checks:
  ```cpp
  ReadableStream* stream = controller->controlled_readable_stream_;
  if (stream->state_ != ReadableStream::kReadable) {
    return;
  }
  controller->ClearAlgorithms();
  ReadableStream::Error(script_state, stream, e);
  ```

Thus, at the C++ operational level, any controller-level signal arriving when `state_ != kReadable` becomes a total no-op (idempotent absorption), while raw stream-level primitive transitions are guarded by `DCHECK_EQ(stream->state_, kReadable)`.

---

## 3. Formal Specification in Rocq/Coq (`BlinkStreamsReadableStreamStateSemantics.v`)

Below is the complete, self-contained Rocq/Coq formalization of the `ReadableStream` state machine, controller guard semantics, multi-step execution traces, and terminal state proofs.

```coq
(** * BlinkStreamsReadableStreamStateSemantics.v
    Formal verification of WHATWG Streams Standard §3.3 and Chromium Blink
    ReadableStream state machine transitions (`readable_stream.cc`).
*)

From Coq Require Import Bool.Bool.
From Coq Require Import ZArith.ZArith.
From Coq Require Import Micega.Lia.
From Coq Require Import Lists.List.
Import ListNotations.

Open Scope Z_scope.

(** ** 1. State and Event Definitions *)

(** Represents `ReadableStream::State` in `readable_stream.h`:
    `enum State : uint8_t { kReadable, kClosed, kErrored };` *)
Inductive StreamState : Type :=
  | kReadable : StreamState
  | kClosed   : StreamState
  | kErrored  : StreamState.

(** Decidable equality and boolean encoding for StreamState *)
Definition stream_state_eqb (s1 s2 : StreamState) : bool :=
  match s1, s2 with
  | kReadable, kReadable => true
  | kClosed, kClosed     => true
  | kErrored, kErrored   => true
  | _, _                 => false
  end.

Lemma stream_state_eqb_eq : forall s1 s2 : StreamState,
  stream_state_eqb s1 s2 = true <-> s1 = s2.
Proof.
  intros [| |] [| |]; simpl; split; intros H; try reflexivity; discriminate.
Qed.

(** Numerical rank mapping for metric monotonicity proofs *)
Definition state_rank (s : StreamState) : Z :=
  match s with
  | kReadable => 0
  | kClosed   => 1
  | kErrored  => 2
  end.

(** Terminal state predicate: a state is terminal iff it is kClosed or kErrored *)
Definition is_terminal (s : StreamState) : bool :=
  match s with
  | kReadable => false
  | kClosed   => true
  | kErrored  => true
  end.

(** ** 2. Stream Model and Internal Slots *)

(** Abstract representation of `blink::ReadableStream` and its associated controller state.
    - `rs_state`: `stream.[[state]]` (`state_`)
    - `rs_disturbed`: `stream.[[disturbed]]` (`is_disturbed_`)
    - `rs_close_requested`: `controller.[[closeRequested]]` (`close_requested_`)
    - `rs_stored_error`: `stream.[[storedError]]` (`stored_error_`, None if undefined, Some err_id if set)
    - `rs_queue_size`: number of chunks currently enqueued in the controller
*)
Record ReadableStreamModel : Type := mkStream {
  rs_state           : StreamState;
  rs_disturbed       : bool;
  rs_close_requested : bool;
  rs_stored_error    : option Z;
  rs_queue_size      : Z
}.

(** Initial stream state corresponding to `InitializeReadableStream` (§3.3.2) *)
Definition init_readable_stream : ReadableStreamModel := {|
  rs_state           := kReadable;
  rs_disturbed       := false;
  rs_close_requested := false;
  rs_stored_error    := None;
  rs_queue_size      := 0
|}.

(** Structural well-formedness invariant of a `ReadableStream` in Blink:
    1. Queue size is non-negative.
    2. If state is `kReadable`, `stored_error` is `None`.
    3. If state is `kClosed`, `stored_error` is `None` and `queue_size` is 0.
    4. If state is `kErrored`, `stored_error` is `Some e` and `queue_size` is 0. *)
Definition stream_wf (st : ReadableStreamModel) : Prop :=
  0 <= st.(rs_queue_size) /\
  match st.(rs_state) with
  | kReadable => st.(rs_stored_error) = None
  | kClosed   => st.(rs_stored_error) = None /\ st.(rs_queue_size) = 0
  | kErrored  => (exists e, st.(rs_stored_error) = Some e) /\ st.(rs_queue_size) = 0
  end.

(** ** 3. Abstract Operations & State Transitions *)

(** Events / Operations that can be applied to a ReadableStream and its controller *)
Inductive StreamOp : Type :=
  | OpEnqueue       : StreamOp
  | OpReadChunk     : StreamOp
  | OpRequestClose  : StreamOp
  | OpClosePrimitive: StreamOp
  | OpError         : Z -> StreamOp
  | OpCancel        : StreamOp.

(** Helper predicate: `ReadableStreamDefaultControllerCanCloseOrEnqueue` (§3.10.4) *)
Definition can_close_or_enqueue (st : ReadableStreamModel) : bool :=
  negb st.(rs_close_requested) && stream_state_eqb st.(rs_state) kReadable.

(** Total functional step semantics modeling Blink's controller & stream methods.
    Note that controller methods guard calls to `ReadableStream::Close` and `ReadableStream::Error`
    so that invalid calls in terminal states are safe no-ops. *)
Definition step_stream (st : ReadableStreamModel) (op : StreamOp) : ReadableStreamModel :=
  match op with
  | OpEnqueue =>
      if can_close_or_enqueue st then
        {| rs_state           := kReadable;
           rs_disturbed       := st.(rs_disturbed);
           rs_close_requested := st.(rs_close_requested);
           rs_stored_error    := None;
           rs_queue_size      := st.(rs_queue_size) + 1 |}
      else st

  | OpReadChunk =>
      if stream_state_eqb st.(rs_state) kReadable then
        if Z.gtb st.(rs_queue_size) 0 then
          let new_q := st.(rs_queue_size) - 1 in
          let should_close := st.(rs_close_requested) && Z.eqb new_q 0 in
          {| rs_state           := if should_close then kClosed else kReadable;
             rs_disturbed       := true;
             rs_close_requested := st.(rs_close_requested);
             rs_stored_error    := None;
             rs_queue_size      := new_q |}
        else
          {| rs_state           := st.(rs_state);
             rs_disturbed       := true;
             rs_close_requested := st.(rs_close_requested);
             rs_stored_error    := st.(rs_stored_error);
             rs_queue_size      := st.(rs_queue_size) |}
      else st

  | OpRequestClose =>
      if can_close_or_enqueue st then
        if Z.eqb st.(rs_queue_size) 0 then
          {| rs_state           := kClosed;
             rs_disturbed       := st.(rs_disturbed);
             rs_close_requested := true;
             rs_stored_error    := None;
             rs_queue_size      := 0 |}
        else
          {| rs_state           := kReadable;
             rs_disturbed       := st.(rs_disturbed);
             rs_close_requested := true;
             rs_stored_error    := None;
             rs_queue_size      := st.(rs_queue_size) |}
      else st

  | OpClosePrimitive =>
      (* Models `ReadableStream::Close` guarded by `state_ == kReadable` and empty queue *)
      if stream_state_eqb st.(rs_state) kReadable && Z.eqb st.(rs_queue_size) 0 then
        {| rs_state           := kClosed;
           rs_disturbed       := st.(rs_disturbed);
           rs_close_requested := true;
           rs_stored_error    := None;
           rs_queue_size      := 0 |}
      else