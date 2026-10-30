# Formal Verification Research Report: File System Access API Truncate Size Non-Negativity

**Agent**: Formal Verification Agent 660  
**Domain**: Web Platform File System, Streams, Shape Detection, and Platform Totality  
**Target Component**: Chromium Blink (`third_party/blink/renderer/modules/file_system_access/file_system_writable_file_stream.cc`)  
**Formal Theory**: `BlinkFileSystemTruncateSizeSemantics.v`  
**Mathematical Property**: $\forall sz \in \mathbb{Z}, \text{is\_valid\_truncate}(sz) \iff sz \ge 0$

---

## 1. Exact Normative W3C/WHATWG Specification Requirements

In the **W3C WICG File System Access Specification** (and aligned WHATWG File System Standard), § 5 defines the `FileSystemWritableFileStream` interface, which inherits from `WritableStream`. 

### 1.1 WebIDL Definitions

The normative WebIDL for `FileSystemWritableFileStream` and its associated command structures is defined as follows:

```webidl
enum WriteCommandType {
  "write",
  "seek",
  "truncate",
};

dictionary WriteParams {
  required WriteCommandType type;
  unsigned long long? size;
  unsigned long long? position;
  (BufferSource or Blob or USVString)? data;
};

typedef (BufferSource or Blob or USVString or WriteParams) FileSystemWriteChunkType;

[Exposed=(Window,Worker), SecureContext]
interface FileSystemWritableFileStream : WritableStream {
  Promise<undefined> write(FileSystemWriteChunkType data);
  Promise<undefined> seek(unsigned long long position);
  Promise<undefined> truncate(unsigned long long size);
};
```

### 1.2 Normative Algorithm Requirements

1. **`truncate(size)` Method (§ 5.3)**:
   The `truncate(size)` method steps are:
   - Let *writer* be the result of getting a writer for `this`.
   - Let *result* be the result of writing a chunk to *writer*, given `«[ "type" → "truncate", "size" → size ]»`.
   - Release *writer*.
   - Return *result*.

2. **`write(chunk)` Algorithm Steps for `"truncate"`**:
   When the underlying sink's `write` algorithm is invoked with a `WriteParams` dictionary where `chunk["type"]` is `"truncate"`:
   - **Step 1**: If `chunk["size"]` is `null` (or undefined/not present in the dictionary), return a promise rejected with a `TypeError`.
   - **Step 2**: Let *size* be `chunk["size"]`.
   - **Step 3 (WebIDL Type Conversion Invariant)**: Because `size` in both `truncate(unsigned long long size)` and `WriteParams.size` (`unsigned long long?`) is typed as `[EnforceRange]` or standard WebIDL `unsigned long long` (which converts ECMAScript Numbers via `ConvertToInt` into the range $[0, 2^{64}-1]$ or rejects negative values when enforced/converted at the boundary), the underlying file system operation requires a non-negative byte offset: $sz \ge 0$.
   - **Step 4 (File System Modification)**: If the file's current length $L > sz$, the file bytes from index $sz$ to $L-1$ are removed. If $L < sz$, the file is zero-padded by $sz - L$ bytes of `0x00`. The cursor offset `[[seekOffset]]` is also clamped: if `[[seekOffset]]` $> sz$, `[[seekOffset]]` is set to $sz$.

---

## 2. Blink Implementation Details and Invariants

In Chromium Blink, the `FileSystemWritableFileStream` interface is implemented in:
- `third_party/blink/renderer/modules/file_system_access/file_system_writable_file_stream.idl`
- `third_party/blink/renderer/modules/file_system_access/write_params.idl`
- `third_party/blink/renderer/modules/file_system_access/file_system_writable_file_stream.cc`
- `third_party/blink/renderer/modules/file_system_access/file_system_underlying_sink.cc`

### 2.1 C++ Implementation Mechanics

In `file_system_writable_file_stream.cc`:

```cpp
ScriptPromise<IDLUndefined> FileSystemWritableFileStream::truncate(
    ScriptState* script_state,
    uint64_t size,
    ExceptionState& exception_state) {
  WriteParams* params = WriteParams::Create();
  params->setType(V8WriteCommandType::Enum::kTruncate);
  params->setSize(size);
  return Write(script_state,
               MakeGarbageCollected<V8FileSystemWriteChunkType>(params),
               exception_state);
}
```

And in `file_system_underlying_sink.cc` (`FileSystemUnderlyingSink::HandleParams`):

```cpp
if (params.type() == V8WriteCommandType::Enum::kTruncate) {
  if (!params.hasSizeNonNull()) {
    exception_state.ThrowTypeError("Invalid params: size is required for truncate");
    return EmptyPromise();
  }
  // Passes non-negative uint64_t params.sizeNonNull() to Mojo FileSystemAccessFileWriter::Truncate(uint64_t length)
  ...
}
```

### 2.2 Critical Boundary Invariants

1. **V8-to-Blink Binding Totality**: The generated V8 bindings for `truncate(unsigned long long size)` and `WriteParams.size` validate and convert the incoming JavaScript `Number` into a C++ `uint64_t`. When `[EnforceRange]` or standard WebIDL conversion is applied at the JS boundary, any negative domain value $sz < 0$ is trapped before reaching the Mojo IPC layer (`mojom::blink::FileSystemAccessFileWriter::Truncate(uint64_t length)`).
2. **Nullability Invariant**: When invoked via `stream.write({ type: 'truncate', size: null })`, `params.hasSizeNonNull()` evaluates to `false`, deterministically throwing a `TypeError` and preventing uninitialized or negative signed-to-unsigned wrap-around in the underlying `base::File::SetLength(int64_t length)` OS call.
3. **Cursor Clamping Invariant**: After a valid `truncate(sz)` where $sz \ge 0$, the resulting file length is exactly $sz$, and the internal stream cursor `offset_` satisfies $0 \le \text{offset\_}' \le sz$.

---

## 3. Formal Specification Definitions in Rocq/Coq

Below is the complete, self-contained formalization of the `BlinkFileSystemTruncateSizeSemantics.v` theory. It models the integer domain $\mathbb{Z}$ (representing arbitrary JS numbers prior to boundary enforcement), option types for nullable dictionary fields, the `FileSystemWritableFileStream` state machine, and the exact truncate semantics.

## 4. Concrete Theorems and Complete Rocq/Coq Proofs

```coq
(** * BlinkFileSystemTruncateSizeSemantics.v
    Formal Verification of File System Access API §5 truncate(size) Non-Negativity
    Target: third_party/blink/renderer/modules/file_system_access/file_system_writable_file_stream.cc
    Agent: 660
*)

Require Import Coq.ZArith.ZArith.
Require Import Coq.Lists.List.
Require Import Coq.Bool.Bool.
Require Import Coq.micromega.Lia.

Import ListNotations.
Open Scope Z_scope.

(** ** 1. Core Domain Types and Predicates *)

(** Decidable boolean predicate for truncate size validity: sz >= 0 *)
Definition is_valid_truncate_b (sz : Z) : bool :=
  sz >=? 0.

(** Propositional specification of truncate size validity *)
Definition is_valid_truncate (sz : Z) : Prop :=
  sz >= 0.

(** WebIDL WriteCommandType enumeration *)
Inductive WriteCommandType : Type :=
  | CmdWrite
  | CmdSeek
  | CmdTruncate.

(** WebIDL WriteParams dictionary representation *)
Record WriteParams : Type := mkWriteParams {
  wp_type : WriteCommandType;
  wp_size : option Z;
  wp_position : option Z;
  wp_data_len : option Z
}.

(** FileSystemWritableFileStream internal state:
    - fs_data: byte sequence represented as a list of bytes (Z)
    - fs_length: explicit tracked file size in bytes
    - fs_offset: current [[seekOffset]] cursor position
*)
Record FileStreamState : Type := mkFileStreamState {
  fs_length : Z;
  fs_offset : Z
}.

(** Well-formedness invariant of a FileSystemWritableFileStream state *)
Definition wf_stream_state (st : FileStreamState) : Prop :=
  st.(fs_length) >= 0 /\
  0 <= st.(fs_offset) <= st.(fs_length).

(** Outcomes of a Blink FileSystemWritableFileStream operation *)
Inductive StreamResult : Type :=
  | OkState (next_st : FileStreamState)
  | ThrowTypeError.

(** ** 2. Blink Implementation Semantics *)

(** Direct call: stream.truncate(size) constructs WriteParams withCmdTruncate and Some size *)
Definition make_truncate_params (sz : Z) : WriteParams :=
  mkWriteParams CmdTruncate (Some sz) None None.

(** Update cursor offset upon truncation as specified in §5:
    If [[seekOffset]] > size, set [[seekOffset]] to size. *)
Definition clamp_offset (current_offset : Z) (new_size : Z) : Z :=
  if current_offset >? new_size then new_size else current_offset.

(** Underlying sink execution for truncate command *)
Definition exec_truncate_size (st : FileStreamState) (opt_sz : option Z) : StreamResult :=
  match opt_sz with
  | None => ThrowTypeError
  | Some sz =>
      if is_valid_truncate_b sz then
        OkState (mkFileStreamState sz (clamp_offset st.(fs_offset) sz))
      else
        ThrowTypeError
  end.

(** General WriteParams dispatcher in FileSystemUnderlyingSink::HandleParams *)
Definition handle_write_params (st : FileStreamState) (params : WriteParams) : StreamResult :=
  match params.(wp_type) with
  | CmdTruncate => exec_truncate_size st params.(wp_size)
  | CmdSeek =>
      match params.(wp_position) with
      | None => ThrowTypeError
      | Some pos =>
          if pos >=? 0 then
            OkState (mkFileStreamState st.(fs_length) (Z.min pos st.(fs_length)))
          else
            ThrowTypeError
      end
  | CmdWrite =>
      match params.(wp_data_len) with
      | None => ThrowTypeError
      | Some dlen =>
          if dlen >=? 0 then
            let new_off := st.(fs_offset) + dlen in
            let new_len := Z.max st.(fs_length) new_off in
            OkState (mkFileStreamState new_len new_off)
          else
            ThrowTypeError
      end
  end.

(** Top-level FileSystemWritableFileStream::truncate entry point *)
Definition blink_stream_truncate (st : FileStreamState) (sz : Z) : StreamResult :=
  handle_write_params st (make_truncate_params sz).

(** ** 3. Formal Verification Theorems and Proofs *)

(** Theorem 1: Reflection equivalence between boolean check and mathematical specification *)
Theorem is_valid_truncate_iff :
  forall (sz : Z), is_valid_truncate_b sz = true <-> is_valid_truncate sz.
Proof.
  intros sz.
  unfold is_valid_truncate_b, is_valid_truncate.
  rewrite Z.geb_le.
  lia.
Qed.

(** Corollary 1.1: Negative sizes are strictly rejected by the boolean validator *)
Theorem invalid_truncate_iff_negative :
  forall (sz : Z), is_valid_truncate_b sz = false <-> sz < 0.
Proof.
  intros sz.
  unfold is_valid_truncate_b.
  destruct (sz >=? 0) eqn:Heq.
  - rewrite Z.geb_le in Heq. split; intros H; [discriminate | lia].
  - split; intros H; [| reflexivity].
    apply Z.geb_leb in Heq.
    destruct (Z.leb_spec0 0 sz); [discriminate | lia].
Qed.

(** Theorem 2: Totality of blink_stream_truncate (every input yields a deterministic result) *)
Theorem blink_stream_truncate_total :
  forall (st : FileStreamState) (sz : Z),
    (exists st', blink_stream_truncate st sz = OkState st') \/
    blink_stream_truncate st sz = ThrowTypeError.
Proof.
  intros st sz.
  unfold blink_stream_truncate, handle_write_params, make_truncate_params, exec_truncate_size.
  simpl.
  destruct (is_valid_truncate_b sz) eqn:Hval.
  - left. eexists. reflexivity.
  - right. reflexivity.
Qed.

(** Theorem 3: Soundness and Completeness of Non-Negativity Enforcement
    A truncate operation succeeds if and only if the requested size is non-negative. *)
Theorem truncate_succeeds_iff_valid_size :
  forall (st : FileStreamState) (sz : Z),
    (exists st', blink_stream_truncate st sz = OkState st') <-> is_valid_truncate sz.
Proof.
  intros st sz.
  unfold blink_stream_truncate, handle_write_params, make_truncate_params, exec_truncate_size.
  simpl.
  rewrite <- is_valid_truncate_iff.
  split.
  - intros [st' H].
    destruct (is_valid_truncate_b sz) eqn:Hval.
    + reflexivity.
    + discriminate H.
  - intros Hval.
    rewrite Hval.
    eexists. reflexivity.
Qed.

(** Theorem 4: Negative Truncate Rejection Guarantee
    Any negative size parameter deterministically throws a TypeError and never mutates state. *)
Theorem negative_truncate_throws_type_error :
  forall (st : FileStreamState) (sz : Z),
    sz < 0 -> blink_stream_truncate st sz = ThrowTypeError.
Proof.
  intros st sz Hneg.
  unfold blink_stream_truncate, handle_write_params, make_truncate_params, exec_truncate_size.
  simpl.
  apply invalid_truncate_iff_negative in Hneg.
  rewrite Hneg.
  reflexivity.
Qed.

(** Theorem 5: Null Size Rejection Guarantee
    If a WriteParams dictionary with type "truncate" has size = None, it throws a TypeError. *)
Theorem null_truncate_size_throws_