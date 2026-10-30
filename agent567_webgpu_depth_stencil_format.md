# Formal Verification Report: WebGPU Depth/Stencil Format Compatibility in Chromium Blink

**Target Module:** `third_party/blink/renderer/modules/webgpu/gpu_render_pipeline.cc`  
**Specification Reference:** W3C WebGPU Specification §10.2 (Depth/Stencil State) & §27.1 (Texture Format Capabilities)  
**Formal Theory Target:** `BlinkWebGPUDepthStencilFormatSemantics.v`  
**Verification Property:** Soundness, Completeness, and Partitioning of `has_depth(format)` and `has_stencil(format)` boolean predicates alongside `GPUDepthStencilState` validation invariants.

---

## 1. Normative W3C WebGPU Specification Requirements

In the W3C WebGPU specification, render pipelines that interact with a depth or stencil attachment must define a `GPUDepthStencilState` dictionary (WebGPU §10.2). This state governs depth testing, depth writing, stencil testing, and depth bias configurations. 

### 1.1 Depth/Stencil Formats (§27.1.3)
The specification partitions the `GPUTextureFormat` enumeration into color formats and depth-stencil formats. A valid `GPUDepthStencilState.format` **must** be a depth-stencil format. The normative capabilities of the five standard depth-stencil formats are defined as follows:

| `GPUTextureFormat` | Depth Aspect (`has_depth`) | Stencil Aspect (`has_stencil`) | Byte Size / Layout | Required Feature |
| :--- | :---: | :---: | :--- | :--- |
| `"stencil8"` | `false` | `true` | 1 byte uint | Baseline |
| `"depth16unorm"` | `true` | `false` | 2 byte unorm | Baseline |
| `"depth24plus"` | `true` | `false` | Implementation-defined | Baseline |
| `"depth24plus-stencil8"` | `true` | `true` | Implementation-defined | Baseline |
| `"depth32float"` | `true` | `false` | 4 byte float | Baseline |
| `"depth32float-stencil8"` | `true` | `true` | 4 byte float + 1 byte uint | `"depth32float-stencil8"` |
| *(All other formats)* | `false` | `false` | Varied (Color / Compressed) | Varied |

### 1.2 Validation Rules for `GPUDepthStencilState` (§10.2.1)
When creating a `GPURenderPipeline` via `createRenderPipeline(descriptor)`, if `descriptor.depthStencil` (denoted $s$) is present, the user agent must validate the following normative requirements:

1. **Format Validity:** $s.\text{format}$ must be a depth-stencil format (i.e., $\text{has\_depth}(s.\text{format}) \lor \text{has\_stencil}(s.\text{format})$ must hold).
2. **Depth Aspect Compatibility:**
   * If $\text{has\_depth}(s.\text{format})$ is `false`:
     * $s.\text{depthWriteEnabled}$ must not be `true` (whether defaulted or explicitly provided).
     * $s.\text{depthCompare}$ must not be provided, or if defaulted/provided, must equal `"always"` when no depth test is performed (in WebIDL, optional `depthWriteEnabled` and `depthCompare` require explicit validation in Blink/Dawn when missing from the dictionary).
   * If $\text{has\_depth}(s.\text{format})$ is `true`:
     * $s.\text{depthWriteEnabled}$ must be specified (`true` or `false`).
     * If $s.\text{depthWriteEnabled}$ is `true`, or if $s.\text{depthCompare} \neq \text{"always"}$, then $s.\text{depthCompare}$ must be specified.
3. **Stencil Aspect Compatibility:**
   * Let $\text{stencilTestEnabled}(s)$ be true if and only if any of the following hold:
     * $s.\text{stencilFront.compare} \neq \text{"always"}$
     * $s.\text{stencilFront.failOp} \neq \text{"keep"}$
     * $s.\text{stencilFront.depthFailOp} \neq \text{"keep"}$
     * $s.\text{stencilFront.passOp} \neq \text{"keep"}$
     * $s.\text{stencilBack.compare} \neq \text{"always"}$
     * $s.\text{stencilBack.failOp} \neq \text{"keep"}$
     * $s.\text{stencilBack.depthFailOp} \neq \text{"keep"}$
     * $s.\text{stencilBack.passOp} \neq \text{"keep"}$
   * If $\text{stencilTestEnabled}(s)$ is `true` and $s.\text{stencilWriteMask} \neq 0$ (or more strictly, if stencil operations are active at all), $\text{has\_stencil}(s.\text{format})$ must be `true`. Specifically, §10.2 states: if $s.\text{format}$ does not have a stencil aspect ($\neg\text{has\_stencil}(s.\text{format})$), then $s.\text{stencilFront}$ and $s.\text{stencilBack}$ operations must all default to `"always"` and `"keep"`.

---

## 2. Chromium Blink Implementation Analysis

In Chromium, WebGPU bindings and type conversions between Blink's V8/WebIDL layer and Dawn's C/C++ native WebGPU implementation reside in `third_party/blink/renderer/modules/webgpu/`. Specifically, `gpu_render_pipeline.cc` translates the Blink `GPUDepthStencilState` dictionary into a Dawn `wgpu::DepthStencilState` struct via `AsDawnType`.

### 2.1 Translation & State Invariants in `gpu_render_pipeline.cc`
In `third_party/blink/renderer/modules/webgpu/gpu_render_pipeline.cc`, the conversion function `AsDawnType` handles the optionality introduced by WebGPU's WebIDL specification:

```cpp
wgpu::DepthStencilState AsDawnType(
    GPUDevice* device,
    const GPUDepthStencilState* webgpu_desc,
    ExceptionState& exception_state) {
  DCHECK(webgpu_desc);

  wgpu::DepthStencilState dawn_desc = {};
  dawn_desc.format = AsDawnEnum(webgpu_desc->format());

  // Optional boolean depthWriteEnabled
  if (webgpu_desc->hasDepthWriteEnabled()) {
    dawn_desc.depthWriteEnabled = webgpu_desc->depthWriteEnabled()
                                      ? wgpu::OptionalBool::True
                                      : wgpu::OptionalBool::False;
  } else {
    dawn_desc.depthWriteEnabled = wgpu::OptionalBool::Undefined;
  }

  // Optional GPUCompareFunction depthCompare
  if (webgpu_desc->hasDepthCompare()) {
    dawn_desc.depthCompare = AsDawnEnum(webgpu_desc->depthCompare());
  } else {
    dawn_desc.depthCompare = wgpu::CompareFunction::Undefined;
  }

  dawn_desc.stencilFront = AsDawnType(webgpu_desc->stencilFront());
  dawn_desc.stencilBack = AsDawnType(webgpu_desc->stencilBack());
  dawn_desc.stencilReadMask = webgpu_desc->stencilReadMask();
  dawn_desc.stencilWriteMask = webgpu_desc->stencilWriteMask();
  dawn_desc.depthBias = webgpu_desc->depthBias();
  dawn_desc.depthBiasSlopeScale = webgpu_desc->depthBiasSlopeScale();
  dawn_desc.depthBiasClamp = webgpu_desc->depthBiasClamp();

  return dawn_desc;
}
```

### 2.2 Format Aspect Predicates & Validation Boundary
When `dawn_desc` crosses the IPC boundary (or in-process wire) to Dawn's `ValidateDepthStencilState`, or when Blink performs preliminary format checks in `dawn_enum_conversions.cc` / `gpu_texture.cc`, texture formats are classified by two fundamental boolean predicates: `HasDepthAspect(wgpu::TextureFormat)` and `HasStencilAspect(wgpu::TextureFormat)`.

 The critical architectural invariant maintained across the Blink/Dawn boundary is:
1. **Disjointness from Color Formats:** For any format $f$, $\text{IsDepthOrStencilFormat}(f) \iff \text{has\_depth}(f) \lor \text{has\_stencil}(f)$. No color format satisfies either predicate.
2. **Tri-partition of Depth/Stencil Formats:** The set of valid depth-stencil formats $F_{DS}$ is partitioned into three non-empty, mutually exclusive subsets:
   * **Depth-Only ($F_D$):** `Depth16Unorm`, `Depth24Plus`, `Depth32Float` ($\text{has\_depth} = \text{true}, \text{has\_stencil} = \text{false}$).
   * **Stencil-Only ($F_S$):** `Stencil8` ($\text{has\_depth} = \text{false}, \text{has\_stencil} = \text{true}$).
   * **Combined Depth-Stencil ($F_{D+S}$):** `Depth24PlusStencil8`, `Depth32FloatStencil8` ($\text{has\_depth} = \text{true}, \text{has\_stencil} = \text{true}$).
3. **Undefined Optional Resolution:** By mapping missing JS dictionary members to `wgpu::OptionalBool::Undefined` and `wgpu::CompareFunction::Undefined` in `gpu_render_pipeline.cc`, Blink ensures that Dawn can deterministically enforce the biconditional safety invariant: a pipeline state that omits `depthWriteEnabled` is accepted if and only if $\neg\text{has\_depth}(f)$, preventing uninitialized register state on the underlying Vulkan/Metal/D3D12 command encoders.

---

## 3. Formal Specification in Rocq/Coq

Below is the complete, self-contained formalization `BlinkWebGPUDepthStencilFormatSemantics.v`. It models the `GPUTextureFormat` space, the Blink `GPUDepthStencilState` WebIDL dictionary (including optional attributes), the Dawn `wgpu::DepthStencilState` lowered representation, the `has_depth` and `has_stencil` predicates, and the normative validation rules.

## 4. Concrete Theorems and Complete Proofs

```coq
(** * BlinkWebGPUDepthStencilFormatSemantics.v
    Formal verification of WebGPU Depth/Stencil format predicates and 
    pipeline state compatibility in Chromium Blink (gpu_render_pipeline.cc).
    Specification: W3C WebGPU §10.2 & §27.1.
*)

From Coq Require Import Bool.Bool.
From Coq Require Import ZArith.ZArith.
From Coq Require Import Micromega.Lia.
From Coq Require Import Lists.List.
Import ListNotations.

Open Scope bool_scope.
Open Scope Z_scope.

(** ========================================================================= *)
(** ** 1. WebGPU Texture Formats and Aspect Predicates                        *)
(** ========================================================================= *)

(** Representation of GPUTextureFormat in Blink/Dawn.
    We explicitly enumerate all Depth/Stencil formats and representative 
    Color/Compressed formats to model the entire format space. *)
Inductive GPUTextureFormat : Type :=
  (* Depth/Stencil Formats *)
  | Stencil8 : GPUTextureFormat
  | Depth16Unorm : GPUTextureFormat
  | Depth24Plus : GPUTextureFormat
  | Depth24PlusStencil8 : GPUTextureFormat
  | Depth32Float : GPUTextureFormat
  | Depth32FloatStencil8 : GPUTextureFormat
  (* Color Formats (Representative class parameterized by format ID) *)
  | ColorFormat : Z -> GPUTextureFormat.

(** Decidable equality for GPUTextureFormat *)
Definition eqb_format (f1 f2 : GPUTextureFormat) : bool :=
  match f1, f2 with
  | Stencil8, Stencil8 => true
  | Depth16Unorm, Depth16Unorm => true
  | Depth24Plus, Depth24Plus => true
  | Depth24PlusStencil8, Depth24PlusStencil8 => true
  | Depth32Float, Depth32Float => true
  | Depth32FloatStencil8, Depth32FloatStencil8 => true
  | ColorFormat c1, ColorFormat c2 => Z.eqb c1 c2
  | _, _ => false
  end.

Lemma eqb_format_spec : forall f1 f2 : GPUTextureFormat,
  eqb_format f1 f2 = true <-> f1 = f2.
Proof.
  intros f1 f2; split; intro H.
  - destruct f1, f2; simpl in H; try discriminate; try reflexivity.
    apply Z.eqb_eq in H. subst. reflexivity.
  - subst. destruct f2; simpl; try reflexivity.
    apply Z.eqb_refl.
Qed.

(** Predicate: has_depth(format)
    Returns true iff the texture format contains a depth component. *)
Definition has_depth (f : GPUTextureFormat) : bool :=
  match f with
  | Depth16Unorm => true
  | Depth24Plus => true
  | Depth24PlusStencil8 => true
  | Depth32Float => true
  | Depth32FloatStencil8 => true
  | Stencil8 => false
  | ColorFormat _ => false
  end.

(** Predicate: has_stencil(format)
    Returns true iff the texture format contains a stencil component. *)
Definition has_stencil (f : GPUTextureFormat) : bool :=
  match f with
  | Stencil8 => true
  | Depth24PlusStencil8 => true
  | Depth32FloatStencil8 => true
  | Depth16Unorm => false
  | Depth24Plus => false
  | Depth32Float => false
  | ColorFormat _ => false
  end.

(** Predicate: is_depth_or_stencil_format(format)
    WebGPU §27.1.3: Depth-stencil formats are those with depth or stencil aspects. *)
Definition is_depth_or_stencil_format (f : GPUTextureFormat) : bool :=
  has_depth f || has_stencil f.

(** Relational specification of depth formats per W3C WebGPU §27.1.3 Table *)
Definition Spec_DepthFormats : list GPUTextureFormat :=
  [Depth16Unorm; Depth24Plus; Depth24PlusStencil8; Depth32Float; Depth32FloatStencil8].

(** Relational specification of stencil formats per W3C WebGPU §27.1.3 Table *)
Definition Spec_StencilFormats : list GPUTextureFormat :=
  [Stencil8; Depth24PlusStencil8; Depth32FloatStencil8].

(**Relational specification of all valid depth-stencil formats *)
Definition Spec_AllDepthStencilFormats : list GPUTextureFormat :=
  [Stencil8; Depth16Unorm; Depth24Plus; Depth24PlusStencil8; Depth32Float; Depth32FloatStencil8].

(** ========================================================================= *)
(** ** 2. WebGPU Depth/Stencil Pipeline State Models (Blink & Dawn)           *)
(** ========================================================================= *)

(** GPUCompareFunction