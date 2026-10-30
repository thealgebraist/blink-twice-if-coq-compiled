# Formal Verification Report: Blink MediaRecorder Chunk Timecode Monotonicity

**Target Component:** `third_party/blink/renderer/modules/mediarecorder/media_recorder.cc`  
**Normative Specification:** W3C MediaStream Recording API, §4.1 (`BlobEvent` `timecode` attribute) and §3.1 (`MediaRecorder` Methods)  
**Formal Theory Module:** `BlinkMediaRecorderTimecodeMonotonicitySemantics.v`  
**Core Invariant:** $\forall c_1, c_2 \in \text{SessionChunks}, \text{seq}(c_1) < \text{seq}(c_2) \implies \text{timecode}(c_1) \le \text{timecode}(c_2)$

---

## 1. Normative W3C Specification Requirements

The W3C MediaStream Recording specification defines the interface for recording `MediaStream` tracks into container blobs (`BlobEvent`). Temporal ordering of emitted media chunks is exposed to the script execution context via the `timecode` attribute of `BlobEvent`.

### 1.1 W3C MediaStream Recording §4.1 (`BlobEvent` Interface)
The `BlobEvent` interface carries the encoded media data payload alongside a `DOMHighResTimeStamp` representing the temporal offset of the chunk:

```webidl
[Exposed=Window]
interface BlobEvent : Event {
  constructor(DOMString type, BlobEventInit eventInitDict);
  [SameObject] readonly attribute Blob data;
  readonly attribute DOMHighResTimeStamp timecode;
};
```

The normative requirements for `timecode` are defined as follows:
1. **Type and Precision:** `timecode` is a `DOMHighResTimeStamp` (a `double` representing milliseconds, accurate to 5 microseconds or subject to High Resolution Time clamping).
2. **Semantic Definition:** "The `timecode` attribute MUST return the difference between the timestamp of the first chunk in the `Blob` and the timestamp of the first chunk in the first `Blob` produced by this recorder, as a `DOMHighResTimeStamp`."
3. **Origin Anchor ($T_0$):** For the initial `BlobEvent` emitted after `start()` is invoked, if the event contains media payload data, its `timecode` offset relative to itself is $0.0$ (or, in absolute epoch implementations, anchored at the initialization timestamp of the first frame).
4. **Monotonicity:** Because media muxers (e.g., WebM `mkvmuxer`, MP4 fragment muxers) process frames in monotonically increasing presentation/capture timestamp order, and `timecode` measures the temporal progression of the first frame in each emitted chunk relative to the session origin, any chunk $c_2$ emitted after $c_1$ within the same recording session must satisfy:
   $$\text{timecode}(c_2) \ge \text{timecode}(c_1)$$

### 1.2 Edge Cases in the Specification
When `requestData()`, `pause()`, or `stop()` is invoked before any media frames have arrived from the underlying `MediaStreamTrack` sources, or when an empty `Blob` (0 bytes) is flushed, the recorder must still emit a `dataavailable` (`BlobEvent`) without violating temporal monotonicity or yielding negative/NaN timestamps.

---

## 2. Blink Implementation & Architectural Invariants

In Chromium's Blink engine, the `MediaRecorder` Web IDL interface is implemented in `third_party/blink/renderer/modules/mediarecorder/media_recorder.cc` and its companion handler `media_recorder_handler.cc`.

### 2.1 Code Path Analysis in `media_recorder.cc`

When the underlying `MediaRecorderHandler` muxes encoded video/audio frames into container chunks (via `WebmMuxer` or `Mp4Muxer`), it invokes `MediaRecorder::WriteData`:

```cpp
void MediaRecorder::WriteData(base::span<const uint8_t> data,
                              double timecode,
                              bool last_in_slice,
                              ErrorEvent* error_event) {
  if (state_ == State::kInactive && !last_in_slice) {
    return;
  }
  if (error_event) {
    ScheduleDispatchEvent(error_event);
  }
  if (!blob_data_) {
    blob_data_ = std::make_unique<BlobData>();
    blob_data_->SetContentType(mime_type_);
  }
  if (!data.empty()) {
    blob_data_->AppendBytes(data);
  }
  if (!last_in_slice) {
    return;
  }
  // Emit the accumulated slice as a BlobEvent with the provided timecode.
  CreateBlobEvent(MakeGarbageCollected<Blob>(
                      BlobDataHandle::Create(std::move(blob_data_), ...)),
                  timecode);
}
```

And the event creation helper:

```cpp
void MediaRecorder::CreateBlobEvent(Blob* blob, double timecode) {
  ScheduleDispatchEvent(MakeGarbageCollected<BlobEvent>(
      event_type_names::kDataavailable, blob, timecode));
}
```

### 2.2 Timestamp Generation & Clamping Invariants

In `MediaRecorderHandler` and the underlying muxer pipeline (`cc::VideoFrame` / `media::AudioBus` $\to$ `Muxer` $\to$ `MediaRecorder::WriteData`), timestamps are derived from `base::TimeTicks` (a monotonic clock guaranteed by the OS kernel, e.g., `CLOCK_MONOTONIC` on POSIX, `QueryPerformanceCounter` on Windows).

However, multi-track asynchronous arrival (audio vs. video threads), encoder buffering, and synchronous `StopRecording()` flushes introduce three critical state transitions that must be guarded to guarantee `chunk_timecode(c2) >= chunk_timecode(c1)`:

1. **Multi-Track Interleaving & Muxer Timestamp Clamping:**
   Audio and video encoders operate on separate task runners (`AudioEncoder` vs. `VideoTrackRecorder`). A video keyframe captured at $t = 100\text{ms}$ may finish encoding *after* an audio frame captured at $t = 105\text{ms}$. The muxer (`WebmMuxer::OnEncodedVideo` / `OnEncodedAudio`) maintains `last_timestamp_written_` and clamps incoming frame timestamps:
   $$t_{\text{clamped}} = \max(t_{\text{incoming}}, t_{\text{last\_emitted}})$$
2. **Accumulation Slices (`last_in_slice == false`):**
   `WriteData` may be called multiple times before `last_in_slice == true` triggers `CreateBlobEvent`. The timecode associated with the emitted `BlobEvent` must reflect the monotonic progression of the slice boundary.
3. **Final Empty Flush on `StopRecording()`:**
   When `stop()` is called, if all buffered data was already flushed via `requestData()`, `StopRecording()` calls `WriteData({}, /*last_in_slice=*/true, ...)`. If the caller passes `base::Time::Now()` or tracks the last emitted timestamp, the timecode of the terminal empty `BlobEvent` must not regress below the previously emitted chunk's timecode (e.g., passing `0.0` on an empty flush when prior chunks had $t > 0$ would violate monotonicity).

### 2.3 Abstract State Machine Model

We formalize the Blink `MediaRecorder` chunk emission pipeline as a deterministic state transition system $\mathcal{S} = (\Sigma, \mathcal{I}, \delta)$:

- **State ($\Sigma$):**
  - `state`: $\text{Inactive} \mid \text{Recording} \mid \text{Paused}$
  - `origin_ts`: $\text{option } \mathbb{Z}$ (the `base::TimeTicks` of the first frame in the recording session, if established)
  - `last_timecode`: $\mathbb{Z}$ (the most recently emitted chunk timecode, initialized to $0$)
  - `slice_buffer_nonempty`: $\mathbb{B}$ (whether `blob_data_` currently holds uncommitted bytes)
  - `slice_first_ts`: $\text{option } \mathbb{Z}$ (capture timestamp of the first frame in the current accumulating slice)
  - `emitted_chunks`: $\text{list Chunk}$ (history of dispatched `BlobEvent`s)

- **Inputs ($\mathcal{I}$):**
  - `WriteFrame(payload_size, capture_ts, last_in_slice)`
  - `FlushEmpty(flush_ts)` (triggered by `requestData()` or `stop()` when buffers are empty)
  - `Pause` / `Resume` / `Stop`

---

## 3. Formal Specification in Rocq (Coq)

Below is the complete, self-contained formalization of `BlinkMediaRecorderTimecodeMonotonicitySemantics.v`. It models the Blink `MediaRecorder` slice accumulation, origin anchoring, monotonic clamping, and lifecycle transitions using integer arithmetic (`ZArith`) representing microsecond/millisecond ticks.

```coq
(** * BlinkMediaRecorderTimecodeMonotonicitySemantics.v
    Formal verification of W3C MediaStream Recording §4.1 and Chromium Blink
    third_party/blink/renderer/modules/mediarecorder/media_recorder.cc
    chunk timecode progression monotonicity. *)

From Coq Require Import ZArith.
From Coq Require Import Bool.
From Coq Require Import List.
From Coq Require Import Lia.
Import ListNotations.

Open Scope Z_scope.

(** ** 1. Basic Types and Data Structures *)

(** Lifecycle states of Blink's MediaRecorder (media_recorder.h) *)
Inductive RecorderState : Type :=
  | StateInactive
  | StateRecording
  | StatePaused.

(** Equality decidability for RecorderState *)
Definition state_eqb (s1 s2 : RecorderState) : bool :=
  match s1, s2 with
  | StateInactive, StateInactive => true
  | StateRecording, StateRecording => true
  | StatePaused, StatePaused => true
  | _, _ => false
  end.

(** Representation of an emitted BlobEvent (MediaStream Recording §4.1) *)
Record Chunk : Type := mkChunk {
  chunk_seq : nat;        (** Monotonic sequence index in session *)
  chunk_size : Z;         (** Size of Blob data in bytes (>= 0) *)
  chunk_timecode : Z      (** BlobEvent.timecode in monotonic ticks *)
}.

(** Internal state of MediaRecorder + MediaRecorderHandler muxer pipeline *)
Record RecorderMachine : Type := mkMachine {
  rm_state : RecorderState;
  rm_origin_ts : option Z;       (** Timestamp of first frame in session *)
  rm_last_timecode : Z;          (** Monotonic high-water mark of emitted timecodes *)
  rm_slice_first_ts : option Z;  (** Timestamp of first frame in current accumulating slice *)
  rm_slice_bytes : Z;            (** Accumulated bytes in current blob_data_ *)
  rm_emitted : list Chunk        (** Chronological list of emitted BlobEvents (head = oldest) *)
}.

(** Initial state upon MediaRecorder construction or after StopRecording() reset *)
Definition initial_machine : RecorderMachine := {|
  rm_state := StateInactive;
  rm_origin_ts := None;
  rm_last_timecode := 0;
  rm_slice_first_ts := None;
  rm_slice_bytes := 0;
  rm_emitted := []
|}.

(** ** 2. Timestamp Clamping & Relative Timecode Computation *)

(** Clamps a candidate relative timecode against the high-water mark
    rm_last_timecode, modeling Blink's std::max(timecode, last_timecode)
    and non-negativity invariant. *)
Definition clamp_timecode (candidate last_tc : Z) : Z :=
  Z.max last_tc (Z.max 0 candidate).

(** Computes the relative timecode given an optional session origin and raw timestamp.
    Per W3C MediaStream Recording §4.1: difference between timestamp of first chunk
    in Blob and timestamp of first chunk in first Blob. *)
Definition compute_raw_relative (origin : Z) (frame_ts : Z) : Z :=
  frame_ts - origin.

(** ** 3. Step Semantics of MediaRecorder::WriteData and Lifecycle *)

(** Actions processed by the MediaRecorder state machine *)
Inductive RecorderAction : Type :=
  | ActStart
  | ActPause
  | ActResume
  | ActWriteData (bytes : Z) (capture_ts : Z) (last_in_slice : bool)
  | ActRequestData (now_ts : Z)
  | ActStop (now_ts : Z).

(** Helper to emit a BlobEvent and reset slice accumulation state *)
Definition emit_blob_event (m : RecorderMachine) (origin : option Z)
                           (bytes : Z) (candidate_tc : Z) (next_state : RecorderState)
  : RecorderMachine :=
  let clamped_tc := clamp_timecode candidate_tc (rm_last_timecode m) in
  let new_chunk := {|
    chunk_seq := List.length (rm_emitted m);
    chunk_size := Z.max 0 bytes;
    chunk_timecode := clamped_tc
  |} in
  {|
    rm_state := next_state;
    rm_origin_ts := origin;
    rm_last_timecode := clamped_tc;
    rm_slice_first_ts := None;
    rm_slice_bytes := 0;
    rm_emitted := rm_emitted m ++ [new_chunk]
  |}.

(** Core step function modeling media_recorder.cc & media_recorder_handler.cc *)
Definition step (m : RecorderMachine) (a : RecorderAction) : RecorderMachine :=
  match a with
  | ActStart =>
      match rm_state m with
      | StateInactive =>
          {| rm_state := StateRecording;
             rm_origin_ts := None;
             rm_last_timecode := 0;
             rm_slice_first_ts := None;
             rm_slice_bytes := 0;
             rm_emitted := [] |}
      | _ => m
      end

  | ActPause =>
      match rm_state m with
      | StateRecording =>
          {| rm_state := StatePaused;
             rm_origin_ts := rm_origin_ts m;
             rm_last_timecode := rm_last_timecode m;
             rm_slice_first_ts := rm_slice_first_ts m;
             rm_slice_bytes := rm_slice_bytes m;
             rm_emitted := rm_emitted m |}
      | _ => m
      end

  | ActResume =>
      match rm_state m with
      | StatePaused =>
          {| rm_state := StateRecording;
             rm_origin_ts := rm_origin_ts m;
             rm_last_timecode := rm_last_timecode m;
             rm_slice_first_ts := rm_slice_first_ts m;
             rm_slice_bytes := rm_slice_bytes m;
             rm_emitted := rm_emitted m |}
      | _ => m
      end

  | ActWriteData bytes capture_ts last_in_slice =>
      (* In media_recorder.cc: if (state_ == State::kInactive && !last_in_slice) return; *)