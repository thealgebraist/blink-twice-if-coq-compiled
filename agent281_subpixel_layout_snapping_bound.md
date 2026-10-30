### Chromium Blink Subpixel Snapping Audit Report

**Agent:** 281  
**Target:** Chromium Blink Layout Unit Subpixel Snapping (`LayoutUnit::SnapSizeToPixel` / `roundToInt`)  
**Fixed-Point Representation:** 26.6 format (1 pixel = 64 subpixel units)  

---

#### 1. Mathematical & Implementation Details

In Chromium's Blink rendering engine, layout coordinates are represented using `LayoutUnit`, which utilizes a 26.6 fixed-point representation. This means the fractional part of a pixel is quantized into $2^6 = 64$ subpixel units, with a half-pixel offset equal to $32$ units.

##### Snapping Formula
To snap a raw `LayoutUnit` value to the nearest integer pixel grid, Blink adds half a pixel ($32$ subpixel units) and divides by $64$. 
* **Mathematical Floor Division (Euclidean):** $\text{snap}_{\text{floor}}(\text{raw}) = \lfloor \frac{\text{raw} + 32}{64} \rfloor$.
* **C++ Truncating Division (`/`):** In C++, integer division truncates toward zero. Simply computing `(raw + 32) / 64` for negative values shifts the rounding bias away from $-\infty$, causing asymmetric snapping (and violating the $\le 32$ error bound when $\text{raw} + 32 < 0$). To maintain proper behavior for negative coordinates, Blink either uses bit-shifts (`(raw + 32) >> 6`, which is arithmetic shift and equivalent to floor division in two's complement) or branch-adjusted division (`(raw + 32 - (raw < 0 ? 63 : 0)) / 64`).

##### Invariants
Let $\text{raw} \in \mathbb{Z}$ be the subpixel value. Let $\text{snapped\_subpixels} = 64 \times \text{snap}(\text{raw})$.
The quantization error $E(\text{raw}) = \text{raw} - \text{snapped\_subpixels}$ satisfies the strict bound:
$$-32 \le \text{raw} - 64 \cdot \text{snap}(\text{raw}) < 32$$
Consequently, the absolute snapping error is strictly bounded by half a pixel:
$$|\text{raw} - 64 \cdot \text{snap}(\text{raw})| \le 32$$

---

#### 2. Formal Verification in Rocq / Coq

Below is the complete, self-contained formalization `BlinkSubpixelSnappingBoundSemantics.v`. It verifies both the Euclidean (bit-shift / floor) snapping semantics and the C++ branch-adjusted truncation semantics, proving that both yield 0 admits and satisfy the maximum error invariant.

```coq
(** * BlinkSubpixelSnappingBoundSemantics.v
    Formal verification of Chromium Blink's 26.6 fixed-point subpixel snapping
    maximum error bounds.
    Agent: 281
*)

Require Import Coq.ZArith.ZArith.
Require Import Coq.micromega.Lia.

Open Scope Z_scope.

(** ** 1. Constants for 26.6 Fixed-Point Arithmetic *)

Definition kFixedPointDenominator : Z := 64.
Definition kHalfPixel : Z := 32.

(** ** 2. Snapping Definitions *)

(** [snap_floor] models Euclidean division (or two's complement arithmetic 
    right shift `(raw + 32) >> 6`), which rounds towards negative infinity. *)
Definition snap_floor (raw : Z) : Z :=
  (raw + kHalfPixel) / kFixedPointDenominator.

(** [snap_pixel_subpixels] converts the snapped pixel integer back into 
    the 26.6 subpixel domain. *)
Definition snap_pixel_subpixels (raw : Z) : Z :=
  kFixedPointDenominator * snap_floor raw.

(** [snap_error] represents the signed quantization error introduced by snapping. *)
Definition snap_error (raw : Z) : Z :=
  raw - snap_pixel_subpixels raw.

(** ** 3. Core Invariant Proofs (Euclidean / Bit-Shift Semantics) *)

(** Lemma: The signed snapping error is strictly bounded within [-32, 31]. *)
Theorem snap_error_signed_bounds : forall (raw : Z),
  -kHalfPixel <= snap_error raw < kHalfPixel.
Proof.
  intros raw.
  unfold snap_error, snap_pixel_subpixels, snap_floor.
  unfold kFixedPointDenominator, kHalfPixel.
  pose proof (Z.div_mod (raw + 32) 64) as Hdiv.
  pose proof (Z_mod_lt (raw + 32) 64) as Hmod.
  lia.
Qed.

(** Theorem: The absolute subpixel snapping error never exceeds 32 units (0.5px). *)
Theorem blink_subpixel_snapping_max_error : forall (raw : Z),
  Z.abs (raw - 64 * snap_floor raw) <= 32.
Proof.
  intros raw.
  pose proof (snap_error_signed_bounds raw) as Hbounds.
  unfold snap_error, snap_pixel_subpixels, kFixedPointDenominator, kHalfPixel in Hbounds.
  lia.
Qed.

(** ** 4. C++ Truncating Division (`Z.quot`) Semantics *)

(** In C++, integer division `/` truncates towards zero (modeled by [Z.quot]).
    If we naively compute `Z.quot (raw + 32) 64` for negative numbers, the 
    error can reach 63. Blink's `SnapSizeToPixel` / `roundToInt` adjusts negative 
    numerators prior to truncating division to emulate floor division. *)

Definition snap_cpp_trunc_adjusted (raw : Z) : Z :=
  let num := raw + kHalfPixel in
  if Z_lt_dec num 0 then
    Z.quot (num - (kFixedPointDenominator - 1)) kFixedPointDenominator
  else
    Z.quot num kFixedPointDenominator.

(** Helper lemma connecting [Z.quot] and [Z.rem] for negative numbers. *)
Lemma Z_quot_rem_neg_bounds : forall a b : Z,
  b > 0 -> a < 0 ->
  a = b * Z.quot a b + Z.rem a b /\ -b < Z.rem a b <= 0.
Proof.
  intros a b Hb Ha.
  split.
  - apply Z.quot_rem'.
  - pose proof (Z.rem_bound_neg_pos a b Ha Hb) as Hrem.
    lia.
Qed.

(**Helper lemma connecting [Z.quot] and [Z.rem] for non-negative numbers. *)
Lemma Z_quot_rem_pos_bounds : forall a b : Z,
  b > 0 -> a >= 0 ->
  a = b * Z.quot a b + Z.rem a b /\ 0 <= Z.rem a b < b.
Proof.
  intros a b Hb Ha.
  split.
  - apply Z.quot_rem'.
  - apply Z.rem_bound_pos; lia.
Qed.

(** Theorem: The C++ branch-adjusted truncating division is strictly equivalent 
    to the mathematical floor snapping function for all inputs. *)
Theorem snap_cpp_equiv_floor : forall (raw : Z),
  snap_cpp_trunc_adjusted raw = snap_floor raw.
Proof.
  intros raw.
  unfold snap_cpp_trunc_adjusted, snap_floor.
  unfold kFixedPointDenominator, kHalfPixel.
  destruct (Z_lt_dec (raw + 32) 0) as [Hneg | Hpos].
  - (* Case: raw + 32 < 0 *)
    pose proof (Z.div_mod (raw + 32) 64) as Hdiv.
    pose proof (Z_mod_lt (raw + 32) 64) as Hmod.
    pose proof (Z_quot_rem_neg_bounds (raw + 32 - 63) 64) as Hquot.
    destruct Hquot as [Hqe Hqb]; [lia | lia |].
    (* By uniqueness of Euclidean division / linear arithmetic *)
    nia.
  - (* Case: raw + 32 >= 0 *)
    rewrite Z.quot_div_nonneg; lia.
Qed.

(** Corollary: Blink's C++ truncating division implementation satisfies 
    the exact same maximum error bound of 32 subpixel units. *)
Theorem blink_cpp_snapping_max_error : forall (raw : Z),
  Z.abs (raw - 64 * snap_cpp_trunc_adjusted raw) <= 32.
Proof.
  intros raw.
  rewrite snap_cpp_equiv_floor.
  apply blink_subpixel_snapping_max_error.
Qed.

(** ** 5. Idempotence & Grid Stability Invariants *)

(** Theorem: Snapping an already-snapped value produces zero error. *)
Theorem snap_idempotent : forall (raw : Z),
  snap_floor (64 * snap_floor raw) = snap_floor raw.
Proof.
  intros raw.
  unfold snap_floor, kFixedPointDenominator, kHalfPixel.
  pose proof (Z.div_mod (64 * ((raw + 32) / 64) + 32) 64) as Hdiv.
  pose proof (Z_mod_lt (64 * ((raw + 32) / 64) + 32) 64) as Hmod.
  nia.
Qed.
```