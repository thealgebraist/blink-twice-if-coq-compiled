# Formal Verification Report: Compression Streams Format Validation Semantics

**Agent**: 664 (Web Platform File System, Streams, Shape Detection, and Platform Totality)  
**Topic**: Compression Streams format validation semantics  
**Chromium Source**: `third_party/blink/renderer/modules/compression/compression_stream.cc`  
**Specification**: WHATWG Compression Standard §3 (`CompressionStream` / `DecompressionStream` format validation)  
**Formal Theory Target**: `BlinkCompressionStreamFormatSemantics.v`  
**Mathematical Property**: `is_valid_format`: distinct supported format enum & complete totality over arbitrary WebIDL `DOMString` inputs.

---

## 1. Normative WHATWG Specification Requirements

In the WHATWG Compression Standard (§3 "Interface `CompressionStream`" and §4 "Interface `DecompressionStream`"), the constructor accepts a `CompressionFormat` string parameter (`format`). While modern versions of the specification define `enum CompressionFormat { "deflate", "deflate-raw", "gzip" };` at the WebIDL layer, historical and implementation-level constructor steps explicitly require validation of the input string before initializing the underlying `TransformStream` and compression context (`zlib`):

### Normative Steps (§3.1 `new CompressionStream(format)`)
1. If `format` is unsupported in `CompressionStream`, then throw a `TypeError`.
2. Supported formats are the exact ASCII case-sensitive strings:
   - `"deflate"` (ZLIB Compressed Data Format, RFC 1950)
   - `"gzip"` (GZIP file format, RFC 1952)
   - `"deflate-raw"` (DEFLATE Compressed Data Format, RFC 1951)
3. Set `this`'s format to the internal enumeration value corresponding to `format`.
4. Let `transformAlgorithm` and `flushAlgorithm` be closures bound to the validated format's compressor state.
5. Set `this`'s transform to a new `TransformStream` initialized with `transformAlgorithm` and `flushAlgorithm`.

**Normative Invariant**: An instance of `CompressionStream` (or `DecompressionStream`) can never be constructed in a state where its internal format representation is undefined or outside the finite set $\{\text{Deflate}, \text{Gzip}, \text{DeflateRaw}\}$. Any unrecognized string must deterministically transition the execution state to an abrupt completion containing a `TypeError` exception prior to allocating native stream resources.

---

## 2. Chromium Blink Implementation Details and Invariants

In Chromium Blink (`third_party/blink/renderer/modules/compression/`), the format validation logic is shared between `CompressionStream` (`compression_stream.cc`) and `DecompressionStream` (`decompression_stream.cc`), mediated by `compression_format.h` and `compression_format.cc`.

### C++ Implementation Structure
In `compression_format.h`:
```cpp
enum class CompressionFormat {
  kDeflate,
  kGzip,
  kDeflateRaw,
};

CompressionFormat LookupCompressionFormat(const AtomicString& format,
                                          ExceptionState& exception_state);
```

In `compression_format.cc` & `compression_stream.cc`:
```cpp
CompressionFormat LookupCompressionFormat(const AtomicString& format,
                                          ExceptionState& exception_state) {
  if (format == "gzip") {
    return CompressionFormat::kGzip;
  } else if (format == "deflate") {
    return CompressionFormat::kDeflate;
  } else if (format == "deflate-raw") {
    return CompressionFormat::kDeflateRaw;
  }

  exception_state.ThrowTypeError("Unsupported compression format: '" +
                                 format + "'");
  return CompressionFormat::kDeflate; // Dummy return; exception_state.HadException() is true
}

CompressionStream::CompressionStream(ScriptState* script_state,
                                     const AtomicString& format,
                                     ExceptionState& exception_state) {
  CompressionFormat inflate_format =
      LookupCompressionFormat(format, exception_state);
  if (exception_state.HadException())
    return;

  transform_ = TransformStream::Create(
      script_state,
      MakeGarbageCollected<DeflateTransformer>(script_state, inflate_format),
      exception_state);
}
```

### Critical Blink Invariants
1. **Exception-Guarded Dummy Return Isolation**: Because C++ functions without C++ exceptions enabled (`-fno-exceptions` in Chromium) must return a value even when setting `ExceptionState::ThrowTypeError`, `LookupCompressionFormat` returns `CompressionFormat::kDeflate` as a dummy sentinel on failure. The caller (`CompressionStream::CompressionStream`) **must** immediately check `if (exception_state.HadException()) return;` before passing `inflate_format` to `MakeGarbageCollected<DeflateTransformer>(...)`.
2. **Bijective Valid Domain Mapping**: Over the valid subset of `AtomicString` inputs `{"deflate", "gzip", "deflate-raw"}`, `LookupCompressionFormat` acts as an exact bijection to `{kDeflate, kGzip, kDeflateRaw}` without mutating `exception_state`.
3. **Platform Totality**: For every possible `AtomicString` input (modeled as arbitrary integer IDs or string representations), the constructor terminates in a single step, either throwing a `TypeError` or producing a valid `DeflateTransformer` with a verified `CompressionFormat`.

---

## 3. Formal Specification in Rocq / Coq (`BlinkCompressionStreamFormatSemantics.v`)

Below is the complete, self-contained formalization in Rocq/Coq using `ZArith`, `Lia`, `Bool`, and `List`. Strings (`AtomicString`) are modeled via canonical integer identifiers (`Z`) where distinct constants represent `"deflate"`, `"gzip"`, and `"deflate-raw"`, and all other integers represent arbitrary unsupported strings.

```coq
(** * BlinkCompressionStreamFormatSemantics.v
    Formal Verification of Chromium Blink CompressionStream Format Validation
    Agent 664 - Web Platform Streams & Platform Totality *)

Require Import Coq.ZArith.ZArith.
Require Import Coq.Lists.List.
Require Import Coq.Bool.Bool.
Require Import Coq.micromega.Lia.
Import ListNotations.

Open Scope Z_scope.

(** ** 1. WebIDL DOMString / AtomicString Representation *)

(** We model AtomicString tokens as integer IDs in Z.
    Canonical constants represent the three specification-defined formats. *)
Definition AtomicString := Z.

Definition STR_DEFLATE     : AtomicString := 1.
Definition STR_GZIP        : AtomicString := 2.
Definition STR_DEFLATE_RAW : AtomicString := 3.

(** ** 2. Internal Blink CompressionFormat Enum *)

Inductive CompressionFormat : Type :=
  | kDeflate
  | kGzip
  | kDeflateRaw.

Scheme Equality for CompressionFormat.

(** Enumeration of all inhabitants of CompressionFormat *)
Definition all_compression_formats : list CompressionFormat :=
  [kDeflate; kGzip; kDeflateRaw].

(** ** 3. Specification-Level Format Validation Predicate *)

Definition supported_format_strings : list AtomicString :=
  [STR_DEFLATE; STR_GZIP; STR_DEFLATE_RAW].

Definition is_valid_format (s : AtomicString) : Prop :=
  In s supported_format_strings.

Definition is_valid_format_b (s : AtomicString) : bool :=
  (s =? STR_DEFLATE) || (s =? STR_GZIP) || (s =? STR_DEFLATE_RAW).

(** ** 4. Blink ExceptionState and Execution Models *)

Inductive ExceptionType : Type :=
  | NoException
  | TypeError.

Record ExceptionState : Type := mkExceptionState {
  exc_status : ExceptionType
}.

Definition initial_exception_state : ExceptionState :=
  mkExceptionState NoException.

Definition ThrowTypeError (es : ExceptionState) : ExceptionState :=
  mkExceptionState TypeError.

Definition HadException (es : ExceptionState) : bool :=
  match es.(exc_status) with
  | NoException => false
  | TypeError   => true
  end.

(** ** 5. Exact Translation of Blink's LookupCompressionFormat *)

(** Mirrors:
    CompressionFormat LookupCompressionFormat(const AtomicString& format,
                                              ExceptionState& exception_state) *)
Definition LookupCompressionFormat (format : AtomicString) (es : ExceptionState)
  : (CompressionFormat * ExceptionState) :=
  if format =? STR_GZIP then
    (kGzip, es)
  else if format =? STR_DEFLATE then
    (kDeflate, es)
  else if format =? STR_DEFLATE_RAW then
    (kDeflateRaw, es)
  else
    (kDeflate, ThrowTypeError es).

(** ** 6. Exact Translation of Blink's CompressionStream Constructor *)

Inductive CompressionStreamState : Type :=
  | StreamAbortedByException (e : ExceptionType)
  | StreamInitialized (fmt : CompressionFormat).

Definition ConstructCompressionStream (format : AtomicString) : CompressionStreamState :=
  let es0 := initial_exception_state in
  let (inflate_format, es1) := LookupCompressionFormat format es0 in
  if HadException es1 then
    StreamAbortedByException es1.(exc_status)
  else
    StreamInitialized inflate_format.

(** ** 7. Forward Mapping from Internal Format back to Canonical String *)

Definition format_to_string (fmt : CompressionFormat) : AtomicString :=
  match fmt with
  | kDeflate    => STR_DEFLATE
  | kGzip       => STR_GZIP
  | kDeflateRaw => STR_DEFLATE_RAW
  end.
```

---

## 4. Concrete Theorems and Complete Admitted-Free Proofs

We now prove the core verification theorems establishing:
1. Decidability and boolean reflection of `is_valid_format`.
2. Exhaustiveness and distinctness of the internal `CompressionFormat` enum.
3. Soundness and completeness of `LookupCompressionFormat` (never leaks the dummy `kDeflate` return on invalid inputs).
4. Bijectivity between valid `AtomicString` inputs and `CompressionFormat`.
5. Totality and exception safety of `ConstructCompressionStream`.

```coq
(** * Formal Verification Theorems and Proofs *)

(** Theorem 1: All three internal CompressionFormat enum values are pairwise distinct. *)
Theorem compression_format_distinct :
  kDeflate <> kGzip /\
  kDeflate <> kDeflateRaw /\
  kGzip <> kDeflateRaw /\
  NoDup all_compression_formats.
Proof.
  repeat split; try discriminate.
  unfold all_compression_formats.
  constructor.
  - simpl. intros [H | [H | H]]; discriminate.
  - constructor.
    + simpl. intros [H | H]; discriminate.
    + constructor.
      * simpl. auto.
      * constructor.
Qed.

(** Theorem 2: The CompressionFormat type is finite and completely covered by all_compression_formats. *)
Theorem compression_format_exhaustive :
  forall (fmt : CompressionFormat), In fmt all_compression_formats.
Proof.
  intros fmt.
  destruct fmt; simpl; auto.
Qed.

(** Theorem 3: Boolean reflection equivalence for is_valid_format. *)
Theorem is_valid_format_iff :
  forall (s : AtomicString),
    is_valid_format s <-> is_valid_format_b s = true.
Proof.
  intros s.
  unfold is_valid_format, supported_format_strings, is_valid_format_b.
  unfold STR_DEFLATE, STR_GZIP, STR_DEFLATE_RAW.
  simpl.
  rewrite !orb_true_iff, !Z.eqb_eq.
  tauto.
Qed.

(** Theorem 4: Soundness of LookupCompressionFormat on valid inputs.
    If the input string satisfies is_valid_format, no exception is thrown. *)
Theorem lookup_valid_no_exception :
  forall (s : AtomicString),
    is_valid_format s ->
    let (_, es') := LookupCompressionFormat s initial_exception_state in
    HadException es' = false.
Proof.
  intros s Hvalid.
  unfold is_valid_format, supported_format_strings in Hvalid.
  simpl in Hvalid.
  unfold LookupCompressionFormat, STR_DEFLATE, STR_GZIP, STR_DEFLATE_RAW in *.
  destruct Hvalid as [H | [H | [H | H]]]; subst; simpl; reflexivity || contradiction.
Qed.

(** Theorem 5: Soundness of LookupCompressionFormat on invalid inputs.
    If the input string does not satisfy is_valid_format, TypeError is thrown. *)
Theorem lookup_invalid_throws_type_error :
  forall (s : AtomicString),
    ~ is_valid_format s ->
    let (_, es') := LookupCompressionFormat s initial_exception_state in
    HadException es' = true /\ es'.(exc_status) = TypeError.
Proof.
  intros s Hinvalid.
  unfold is_valid_format, supported_format_strings in Hinvalid.
  simpl in Hinvalid.
  unfold LookupCompressionFormat, STR_DEFLATE, STR_GZIP, STR_DEFLATE_RAW in *.
  destruct (s =? 2) eqn:E2.
  - apply Z.eqb_eq in E2. exfalso. apply Hinvalid. right. left. symmetry. exact E2.
  - destruct (s =? 1) eqn:E1.
    + apply Z.eqb_eq in E1. exfalso. apply Hinvalid. left. symmetry. exact E1.
    + destruct (s =? 3) eqn:E3.
      * apply Z.eqb_eq in E3. exfalso. apply Hinvalid. right. right. left. symmetry. exact E3.
      * simpl. split; reflexivity.
Qed.

(** Theorem 6: Dummy Return Isolation Guarantee.
    Even though LookupCompressionFormat returns kDeflate as a dummy value when throwing
    a TypeError, ConstructCompressionStream never initializes a stream when s is invalid. *)
Theorem constructor_isolates_dummy_return :
  forall (s : AtomicString),
    ~ is_valid_format s ->
    ConstructCompressionStream s = StreamAbortedByException TypeError.
Proof.
  intros s Hinvalid.
  unfold ConstructCompressionStream.
  pose proof (lookup_invalid_throws_type_error s Hinvalid) as Hlookup.
  destruct (LookupCompressionFormat s initial_exception_state) as [fmt es1].
  destruct Hlookup as [Hhad Hstatus].
  rewrite Hhad, Hstatus.
  reflexivity.
Qed.

(** Theorem 7: Exact Bijection between Valid Strings and Initialized Stream Formats. *)
Theorem constructor_valid_bijection :
  forall (s : AtomicString),
    is_valid_format s ->
    exists (fmt : CompressionFormat),
      ConstructCompressionStream s = StreamInitialized fmt /\
      format_to_string fmt = s.
Proof.
  intros s Hvalid.
  unfold is_valid_format, supported_format_strings in Hvalid.
  simpl in Hvalid.
  destruct Hvalid as [H | [H