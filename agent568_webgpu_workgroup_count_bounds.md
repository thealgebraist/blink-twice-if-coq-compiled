# Formal Verification Report: WebGPU Compute Pass Workgroup Count Bounds

**Target Component:** `third_party/blink/renderer/modules/webgpu/gpu_compute_pass_encoder.cc`  
**Normative Specification:** W3C WebGPU §11.1 (`GPUComputePassEncoder` — `dispatchWorkgroups`)  
**Formal Theory Target:** `BlinkWebGPUWorkgroupCountBoundsSemantics.v`  
**Mathematical Property:** `valid_workgroups(x, y, z, max_wg) = (0 <=? x) && (x <=? max_wg) && (0 <=? y) && (y <=? max_wg) && (0 <=? z) && (z <=? max_wg)`

---

## 1. Normative W3C WebGPU Specification Requirements

In the W3C WebGPU Specification (§11.1, *Compute Pass Encoding*), the `GPUComputePassEncoder` interface exposes the `dispatchWorkgroups` method to schedule the execution of a compute shader across a three-dimensional grid of workgroups.

### 1.1 WebIDL Interface Definition
```webidl
typedef [EnforceRange] unsigned long GPUSize32;

interface GPUComputePassEncoder {
    undefined dispatchWorkgroups(GPUSize32 workgroupCountX,
                                 optional GPUSize32 workgroupCountY = 1,
                                 optional GPUSize32 workgroupCountZ = 1);
};
```

### 1.2 Validation Rules for `dispatchWorkgroups(workgroupCountX, workgroupCountY, workgroupCountZ)`
When `dispatchWorkgroups(workgroupCountX, workgroupCountY, workgroupCountZ)` is invoked on a `GPUComputePassEncoder` $E$ associated with a `GPUDevice` $D$, the user agent must enforce the following normative validation conditions before issuing the underlying hardware command:

1. **WebIDL Type Enforcement (`[EnforceRange]`):** Because `GPUSize32` is annotated with `[EnforceRange]`, ECMAScript `Number` arguments outside the range $[0, 2^{32} - 1]$ throw a `TypeError` at the bindings layer before reaching the WebGPU command processor.
2. **Encoder State Validation:** $E$ must be open and valid, and a valid `GPUComputePipeline` must be currently bound to $E$.
3. **Workgroup Dimension Limits:** Let $\text{max\_wg} = D.\text{[[limits]]}.\text{maxComputeWorkgroupsPerDimension}$ (whose default minimum guaranteed value across all WebGPU-conformant devices is $65535$). The workgroup counts along each axis must satisfy:
   $$\begin{aligned}
   0 \le \text{workgroupCountX} &\le \text{max\_wg} \\
   0 \le \text{workgroupCountY} &\le \text{max\_wg} \\
   0 \le \text{workgroupCountZ} &\le \text{max\_wg}
   \end{aligned}$$
4. **Zero-Dimension Semantics:** If any of $\text{workgroupCountX}$, $\text{workgroupCountY}$, or $\text{workgroupCountZ}$ equals $0$, the validation **succeeds**, and the dispatch operation becomes a valid no-op (0 total workgroups are executed).
5. **Failure Semantics:** If any dimension strictly exceeds $\text{max\_wg}$ (or if negative values were hypothetically passed across an unverified IPC boundary), the compute pass encoder $E$ is transitioned to an **invalid** state, and a validation error is generated on $D$'s error scope timeline. No hardware dispatch is emitted.

---

## 2. Chromium Blink & Dawn Implementation Analysis

In Chromium's multi-process architecture, WebGPU validation is split between the Blink renderer bindings (`third_party/blink/renderer/modules/webgpu/gpu_compute_pass_encoder.cc`) and the Dawn wire/native backend (`third_party/dawn/src/dawn/native/ComputePassEncoder.cpp`).

### 2.1 Blink Renderer Layer (`gpu_compute_pass_encoder.cc`)
In Blink, `GPUComputePassEncoder` wraps a Dawn `wgpu::ComputePassEncoder` handle (`GetHandle()`). The C++ implementation of `dispatchWorkgroups` in `third_party/blink/renderer/modules/webgpu/gpu_compute_pass_encoder.cc` is structured as follows:

```cpp
void GPUComputePassEncoder::dispatchWorkgroups(uint32_t workgroup_count_x,
                                               uint32_t workgroup_count_y,
                                               uint32_t workgroup_count_z) {
  GetHandle().DispatchWorkgroups(workgroup_count_x, workgroup_count_y,
                                 workgroup_count_z);
}
```

### 2.2 Architectural Invariants Across Blink and Dawn
1. **Bindings Boundary Invariant:** Blink's generated V8 bindings (`v8_gpu_compute_pass_encoder.cc`) implement the WebIDL `[EnforceRange] unsigned long` conversion via `NativeValueTraits<IDLIntegerConv<uint32_t, bindings::V8ConversionMode::kEnforceRange>>`. Any JavaScript value $v \notin [0, 2^{32}-1]$ after `ToIntegerOrInfinity` immediately throws a V8 `TypeError`. Consequently, within `GPUComputePassEncoder::dispatchWorkgroups`, the parameters `workgroup_count_{x,y,z}` are guaranteed to be unsigned 32-bit integers satisfying $0 \le x, y, z \le 2^{32} - 1$.
2. **Default Parameter Resolution:** If `workgroupCountY` or `workgroupCountZ` are omitted in JavaScript, Blink's V8 bindings supply the WebIDL default value `1u` prior to calling `GPUComputePassEncoder::dispatchWorkgroups(x, y, z)`.
3. **Dawn Backend Enforcement:** `GetHandle().DispatchWorkgroups(x, y, z)` serializes the command over the Dawn wire to the GPU process, where Dawn's `ComputePassEncoder::APIDispatchWorkgroups` validates the counts against the device's configured limits:
   ```cpp
   uint32_t maxComputeWorkgroupsPerDimension =
       GetDevice()->GetLimits().v1.maxComputeWorkgroupsPerDimension;

   DAWN_INVALID_IF(
       workgroupCountX > maxComputeWorkgroupsPerDimension ||
       workgroupCountY > maxComputeWorkgroupsPerDimension ||
       workgroupCountZ > maxComputeWorkgroupsPerDimension,
       "Dispatch workgroup counts (%u, %u, %u) exceed "
       "maxComputeWorkgroupsPerDimension (%u).",
       workgroupCountX, workgroupCountY, workgroupCountZ,
       maxComputeWorkgroupsPerDimension);
   ```
4. **Integer Domain Unification:** By modeling the combined Blink + Dawn pipeline over unbounded signed integers ($\mathbb{Z}$), we capture both the lower-bound non-negativity invariant ($0 \le x, y, z$) enforced by Blink's V8 `[EnforceRange]` bindings and the upper-bound device limit check ($x, y, z \le \text{max\_wg}$) enforced during command validation.

---

## 3. Formal Specification in Rocq/Coq

Below is the complete, self-contained formalization of `BlinkWebGPUWorkgroupCountBoundsSemantics.v`. It defines the mathematical boolean decision procedure `valid_workgroups`, the propositional specification `ValidWorkgroupsProp`, the state transition semantics of `GPUComputePassEncoder`, and the safety theorems.

## 4. Formal Verification & Complete Proofs (`BlinkWebGPUWorkgroupCountBoundsSemantics.v`)

```coq
(** * BlinkWebGPUWorkgroupCountBoundsSemantics.v
    Formal verification of WebGPU §11.1 Compute Pass Workgroup Count Bounds
    corresponding to Chromium Blink's [gpu_compute_pass_encoder.cc]. *)

From Coq Require Import Bool.Bool.
From Coq Require Import ZArith.ZArith.
From Coq Require Import Micega.Lia.

Open Scope bool_scope.
Open Scope Z_scope.

(** ** 1. Core Mathematical Predicate and Specification Constants *)

(** The W3C WebGPU §3.6.2 default minimum guaranteed limit for
    [maxComputeWorkgroupsPerDimension] is 65535 (2^16 - 1). *)
Definition WGPU_DEFAULT_MAX_COMPUTE_WORKGROUPS_PER_DIMENSION : Z := 65535.

(** The WebIDL [EnforceRange] unsigned long upper bound (2^32 - 1). *)
Definition WGPU_MAX_UINT32 : Z := 4294967295.

(** Target boolean validation predicate for 3D compute workgroup counts. *)
Definition valid_workgroups (x y z max_wg : Z) : bool :=
  (0 <=? x) && (x <=? max_wg) &&
  (0 <=? y) && (y <=? max_wg) &&
  (0 <=? z) && (z <=? max_wg).

(** Propositional specification of valid workgroup counts. *)
Definition ValidWorkgroupsProp (x y z max_wg : Z) : Prop :=
  0 <= x <= max_wg /\
  0 <= y <= max_wg /\
  0 <= z <= max_wg.

(** Well-formedness invariant for a WebGPU device's configured limit. *)
Definition ValidDeviceLimit (max_wg : Z) : Prop :=
  WGPU_DEFAULT_MAX_COMPUTE_WORKGROUPS_PER_DIMENSION <= max_wg <= WGPU_MAX_UINT32.

(** Blink V8 [EnforceRange] uint32_t bindings invariant. *)
Definition BlinkUInt32Range (v : Z) : Prop :=
  0 <= v <= WGPU_MAX_UINT32.

(** ** 2. State Machine Model of [GPUComputePassEncoder] *)

Inductive EncoderState : Type :=
  | EncoderOpen
  | EncoderInvalid
  | EncoderEnded.

Record DispatchedGrid : Type := mkGrid {
  grid_x : Z;
  grid_y : Z;
  grid_z : Z
}.

Record ComputePassEncoder : Type := mkEncoder {
  enc_state : EncoderState;
  enc_max_wg : Z;
  enc_dispatches : list DispatchedGrid
}.

(** Operational semantics of [GPUComputePassEncoder::dispatchWorkgroups(x, y, z)]. *)
Definition dispatch_workgroups (enc : ComputePassEncoder) (x y z : Z) : ComputePassEncoder :=
  match enc.(enc_state) with
  | EncoderOpen =>
      if valid_workgroups x y z enc.(enc_max_wg) then
        mkEncoder EncoderOpen enc.(enc_max_wg)
                  (mkGrid x y z :: enc.(enc_dispatches))
      else
        mkEncoder EncoderInvalid enc.(enc_max_wg) enc.(enc_dispatches)
  | EncoderInvalid => enc
  | EncoderEnded =>
      mkEncoder EncoderInvalid enc.(enc_max_wg) enc.(enc_dispatches)
  end.

(** Wrapper modeling WebIDL optional parameter defaults:
    [optional GPUSize32 workgroupCountY = 1, optional GPUSize32 workgroupCountZ = 1] *)
Definition dispatch_workgroups_optional
  (enc : ComputePassEncoder) (x : Z) (opt_y opt_z : option Z) : ComputePassEncoder :=
  let y := match opt_y with Some v => v | None => 1 end in
  let z := match opt_z with Some v => v | None => 1 end in
  dispatch_workgroups enc x y z.

(** Hardware safety invariant: every recorded dispatch in the command buffer
    strictly respects the device's [maxComputeWorkgroupsPerDimension] bounds. *)
Definition EncoderDispatchesSafe (enc : ComputePassEncoder) : Prop :=
  forall g, List.In g enc.(enc_dispatches) ->
    ValidWorkgroupsProp g.(grid_x) g.(grid_y) g.(grid_z) enc.(enc_max_wg).

(** ** 3. Fundamental Equivalence and Structural Theorems *)

(** Theorem 1: Reflection equivalence between the executable boolean validator
    [valid_workgroups] and the propositional specification [ValidWorkgroupsProp]. *)
Theorem valid_workgroups_iff :
  forall x y z max_wg : Z,
    valid_workgroups x y z max_wg = true <-> ValidWorkgroupsProp x y z max_wg.
Proof.
  intros x y z max_wg.
  unfold valid_workgroups, ValidWorkgroupsProp.
  repeat rewrite andb_true_iff.
  repeat rewrite Z.leb_le.
  tauto.
Qed.

(** Theorem 2: Exact characterization of validation failure (out-of-bounds rejection). *)
Theorem valid_workgroups_false_iff :
  forall x y z max_wg : Z,
    valid_workgroups x y z max_wg = false <->
    (x < 0 \/ x > max_wg \/ y < 0 \/ y > max_wg \/ z < 0 \/ z > max_wg).
Proof.
  intros x y z max_wg.
  unfold valid_workgroups.
  repeat rewrite andb_false_iff.
  repeat rewrite Z.leb_gt.
  lia.
Qed.

(** Theorem 3: Non-negativity of the device limit is necessary for any dispatch
    to succeed. *)
Theorem valid_workgroups_implies_nonneg_limit :
  forall x y z max_wg : Z,
    valid_workgroups x y z max_wg = true -> 0 <= max_wg.
Proof.
  intros x y z max_wg H.
  apply valid_workgroups_iff in H.
  unfold ValidWorkgroupsProp in H.
  lia.
Qed.

(** Theorem 4: Monotonicity of workgroup validation with respect to adapter limits.
    If a dispatch is valid on a device with limit [max_wg1], it remains valid on
    any device with a higher limit [max_wg2 >= max_wg1]. *)
Theorem valid_workgroups_monotone_limit :
  forall x y z max_wg1 max_wg2 : Z,
    max_wg1 <= max_wg2 ->
    valid_workgroups x y z max_wg1 = true ->
    valid_workgroups x y z max_wg2 = true.
Proof.
  intros x y z max_wg1 max_wg2 Hle Hval.
  apply valid_workgroups_iff in Hval.
  apply valid_workgroups_iff.
  unfold ValidWorkgroupsProp in *.
  lia.
Qed.

(** Theorem 5: Symmetry across the X, Y, and Z workgroup dimensions. *)
Theorem valid_workgroups_perm_xy :
  forall x y z max_wg : Z,
    valid_workgroups x y z max_wg = valid_workgroups y x z max_wg.
Proof.
  intros x y z max_wg.
  unfold valid_workgroups.
  destruct (0 <=? x); destruct (x <=? max_wg);
  destruct (0 <=? y); destruct (y <=? max_wg);
  destruct (0 <=? z); destruct (z <=? max_wg);
  reflexivity.
