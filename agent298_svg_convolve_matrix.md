### Audit Report: Agent 298 — Chromium Blink `feConvolveMatrix` Normalization

#### 1. Kernel Divisor Normalization
In the SVG Filter Effects specification (and implemented in Chromium Blink's `FEConvolveMatrix` / Skia's `SkMatrixImageFilter`), the `feConvolveMatrix` filter applies a matrix convolution filter effect to an input image. The normalization of the convolution result is controlled by the `divisor` and `bias` attributes:

* **Default Divisor Calculation:** If the `divisor` attribute is not specified by the author, it defaults to the sum of all values in the `kernelMatrix`:
  $$\text{divisor}_{\text{default}} = \sum_{i=0}^{k_x - 1} \sum_{j=0}^{k_y - 1} K_{i,j}$$
* **Fallback to Unity:** If the calculated sum of the kernel entries is zero (or if a user-specified divisor evaluates to zero, which is treated as an error/degenerate state in rendering pipelines), the effective divisor falls back to $1$ to prevent division-by-zero faults (NaN/Inf propagation in floating-point color buffers).
* **Convolution Evaluation:** For a given color channel value $C_{x,y}$, the convolved value prior to clamping is computed as:
  $$C'_{x,y} = \left\lfloor \frac{\sum_{i,j} K_{i,j} \cdot C_{x+i, y+j}}{\text{divisor}_{\text{effective}}} + \text{bias} \cdot 255 \right\rfloor$$

---

#### 2. Invariants
* **Divisor Non-Zero Invariant:** For any kernel configuration and user input, the effective divisor $D_{\text{eff}}$ satisfies $D_{\text{eff}} \neq 0$.
* **Channel Clamping Invariant:** Regardless of kernel weights, divisor magnitude, or bias offset, the final post-processed pixel channel value $P_{\text{out}}$ is strictly bounded within the 8-bit unsigned integer range:
  $$0 \le P_{\text{out}} \le 255$$
* **Identity Preservation under Zero-Sum Kernels:** When the kernel sum is $0$ and no user divisor is provided, normalization scales by $1$, preserving raw differential energy (e.g., standard Sobel or Laplacian edge-detection kernels) before bias and clamping.

---

#### 3. Formal Verification (`BlinkSVGConvolveMatrixSemantics.v`)

Below is the complete, self-contained Rocq (Coq) formalization verifying the divisor normalization and channel clamping invariants with **0 admits**.

```coq
(** * BlinkSVGConvolveMatrixSemantics.v
    Formal audit of Chromium Blink feConvolveMatrix normalization and clamping semantics.
    Agent 298 Verification Artifact. *)

Require Import Coq.ZArith.ZArith.
Require Import Coq.Lists.List.
Require Import Coq.micromega.Lia.
Import ListNotations.

Open Scope Z_scope.

(** ** 1. Kernel and Divisor Definitions *)

(** A kernel is represented as a flat list of integer weights (scaled fixed-point or integer representation). *)
Definition Kernel := list Z.

(** Sum of all entries in the kernel matrix. *)
Definition kernel_sum (k : Kernel) : Z :=
  fold_right Z.add 0 k.

(** Effective divisor resolution following SVG / Blink semantics:
    - If a user divisor is provided and non-zero, use it.
    - If a user divisor is provided and is zero, fallback to 1 (error recovery).
    - If no user divisor is provided, use the sum of the kernel.
    - If the sum of the kernel is zero, fallback to 1. *)
Definition effective_divisor (k : Kernel) (user_divisor : option Z) : Z :=
  match user_divisor with
  | Some d => if Z.eq_dec d 0 then 1 else d
  | None =>
      let s := kernel_sum k in
      if Z.eq_dec s 0 then 1 else s
  end.

(** ** 2. Clamping and Convolution Semantics *)

(** 8-bit color channel clamping function [0, 255]. *)
Definition clamp_channel (v : Z) : Z :=
  Z.max 0 (Z.min 255 v).

(** Dot product of kernel weights and corresponding pixel neighborhood values. *)
Fixpoint convolve_accum (k : Kernel) (pixels : list Z) : Z :=
  match k, pixels with
  | w :: ks, p :: ps => (w * p) + convolve_accum ks ps
  | _, _ => 0
  end.

(** Full evaluation of a single channel through feConvolveMatrix. *)
Definition evaluate_convolve_channel
  (k : Kernel) (pixels : list Z) (user_divisor : option Z) (bias : Z) : Z :=
  let raw_sum := convolve_accum k pixels in
  let div := effective_divisor k user_divisor in
  let normalized := (raw_sum / div) + bias in
  clamp_channel normalized.

(** ** 3. Safety & Invariant Theorems *)

(** Theorem 1: The effective divisor is never zero, preventing division-by-zero faults. *)
Theorem effective_divisor_nonzero :
  forall (k : Kernel) (user_divisor : option Z),
    effective_divisor k user_divisor <> 0.
Proof.
  intros k [d | ]; unfold effective_divisor.
  - destruct (Z.eq_dec d 0) as [Heq | Hneq].
    + lia.
    + exact Hneq.
  - destruct (Z.eq_dec (kernel_sum k) 0) as [Heq | Hneq].
    + lia.
    + exact Hneq.
Qed.

(** Lemma: Clamping strictly bounds any integer within [0, 255]. *)
Lemma clamp_channel_bounds :
  forall (v : Z),
    0 <= clamp_channel v <= 255.
Proof.
  intros v.
  unfold clamp_channel.
  lia.
Qed.

(** Theorem 2: The output of feConvolveMatrix channel evaluation is strictly within [0, 255]. *)
Theorem evaluate_convolve_channel_in_bounds :
  forall (k : Kernel) (pixels : list Z) (user_divisor : option Z) (bias : Z),
    0 <= evaluate_convolve_channel k pixels user_divisor bias <= 255.
Proof.
  intros k pixels user_divisor bias.
  unfold evaluate_convolve_channel.
  apply clamp_channel_bounds.
Qed.

(** Theorem 3: Default divisor equals kernel sum whenever kernel sum is non-zero. *)
Theorem default_divisor_is_kernel_sum :
  forall (k : Kernel),
    kernel_sum k <> 0 ->
    effective_divisor k None = kernel_sum k.
Proof.
  intros k Hnonzero.
  unfold effective_divisor.
  destruct (Z.eq_dec (kernel_sum k) 0) as [Heq | Hneq].
  - contradiction.
  - reflexivity.
Qed.

(** Theorem 4: Zero-sum kernel fallback guarantees unity divisor when user_divisor is None. *)
Theorem zero_sum_kernel_unity_divisor :
  forall (k : Kernel),
    kernel_sum k = 0 ->
    effective_divisor k None = 1.
Proof.
  intros k Hzero.
  unfold effective_divisor.
  destruct (Z.eq_dec (kernel_sum k) 0) as [Heq | Hneq].
  - reflexivity.
  - contradiction.
Qed.

(** Theorem 5: Valid non-zero user divisor overrides kernel sum. *)
Theorem user_divisor_override :
  forall (k : Kernel) (d : Z),
    d <> 0 ->
    effective_divisor k (Some d) = d.
Proof.
  intros k d Hnonzero.
  unfold effective_divisor.
  destruct (Z.eq_dec d 0) as [Heq | Hneq].
  - contradiction.
  - reflexivity.
Qed.
```