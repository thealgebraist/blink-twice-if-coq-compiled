# Formal Verification Report: WebGPU Query Set Index Bounds in Chromium Blink

**Target Module:** `third_party/blink/renderer/modules/webgpu/gpu_query_set.cc`  
**Specification Reference:** W3C WebGPU Specification §14.1 (QuerySets)  
**Formal Theory Target:** `BlinkWebGPUQuerySetIndexBoundsSemantics.v`  
**Mathematical Property:** $\text{valid\_query\_index}(\text{idx}, \text{count}) = (0 \le \text{idx}) \land (\text{idx} < \text{count})$

---

## 1. Normative W3C WebGPU Specification Requirements

In the W3C WebGPU Specification (§14.1, *QuerySets*), a `GPUQuerySet` represents an opaque array of fixed-size slots capable of storing hardware telemetry results (such as occlusion sample counts or pipeline execution timestamps). 

### 1.1 Creation Invariants (`createQuerySet`)
When creating a `GPUQuerySet` via `GPUDevice.createQuerySet(descriptor)`:
* The `descriptor` dictionary is of type `GPUQuerySetDescriptor`, containing:
  * `type`: `GPUQueryType` (`"occlusion"` or `"timestamp"`).
  * `count`: `GPUSize32Out` (an unsigned 32-bit integer `[EnforceRange] unsigned long`).
* **Normative Validation Rule:** The `count` must be strictly bounded by the device's architectural limit:
  $$0 \le \text{count} \le \text{maxQuerySetSize} \quad (\text{where default } \text{maxQuerySetSize} = 4096)$$
  *(Note: Depending on spec revision and Dawn backend constraints, `count` must be $\le 4096$. If an indexed operation is performed on a zero-sized or out-of-bounds slot, validation fails).*

### 1.2 Query Index Bounds Invariants
Across the command encoding pipeline, any operation referencing a query slot by index (`queryIndex`) must satisfy strict bounds checking against the `GPUQuerySet.count` property:

1. **`GPUCommandEncoder.writeTimestamp(querySet, queryIndex)`**:
   * `queryIndex` is of type `GPUSize32` (`[EnforceRange] unsigned long`).
   * **Validation Requirement:** $\text{queryIndex} < \text{querySet.count}$.
2. **`GPURenderPassEncoder.beginOcclusionQuery(queryIndex)`**:
   * Let `occlusionQuerySet` be the render pass's configured query set.
   * **Validation Requirement:** $\text{queryIndex} < \text{occlusionQuerySet.count}$.
3. **`GPURenderPassTimestampWrites` / `GPUComputePassTimestampWrites`**:
   * Contains `beginningOfPassWriteIndex` and `endOfPassWriteIndex`.
   * **Validation Requirement:** If defined, each index must be strictly less than `querySet.count`.
4. **`GPUCommandEncoder.resolveQuerySet(querySet, firstQuery, queryCount, destination, destinationOffset)`**:
   * **Validation Requirement:** 
     $$\text{firstQuery} + \text{queryCount} \le \text{querySet.count}$$
     This implies that for every individual query index $\text{idx} \in [\text{firstQuery}, \text{firstQuery} + \text{queryCount} - 1]$, the fundamental single-index invariant $\text{idx} < \text{querySet.count}$ holds.

When lifting these unsigned 32-bit IDL types into arbitrary-precision mathematical integers ($\mathbb{Z}$) for formal verification alongside signed C++ / IPC intermediate representations, the exact single-index safety predicate is:
$$\text{valid\_query\_index}(\text{idx}, \text{count}) \iff (0 \le \text{idx}) \land (\text{idx} < \text{count})$$

---

## 2. Chromium Blink Implementation & Invariants

In Chromium's multi-process architecture, WebGPU calls originate in the Renderer process (Blink) and are serialized over the Dawn Wire to the GPU process (Dawn native).

### 2.1 `gpu_query_set.cc` Architecture
Located in `third_party/blink/renderer/modules/webgpu/gpu_query_set.cc` (and its header `gpu_query_set.h`), `GPUQuerySet` wraps a `wgpu::QuerySet` handle managed by the Dawn client wire:

```cpp
// Conceptual structure of blink::GPUQuerySet
GPUQuerySet* GPUQuerySet::Create(GPUDevice* device,
                                 const GPUQuerySetDescriptor* webgpu_desc) {
  DCHECK(device);
  DCHECK(webgpu_desc);

  wgpu::QuerySetDescriptor dawn_desc = AsDawnType(webgpu_desc);
  GPUQuerySet* query_set = MakeGarbageCollected<GPUQuerySet>(
      device, device->GetHandle().CreateQuerySet(&dawn_desc),
      webgpu_desc->label());
  return query_set;
}
```

### 2.2 Type Enforcement and State Caching
1. **WebIDL Boundary (`[EnforceRange]`):**  
   Blink's V8 bindings generator translates `GPUSize32` (`[EnforceRange] unsigned long`) into C++ `uint32_t`. If JavaScript passes a negative number, `NaN`, or a value $> 2^{32}-1$, V8 throws a `TypeError` before entering Blink C++ code. Thus, at the entry of Blink C++, $0 \le \text{idx} \le 2^{32}-1$ and $0 \le \text{count} \le 2^{32}-1$.
2. **State Reflection (`count()` and `type()`):**  
   In `gpu_query_set.cc`, `GPUQuerySet::count()` returns `GetHandle().GetCount()`, which retrieves the immutable `uint32_t` capacity cached inside the Dawn client wire object upon creation.
3. **Command Encoding & Wire Serialization:**  
   When Blink invokes `writeTimestamp(GPUQuerySet* querySet, uint32_t queryIndex)` or `resolveQuerySet(...)` on `GPUCommandEncoder`, Blink extracts `querySet->GetHandle()` and forwards `queryIndex` directly to the Dawn wire serializer.
4. **Hardware Memory Safety Invariant:**  
   In the GPU process, Dawn validates `queryIndex < querySet->GetCount()` before issuing Vulkan (`vkCmdWriteTimestamp`, `vkCmdBeginQuery`), D3D12 (`EndQuery`, `ResolveQueryData`), or Metal (`sampleCountersInBuffer`) commands. If $\text{idx} \ge \text{count}$ or $\text{idx} < 0$, the command buffer is marked as an error object, preventing out-of-bounds GPU heap writes or driver-level page faults.

---

## 3. Formal Specification in Rocq / Coq

Below is the complete, self-contained formalization of `BlinkWebGPUQuerySetIndexBoundsSemantics.v`. It models the mathematical integers $\mathbb{Z}$, fixed-width 32-bit unsigned constraints (`uint32`), query set descriptors, single-index validation, range-resolution validation, and proves their mutual consistency.

## 4. Concrete Theorems and Complete Proofs

```coq
(** * BlinkWebGPUQuerySetIndexBoundsSemantics.v
    Formal Verification of WebGPU Query Set Index Bounds in Chromium Blink
    Specification: W3C WebGPU §14.1
    Source: third_party/blink/renderer/modules/webgpu/gpu_query_set.cc
*)

From Coq Require Import ZArith.
From Coq Require Import Bool.
From Coq Require Import Lia.

Open Scope Z_scope.
Open Scope bool_scope.

(** ** 1. Architectural Constants and WebIDL Types *)

(** Maximum unsigned 32-bit integer value (GPUSize32 / uint32_t) *)
Definition UINT32_MAX : Z := 4294967295.

(** WebGPU §14.1 Architectural limit for QuerySet capacity *)
Definition MAX_QUERY_SET_SIZE : Z := 4096.

(** Predicate modeling WebIDL [EnforceRange] unsigned long (uint32_t) *)
Definition is_uint32 (n : Z) : Prop :=
  0 <= n <= UINT32_MAX.

(** Executable boolean check for uint32 bounds *)
Definition is_uint32_b (n : Z) : bool :=
  (0 <=? n) && (n <=? UINT32_MAX).

(** ** 2. WebGPU QuerySet Domain Models *)

Inductive GPUQueryType : Type :=
  | Occlusion : GPUQueryType
  | Timestamp : GPUQueryType.

Record GPUQuerySetDescriptor : Type := mkQuerySetDesc {
  qsd_type  : GPUQueryType;
  qsd_count : Z
}.

Record GPUQuerySet : Type := mkQuerySet {
  qs_type      : GPUQueryType;
  qs_count     : Z;
  qs_destroyed : bool
}.

(** Creation validation: count must be within [0, MAX_QUERY_SET_SIZE] *)
Definition valid_query_set_descriptor (desc : GPUQuerySetDescriptor) : bool :=
  (0 <=? qsd_count desc) && (qsd_count desc <=? MAX_QUERY_SET_SIZE).

(** Model of GPUQuerySet::Create in gpu_query_set.cc *)
Definition create_query_set (desc : GPUQuerySetDescriptor) : GPUQuerySet :=
  mkQuerySet (qsd_type desc) (qsd_count desc) false.

(** ** 3. Core Mathematical Property: Query Set Index Bounds *)

(** Exact boolean specification required by target theory:
    valid_query_index(idx, count) = (0 <=? idx) && (idx <? count) *)
Definition valid_query_index (idx count : Z) : bool :=
  (0 <=? idx) && (idx <? count).

(** Propositional counterpart of valid_query_index *)
Definition ValidQueryIndexProp (idx count : Z) : Prop :=
  0 <= idx /\ idx < count.

(** High-level validation of a query operation against a live GPUQuerySet *)
Definition validate_query_operation (qs : GPUQuerySet) (idx : Z) : bool :=
  negb (qs_destroyed qs) && valid_query_index idx (qs_count qs).

(** Validation of resolveQuerySet range [firstQuery, firstQuery + queryCount) *)
Definition valid_query_resolve_range (first_query query_count count : Z) : bool :=
  (0 <=? first_query) &&
  (0 <=? query_count) &&
  (first_query + query_count <=? count).

(** ** 4. Formal Verification Theorems & Proofs *)

(** Theorem 1: Boolean reflection equivalence for valid_query_index.
    Proves that the executable check exactly reflects the mathematical bounds. *)
Theorem valid_query_index_iff : forall (idx count : Z),
  valid_query_index idx count = true <-> ValidQueryIndexProp idx count.
Proof.
  intros idx count.
  unfold valid_query_index, ValidQueryIndexProp.
  rewrite andb_true_iff.
  rewrite Z.leb_le.
  rewrite Z.ltb_lt.
  reflexivity.
Qed.

(** Theorem 2: Falsity reflection for out-of-bounds indices.
    Proves that any negative index or index >= count is rejected. *)
Theorem valid_query_index_false_iff : forall (idx count : Z),
  valid_query_index idx count = false <-> (idx < 0 \/ count <= idx).
Proof.
  intros idx count.
  unfold valid_query_index.
  rewrite andb_false_iff.
  rewrite Z.leb_gt.
  rewrite Z.ltb_ge.
  reflexivity.
Qed.

(** Theorem 3: Non-empty QuerySet invariant.
    If a valid query index exists, the QuerySet capacity must be strictly positive. *)
Theorem valid_index_implies_positive_count : forall (idx count : Z),
  valid_query_index idx count = true -> 0 < count.
Proof.
  intros idx count H.
  apply valid_query_index_iff in H.
  unfold ValidQueryIndexProp in H.
  lia.
Qed.

(** Theorem 4: Zero-capacity QuerySets reject all indices.
    Regardless of the index supplied, a QuerySet with count <= 0 rejects all accesses. *)
Theorem non_positive_count_rejects_all : forall (idx count : Z),
  count <= 0 -> valid_query_index idx count = false.
Proof.
  intros idx count Hcount.
  apply valid_query_index_false_iff.
  lia.
Qed.

(** Theorem 5: WebIDL uint32_t Optimization Equivalence.
    Since Blink enforces [EnforceRange] unsigned long (0 <= idx), Dawn's C++ check
    (idx < count) is mathematically equivalent to the full two-sided bounds check. *)
Theorem uint32_single_bound_sufficiency : forall (idx count : Z),
  is_uint32 idx ->
  valid_query_index idx count = (idx <? count).
Proof.
  intros idx count Huint.
  unfold is_uint32 in Huint.
  unfold valid_query_index.
  assert (Hge0 : (0 <=? idx) = true).
  { apply Z.leb_le. lia. }
  rewrite Hge0.
  simpl.
  reflexivity.
Qed.

(** Theorem 6: Hardware Limit Boundedness.
    If a GPUQuerySet is created from a valid descriptor, any valid query index
    is guaranteed to be strictly bounded by MAX_QUERY_SET_SIZE (4096) and fit in uint32. *)
Theorem query_index_within_hardware_limits :
  forall (desc : GPUQuerySetDescriptor) (idx : Z),
  valid_query_set_descriptor desc = true ->
  validate_query_operation (create_query_set desc) idx = true ->
  0 <= idx < MAX_QUERY_SET_SIZE /\ is_uint32 idx.
Proof.
  intros desc idx Hdesc Hval.
  unfold valid_query_set_descriptor in Hdesc.
  rewrite andb_true_iff, Z.leb_le, Z.leb_le in Hdesc.
  unfold validate_query_operation, create_query_set in Hval.
  simpl in Hval.
  apply valid_query_index_iff in Hval.
  unfold ValidQueryIndexProp in Hval.
  unfold is_uint32, MAX_QUERY_SET_SIZE, UINT32_MAX in *.
  lia.
Qed.

(** Theorem 7: Range Resolution Soundness (resolveQuerySet).
    If resolveQuerySet(querySet, firstQuery, queryCount, ...) passes range validation,
    then EVERY individual slot idx in [firstQuery, firstQuery + queryCount - 1]
    satisfies valid_query_index(idx, count) = true. *)
Theorem resolve_query_set_pointwise_safety :
  forall (first_query query_count count idx : Z),
  valid_query_resolve_range first_query query_count count = true ->
  first