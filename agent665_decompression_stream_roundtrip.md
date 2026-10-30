# Formal Verification Report: Compression Streams Decompression Roundtrip Length Preservation

**Agent**: Formal Verification Agent 665  
**Specialization**: Web Platform File System, Streams, Shape Detection, and Platform Totality in Chromium Blink  
**Topic**: Compression Streams decompression roundtrip length preservation  
**Chromium Source**: `third_party/blink/renderer/modules/compression/decompression_stream.cc`  
**Specification**: WHATWG Compression Streams §3 (`DecompressionStream` interface)  
**Formal Theory Target**: `BlinkDecompressionStreamRoundtripSemantics.v`  
**Mathematical Property**: $\text{decompress\_len}(\text{compress}(\text{raw})) = \text{raw\_len}$

---

## 1. Normative WHATWG Specification Requirements

The WHATWG Compression Streams Living Standard defines the `CompressionStream` and `DecompressionStream` APIs on top of the WHATWG Streams Standard (`TransformStream`).

### 1.1 Section 2 & 3: Compression and Decompression Contexts
1. **Supported Formats**: Both streams support `"deflate"` (ZLIB data format, RFC 1950), `"deflate-raw"` (DEFLATE compressed data format, RFC 1951), and `"gzip"` (GZIP file format, RFC 1952).
2. **Compression Transform & Flush (§2)**:
   - Given a sequence of input `BufferSource` chunks $C_{\text{in}} = [c_1, c_2, \dots, c_n]$, the `compress and enqueue a chunk` algorithm feeds each chunk $c_i$ into the lossless compression context.
   - Upon stream closure, `compress flush and finish` signals the end of the input and emits any remaining compressed bytes, yielding an output chunk sequence $C_{\text{comp}} = [z_1, z_2, \dots, z_m]$.
3. **Decompression Transform & Flush (§3)**:
   - A `DecompressionStream` has an associated **format** and **context**.
   - **Transform Algorithm (`decompress and enqueue a chunk`)**:
     1. If *chunk* is not a `BufferSource` type, throw a `TypeError`.
     2. Decompress *chunk* using *ds*'s format and context. If this results in an error, throw a `TypeError`.
     3. If no output is produced, return.
     4. Split produced bytes into one or more non-empty `Uint8Array` chunks and enqueue each into *ds*'s transform.
     5. If the end of the compressed input has been reached and there are still unconsumed bytes in *chunk* (trailing junk), throw a `TypeError`.
   - **Flush Algorithm (`decompress flush and finish`)**:
     1. Decompress the empty input with the finish flag using *ds*'s format and context.
     2. If the end of the compressed input has not been reached (truncated stream), throw a `TypeError`.
     3. Enqueue any remaining produced output chunks.

### 1.2 Roundtrip Totality and Length Invariant
Because RFC 1950 (`deflate`), RFC 1951 (`deflate-raw`), and RFC 1952 (`gzip`) are lossless compression specifications, any sequence of raw byte chunks $C_{\text{in}}$ processed through a `CompressionStream` (including its flush phase) and subsequently piped through a `DecompressionStream` of the identical format (including its flush phase) must reconstruct a byte sequence $C_{\text{out}}$ whose flattened byte concatenation is identical to the flattened byte concatenation of $C_{\text{in}}$. Consequently, the total byte length across all output chunks equals the total byte length across all input chunks:

$$\sum_{u \in C_{\text{out}}} |u| = \sum_{c \in C_{\text{in}}} |c|$$

---

## 2. Blink Implementation Details and Invariants

In Chromium Blink, `DecompressionStream` and its underlying transformer are implemented across:
- `third_party/blink/renderer/modules/compression/decompression_stream.cc`
- `third_party/blink/renderer/modules/compression/inflate_transformer.cc`
- `third_party/blink/renderer/modules/compression/deflate_transformer.cc` (the dual compression transformer)

### 2.1 Architecture in `decompression_stream.cc`
`DecompressionStream::DecompressionStream(ScriptState* script_state, const AtomicString& format, ExceptionState& exception_state)` performs:
1. Format validation via `LookupCompressionFormat(format, exception_state)`, mapping `"gzip"`, `"deflate"`, and `"deflate-raw"` to `CompressionFormat::kGzip`, `CompressionFormat::kDeflate`, and `CompressionFormat::kDeflateRaw`.
2. Instantiation of `TransformStream::Create(script_state, MakeGarbageCollected<InflateTransformer>(script_state, compression_format), exception_state)`.

### 2.2 Stream Transformation Invariants in `InflateTransformer` & `DeflateTransformer`
Both transformers wrap `third_party/zlib` (`z_stream`) and execute streaming buffer transformations using fixed-size output buffers (`kBufferSize = 16384` bytes, i.e., 16 KiB):

1. **Chunk Fragmentation Invariant**:
   - In `DeflateTransformer::Deflate()` and `InflateTransformer::Inflate()`, input `DOMArrayBufferView` or `DOMArrayBuffer` chunks are passed to `deflate(&stream_, finish ? Z_FINISH : Z_NO_FLUSH)` or `inflate(&stream_, finish ? Z_FINISH : Z_NO_FLUSH)` inside a `do { ... } while (stream_.avail_out == 0)` loop.
   - At each iteration, `bytes = kBufferSize - stream_.avail_out` bytes are emitted via `controller->Enqueue(DOMUint8Array::Create(out_buffer, bytes))` whenever `bytes > 0`.
2. **Stream Boundary Independence**:
   - The `z_stream` maintains internal sliding window (LZ77 32 KiB window) and Huffman state across calls to `Transform()`.
   - Regardless of how the caller partitions the input stream into `Uint8Array` chunks (or how `kBufferSize` partitions the emitted compressed/decompressed chunks), the concatenated stream of bytes processed by `z_stream` is invariant.
3. **Flush Completeness and Trailing/Truncated Checks**:
   - When `DeflateTransformer::Flush()` executes with `Z_FINISH`, `deflate` returns `Z_STREAM_END`, guaranteeing a complete RFC-compliant frame with checksums/footers.
   - When `InflateTransformer::Inflate()` receives the final bytes of a valid frame, `inflate` returns `Z_STREAM_END` (`was_stream_end_reached_ = true`). If `stream_.avail_in > 0` or subsequent chunks arrive after `was_stream_end_reached_`, Blink throws a `TypeError` ("Junk found after the end of the compressed data").
   - In `InflateTransformer::Flush()`, if `!was_stream_end_reached_`, Blink throws a `TypeError` ("Compressed input was truncated").

Because `DeflateTransformer` followed by `Flush()` emits a well-formed, non-truncated compressed stream with zero trailing junk, `InflateTransformer` followed by `Flush()` is guaranteed to reach `was_stream_end_reached_ = true` without throwing a `TypeError`, yielding output chunks whose lengths sum to `stream_.total_out == raw_len`.

---

## 3. Formal Specification in Rocq/Coq

Below is the formal specification and mechanical verification in `BlinkDecompressionStreamRoundtripSemantics.v`. We model:
1. Compression formats (`CompressionFormat`).
2. Byte chunks (`Chunk := list Z`), stream chunk lists (`ChunkStream := list Chunk`), and total byte length over chunked streams (`stream_byte_len`).
3. Chunk-slicing operations (`rechunk`) modeling Blink's `kBufferSize` (`out_buffer`) loop in `InflateTransformer::Inflate` and `DeflateTransformer::Deflate`.
4. Abstract codec frames carrying format headers, lossless payload encodings, and footers (CRC32/ISIZE for GZIP, Adler32 for ZLIB), alongside `DeflateTransformer` and `InflateTransformer` state machines.

---

## 4. Complete, Admitted-Free Rocq/Coq Proof (`BlinkDecompressionStreamRoundtripSemantics.v`)

```coq
(** * BlinkDecompressionStreamRoundtripSemantics.v
    Formal Verification of WHATWG Compression Streams §3 &
    Chromium Blink third_party/blink/renderer/modules/compression/decompression_stream.cc
    Property: decompress_len(compress(raw)) = raw_len *)

From Coq Require Import List.
From Coq Require Import ZArith.
From Coq Require Import Bool.
From Coq Require Import Lia.
From Coq Require Import PeanoNat.
Import ListNotations.

Open Scope Z_scope.

(** ** 1. Web Platform Compression Formats (WHATWG Compression §2, §3) *)

Inductive CompressionFormat : Type :=
  | kDeflate    (* RFC 1950 ZLIB *)
  | kDeflateRaw (* RFC 1951 DEFLATE *)
  | kGzip.      (* RFC 1952 GZIP *)

Scheme Equality for CompressionFormat.

Definition format_eqb (f1 f2 : CompressionFormat) : bool :=
  if CompressionFormat_eq_dec f1 f2 then true else false.

Lemma format_eqb_eq : forall f1 f2,
  format_eqb f1 f2 = true <-> f1 = f2.
Proof.
  intros f1 f2. unfold format_eqb.
  destruct (CompressionFormat_eq_dec f1 f2) as [Heq | Hneq].
  - split; intros; auto.
  - split; intros H; [discriminate H | contradiction].
Qed.

Lemma format_eqb_refl : forall f, format_eqb f f = true.
Proof.
  intro f. apply format_eqb_eq. reflexivity.
Qed.

(** ** 2. Bytes, Chunks, and Stream Length Algebra *)

Definition Byte : Type := Z.
Definition ByteBuffer : Type := list Byte.
Definition Chunk : Type := ByteBuffer.
Definition ChunkStream : Type := list Chunk.

(** Length of a single buffer in Z *)
Definition buf_len (b : ByteBuffer) : Z :=
  Z.of_nat (length b).

(** Total byte length across a list of stream chunks *)
Fixpoint stream_byte_len (s : ChunkStream) : Z :=
  match s with
  | [] => 0
  | c :: cs => buf_len c + stream_byte_len cs
  end.

(** Concatenation of all chunks in a stream into a flat byte buffer *)
Definition flatten_stream (s : ChunkStream) : ByteBuffer :=
  concat s.

Lemma buf_len_nonneg : forall (b : ByteBuffer),
  0 <= buf_len b.
Proof.
  intro b. unfold buf_len. lia.
Qed.

Lemma buf_len_app : forall (b1 b2 : ByteBuffer),
  buf_len (b1 ++ b2) = buf_len b1 + buf_len b2.
Proof.
  intros b1 b2. unfold buf_len.
  rewrite app_length. lia.
Qed.

Lemma stream_byte_len_nonneg : forall (s : ChunkStream),
  0 <= stream_byte_len s.
Proof.
  induction s as [| c cs IH].
  - simpl. lia.
  - simpl. specialize (buf_len_nonneg c). lia.
Qed.

Lemma stream_byte_len_app : forall (s1 s2 : ChunkStream),
  stream_byte_len (s1 ++ s2) = stream_byte_len s1 + stream_byte_len s2.
Proof.
  induction s1 as [| c cs IH]; intro s2.
  - simpl. lia.
  - simpl. rewrite IH. lia.
Qed.

Lemma flatten_stream_len : forall (s : ChunkStream),
  buf_len (flatten_stream s) = stream_byte_len s.
Proof.
  induction s as [| c cs IH].
  - unfold flatten_stream. simpl. unfold buf_len. simpl. lia.
  - unfold flatten_stream in *. simpl.
    rewrite buf_len_app. rewrite IH. reflexivity.
Qed.

(** Filtering empty chunks (WHATWG §3: "If no output is produced, return" /
    Blink: if (bytes > 0) controller->Enqueue(...)) *)
Definition filter_nonempty (s : ChunkStream) : ChunkStream :=
  filter (fun c => match c with [] => false | _ :: _ => true end) s.

Lemma flatten_filter_nonempty : forall (s : ChunkStream),
  flatten_stream (filter_nonempty s) = flatten_stream s.
Proof.
  induction s as [| c cs IH].
  - reflexivity.
  - simpl. destruct c as [| b bs].
    + simpl. exact IH.
    + unfold flatten_stream in *. simpl.
      f_equal. exact IH.
Qed.

Lemma stream_byte_len_filter_nonempty : forall (s : ChunkStream),
  stream_byte_len (filter_nonempty s) = stream_byte_len s.
Proof.
  intro s.
  rewrite <- flatten_stream_len.
  rewrite flatten_filter_nonempty.
   apply flatten_stream_len.
Qed.

(** ** 3. Blink Fixed-Buffer Chunking Model (kBufferSize = 16384) *)

(** Models Blink's `do { ... controller->Enqueue(DOMUint8Array::Create(out_buffer, bytes)); } while (stream_.avail_out == 0)`
    which partitions a flat output buffer into chunks of size at most `kBufferSize`. *)
Fixpoint chunk_by_fuel (fuel : nat) (chunk_sz : nat) (buf : ByteBuffer) : ChunkStream :=
  match fuel with
  | O => match buf with [] => [] | _ => [buf] end
  | S fuel' =>
      match buf with
      | [] => []
      | _ =>
          let c := firstn chunk_sz buf in
          let rest := skipn chunk_sz buf in
          match c with
          | [] => [buf]
          | _ => c :: chunk_by_fuel fuel' chunk_sz rest
          end
      end
  end.

Definition blink_chunk_buffer (chunk_sz : nat) (buf : ByteBuffer) : ChunkStream :=
  chunk_by_fuel (length buf) chunk_sz buf.

Lemma flatten_chunk_by_fuel : forall fuel chunk_sz buf,
  flatten_stream (chunk_by_fuel fuel chunk_sz buf) = buf.
Proof.
  induction fuel as [| fuel' IH]; intros chunk_sz buf.
  - simpl. destruct buf; reflexivity.
  - simpl. destruct buf as [| b bs].
    + reflexivity.
    + remember (firstn chunk_sz (b :: bs)) as c eqn:Hc.
      destruct c as [| x xs].
      * unfold flatten_stream. simpl. rewrite app_nil_r. reflexivity.
      * unfold flatten_stream. simpl.
        fold (flatten_stream (chunk_by_