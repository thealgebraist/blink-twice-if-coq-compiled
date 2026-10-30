# Formal Verification Report: WebGPU Vertex Buffer Stride 4-Byte Alignment Semantics in Chromium Blink

**Target Module:** `third_party/blink/renderer/modules/webgpu/gpu_render_pipeline.cc`  
**Specification Reference:** W3C WebGPU Specification §10.3 (Vertex State & Input Layouts)  
**Formal Theory Target:** `BlinkWebGPUVertexStrideAlignmentSemantics.v`  
**Verification Engine:** Rocq / Coq Proof Assistant (`ZArith`, `Lia`, `Bool`)  

---

## 1. Normative W3C WebGPU Specification Requirements

In the W3C WebGPU specification, vertex input assemblies are configured during render pipeline creation via the `GPUVertexState` dictionary, which contains a sequence of `GPUVertexBufferLayout` descriptors. Each `GPUVertexBufferLayout` defines how vertex data is stepped and unpacked in memory by the hardware input assembler (IA) stage.

### 1.1 WebIDL Definition (§10.3.2)
```webidl
dictionary GPUVertexBufferLayout {
    required GPUSize64 arrayStride;
    GPUVertexStepMode stepMode = "vertex";
    required sequence<GPUVertexAttribute> attributes;
};
```
Where `GPUSize64` is defined as `[EnforceRange] unsigned long long`, representing a non-negative 64-bit integer ($0 \le \text{arrayStride} < 2^{64}$).

### 1.2 Normative Validation Rules (§10.3.1 / `createRenderPipeline` Validation)
When validating a `GPUVertexBufferLayout` descriptor $L$ against a `GPUDevice` $D$ with supported limits $\text{Limits}(D)$, all of the following normative conditions must be satisfied for the vertex buffer stride:

1. **Maximum Stride Limit Bound:**
   $$\text{L.arrayStride} \le \text{Limits}(D).\text{maxVertexBufferArrayStride}$$
   By the WebGPU Default Limits table (§3.6.2), the baseline guarantee across all conforming WebGPU adapters is:
   $$\text{maxVertexBufferArrayStride}_{\text{default}} = 2048\text{ bytes}$$

2. **4-Byte Alignment Invariant:**
   $$\text{L.arrayStride} \bmod 4 = 0$$
   The byte stride between consecutive elements (vertices or instances) in a vertex buffer must be a multiple of $4$ bytes. Note that an `arrayStride` of $0$ is explicitly valid ($0 \bmod 4 = 0 \land 0 \le 2048$), corresponding to repeating the exact same vertex/instance attribute data across every draw step.

3. **Hardware Rationale:**
   Underlying graphics APIs (D3D12 `D3D12_VERTEX_BUFFER_VIEW`, Metal `MTLVertexBufferLayoutDescriptor`, and Vulkan `VkVertexInputBindingDescription` under portability subset and 32-bit attribute fetch constraints) require 32-bit (4-byte) word alignment for hardware DMA fetch units and SIMD vertex shader input registers. Unaligned strides can trigger unaligned memory access faults, silent truncation of lower address bits on certain GPU architectures, or out-of-bounds page reads during speculative hardware vertex prefetching.

---

## 2. Chromium Blink Implementation & Invariants

In Chromium's multi-process architecture, WebGPU JavaScript bindings live in the Blink renderer process (`third_party/blink/renderer/modules/webgpu/`), while Dawn (`third_party/dawn/`) acts as the native WebGPU implementation in the GPU process (and via Wire serialization in the renderer).

### 2.1 Blink Conversion Pipeline (`gpu_render_pipeline.cc`)
In `third_party/blink/renderer/modules/webgpu/gpu_render_pipeline.cc`, Blink converts V8-managed Blink IDL dictionaries (`blink::GPUVertexBufferLayout`) into Dawn native C structures (`WGPUVertexBufferLayout`) via `AsDawnType`:

```cpp
// Conceptual representation of third_party/blink/renderer/modules/webgpu/gpu_render_pipeline.cc
void DawnVertexStateAsWGPUVertexState(
    GPUDevice* device,
    const GPUVertexState* descriptor,
     OwnedVertexState* dawn_vertex_state,
    ExceptionState& exception_state) {
  // ...
  for (wtf_size_t i = 0; i < buffers.size(); ++i) {
    const GPUVertexBufferLayout* buffer = buffers[i];
    WGPUVertexBufferLayout& dawn_buffer = dawn_vertex_state->buffers[i];

    // 64-bit unsigned integer extracted via V8 [EnforceRange]
    uint64_t array_stride = buffer->arrayStride();
    dawn_buffer.arrayStride = array_stride;
    dawn_buffer.stepMode = AsDawnEnum(buffer->stepMode());
    // ...
  }
}
```

### 2.2 Architectural Invariants Across the Blink-Dawn Boundary
1. **Non-Negativity (`[EnforceRange]` Invariant):** V8 bindings enforce that `buffer->arrayStride()` is within $[0, 2^{64}-1]$ before entering `gpu_render_pipeline.cc`. Any negative JS `Number` or value $\ge 2^{64}$ throws a `TypeError` at the WebIDL boundary.
2. **Lossless Serialization Invariant:** `dawn_buffer.arrayStride` is a `uint64_t` serialized over the Dawn Wire (`WGPUVertexBufferLayout::arrayStride`) without narrowing casts (preventing integer truncation vulnerabilities such as $2^{32} + 2 \to 2$).
3. **Validation Gate Invariant:** Before any backend command buffer or PSO (Pipeline State Object) is compiled in Vulkan/D3D12/Metal, the validation predicate:
   $$\text{is\_valid\_stride}(\text{stride}) \iff (\text{stride} \bmod 4 = 0) \land (0 \le \text{stride} \le 2048)$$
   must evaluate to `true`. If it evaluates to `false`, pipeline creation yields an invalid `GPURenderPipeline` object and generates a `GPUValidationError` on the device's error scope, preventing native driver invocation.

---

## 3. Formal Specification in Rocq / Coq

Below is the complete, self-contained formalization of the Blink WebGPU vertex stride alignment semantics, executable in Rocq/Coq without any external axioms or admitted lemmas.

```coq
(** * BlinkWebGPUVertexStrideAlignmentSemantics.v
    Formal verification of W3C WebGPU §10.3 Vertex Buffer Stride 4-Byte Alignment
    and Limit Validation in Chromium Blink (gpu_render_pipeline.cc). *)

Require Import Coq.ZArith.ZArith.
Require Import Coq.Bool.Bool.
Require Import Coq.Lists.List.
Require Import Coq.micromega.Lia.
Import ListNotations.

Open Scope Z_scope.

(** ** 1. Constants and Architectural Limits *)

(** W3C WebGPU §3.6.2 Default Limit: maxVertexBufferArrayStride = 2048 bytes *)
Definition MAX_VERTEX_BUFFER_ARRAY_STRIDE : Z := 2048.

(** W3C WebGPU §10.3 Alignment requirement: 4 bytes *)
Definition VERTEX_STRIDE_ALIGNMENT : Z := 4.

(** WebIDL GPUSize64 upper bound: 2^64 - 1 *)
Definition MAX_GPU_SIZE_64 : Z := 18446744073709551615.

(** ** 2. Data Types Modeling Blink & Dawn Descriptors *)

Inductive GPUVertexStepMode : Type :=
  | StepModeVertex
  | StepModeInstance.

Record GPUVertexBufferLayout : Type := mkVertexBufferLayout {
  arrayStride : Z;
  stepMode    : GPUVertexStepMode;
  attributeCount : Z
}.

Inductive PipelineValidationResult : Type :=
  | PipelineValid (layout : GPUVertexBufferLayout)
  | PipelineValidationError_NegativeStride
  | PipelineValidationError_ExceedsMaxStride
  | PipelineValidationError_UnalignedStride.

(** ** 3.Executable Boolean Validation Predicates *)

(** Core mathematical property from specification:
    is_valid_stride(stride) = (stride mod 4 =? 0) && (stride <=? 2048)
    Note: We also provide a total Z-domain guard for non-negativity,
    and prove their equivalence under WebIDL GPUSize64 invariants. *)
Definition is_valid_stride (stride : Z) : bool :=
  (stride mod 4 =? 0) && (stride <=? 2048).

(** Full domain-guarded validation predicate over arbitrary integer Z *)
Definition is_valid_stride_total (stride : Z) : bool :=
  (0 <=? stride) && is_valid_stride stride.

(** WebIDL [EnforceRange] GPUSize64 invariant *)
Definition is_gpu_size64 (n : Z) : Prop :=
  0 <= n <= MAX_GPU_SIZE_64.

(** ** 4. Propositional Specification of Safe Hardware Stride *)

(** Prop-level normative specification of W3C WebGPU §10.3 *)
Definition Spec_ValidVertexStride (stride : Z) : Prop :=
  0 <= stride /\
  stride <= MAX_VERTEX_BUFFER_ARRAY_STRIDE /\
  (exists k : Z, stride = 4 * k /\ 0 <= k <= 512).

(** Operational validation step in Blink/Dawn pipeline creation *)
Definition validate_vertex_buffer_layout
  (layout : GPUVertexBufferLayout) : PipelineValidationResult :=
  let s := arrayStride layout in
  if s <? 0 then
    PipelineValidationError_NegativeStride
  else if negb (s <=? MAX_VERTEX_BUFFER_ARRAY_STRIDE) then
    PipelineValidationError_ExceedsMaxStride
  else if negb (s mod VERTEX_STRIDE_ALIGNMENT =? 0) then
    PipelineValidationError_UnalignedStride
  else
    PipelineValid layout.
```

---

## 4. Concrete Theorems and Complete Proofs

We now state and prove the core correctness, soundness, completeness, decidability, and memory alignment theorems for `BlinkWebGPUVertexStrideAlignmentSemantics.v`.

```coq
(** ** 5. Formal Verification Theorems and Proofs *)

(** Theorem 1: Equivalence of the core predicate [is_valid_stride] and the
    normative propositional specification [Spec_ValidVertexStride] for all
    WebIDL GPUSize64 inputs (0 <= stride). *)
Theorem is_valid_stride_iff_spec :
  forall (stride : Z),
    0 <= stride ->
    (is_valid_stride stride = true <-> Spec_ValidVertexStride stride).
Proof.
  intros stride Hnonneg.
  unfold is_valid_stride, Spec_ValidVertexStride, MAX_VERTEX_BUFFER_ARRAY_STRIDE.
  rewrite andb_true_iff.
  rewrite Z.eqb_eq.
  rewrite Z.leb_le.
  split.
  - intros [Hmod Hle].
    split; [exact Hnonneg |].
    split; [exact Hle |].
    exists (stride / 4).
    pose proof (Z.div_mod stride 4 ltac:(lia)) as Hdiv.
    rewrite Hmod in Hdiv.
    rewrite Z.add_0_r in Hdiv.
    split.
    + exact Hdiv.
    + split.
      * apply Z.div_pos; lia.
      * apply Z.div_le_upper_bound; lia.
  - intros [_ [Hle [k [Heq [Hk_low Hk_high]]]]].
    split.
    + subst stride.
      rewrite Z.mul_comm.
      apply Z_mod_mult.
    + exact Hle.
Qed.

(** Theorem 2: Exact Characterization of the Valid Stride Space.
    Any valid non-negative stride is strictly one of the 513 discrete values
    {0, 4, 8, ..., 2048}, ensuring bounded word-aligned offsets. *)
Theorem valid_stride_word_index_bound :
  forall (stride : Z),
    is_valid_stride_total stride = true ->
    exists (word_count : Z),
      stride = 4 * word_count /\ 0 <= word_count <= 512.
Proof.
  intros stride Hval.
  unfold is_valid_stride_total in Hval.
  apply andb_true_iff in Hval as [Hge0 Hvalid].
  apply Z.leb_le in Hge0.
  apply (proj1 (is_valid_stride_iff_spec stride Hge0)) in Hvalid.
  destruct Hvalid as [_ [_ Hexists]].
  exact Hexists.
Qed.

(** Theorem 3: Soundness and Completeness of Operational Pipeline Validation.
    [validate_vertex_buffer_layout] returns [PipelineValid layout] if and only if
    [is_valid_stride_total (arrayStride layout) = true]. *)
Theorem validate_layout_sound_and_complete :
  forall (layout : GPUVertexBufferLayout),
    validate_vertex_buffer_layout layout = PipelineValid layout <->
    is_valid_stride_total (arrayStride layout) = true.
Proof.
  intros layout.
  unfold validate_vertex_buffer_layout, is_valid_stride_total, is_valid_stride.
  unfold MAX_VERTEX_BUFFER_ARRAY_STRIDE, VERTEX_STRIDE_ALIGNMENT.
  set (s := arrayStride layout).
  destruct (s <? 0) eqn:Hlt0.
  - apply Z.ltb_lt in Hlt0.
    split; intros H; [discriminate H |].
    apply andb_true_iff in H as [Hge0 _].
    apply Z.leb_le in Hge0. lia.
  - apply Z.ltb_ge in Hlt0.
    destruct (s <=? 2048) eqn:Hle2048; simpl.
    + destruct (s mod 4 =? 0) eqn:Hmod4; simpl.
      * split; intros _.
        -- apply andb_true_iff. split.
           ++ apply Z.leb_le. exact Hlt0.
           ++ apply andb_true_iff. split; [exact Hmod4 | exact Hle2048].
        -- reflexivity.
      * split; intros H; [discriminate H |].
        apply andb_true_iff in H as [_ H].
        apply andb_true_iff in H as [Hmod_true _].
         congruence.
    + split; intros H; [discriminate H |].
      apply andb_true_iff in H as [_ H].
      apply andb_true_iff in H as [_ Hle_true].
      congruence.
Qed.

(** Theorem 4: Rejection of Unaligned Strides.
    Any stride leaving a non-zero remainder modulo 4 is guaranteed to be rejected. *)
Theorem unaligned_stride_rejected :
  forall (stride : Z),
    stride mod 4 <> 0 ->
    is_valid_stride stride = false.
Proof.
  