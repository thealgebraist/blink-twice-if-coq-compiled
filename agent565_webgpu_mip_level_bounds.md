# Formal Verification Report: WebGPU Texture Mip Level Bounds in Chromium Blink

**Formal Theory Target:** `BlinkWebGPUMipLevelBoundsSemantics.v`  
**Chromium Component:** `third_party/blink/renderer/modules/webgpu/gpu_texture.cc`  
**W3C Specification:** WebGPU §7.2 (*GPUTexture* & *GPUTextureView* Creation)  
**Mathematical Invariant:** $0 \le \text{mip\_level} < \text{max\_mip\_levels} \land \text{baseMipLevel} + \text{mipLevelCount} \le \text{mipLevelCount}_{\text{texture}}$

---

## 1. Normative W3C WebGPU Specification Requirements

In the W3C WebGPU Specification (§7.2 *Textures and Texture Views*), texture resources represent multi-dimensional arrays of texels arranged into mipmap chains (pyramids of successively halved resolutions). Memory safety in the underlying native graphics APIs (Vulkan, Metal, Direct3D 12) strictly requires that all subresource indexings—specifically mipmap level allocations and view sub-ranges—remain bounded by the physical geometry of the allocation.

### 1.1. Maximum Mip Level Limit Calculation
For a texture created via `GPUDevice.createTexture(descriptor)` with dimension $D \in \{\text{1d}, \text{2d}, \text{3d}\}$ and `size` $= (W, H, L)$ (representing width, height, and depth/array layers), the theoretical upper bound of distinct mip levels $\text{maxMipLevels}(D, W, H, L)$ is defined normatively as:

$$\text{maxMipLevels}(D, W, H, L) = \begin{cases} 
1 & \text{if } D = \text{1d} \\
\lfloor \log_2(\max(W, H)) \rfloor + 1 & \text{if } D = \text{2d} \\
\lfloor \log_2(\max(W, H, L)) \rfloor + 1 & \text{if } D = \text{3d}
\end{cases}$$

### 1.2. Texture Creation Validation (`createTexture`)
When validating a `GPUTextureDescriptor` $T_{\text{desc}}$:
1. All extents must be strictly positive: $W > 0, H > 0, L > 0$.
2. `T_desc.mipLevelCount` (typed in WebIDL as `[EnforceRange] GPUIntegerCoordinate`, mapping to an unsigned 32-bit integer) must satisfy:
   $$1 \le T_{\text{desc}}.\text{mipLevelCount} \le \text{maxMipLevels}(T_{\text{desc}}.\text{dimension}, W, H, L)$$

### 1.3. Texture View Subresource Bounds (`createView`)
When creating a `GPUTextureView` via `GPUTexture.createView(descriptor)` on a parent texture $T$ with allocated levels $M_{\text{tex}} = T.\text{mipLevelCount}$:
1. The view's starting mip level $B = V_{\text{desc}}.\text{baseMipLevel}$ defaults to $0$ and is an unsigned 32-bit integer ($B \ge 0$).
2. If $V_{\text{desc}}.\text{mipLevelCount}$ is omitted (`undefined`), the resolved count $C$ defaults to $M_{\text{tex}} - B$.
3. If $V_{\text{desc}}.\text{mipLevelCount}$ is explicitly provided as $C$, it must satisfy:
   $$C > 0 \land B + C \le M_{\text{tex}}$$
4. Consequently, for every mip level index $m$ accessible through the view ($B \le m < B + C$), the fundamental safety property holds:
   $$0 \le m < M_{\text{tex}} \le \text{maxMipLevels}(T)$$

---

## 2. Chromium Blink Implementation Analysis

In Chromium's multi-process architecture, WebGPU calls originate in the Blink renderer process (`third_party/blink/renderer/modules/webgpu/gpu_texture.cc`) and are serialized over the Dawn Wire protocol to the GPU process (`third_party/dawn/src/dawn/native/Texture.cpp`).

### 2.1. `gpu_texture.cc` Translation & Descriptor Conversion
In `third_party/blink/renderer/modules/webgpu/gpu_texture.cc`, `GPUTexture` manages the Blink-side lifecycle, WebIDL type marshaling, and Dawn `WGPUTextureDescriptor` / `WGPUTextureViewDescriptor` construction.

```cpp
// Conceptual structure in third_party/blink/renderer/modules/webgpu/gpu_texture.cc
wgpu::TextureDescriptor AsDawnType(
     GPUDevice* device,
    const V8GPUTextureDescriptor* webgpu_desc,
    std::string* label) {
  wgpu::TextureDescriptor dawn_desc = {};
  dawn_desc.usage = AsDawnEnum<wgpu::TextureUsage>(webgpu_desc->usage());
  dawn_desc.dimension = AsDawnEnum<wgpu::TextureDimension>(webgpu_desc->dimension());
  dawn_desc.size = AsDawnType(webgpu_desc->size());
  dawn_desc.format = AsDawnEnum<wgpu::TextureFormat>(webgpu_desc->format());
  dawn_desc.mipLevelCount = webgpu_desc->mipLevelCount();
  dawn_desc.sampleCount = webgpu_desc->sampleCount();
  // ...
  return dawn_desc;
}
```

And for `GPUTexture::createView`:

```cpp
GPUTextureView* GPUTexture::createView(
    const GPUTextureViewDescriptor* webgpu_desc,
    ExceptionState& exception_state) {
  wgpu::TextureViewDescriptor dawn_desc = {};
  if (webgpu_desc) {
    dawn_desc.baseMipLevel = webgpu_desc->baseMipLevel();
    if (webgpu_desc->hasMipLevelCount()) {
      dawn_desc.mipLevelCount = webgpu_desc->mipLevelCount();
    } else {
      dawn_desc.mipLevelCount = WGPU_MIP_LEVEL_COUNT_UNDEFINED;
    }
    // ...
  }
  WGPUTextureView view = GetProcs().textureCreateView(GetHandle(), &dawn_desc);
  return MakeGarbageCollected<GPUTextureView>(device_, view, label);
}
```

### 2.2. Boundary Invariants Between Blink and Dawn
1. **WebIDL `[EnforceRange]` Enforcement:** Blink's V8 bindings enforce `[EnforceRange] unsigned long` on `mipLevelCount` and `baseMipLevel`. Any negative JS Number or value $\ge 2^{32}$ throws a `TypeError` in Blink *before* reaching `gpu_texture.cc`. Thus, in C++, `uint32_t` values naturally satisfy $0 \le x < 2^{32}$.
2. **Sentinel Resolution (`WGPU_MIP_LEVEL_COUNT_UNDEFINED`):** When `hasMipLevelCount()` is false, Blink passes `WGPU_MIP_LEVEL_COUNT_UNDEFINED` (`0xFFFFFFFFu`). Care must be taken that the sentinel is resolved *before* range arithmetic, or else $B + \text{0xFFFFFFFF}$ overflows 32-bit unsigned arithmetic.
3. **Overflow-Safe Subresource Validation:** When checking `baseMipLevel + mipLevelCount <= texture.mipLevelCount`, naïve 32-bit unsigned addition `baseMipLevel + mipLevelCount` can wrap around modulo $2^{32}$, bypassing bounds checks. The implementation and formal semantics must enforce mathematical (unbounded $\mathbb{Z}$ or 64-bit widened) addition or subtraction-based bounds checking (`baseMipLevel <= texture.mipLevelCount && mipLevelCount <= texture.mipLevelCount - baseMipLevel`).
4. **Renderer-Side State Caching:** `GPUTexture` caches `dimension_`, `format_`, `usage_`, and `mip_level_count_` directly on the Blink `GPUTexture` C++ object to service synchronous JS getters (`texture.mipLevelCount`) without an IPC round-trip to the GPU process.

---

## 3. Formal Specification in Rocq / Coq

Below is the complete, self-contained formalization of `BlinkWebGPUMipLevelBoundsSemantics.v`. It models WebIDL range enforcement, discrete binary logarithm mip-chain limits, Blink-to-Dawn sentinel resolution, overflow-safe view range checks, and mip-level indexing invariants.

```coq
(** * BlinkWebGPUMipLevelBoundsSemantics.v
    Formal verification of WebGPU Texture & TextureView Mip Level Bounds
    corresponding to Chromium's third_party/blink/renderer/modules/webgpu/gpu_texture.cc
    and W3C WebGPU Specification Section 7.2. *)

From Coq Require Import ZArith.
From Coq Require Import Bool.
From Coq Require Import Lia.
From Coq Require Import List.
Import ListNotations.

Open Scope Z_scope.

(** ** 1. WebIDL and Hardware Constants *)

Definition UINT32_MAX : Z := 4294967295. (* 2^32 - 1 *)
Definition WGPU_MIP_LEVEL_COUNT_UNDEFINED : Z := UINT32_MAX.

(** WebIDL [EnforceRange] for GPUIntegerCoordinate (uint32_t) *)
Definition in_uint32_range (x : Z) : Prop :=
  0 <= x <= UINT32_MAX.

Definition in_uint32_range_b (x : Z) : bool :=
  (0 <=? x) && (x <=? UINT32_MAX).

(** ** 2. Texture Dimensions and Extents *)

Inductive GPUTextureDimension : Type :=
  | Dim1D
  | Dim2D
  | Dim3D.

Record GPUExtent3D : Type := mkExtent3D {
  width : Z;
  height : Z;
  depthOrArrayLayers : Z
}.

(** Maximum texture dimension limit in WebGPU (standard max limit is 8192 or 16384,
    strictly bounded well below 2^31). *)
Definition MAX_TEXTURE_DIMENSION : Z := 16384.

Definition valid_extent_b (e : GPUExtent3D) : bool :=
  (0 <? width e) && (width e <=? MAX_TEXTURE_DIMENSION) &&
  (0 <? height e) && (height e <=? MAX_TEXTURE_DIMENSION) &&
  (0 <? depthOrArrayLayers e) && (depthOrArrayLayers e <=? MAX_TEXTURE_DIMENSION).

Definition valid_extent (e : GPUExtent3D) : Prop :=
  0 < width e <= MAX_TEXTURE_DIMENSION /\
  0 < height e <= MAX_TEXTURE_DIMENSION /\
  0 < depthOrArrayLayers e <= MAX_TEXTURE_DIMENSION.

(** ** 3. Formal Mip Level Limit Calculation (WebGPU §7.2) *)

(** In Coq's ZArith, Z.log2 returns floor(log2(x)) for x > 0, and 0 for x <= 0.
    Per WebGPU §7.2:
    - 1D textures only support a single mip level (max = 1).
    - 2D textures support floor(log2(max(width, height))) + 1.
    - 3D textures support floor(log2(max(width, height, depth))) + 1. *)
Definition max_mip_levels (dim : GPUTextureDimension) (e : GPUExtent3D) : Z :=
  match dim with
  | Dim1D => 1
  | Dim2D => Z.log2 (Z.max (width e) (height e)) + 1
  | Dim3D => Z.log2 (Z.max (Z.max (width e) (height e)) (depthOrArrayLayers e)) + 1
  end.

(** ** 4. Descriptors and Blink/Dawn State *)

Record GPUTextureDescriptor : Type := mkTextureDesc {
  td_dimension : GPUTextureDimension;
  td_size : GPUExtent3D;
  td_mipLevelCount : Z;
  td_sampleCount : Z
}.

Record GPUTexture : Type := mkTexture {
  tex_dimension : GPUTextureDimension;
  tex_size : GPUExtent3D;
  tex_mipLevelCount : Z;
  tex_valid : bool
}.

Record GPUTextureViewDescriptor : Type := mkViewDesc {
  vd_baseMipLevel : Z;
  vd_mipLevelCount : option Z (* None represents omitted in JS -> WGPU_MIP_LEVEL_COUNT_UNDEFINED *)
}.

Record GPUTextureView : Type := mkTextureView {
  tv_baseMipLevel : Z;
  tv_mipLevelCount : Z;
  tv_parentMipLevelCount : Z;
  tv_valid : bool
}.

(** ** 5. Validation Predicates and Functions *)

(** Texture creation mip level validation:
    1 <= mipLevelCount <= max_mip_levels(dimension, size) *)
Definition validate_texture_mip_levels_b (desc : GPUTextureDescriptor) : bool :=
  valid_extent_b (td_size desc) &&
  in_uint32_range_b (td_mipLevelCount desc) &&
  (1 <=? td_mipLevelCount desc) &&
  (td_mipLevelCount desc <=? max_mip_levels (td_dimension desc) (td_size desc)).

Definition blink_create_texture (desc : GPUTextureDescriptor) : GPUTexture :=
  mkTexture
    (td_dimension desc)
    (td_size desc)
    (td_mipLevelCount desc)
    (validate_texture_mip_levels_b desc).

(** Resolution of optional mipLevelCount in GPUTexture::createView *)
Definition resolve_view_mip_count (tex_mips : Z) (base_mip : Z) (opt_count : option Z) : Z :=
  match opt_count with
  | Some c => c
  | None => tex_mips - base_mip
  end.

(** Overflow-safe validation of TextureView mip subresource range.
    Checks baseMipLevel <= tex_mips first, then resolved_count <= tex_mips - baseMipLevel. *)
Definition validate_view_mip_range_b (tex : GPUTexture) (vdesc : GPUTextureViewDescriptor) : bool :=
  let tex_mips := tex_mipLevelCount tex in
  let base := vd_baseMipLevel vdesc in
  let count := resolve_view_mip_count tex_mips base (vd_mipLevelCount vdesc) in
  tex_valid tex &&
  in_uint32_range_b base &&
  (base <? tex_mips) &&
  match vd_mipLevelCount vdesc with
  | Some c => in_uint32_range_b c && (0 <? c) && (c <=? tex_mips - base)
  | None => (0 <? count) && (count <=? tex_mips - base)
  end.

Definition blink_create_view (