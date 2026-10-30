# Research Report: Formal Verification of WebAssembly Table Indirect Call Bounds Checking in Chromium V8/Blink

**Topic**: WebAssembly Table Indirect Call Bounds Checking  
**Chromium Source**: `v8/src/wasm/wasm-objects.cc`  
**Specification**: WebAssembly Core Specification §2.4, §3.3, §4.4.8, §5.4  
**Formal Theory Target**: `BlinkWasmTableIndirectCallBoundsSemantics.v`  
**Mathematical Property**: $\text{call\_indirect valid} \iff 0 \le \text{table\_index} < \text{table\_size}$  

---

## 1. Normative Specification Requirements

While §5.4 of the WebAssembly Core Specification defines the binary encoding of control instructions (`call_indirect` encoded as byte `0x11` followed by a `typeidx:u32` and `tableidx:u32`), the dynamic execution semantics governing bounds verification are normatively defined in **§4.4.8 (Control Instructions)**, alongside structural validation in **§3.3.8** and abstract syntax in **§2.4.8**.

The dynamic execution of `call_indirect x y` (where `x` is the table index `tableidx` and `y` is the expected function type index `typeidx`) requires the following exact sequence of abstract machine operations:

1. Let $F$ be the current activation frame.
2. Assert: due to validation, $F.\text{module}.\text{tableaddrs}[x]$ exists.
3. Let $a$ be the table address $F.\text{module}.\text{tableaddrs}[x]$.
4. Assert: due to validation, $S.\text{tables}[a]$ exists, where $S$ is the global store.
5. Let $tab$ be the table instance $S.\text{tables}[a]$.
6. Assert: due to validation, a value of value type `i32` is on the top of the stack.
7. Pop the value `i32.const` $i$ from the stack.
8. **Bounds Check Requirement**: If $i$ is not smaller than the length of $tab.\text{elem}$ (i.e., $i \ge |tab.\text{elem}|$, evaluated as an unsigned 32-bit integer comparison, or equivalently $i < 0 \lor i \ge |tab.\text{elem}|$ when $i$ is lifted to $\mathbb{Z}$), then **trap**.
9. Let $r$ be the reference $tab.\text{elem}[i]$.
10. **Null Check Requirement**: If $r$ is `ref.null` $t$, then **trap**.
11. Assert: due to validation of `funcref` tables, $r$ is `ref.func` $a_f$ for some function address $a_f$.
12. Let $f$ be the function instance $S.\text{funcs}[a_f]$.
13. **Signature Check Requirement**: If $f.\text{type}$ does not match the expected function type $F.\text{module}.\text{types}[y]$, then **trap**.
14. Invoke the function instance at address $a_f$.

In the context of the Web Platform's Grand Unified Engine Pipeline (Blink + V8), any violation of step 8 must deterministically raise a `WebAssembly.RuntimeError` exception ("table index is out of bounds") without corrupting V8 heap memory or Blink AudioWorklet/AnimationWorklet execution contexts.

---

## 2. Chromium V8 / Blink Implementation Details and Invariants

In Chromium, WebAssembly execution is tightly coupled with Blink's execution environments (Window, Worker, and Worklet realms) via V8. The management of `WebAssembly.Table` objects and the underlying dispatch tables used by `call_indirect` is implemented in `v8/src/wasm/wasm-objects.cc`.

### 2.1. Architectural Representation (`WasmTableObject` & `WasmDispatchTable`)

In `v8/src/wasm/wasm-objects.cc`, a WebAssembly table is represented at the JS/Blink boundary by `WasmTableObject` and at the JIT/Liftoff/TurboFan execution boundary by `WasmDispatchTable` (formerly managed via `WasmIndirectFunctionTable` on `WasmInstanceObject`).

Key implementation mechanisms in `v8/src/wasm/wasm-objects.cc`:
* **`WasmTableObject::New`**: Allocates a backing `FixedArray` (the `entries` array) initialized to the table's `initial` size, and constructs a corresponding native/trusted `WasmDispatchTable`.
* **`WasmTableObject::Grow`**: Validates that `current_length + count <= maximum_length` and `<= kV8MaxWasmTableSize`. It reallocates both the JS-visible `FixedArray` and the low-level `WasmDispatchTable`.
* **`WasmTableObject::Set` / `WasmTableObject::Get`**: Performs explicit unsigned bounds checks at the C++ API boundary:
  ```cpp
  if (entry_index >= static_cast<uint32_t>(table->current_length())) {
     isolate->Throw(*isolate->factory()->NewWasmRuntimeError(
        MessageTemplate::kWasmTrapTableOutOfBounds));
    return {};
  }
  ```

### 2.2. JIT Execution and `WasmDispatchTable` Invariants

When Liftoff (baseline compiler) or TurboFan/Turboshaft (optimizing compiler) compiles a `call_indirect` instruction, it emits machine code that directly accesses the `WasmDispatchTable` synchronized by `wasm-objects.cc`:

1. **Synchronization Invariant**: For every `WasmTableObject` $T$ associated with a `WasmDispatchTable` $D$, `T->current_length() == D->length()`. This invariant is maintained across `WasmTableObject::Grow` and `WasmTableObject::AddDispatchTable` in `wasm-objects.cc`.
2. **Unsigned Comparison Trick**: The 32-bit index $i$ popped from the operand stack is treated as a `uint32_t` (or zero-extended to 64-bit). In machine code, a single unsigned comparison (`cmp index, table_size; jae TrapTableOutOfBounds`) checks both $0 \le i$ and $i < \text{table\_size}$ simultaneously when $i$ is interpreted in $\mathbb{Z}$.
3. **Speculative Execution Barrier**: To prevent Spectre v1 out-of-bounds reads of function pointers in the dispatch table, V8 applies branchless masking or poisoning on architectures where pointer masking is enabled, contingent on the primary bounds check $0 \le i < \text{size}$.

---

## 3. Formal Specification in Rocq / Coq

Below is the complete, self-contained formalization of the `BlinkWasmTableIndirectCallBoundsSemantics.v` theory. It models the store, table instances, dispatch tables, the `call_indirect` bounds/signature/null semantics, the unsigned 32-bit machine optimization used by V8, and the structural preservation invariants across `WasmTableObject::Grow`.

```coq
(** * BlinkWasmTableIndirectCallBoundsSemantics.v
    Formal Verification of WebAssembly Table Indirect Call Bounds Checking
    Target: Chromium V8 (v8/src/wasm/wasm-objects.cc) & Wasm Core Spec §4.4.8 / §5.4 *)

From Coq Require Import ZArith.
From Coq Require Import Bool.
From Coq Require Import List.
From Coq Require Import Lia.
Import ListNotations.

Open Scope Z_scope.

(** ** 1. Fundamental Types and Constants *)

(** V8 implementation limits (v8/src/wasm/wasm-limits.h) *)
Definition kV8MaxWasmTableSize : Z := 10000000.
Definition kUInt32Max : Z := 4294967295. (* 2^32 - 1 *)

(** Function Type Identifier (canonicalized sig_id in V8 TypeCanonicalizer) *)
Definition FuncTypeIdx := Z.

(** Function Address in the Wasm Store / Native Module *)
Definition FuncAddr := Z.

(** Table Entry representation modeling WasmDispatchTable entries in wasm-objects.cc *)
Record DispatchTableEntry : Type := mkEntry {
  entry_is_null : bool;
  entry_sig_id  : FuncTypeIdx;
  entry_target  : FuncAddr
}.

(** Representation of a WasmTableObject paired with its WasmDispatchTable *)
Record WasmTable : Type := mkTable {
  table_size    : Z;
  table_max     : option Z;
  table_entries : list DispatchTableEntry
}.

(** Well-formedness invariant maintained by v8/src/wasm/wasm-objects.cc *)
Definition wf_wasm_table (t : WasmTable) : Prop :=
  0 <= table_size t /\
  table_size t <= kV8MaxWasmTableSize /\
  Z.of_nat (length (table_entries t)) = table_size t /\
  match table_max t with
  | Some m => table_size t <= m /\ m <= kV8MaxWasmTableSize
  | None => True
  end.

(** ** 2. Bounds Checking Predicates (Mathematical vs. Machine) *)

(** Mathematical property: 0 <= table_index < table_size *)
Definition call_indirect_bounds_valid (table_index table_len : Z) : Prop :=
  0 <= table_index < table_len.

(** Executable boolean decision procedure for bounds checking *)
Definition check_bounds_b (table_index table_len : Z) : bool :=
  (0 <=? table_index) && (table_index <? table_len).

(** V8 JIT / C++ unsigned 32-bit comparison:
    In C++: static_cast<uint32_t>(index) < static_cast<uint32_t>(size).
    When index is represented in two's complement [0, 2^32 - 1] or signed [-2^31, 2^31 - 1]
    cast to uint32_t, negative signed integers map to [2^31, 2^32 - 1]. *)
Definition to_uint32 (x : Z) : Z :=
  Z.modulo x 4294967296.

Definition v8_uint32_bounds_check_b (raw_index table_len : Z) : bool :=
  to_uint32 raw_index <? table_len.

(** ** 3. Outcome of call_indirect Execution *)

Inductive TrapReason : Type :=
  | TrapTableOutOfBounds
  | TrapNullFunc
  | TrapFuncSigMismatch.

Inductive CallIndirectResult : Type :=
  | CallSuccess (target : FuncAddr)
  | CallTrap (reason : TrapReason).

(** Safe list lookup indexed by Z *)
Fixpoint nth_entry_Z (entries : list DispatchTableEntry) (idx : Z) : option DispatchTableEntry :=
  match entries with
  | [] => None
  | x :: xs =>
      if idx <? 0 then None
      else if idx =? 0 then Some x
      else nth_entry_Z xs (idx - 1)
  end.

(** Full operational semantics of call_indirect (Spec §4.4.8 & V8 Dispatch) *)
Definition eval_call_indirect
  (t : WasmTable)
  (expected_sig : FuncTypeIdx)
  (table_index : Z) : CallIndirectResult :=
  if check_bounds_b table_index (table_size t) then
    match nth_entry_Z (table_entries t) table_index with
    | None => CallTrap TrapTableOutOfBounds (* Unreachable for well-formed tables *)
    | Some entry =>
        if entry_is_null entry then
          CallTrap TrapNullFunc
        else if negb (entry_sig_id entry =? expected_sig) then
          CallTrap TrapFuncSigMismatch
        else
          CallSuccess (entry_target entry)
    end
  else
    CallTrap TrapTableOutOfBounds.

(** Predicate characterizing absence of out-of-bounds traps *)
Definition not_oob_trap (res : CallIndirectResult) : Prop :=
  res <> CallTrap TrapTableOutOfBounds.
```

---

## 4. Concrete Theorems and Complete Rocq/Coq Proofs

The following theorems establish the exact equivalence between the Boolean implementation, the mathematical specification $0 \le \text{table\_index} < \text{table\_size}$, the absence of `TrapTableOutOfBounds`, the soundness of V8's unsigned 32-bit bounds check, and invariant preservation across `WasmTableObject::Grow`.

```coq
(** ** 4. Formal Verification Theorems and Proofs *)

(** Theorem 1: Reflection equivalence between boolean bounds check and mathematical specification *)
Theorem check_bounds_b_correct :
  forall (table_index table_len : Z),
    check_bounds_b table_index table_len = true <->
    call_indirect_bounds_valid table_index table_len.
Proof.
  intros table_index table_len.
  unfold check_bounds_b, call_indirect_bounds_valid.
  rewrite andb_true_iff.
  rewrite Z.leb_le.
  rewrite Z.ltb_lt.
  split; intros H; lia.
Qed.

(** Helper Lemma: Relationship between nth_entry_Z and list length *)
Lemma nth_entry_Z_some_iff :
  forall (entries : list DispatchTableEntry) (idx : Z),
    0 <= idx < Z.of_nat (length entries) <->
    exists e, nth_entry_Z entries idx = Some e.
Proof.
  induction entries as [| x xs IH]; intros idx.
  - simpl. split; intros H.
    + lia.
    + destruct H as [e He]. discriminate He.
  - simpl length. rewrite Nat2Z.inj_succ. simpl nth_entry_Z.
    destruct (idx <? 0) eqn:Hlt0.
    + apply Z.ltb_lt in Hlt0.
      split; intros H.
      * lia.
      * destruct H as [e He]. discriminate He.
    + apply Z.ltb_ge in Hlt0.
      destruct (idx =? 0) eqn:Heq0.
      * apply Z.eqb_eq in Heq0. subst idx.
        split; intros H.
        -- exists x. reflexivity.
        -- lia.
      * apply Z.eqb_neq in Heq0.
        assert (Hidx_pos : 0 <= idx - 1) by lia.
        rewrite <- IH.
        split; intros H; lia.
Qed.

(** Theorem 2: Core Bounds Checking Soundness & Completeness
    For any well-formed WasmTable, call_indirect does not trap with TrapTableOutOfBounds
    if and only if 0 <= table_index < table_size. *)
Theorem call_indirect_bounds_sound_and_complete :
  forall (t : WasmTable) (expected_sig : FuncTypeIdx) (table_index : Z),
    wf_wasm_table t ->
    (not_oob_trap (eval_call_indirect t expected