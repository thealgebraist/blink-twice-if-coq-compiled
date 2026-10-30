# Formal Verification Report: Agent 659
**Target Component:** Chromium Blink — File System Access API (`FileSystemWritableFileStream::seek`)  
**Source File:** `third_party/blink/renderer/modules/file_system_access/file_system_writable_file_stream.cc`  
**Formalization Target:** `BlinkFileSystemWritableSeekClampingSemantics.v`  
**Core Mathematical Property:** $\forall \text{pos} \in \mathbb{Z}, \text{clamp\_seek\_pos}(\text{pos}) = \max(0, \text{pos})$

---

## 1. Normative Specification Requirements

According to the WHATWG File System Standard and W3C File System Access API Specification (§5 *The `FileSystemWritableFileStream` interface*), the `seek(position)` method updates the current file cursor offset used by subsequent write operations.

### 1.1 WebIDL Signature
```webidl
[Exposed=(Window,Worker), SecureContext]
interface FileSystemWritableFileStream : WritableStream {
  Promise<undefined> write(FileSystemWriteChunkType data);
  Promise<undefined> seek([EnforceRange] unsigned long long position);
  Promise<undefined> truncate([EnforceRange] unsigned long long size);
};

dictionary WriteParams {
  required WriteCommandType type;
  [EnforceRange] unsigned long long? size;
  [EnforceRange] unsigned long long? position;
  (BufferSource or Blob or USVString)? data;
};
```

### 1.2 Normative Algorithm Requirements
1. **Range Enforcement (`[EnforceRange]`):**  
   When `seek(position)` or `write({ type: "seek", position })` is invoked from ECMAScript, WebIDL converts the ECMAScript `Number` to an `unsigned long long` ($[0, 2^{64}-1]$) using `[EnforceRange]`. If the input value is negative ($< 0$), `NaN`, $+\infty$, $-\infty$, or $> 2^{64}-1$, a `TypeError` exception must be thrown (or the returned Promise rejected with a `TypeError`).
2. **Internal State Representation & Clamping Defense-in-Depth:**  
   Within the underlying sink and Mojo IPC boundaries, file offsets are often bridged between unsigned WebIDL types (`uint64_t`) and signed POSIX/base file offset representations (`int64_t`). To guarantee memory and storage safety across conversion boundaries, any internal seek position calculation or signed representation must satisfy the non-negativity invariant:
   $$\text{effective\_position} = \max(0, \text{pos})$$
   Specifically, if a signed intermediate offset $\text{pos} \in \mathbb{Z}$ is processed at the stream/sink boundary, its clamped domain value must be non-negative before mutating the stream cursor or dispatching to the underlying `FileSystemAccessFileDelegate`.

---

## 2. Chromium Blink Implementation Analysis

In `third_party/blink/renderer/modules/file_system_access/file_system_writable_file_stream.cc` and its associated underlying sink (`FileSystemUnderlyingSink`), seek operations are funneled through `FileSystemWritableFileStream::seek` and `FileSystemWritableFileStream::write`.

### 2.1 Implementation Mechanics
```cpp
// third_party/blink/renderer/modules/file_system_access/file_system_writable_file_stream.cc

ScriptPromise<IDLUndefined> FileSystemWritableFileStream::seek(
    ScriptState* script_state,
    uint64_t position,
    ExceptionState& exception_state) {
  auto* options = WriteParams::Create();
  options->setType(V8WriteCommandType::Enum::kSeek);
  options->setPosition(position);
  return write(script_state,
               MakeGarbageCollected<V8FileSystemWriteChunkType>(options),
               exception_state);
}
```
When the `WriteParams` dictionary is unpacked in `FileSystemUnderlyingSink::HandleParams`:
1. The presence of `position` is checked (`if (!params.hasPositionNonNull())` $\rightarrow$ throws `TypeError`).
2. V8 bindings enforce `[EnforceRange]` on `uint64_t position`, rejecting values $< 0$ at the JS-to-C++ boundary.
3. Internally, when interacting with `base::File` or `mojo::DataPipe` / `FileSystemAccessWriter`, offsets are bounded within non-negative integer domains. Where signed 64-bit offsets (`int64_t`) or defensive clamping logic `std::max<int64_t>(0, pos)` is applied to stream offsets, the state transition guarantees that the cursor position $p'$ satisfies $p' \ge 0$.

### 2.2 Platform Totality and Invariants
- **Totality Invariant:** Every input $\text{pos} \in \mathbb{Z}$ either triggers a deterministic WebIDL range rejection or resolves to a well-defined non-negative cursor offset $\text{clamp\_seek\_pos}(\text{pos}) = \max(0, \text{pos})$.
- **Non-Negativity Invariant:** $\forall \text{pos} \in \mathbb{Z}, \text{clamp\_seek\_pos}(\text{pos}) \ge 0$.
- **Idempotence Invariant:** Clamping an already clamped seek position yields the exact same position: $\text{clamp\_seek\_pos}(\text{clamp\_seek\_pos}(\text{pos})) = \text{clamp\_seek\_pos}(\text{pos})$.
- **Monotonicity Invariant:** If $\text{pos}_1 \le \text{pos}_2$, then $\text{clamp\_seek\_pos}(\text{pos}_1) \le \text{clamp\_seek\_pos}(\text{pos}_2)$.

---

## 3. Formal Specification in Rocq / Coq

Below is the complete, self-contained formalization in `BlinkFileSystemWritableSeekClampingSemantics.v`. It models both the defensive mathematical clamping operator $\text{clamp\_seek\_pos}(\text{pos}) = \max(0, \text{pos})$ and its relationship with the strict WebIDL `[EnforceRange]` semantics on stream state transitions.

```coq
(** * BlinkFileSystemWritableSeekClampingSemantics.v
    Formal Verification of File System Access API Writable Stream Seek Clamping
    Source: third_party/blink/renderer/modules/file_system_access/file_system_writable_file_stream.cc
    Specification: File System Access API §5 seek(position)
*)

From Coq Require Import ZArith.
From Coq Require Import Lia.
From Coq Require Import Bool.
From Coq Require Import List.
Import ListNotations.

Open Scope Z_scope.

Section FileSystemWritableSeekSemantics.

  (** ** 1. Core Mathematical Clamping Definition *)

  (** [clamp_seek_pos] models the non-negative clamping function
      clamp_seek_pos(pos) = max(0, pos) over arbitrary integers. *)
  Definition clamp_seek_pos (pos : Z) : Z :=
    Z.max 0 pos.

  (** Explicit conditional specification of seek position clamping. *)
  Definition clamp_seek_pos_branch (pos : Z) : Z :=
    if Z.leb pos 0 then 0 else pos.

  (** ** 2. WebIDL [EnforceRange] and Stream Cursor State Model *)

  (** Maximum representable unsigned 64-bit integer (2^64 - 1) *)
  Definition UINT64_MAX : Z := 18446744073709551615.

  (** Maximum safe signed 64-bit file offset (2^63 - 1) *)
  Definition INT64_MAX : Z := 9223372036854775807.

  (** Representation of a FileSystemWritableFileStream state. *)
  Record WritableStreamState : Type := mkStreamState {
    stream_cursor : Z;
    stream_size   : Z;
    stream_closed : bool
  }.

  (** Well-formedness predicate for stream state:
      The cursor and file size must always be non-negative. *)
  Definition wf_stream_state (st : WritableStreamState) : Prop :=
    0 <= stream_cursor st /\ 0 <= stream_size st.

  (** Outcome of a seek command execution in Blink. *)
  Inductive SeekResult : Type :=
    | SeekSuccess (new_state : WritableStreamState)
    | SeekTypeError
    | SeekInvalidStateError.

  (** Defensive seek transition using [clamp_seek_pos]. *)
  Definition exec_seek_clamped (st : WritableStreamState) (pos : Z) : SeekResult :=
    if stream_closed st then
      SeekInvalidStateError
    else
      let clamped_pos := clamp_seek_pos pos in
      SeekSuccess (mkStreamState clamped_pos (stream_size st) false).

  (** Strict WebIDL [EnforceRange] seek transition coupled with clamping. *)
  Definition exec_seek_webidl (st : WritableStreamState) (pos : option Z) : SeekResult :=
    match pos with
    | None => SeekTypeError (* Missing required position in WriteParams *)
    | Some p =>
        if (p <? 0) || (UINT64_MAX <? p) then
          SeekTypeError
        else if stream_closed st then
          SeekInvalidStateError
        else
          SeekSuccess (mkStreamState (clamp_seek_pos p) (stream_size st) false)
    end.

  (** Sequence of clamped seek positions applied to an initial state. *)
  Fixpoint exec_seek_sequence (st : WritableStreamState) (positions : list Z) : WritableStreamState :=
    match positions with
    | [] => st
    | p :: ps =>
        let st' := mkStreamState (clamp_seek_pos p) (stream_size st) (stream_closed st) in
        exec_seek_sequence st' ps
    end.

End FileSystemWritableSeekSemantics.
```

---

## 4. Concrete Theorems and Complete Proofs

The following section provides the complete, admitted-free proofs establishing the exact mathematical and platform invariants of `clamp_seek_pos` and the `FileSystemWritableFileStream` seek transitions.

```coq
Section FileSystemWritableSeekProofs.

  (** Theorem 1: Direct definitional equivalence with max(0, pos). *)
  Theorem clamp_seek_pos_eq_max :
    forall pos : Z, clamp_seek_pos pos = Z.max 0 pos.
  Proof.
    intros pos.
    unfold clamp_seek_pos.
    reflexivity.
  Qed.

  (** Theorem 2: Equivalence between Z.max formulation and branching formulation. *)
  Theorem clamp_seek_pos_branch_equiv :
    forall pos : Z, clamp_seek_pos pos = clamp_seek_pos_branch pos.
  Proof.
    intros pos.
    unfold clamp_seek_pos, clamp_seek_pos_branch.
    destruct (Z.leb_spec0 pos 0) as [Hle | Hgt].
    - lia.
    - lia.
  Qed.

  (** Theorem 3: Non-negativity invariant.
      For any integer input pos, the clamped seek position is >= 0. *)
  Theorem clamp_seek_pos_nonneg :
    forall pos : Z, 0 <= clamp_seek_pos pos.
  Proof.
    intros pos.
    unfold clamp_seek_pos.
    lia.
  Qed.

  (** Theorem 4: Identity on non-negative positions.
      If pos >= 0, clamping preserves pos exactly. *)
  Theorem clamp_seek_pos_nonneg_id :
    forall pos : Z, 0 <= pos -> clamp_seek_pos pos = pos.
  Proof.
    intros pos Hnonneg.
    unfold clamp_seek_pos.
    lia.
  Qed.

  (** Theorem 5: Zero floor on negative positions.
      If pos <= 0, clamping maps pos to 0. *)
  Theorem clamp_seek_pos_neg_zero :
    forall pos : Z, pos <= 0 -> clamp_seek_pos pos = 0.
  Proof.
    intros pos Hneg.
    unfold clamp_seek_pos.
    lia.
  Qed.

  (** Theorem 6: Idempotence of seek position clamping.
      Clamping an already clamped position has no further effect. *)
  Theorem clamp_seek_pos_idempotent :
    forall pos : Z, clamp_seek_pos (clamp_seek_pos pos) = clamp_seek_pos pos.
  Proof.
    intros pos.
    unfold clamp_seek_pos.
    lia.
  Qed.

  (** Theorem 7: Monotonicity of seek position clamping.
      Order between positions is preserved under clamping. *)
  Theorem clamp_seek_pos_monotonic :
    forall p1 p2 : Z, p1 <= p2 -> clamp_seek_pos p1 <= clamp_seek_pos p2.
  Proof.
    intros p1 p2 Hle.
    unfold clamp_seek_pos.
    lia.
  Qed.

  (** Theorem 8: Upper bound domination.
      The clamped seek position is always >= the raw input position. *)
  Theorem clamp_seek_pos_ge_input :
    forall pos : Z, pos <= clamp_seek_pos pos.
  Proof.
    intros pos.
    unfold clamp_seek_pos.
    lia.
  Qed.

  (** Theorem 9: Upper bound preservation.
      If a position is bounded above by a non-negative limit B (such as INT64_MAX
      or UINT64_MAX), the clamped position remains bounded above by B. *)
  Theorem clamp_seek_pos_preserves_upper_bound :
    forall pos B : Z, 0 <= B -> pos <= B -> clamp_seek_pos pos <= B.
  Proof.
    intros pos B HB Hpos.
    unfold clamp_seek_pos.
    lia.
  Qed.

  (** Theorem 10: Preservation of Stream State Well-Formedness under Clamped Seek.
      Executing a clamped seek on any well-formed stream state produces a
      well-formed stream state whenever it succeeds. *)
  Theorem exec_seek_clamped_preserves_wf :
    forall (st st' : WritableStreamState) (pos : Z),
      wf_stream_state st ->
      exec_seek_clamped st pos = SeekSuccess st' ->
      wf_stream_state st'.
  Proof.
    intros st st' pos [Hcursor Hsize] Hexec.
    unfold exec_seek_clamped in Hexec.
    destruct (stream_closed st) eqn:Hclosed.
    - discriminate Hexec.
    - inversion Hexec; subst; clear Hexec.
      unfold wf_stream_state; simpl.
      split.
      + apply clamp_seek_pos_nonneg.
      + exact Hsize.
  Qed.

  (** Theorem 11: WebIDL Seek Totality and Well-Formedness Preservation.
      Executing a full WebIDL seek operation preserves stream well-formedness
      and guarantees that the resulting cursor