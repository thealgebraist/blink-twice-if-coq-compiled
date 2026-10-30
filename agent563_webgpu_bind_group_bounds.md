# Formal Verification Report: WebGPU Bind Group Index Bounds Semantics

## 1. Normative W3C WebGPU Specification Requirements

Under **W3C WebGPU Specification §8.2 (Bind Groups)** and the related programmable pass encoding validation rules (§14.2 *GPUProgrammablePassEncoder*), resource binding operates over a fixed-capacity slot array determined by the hardware and logical device limits:

1. **Device Limits (`maxBindGroups`)**: Every `GPUDevice` exposes a `GPUSupportedLimits` structure specifying `maxBindGroups` (with a guaranteed baseline default of at least $4$). This limit dictates the upper bound on the number of `GPUBindGroup` objects that can be simultaneously bound to a pipeline layout or programmable pass encoder.
2. **Index Domain**: The `GPUIndex32` WebIDL type represents an unsigned 32-bit integer (`[EnforceRange] unsigned long`). In abstract mathematical models of the renderer and IPC validation layers, indices are frequently lifted into signed arbitrary-precision integers ($\mathbb{Z}$) to reason uniformly about underflow, sign-extension bugs, and upper-bound violations.
3. **Normative Validation Rule**: When invoking `setBindGroup(index, bindGroup, ...)` on a `GPUProgrammablePassEncoder` (`GPURenderPassEncoder`, `GPUComputePassEncoder`, or `GPURenderBundleEncoder`), or when validating bind group indices within a `GPUPipelineLayout` against `GPUBindGroup` descriptors, the user agent must enforce:
   $$\text{index} \in \mathbb{Z} \land 0 \le \text{index} < \text{device}.\text{limits}.\text{maxBindGroups}$$
   If $\text{index} \ge \text{maxBindGroups}$ (or $\text{index} < 0$ in signed representations), a validation error must be generated on the current validation scope, invalidating the encoder or object and preventing out-of-bounds descriptor table indexing in the underlying native graphics API (Vulkan, Metal, D3D12).

---

## 2. Blink Implementation Details and Invariants

In Chromium's Blink rendering engine (`third_party/blink/renderer/modules/webgpu/gpu_bind_group.cc` and its interactions with `gpu_programmable_pass_encoder.cc` and Dawn wire serialization), `GPUBindGroup` lifecycle and slot assignment rely on strict boundary invariants:

1. **Blink-to-Dawn Boundary (`gpu_bind_group.cc`)**:
   `GPUBindGroup::Create` constructs a Blink-side wrapper around a `wgpu::BindGroup` handle allocated via the Dawn wire client (`GetProcs().deviceCreateBindGroup(...)`). While `GPUBindGroup` itself encapsulates the bound resources defined by a `GPUBindGroupLayout`, its consumption occurs when indexed into a pipeline's bind group slot array.
2. **Type Representation & Range Enforcement**:
   Blink bindings generated from `gpu_programmable_pass_encoder.idl` translate JavaScript numbers into `uint32_t` (`GPUIndex32`). However, internal offset calculations, Dawn wire command buffer serialization, and shader binding table offsets interact with signed integer arithmetic and fixed-size C++ arrays (e.g., `std::array<wgpu::BindGroup, kMaxBindGroups>`).
3. **Core Safety Invariant**:
   Before any state mutation or command buffer emission commits a `GPUBindGroup` to slot `idx`, the index must satisfy the boolean predicate:
   $$\text{is\_valid\_bind\_group\_index}(\text{idx}, \text{max\_groups}) \iff (0 \le \text{idx}) \land (\text{idx} < \text{max\_groups})$$
   Enforcing this invariant guarantees:
   * **Memory Safety**: Prevents out-of-bounds array accesses in fixed-capacity command encoder tracking structures in Blink and Dawn.
   * **Hardware Descriptor Safety**: Ensures that root signature mappings (D3D12), descriptor set indices (Vulkan `vkCmdBindDescriptorSets`), and buffer/texture argument table indices (Metal) never exceed allocated pipeline layout capacities.

---

## 3. Formal Specification in Rocq / Coq

Below is the self-contained formalization in `BlinkWebGPUBindGroupBoundsSemantics.v`. It models bind group indices and device limits over $\mathbb{Z}$, defines the operational boolean decision procedure used in validation, establishes the propositional specification, and proves soundness, completeness, decidability, and structural bounds invariants.

```coq
(** * BlinkWebGPUBindGroupBoundsSemantics.v
    Formal verification of WebGPU Bind Group Index Bounds (§8.2)
    Target: third_party/blink/renderer/modules/webgpu/gpu_bind_group.cc *)

From Coq Require Import ZArith.
From Coq Require Import Bool.
From Coq Require Import Lia.
From Coq Require Import List.
Import ListNotations.

Open Scope Z_scope.
Open Scope bool_scope.

(** ** 1. Types and Constants *)

(** In WebGPU, indices and limits are modeled over Z to capture both
    unsigned 32-bit values and potential signed conversion/underflow hazards. *)
Definition BindGroupIndex := Z.
Definition MaxBindGroupsLimit := Z.

(** WebGPU §8.2 / §3.6.2 default minimum guaranteed maxBindGroups limit is 4. *)
Definition kWebGPUDefaultMaxBindGroups : MaxBindGroupsLimit := 4.

(** Dawn / Blink upper architectural cap on bind groups (kMaxBindGroups). *)
Definition kDawnMaxBindGroupsCap : MaxBindGroupsLimit := 4.

(** Well-formedness of a device's maxBindGroups limit: must be strictly positive
    and at least the WebGPU baseline minimum of 4. *)
Definition is_well_formed_limit (max_groups : MaxBindGroupsLimit) : Prop :=
  kWebGPUDefaultMaxBindGroups <= max_groups.

(** ** 2. Executable Validation Predicate (Boolean Decision Procedure) *)

(** Exact mathematical property required by the verification target:
    is_valid_bind_group_index(idx, max_groups) = (0 <=? idx) && (idx <? max_groups). *)
Definition is_valid_bind_group_index (idx : BindGroupIndex) (max_groups : MaxBindGroupsLimit) : bool :=
  (0 <=? idx) && (idx <? max_groups).

(** ** 3. Propositional Specification (Normative W3C WebGPU §8.2 Semantics) *)

Definition ValidBindGroupIndexProp (idx : BindGroupIndex) (max_groups : MaxBindGroupsLimit) : Prop :=
  0 <= idx < max_groups.

(** Modeling the outcome of a bind group slot validation check in Blink/Dawn. *)
Inductive BindGroupValidationResult : Type :=
  | BG_ValidSlot (validated_idx : BindGroupIndex)
  | BG_ValidationError_NegativeIndex (invalid_idx : BindGroupIndex)
  | BG_ValidationError_ExceedsMaxBindGroups (invalid_idx : BindGroupIndex) (limit : MaxBindGroupsLimit).

(** Operational validation step classifying the index against max_groups. *)
Definition validate_bind_group_slot (idx : BindGroupIndex) (max_groups : MaxBindGroupsLimit)
  : BindGroupValidationResult :=
  if idx <? 0 then
    BG_ValidationError_NegativeIndex idx
  else if idx <? max_groups then
    BG_ValidSlot idx
  else
    BG_ValidationError_ExceedsMaxBindGroups idx max_groups.
```

---

## 4. Concrete Theorems and Complete Proofs

We now state and prove the core correctness, equivalence, boundary rejection, monotonic limit relaxation, and pipeline safety theorems without any `Admitted` or `admit` axioms.

```coq
(** ** 4. Formal Verification Theorems and Proofs *)

(** Theorem 1: Equivalence between the boolean validator and the propositional spec. *)
Theorem is_valid_bind_group_index_iff :
  forall (idx : BindGroupIndex) (max_groups : MaxBindGroupsLimit),
    is_valid_bind_group_index idx max_groups = true <->
    ValidBindGroupIndexProp idx max_groups.
Proof.
  intros idx max_groups.
  unfold is_valid_bind_group_index, ValidBindGroupIndexProp.
  rewrite andb_true_iff.
  rewrite Z.leb_le.
  rewrite Z.ltb_lt.
  reflexivity.
Qed.

(** Theorem 2: Exact characterization of validation failure (false case). *)
Theorem is_valid_bind_group_index_false_iff :
  forall (idx : BindGroupIndex) (max_groups : MaxBindGroupsLimit),
    is_valid_bind_group_index idx max_groups = false <->
    (idx < 0 \/ max_groups <= idx).
Proof.
  intros idx max_groups.
  unfold is_valid_bind_group_index.
  rewrite andb_false_iff.
  rewrite Z.leb_gt.
  rewrite Z.ltb_ge.
  reflexivity.
Qed.

(** Theorem 3: Reflection / Decidability of ValidBindGroupIndexProp. *)
Theorem ValidBindGroupIndex_dec :
  forall (idx : BindGroupIndex) (max_groups : MaxBindGroupsLimit),
    {ValidBindGroupIndexProp idx max_groups} + {~ ValidBindGroupIndexProp idx max_groups}.
Proof.
  intros idx max_groups.
  destruct (is_valid_bind_group_index idx max_groups) eqn:Hval.
  - left. apply is_valid_bind_group_index_iff. exact Hval.
  - right. intro Hprop.
    apply is_valid_bind_group_index_iff in Hprop.
    congruence.
Qed.

(** Theorem 4: Strict Rejection of Negative Indices (Underflow Protection). *)
Theorem negative_index_always_rejected :
  forall (idx : BindGroupIndex) (max_groups : MaxBindGroupsLimit),
    idx < 0 ->
    is_valid_bind_group_index idx max_groups = false.
Proof.
  intros idx max_groups Hneg.
  apply is_valid_bind_group_index_false_iff.
  left. exact Hneg.
Qed.

(** Theorem 5: Strict Rejection at or above the Upper Bound (Off-by-One / Overflow Protection). *)
Theorem upper_bound_overflow_rejected :
  forall (idx : BindGroupIndex) (max_groups : MaxBindGroupsLimit),
    max_groups <= idx ->
    is_valid_bind_group_index idx max_groups = false.
Proof.
  intros idx max_groups Hge.
  apply is_valid_bind_group_index_false_iff.
  right. exact Hge.
Qed.

(** Corollary 5.1: Specifically, idx = max_groups is strictly rejected. *)
Corollary exact_limit_boundary_rejected :
  forall (max_groups : MaxBindGroupsLimit),
    is_valid_bind_group_index max_groups max_groups = false.
Proof.
  intros max_groups.
  apply upper_bound_overflow_rejected.
  lia.
Qed.

(** Theorem 6: Non-positive limits admit no valid bind group indices. *)
Theorem non_positive_limit_empty_domain :
  forall (idx : BindGroupIndex) (max_groups : MaxBindGroupsLimit),
    max_groups <= 0 ->
    is_valid_bind_group_index idx max_groups = false.
Proof.
  intros idx max_groups Hnonpos.
  apply is_valid_bind_group_index_false_iff.
  lia.
Qed.

(** Theorem 7: Zero index is always valid for any well-formed WebGPU device limit. *)
Theorem zero_index_valid_for_well_formed_limit :
  forall (max_groups : MaxBindGroupsLimit),
    is_well_formed_limit max_groups ->
    is_valid_bind_group_index 0 max_groups = true.
Proof.
  intros max_groups Hwf.
  unfold is_well_formed_limit, kWebGPUDefaultMaxBindGroups in Hwf.
  apply is_valid_bind_group_index_iff.
  unfold ValidBindGroupIndexProp.
  lia.
Qed.

(** Theorem 8: Baseline indices (0, 1, 2, 3) are universally valid on any compliant WebGPU device. *)
Theorem baseline_indices_universally_valid :
  forall (idx : BindGroupIndex) (max_groups : MaxBindGroupsLimit),
    is_well_formed_limit max_groups ->
    0 <= idx < kWebGPUDefaultMaxBindGroups ->
    is_valid_bind_group_index idx max_groups = true.
Proof.
  intros idx max_groups Hwf Hbase.
  unfold is_well_formed_limit in Hwf.
  apply is_valid_bind_group_index_iff.
  unfold ValidBindGroupIndexProp.
  lia.
Qed.

(** Theorem 9: Monotonicity of validation with respect to device limit upgrades.
    If a bind group index is valid under a device with limit L1, it remains valid
    under any higher-tier device with limit L2 >= L1. *)
Theorem limit_monotonicity :
  forall (idx : BindGroupIndex) (L1 L2 : MaxBindGroupsLimit),
    L1 <= L2 ->
    is_valid_bind_group_index idx L1 = true ->
    is_valid_bind_group_index idx L2 = true.
Proof.
  intros idx L1 L2 Hle Hval1.
  apply is_valid_bind_group_index_iff in Hval1.
  apply is_valid_bind_group_index_iff.
  unfold ValidBindGroupIndexProp in *.
  lia.
Qed.

(** Theorem 10: Operational Classifier Soundness and Completeness.
    The multi-branch validator returns BG_ValidSlot idx if and only if
    is_valid_bind_group_index idx max_groups = true. *)
Theorem validate_bind_group_slot_correct :
  forall (idx : BindGroupIndex) (max_groups : MaxBindGroupsLimit),
    validate_bind_group_slot idx max_groups = BG_ValidSlot idx <->
    is_valid_bind_group_index idx max_groups = true.
Proof.
  intros idx max_groups.
  unfold validate_bind_group_slot.
   rewrite is_valid_bind_group_index_iff.
  unfold ValidBindGroupIndexProp.
  destruct (idx <? 0) eqn:Hlt0.
  - rewrite Z.ltb_lt in Hlt0.
    split; intro H.
    + discriminate H.
    + lia.
  - rewrite Z.ltb_ge in Hlt0.
    destruct (idx <? max_groups) eqn:Hltmax.
    + rewrite Z.ltb_lt in Hltmax.
      split; intro H.
      * lia.
      * reflexivity.
    + rewrite Z.ltb_ge in Hltmax.
      split; intro H.
      * discriminate H.
      * lia.
Qed.

(** Theorem 11: Array Indexing Memory Safety Guarantee.
    Given a fixed-capacity bind group table (modeled as