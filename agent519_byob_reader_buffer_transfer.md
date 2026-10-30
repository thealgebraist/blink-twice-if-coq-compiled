# Formal Verification of BYOB Reader Buffer Detachment and Transfer Clamping in Chromium Blink

**Author**: Formal Methods & Web Platform Networking Research Group  
**Target Source**: `third_party/blink/renderer/core/streams/readable_byte_stream_controller.cc`  
**Normative Specification**: WHATWG Streams Standard §3.8 (ReadableByteStreamController), §4.5 (ReadableStreamBYOBRequest)  
**Formalization Target**: `BlinkStreamsBYOBReaderBufferTransferSemantics.v`  

---

## 1. Normative Specification Requirements

The WHATWG Streams Standard defines the lifecycle of zero-copy byte streams via the `ReadableStreamBYOBReader` and `ReadableByteStreamController` interfaces. When a consumer reads into a provided `ArrayBufferView` using `read(view)`, ownership of the underlying `ArrayBuffer` must be transferred into the stream engine, mutated safely within strictly bounded memory regions, and subsequently transferred back to the consumer upon fulfillment of the read request.

### 1.1 Abstract Operations & Memory Ownership (§3.8 / §3.10)

The specification enforces strict memory isolation and bounds clamping through the following normative algorithms:

1. **`ReadableByteStreamControllerPullInto(controller, view, min, readIntoRequest)`**:
   * **Precondition & Detachment**: Checks `IsDetachedBuffer(view.[[ViewedArrayBuffer]])`. If `true`, rejects `readIntoRequest` with a `TypeError`. Otherwise, executes ` Let buffer be ? TransferArrayBuffer(view.[[ViewedArrayBuffer]])`. This operation detaches the input `ArrayBuffer` in the caller's realm, neutralizing concurrent JavaScript mutation or Use-After-Free (UAF) vulnerabilities during asynchronous network I/O.
   * **Descriptor Construction**: Creates a `PullIntoDescriptor` recording `buffer`, `bufferByteLength`, `byteOffset`, `byteLength` (the maximum capacity requested by the view), `bytesFilled` (initialized to 0), `minimumFill` (`min`), and `elementSize`.

2. **`ReadableByteStreamControllerRespondInternal(controller, bytesWritten)`**:
   * **Bounds Validation**: Asserts that `firstDescriptor.[[bytesFilled]] + bytesWritten <= firstDescriptor.[[byteLength]]`. If an underlying byte source attempts to claim it wrote more bytes than the view's capacity (`byteLength`), the operation throws a `RangeError` before modifying descriptor state.
   * **Buffer Transfer on RespondWithNewView**: In `ReadableByteStreamControllerRespondWithNewView(controller, view)`, the supplied `view.[[ViewedArrayBuffer]]` is validated (`byteOffset` and `byteLength` matching active descriptor constraints) and immediately detached via `TransferArrayBuffer` before replacing `firstDescriptor.[[buffer]]`.

3. **`ReadableByteStreamControllerFillPullIntoDescriptorFromQueue(controller, pullIntoDescriptor)`**:
   * **Transfer Clamping**: Calculates `maxBytesToCopy = pullIntoDescriptor.[[byteLength]] - pullIntoDescriptor.[[bytesFilled]]`. When copying queued chunks (`queueElement`) into the descriptor's buffer, the transfer size is strictly clamped:
     $$\text{bytesToCopy} = \min(\text{totalQueuedBytes}, \text{maxBytesToCopy})$$
   * Because `byteOffset + byteLength <= bufferByteLength` is a structural invariant of `ArrayBufferView` construction, clamping `bytesFilled` to `byteLength` guarantees that:
     $$\text{byteOffset} + \text{bytesFilled} \le \text{bufferByteLength}$$

4. **`ReadableByteStreamControllerCommitPullIntoDescriptor(stream, pullIntoDescriptor)`**:
   * Reconstructs the output `ArrayBufferView` via `ReadableByteStreamControllerConvertPullIntoDescriptor`, which again invokes `TransferArrayBuffer(pullIntoDescriptor.[[buffer]])`, detaching the controller's internal buffer reference and transferring unique ownership to the newly minted view resolved to the reader.

---

## 2. Chromium Blink Implementation Analysis

In Chromium's Blink engine (`third_party/blink/renderer/core/streams/readable_byte_stream_controller.cc`), the abstract operations of WHATWG Streams §3.8 are realized over V8 `DOMArrayBuffer` and `DOMArrayBufferView` wrappers integrated with Oilpan (` GarbageCollected<T>`).

### 2.1 Core Data Structures (`PullIntoDescriptor`)

Within `ReadableByteStreamController::PullIntoDescriptor`, Blink tracks the exact memory geometry of the detached buffer:

```cpp
struct ReadableByteStreamController::PullIntoDescriptor final
    : public GarbageCollected<PullIntoDescriptor> {
  Member<DOMArrayBuffer> buffer;
  const size_t buffer_byte_length;
  size_t byte_offset;
  const size_t byte_length;
  size_t bytes_filled;
  const size_t minimum_fill;
  const size_t element_size;
  const ViewConstructorType view_constructor;
  const ReaderType reader_type;
};
```

### 2.2 Buffer Detachment (`TransferArrayBuffer`)

Blink implements `TransferArrayBuffer` in `readable_byte_stream_controller.cc` (lines 72–91) by delegating to `DOMArrayBuffer::Transfer(v8::Isolate*, v8::Local<v8::Value>, ExceptionState&)`:

```cpp
DOMArrayBuffer* ReadableByteStreamController::TransferArrayBuffer(
    ScriptState* script_state,
    DOMArrayBuffer* buffer,
    ExceptionState& exception_state) {
  DCHECK(!buffer->IsDetached());
  ArrayBufferContents contents;
  if (!buffer->Transfer(script_state->GetIsolate(), contents, exception_state)) {
    return nullptr;
  }
  return DOMArrayBuffer::Create(std::move(contents));
}
```

When `buffer->Transfer(...)` succeeds:
1. The source `DOMArrayBuffer` marks its internal V8 backing store as detached (`IsDetached() == true`) and zeroes out its data pointer and byte length.
2. Ownership of the underlying `ArrayBufferContents` memory block moves into the newly allocated `DOMArrayBuffer` instance stored in `PullIntoDescriptor::buffer` (or the queue entry).
3. If the buffer was non-detachable (e.g., a WebAssembly memory buffer or locked buffer), `Transfer` throws a `TypeError` via `ExceptionState` and aborts the transition before any state mutation occurs.

### 2.3 Transfer Clamping & Invariant Preservation

In `FillPullIntoDescriptorFromQueue` and `RespondInternal`, Blink enforces two critical numerical invariants over `size_t`:

1. **Sub-View Clamping Invariant**:
   ```cpp
   const size_t max_bytes_to_copy =
       pull_into_descriptor->byte_length - pull_into_descriptor->bytes_filled;
   const size_t bytes_to_copy =
       std::min(controller->queue_total_size_, max_bytes_to_copy);
   ```
   Since `bytes_filled` starts at `0` and only increases by `bytes_to_copy <= byte_length - bytes_filled` (or via `RespondInternal` where `bytes_filled + bytes_written > byte_length` triggers `exception_state.ThrowRangeError`), the invariant `bytes_filled <= byte_length` is strictly preserved across all execution paths.

2. **Backing Buffer Boundary Invariant**:
   Upon entry to `PullInto`, the input `DOMArrayBufferView* view` satisfies the V8 typed array structural invariant:
   $$\text{view->byteOffset}() + \text{view->byteLength}() \le \text{view->buffer}()->\text{ByteLength}()$$
   Because `PullIntoDescriptor` captures `buffer_byte_length = buffer->ByteLength()`, `byte_offset = view->byteOffset()`, and `byte_length = view->byteLength()`, the clamped transfer size (`bytes_filled`) obeys:
   $$\text{bytes\_filled} \le \text{byte\_length} \implies \text{byte\_offset} + \text{bytes\_filled} \le \text{buffer\_byte\_length}$$

---

## 3. Formal Specification in Rocq (Coq)

We now construct a self-contained, mechanically verified formalization of Blink's `ReadableByteStreamController` BYOB buffer transfer and clamping semantics in Rocq (`BlinkStreamsBYOBReaderBufferTransferSemantics.v`).

### 3.1 State Space, Types, and Transitions

```coq
(** * BlinkStreamsBYOBReaderBufferTransferSemantics.v
    Formal verification of WHATWG Streams Standard §3.8 & Chromium Blink's
    ReadableByteStreamController BYOB buffer detachment and transfer clamping. *)

From Coq Require Import ZArith.
From Coq Require Import Lia.
From Coq Require Import Bool.
From Coq Require Import List.
Import ListNotations.

Open Scope Z_scope.

(** ** 1. Memory and Buffer Representation *)

(** Represents an ArrayBuffer in V8 / Blink DOMArrayBuffer *)
Record DOMArrayBuffer := mkBuffer {
  buf_id : Z;
  buf_byte_length : Z;
  buf_detached : bool;
  buf_detachable : bool
}.

(** Represents an ArrayBufferView (e.g., Uint8Array, DataView) *)
Record DOMArrayBufferView := mkView {
  view_buffer : DOMArrayBuffer;
  view_byte_offset : Z;
  view_byte_length : Z;
  view_element_size : Z
}.

(** Well-formedness predicate for DOMArrayBufferView enforced by V8 / Blink *)
Definition wf_view (v : DOMArrayBufferView) : Prop :=
  0 <= view_byte_offset v /\
  0 <= view_byte_length v /\
  0 < view_element_size v /\
  0 <= buf_byte_length (view_buffer v) /\
  view_byte_offset v + view_byte_length v <= buf_byte_length (view_buffer v).

(** ** 2. PullIntoDescriptor & Controller Queue Representation *)

Record PullIntoDescriptor := mkDescriptor {
  desc_buffer : DOMArrayBuffer;
  desc_buffer_byte_length : Z;
  desc_byte_offset : Z;
  desc_byte_length : Z;
  desc_bytes_filled : Z;
  desc_minimum_fill : Z;
  desc_element_size : Z
}.

(** Structural invariant of an active PullIntoDescriptor in Blink *)
Definition wf_descriptor (d : PullIntoDescriptor) : Prop :=
  buf_detached (desc_buffer d) = false /\
  buf_byte_length (desc_buffer d) = desc_buffer_byte_length d /\
  0 <= desc_byte_offset d /\
  0 <= desc_byte_length d /\
  0 <= desc_bytes_filled d /\
  desc_bytes_filled d <= desc_byte_length d /\
  desc_byte_offset d + desc_byte_length d <= desc_buffer_byte_length d /\
  0 < desc_element_size d /\
  0 < desc_minimum_fill d /\
  desc_minimum_fill d <= desc_byte_length d.

(** Result of an operation that transfers an ArrayBuffer *)
Inductive TransferResult (A : Type) :=
  | TransferOk (detached_source : DOMArrayBuffer) (result : A)
  | TransferThrowTypeError
  | TransferThrowRangeError.

Arguments TransferOk {A} _ _.
Arguments TransferThrowTypeError {A}.
Arguments TransferThrowRangeError {A}.

(** ** 3. Abstract Operations (§3.8 & Blink Implementation) *)

(** TransferArrayBuffer(script_state, buffer, exception_state)
    Returns (detached_old_buffer, newly_created_buffer) or throws TypeError. *)
Definition transfer_array_buffer (b : DOMArrayBuffer) (new_id : Z)
  : TransferResult DOMArrayBuffer :=
  if buf_detached b then TransferThrowTypeError
  else if negb (buf_detachable b) then TransferThrowTypeError
  else
    let old_buf := mkBuffer (buf_id b) 0 true (buf_detachable b) in
    let new_buf := mkBuffer new_id (buf_byte_length b) false true in
    TransferOk old_buf new_buf.

(** ReadableByteStreamControllerPullInto (§3.8.11)
    Validates view, detaches underlying buffer, constructs PullIntoDescriptor. *)
Definition controller_pull_into
  (v : DOMArrayBufferView) (min_fill : Z) (new_buf_id : Z)
  : TransferResult PullIntoDescriptor :=
  let b := view_buffer v in
  if buf_detached b then TransferThrowTypeError
  else if (min_fill <=? 0) || (view_byte_length v <? min_fill) ||
          (view_element_size v <=? 0) then TransferThrowRangeError
  else
    match transfer_array_buffer b new_buf_id with
    | TransferOk old_b new_b =>
        let desc := mkDescriptor
          new_b
          (buf_byte_length new_b)
          (view_byte_offset v)
          (view_byte_length v)
          0
          min_fill
          (view_element_size v) in
        TransferOk old_b desc
    | TransferThrowTypeError => TransferThrowTypeError
    | TransferThrowRangeError => TransferThrowRangeError
    end.

(** Clamping function used in FillPullIntoDescriptorFromQueue *)
Definition clamp_transfer_bytes (queue_total_size : Z) (d : PullIntoDescriptor) : Z :=
  let max_bytes_to_copy := desc_byte_length d - desc_bytes_filled d in
  Z.min queue_total_size max_bytes_to_copy.

(** FillPullIntoDescriptorFromQueue (§3.8.9) *)
Definition fill_pull_into_descriptor_from_queue
  (queue_total_size : Z) (d : PullIntoDescriptor) : PullIntoDescriptor :=
  let bytes_to_copy := clamp_transfer_bytes queue_total_size d in
  if bytes_to_copy <=? 0 then d
  else
    mkDescriptor
      (desc_buffer d)
      (desc_buffer_byte_length d)
      (desc_byte_offset d)
      (desc_byte_length d)
      (desc_bytes_filled d + bytes_to_copy)
      (desc_minimum_fill d)
      (desc_element_size d).

(** RespondInternal / RespondInClosedState / RespondInReadableState (§3.8.15) *)
Definition controller_respond_internal
  (d : PullIntoDescriptor) (bytes_written : Z)
  : option PullIntoDescriptor :=
  if (bytes_written <? 0) ||
     (desc_byte_length d <? desc_bytes_filled d + bytes_written) then
    None (* Throws RangeError in Blink *)
  else
    Some (mkDescriptor
      (desc_buffer d)
      (desc_buffer_byte_length d)
      (desc_byte_offset d)
      (desc_byte_length d)
      (desc_bytes_filled d + bytes_written)
      (desc_minimum_fill d)
      (desc_element_size d)).

(** RespondWithNewView (§3.8.18) *)
Definition controller_respond_with_new_view
  (d : PullIntoDescriptor) (v : DOMArrayBufferView) (new_