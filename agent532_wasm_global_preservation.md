# Formal Verification Report: WebAssembly Mutable Global Variable Preservation in Chromium V8/Blink

**Formal Theory Target**: `BlinkWasmGlobalVariablePreservationSemantics.v`  
**Chromium Subsystem**: `v8/src/wasm/wasm-objects.cc` (interfacing with Blink's `third_party/blink/renderer/bindings/core/v8/`)  
**Specification Reference**: WebAssembly Core Specification (W3C Recommendation) §2.3, §4.2, §4.4, §5.4  
**Mathematical Property**: Updating a mutable WebAssembly global variable strictly preserves its declared static value type and signed/unsigned two's-complement bitwidth bounds across execution steps and host-engine boundaries.

---

## 1. Exact Normative W3C / WebAssembly Specification Requirements

Within the WebAssembly Core Specification, global variables are stateful storage locations allocated in the global store $S$ and indexed through a module instance's global address space. Their structural and operational semantics are governed by the following normative sections:

### 1.1 Syntax and Binary Format (§2.3.5 & §5.4.5)
A global type $gt$ classifies a global variable by its underlying value type $t$ and a mutability flag $mut$:
$$\text{globaltype} ::= \text{mut}~\text{valtype}$$
$$\text{mut} ::= \mathsf{const} \mid \mathsf{var}$$
$$\text{valtype} ::= \mathsf{i32} \mid \mathsf{i64} \mid \mathsf{f32} \mid \mathsf{f64} \mid \mathsf{v128} \mid \text{reftype}$$

In the binary format (§5.4.5), a `globaltype` is encoded as a `valtype` byte followed by a mutability byte $b \in \{\mathtt{0x00}, \mathtt{0x01}\}$:
- $\mathtt{0x00} \implies \mathsf{const}$ (immutable)
- $\mathtt{0x01} \implies \mathsf{var}$ (mutable)

Any other byte value in the binary stream represents a malformed module and must be rejected during decoding.

### 1.2 Runtime Store and Global Instances (§4.2.8)
At runtime, a global instance $gi \in \text{globalinst}$ is allocated in the store $S.\text{globals}$ and holds a dynamic value $v \in \text{val}$ along with its static `globaltype`:
$$\text{globalinst} ::= \{ \text{type}~\text{globaltype}, \text{value}~\text{val} \}$$

**Store Well-Formedness Invariant (§4.2.8 / Appendix A.2)**: For every global instance $\{ \text{type}~(\text{mut}~t), \text{value}~v \}$ in the store, the runtime value $v$ must dynamically inhabit the static value type $t$:
$$\vdash v : t$$
For integer types $t \in \{\mathsf{i32}, \mathsf{i64}\}$ of bitwidth $N \in \{32, 64\}$, signed interpretation requires $v \in [-2^{N-1}, 2^{N-1}-1]$, and unsigned interpretation requires $v \in [0, 2^N - 1]$.

### 1.3 Validation and Execution of `global.set` (§3.3.2.2 & §4.4.4)
- **Validation**: For an instruction $\mathsf{global.set}~x$, the context $C.\text{globals}[x]$ must be defined as $\mathsf{var}~t$. The instruction has type $[t] \rightarrow []$. If $C.\text{globals}[x]$ is $\mathsf{const}~t$, validation fails.
- **Execution**: Let $F$ be the current frame, $a = F.\text{module}.\text{globals}[x]$ be the global address, and $g = S.\text{globals}[a] = \{ \text{type}~(\mathsf{var}~t), \text{value}~v_{old} \}$. Popping $v$ from the stack updates $S.\text{globals}[a]$ to $g' = \{ \text{type}~(\mathsf{var}~t), \text{value}~v \}$:
$$S; F; v~(\mathsf{global.set}~x) \hookrightarrow S' \text{ with } S'.\text{globals}[a] = \{ \text{type}~(\mathsf{var}~t), \text{value}~v \}; F; \epsilon$$

---

## 2. V8 / Blink Implementation Details and Invariants

In Chromium's Grand Unified Engine pipeline, WebAssembly execution in V8 directly interacts with Blink's DOM, AudioWorklets, PaintWorklets, and task scheduling infrastructure. In `v8/src/wasm/wasm-objects.cc`, WebAssembly globals are reified via the `WasmGlobalObject` C++ class (`JSObject` subclass).

### 2.1 Memory Layout and Buffer Partitioning (`WasmGlobalObject`)
`WasmGlobalObject` separates storage into two disjoint backing stores based on whether the `ValueType` is a primitive numeric value or a garbage-collected reference:
1. **Untagged Buffer (`untagged_buffer`)**: A `JSArrayBuffer` backing raw memory for $\mathsf{i32}, \mathsf{i64}, \mathsf{f32}, \mathsf{f64}, \mathsf{v128}$. The global holds a byte `offset` into this buffer.
2. **Tagged Buffer (`tagged_buffer`)**: A V8 `FixedArray` holding GC-traced pointers (`externref`, `funcref`, WasmGC structs/arrays) indexed by `offset`.

### 2.2 C++ Mutator and Bitwidth Preservation (`wasm-objects.cc` & `wasm-objects-inl.h`)
When a global is mutated via the JS/Blink boundary (`WebAssembly.Global.prototype.value` setter) or initialized via `WasmGlobalObject::New` in `v8/src/wasm/wasm-objects.cc`:
1. **Mutability Check**: The runtime inspects `global->is_mutable()`. If `false`, V8 throws a `TypeError` (`kWasmTrapImmutableGlobal`), preserving the exact state of the backing store.
2. **Type Coercion & Bitwidth Truncation**: Before writing to the untagged buffer, the JS/Blink value undergoes WebIDL/Wasm boundary conversion (`ToI32`, `ToBigInt64`, etc.).
   - `WasmGlobalObject::SetI32(int32_t value)` writes exactly `sizeof(int32_t)` (4 bytes) at `raw_buffer_ptr() + offset` using `base::WriteUnalignedValue<int32_t>(address, value)`.
   - `WasmGlobalObject::SetI64(int64_t value)` writes exactly `sizeof(int64_t)` (8 bytes) using `base::WriteUnalignedValue<int64_t>(address, value)`.

### 2.3 Cross-Thread / Worklet Invariants
When a `WasmGlobalObject` is imported/exported across Blink `WorkletGlobalScope` executions or JIT-compiled via TurboFan/Liftoff:
- The `type()` and `is_mutable()` properties are immutable metadata encoded in the `WasmGlobalObject` heap descriptor and module wire bytes.
- Because the JIT compiler emits direct memory stores to `untagged_buffer` based on the static `ValueType` without dynamic type tags, the memory safety of the entire renderer process relies on the invariant that `SetGlobal` never alters the global's type metadata and strictly enforces two's-complement bitwidth bounds $[-2^{31}, 2^{31}-1]$ for `i32` and $[-2^{63}, 2^{63}-1]$ for `i64`.

---

## 3. Formal Specification in Rocq / Coq

Below is the complete, self-contained formalization of `BlinkWasmGlobalVariablePreservationSemantics.v`. It models WebAssembly value types, signed two's-complement integer bounds, runtime values, global descriptors, store update semantics, and machine-checked proofs of preservation.

```coq
(** * BlinkWasmGlobalVariablePreservationSemantics.v
    Formal verification of WebAssembly Mutable Global Variable Preservation
    in Chromium V8/Blink (v8/src/wasm/wasm-objects.cc & Wasm Core Spec §5.4). *)

From Coq Require Import Bool.Bool.
From Coq Require Import ZArith.ZArith.
From Coq Require Import Lists.List.
From Coq Require Import micromega.Lia.
Import ListNotations.

Open Scope Z_scope.

(** ** 1. WebAssembly Value Types and Mutability (§2.3.5, §5.4.5) *)

Inductive WasmValType : Type :=
  | TI32 : WasmValType
  | TI64 : WasmValType
  | TF32 : WasmValType
  | TF64 : WasmValType
  | TV128 : WasmValType
  | TExternRef : WasmValType.

Scheme Equality for WasmValType.

Definition valtype_eqb (t1 t2 : WasmValType) : bool :=
  if WasmValType_eq_dec t1 t2 then true else false.

Lemma valtype_eqb_eq : forall t1 t2,
  valtype_eqb t1 t2 = true <-> t1 = t2.
Proof.
  intros t1 t2; unfold valtype_eqb; destruct (WasmValType_eq_dec t1 t2); split; congruence.
Qed.

Inductive Mutability : Type :=
  | Imm : Mutability (* 0x00: const *)
  | Mut : Mutability (* 0x01: var   *).

Definition mut_eqb (m1 m2 : Mutability) : bool :=
  match m1, m2 with
  | Imm, Imm => true
  | Mut, Mut => true
  | _, _ => false
  end.

(** Binary decoding of mutability byte (§5.4.5) *)
Definition decode_mutability (b : Z) : option Mutability :=
  if Z.eqb b 0 then Some Imm
  else if Z.eqb b 1 then Some Mut
  else None.

Record GlobalType : Type := mkGlobalType {
  gt_mut : Mutability;
  gt_type : WasmValType
}.

(** ** 2. Signed Bitwidth Bounds and Runtime Values (§4.2, wasm-objects.cc) *)

Definition I32_MIN : Z := -2147483648.              (* -2^31     *)
Definition I32_MAX : Z :=  2147483647.              (*  2^31 - 1 *)
Definition I32_MOD : Z :=  4294967296.              (*  2^32     *)

Definition I64_MIN : Z := -9223372036854775808.     (* -2^63     *)
Definition I64_MAX : Z :=  9223372036854775807.     (*  2^63 - 1 *)
Definition I64_MOD : Z :=  18446744073709551616.    (*  2^64     *)

Definition in_i32_bounds (z : Z) : Prop :=
  I32_MIN <= z <= I32_MAX.

Definition in_i64_bounds (z : Z) : Prop :=
  I64_MIN <= z <= I64_MAX.

Definition in_i32_bounds_b (z : Z) : bool :=
  (I32_MIN <=? z) && (z <=? I32_MAX).

Definition in_i64_bounds_b (z : Z) : bool :=
  (I64_MIN <=? z) && (z <=? I64_MAX).

Lemma in_i32_bounds_b_iff : forall z,
  in_i32_bounds_b z = true <-> in_i32_bounds z.
Proof.
  intros z; unfold in_i32_bounds_b, in_i32_bounds.
  rewrite andb_true_iff, !Z.leb_le. reflexivity.
Qed.

Lemma in_i64_bounds_b_iff : forall z,
  in_i64_bounds_b z = true <-> in_i64_bounds z.
Proof.
  intros z; unfold in_i64_bounds_b, in_i64_bounds.
  rewrite andb_true_iff, !Z.leb_le. reflexivity.
Qed.

(** Two's-complement signed wrapping (WebIDL / V8 ToI32 & ToBigInt64) *)
Definition wrap_i32 (z : Z) : Z :=
  let u := z mod I32_MOD in
  if u >? I32_MAX then u - I32_MOD else u.

Definition wrap_i64 (z : Z) : Z :=
  let u := z mod I64_MOD in
  if u >? I64_MAX then u - I64_MOD else u.

(** Runtime values stored in WasmGlobalObject backing buffers *)
Inductive WasmVal : Type :=
  | VI32 : Z -> WasmVal
  | VI64 : Z -> WasmVal
  | VF32 : Z -> WasmVal       (* IEEE-754 32-bit bit-pattern in [0, 2^32) *)
  | VF64 : Z -> WasmVal       (* IEEE-754 64-bit bit-pattern in [0, 2^64) *)
  | VV128 : Z -> WasmVal      (* 128-bit SIMD lane bit-pattern             *)
  | VExternRef : Z -> WasmVal (* Tagged heap handle index in tagged_buffer *).

(** Dynamic type extraction *)
Definition typeof_val (v : WasmVal) : WasmValType :=
  match v with
  | VI32 _ => TI32
  | VI64 _ => TI64
  | VF32 _ => TF32
  | VF64 _ => TF64
  | VV128 _ => TV128
  | VExternRef _ => TExternRef
  end.

(** Bitwidth well-formedness predicate for runtime values *)
Definition wf_val_bounds (v : WasmVal) : Prop :=
  match v with
  | VI32 z => in_i32_bounds z
  | VI64 z => in_i64_bounds z
  | VF32 z => 0 <= z < I32_MOD
  | VF64 z => 0 <= z < I64_MOD
  | VV128 z => 0 <= z
  | VExternRef ref_id => 0 <= ref_id
  end.

Definition wf_val_bounds