(** * Formal Verification & Parameter Specialization of Chromium Blink Leaf Functions
    Target Functions:
    1. [MinimumValueForLength]     (platform/geometry/length_functions.cc)
    2. [InlineSizeFromAspectRatio] (core/layout/length_utils.h)
*)

From Stdlib Require Import ZArith List Lia Bool.
Open Scope Z_scope.

(* ========================================================================== *)
(* 1. DOMAIN MODELS: 26.6 Fixed-Point LayoutUnit & Blink Geometry Primitives  *)
(* ========================================================================== *)

(** Blink's [LayoutUnit] is a 32-bit signed 26.6 fixed-point number.
    Here we represent the underlying raw integer value (in 1/64th pixel units)
    constrained to signed 32-bit integer bounds. *)
Definition LayoutUnit := Z.

Definition kInt32Min : Z := -2147483648.
Definition kInt32Max : Z :=  2147483647.
Definition kFixedPointDenominator : Z := 64.

(** Sentinel value for indefinite layout sizes (-1px = -64 raw units). *)
Definition kIndefiniteSize : LayoutUnit := -64.

(** Saturating 32-bit clamp operation used by [LayoutUnit] constructors and
    arithmetic operations. *)
Definition sat_clamp (x : Z) : LayoutUnit :=
  Z.max kInt32Min (Z.min kInt32Max x).

(** Saturating addition on [LayoutUnit]. *)
Definition lu_add (a b : LayoutUnit) : LayoutUnit :=
  sat_clamp (a + b).

(** Saturating subtraction on [LayoutUnit]. *)
Definition lu_sub (a b : LayoutUnit) : LayoutUnit :=
  sat_clamp (a - b).

(** 64-bit intermediate [MulDiv] with saturating clamping to 32-bit [LayoutUnit].
    Models [LayoutUnit::MulDiv(LayoutUnit, LayoutUnit, LayoutUnit)]. *)
Definition lu_mul_div (val num den : LayoutUnit) : LayoutUnit :=
  if Z.eqb den 0 then 0
  else sat_clamp (Z.quot (val * num) den).

(** Lemma: Values already within 32-bit bounds are unchanged by [sat_clamp]. *)
Lemma sat_clamp_id : forall x : Z,
  kInt32Min <= x <= kInt32Max ->
  sat_clamp x = x.
Proof.
  intros x [Hmin Hmax].
  unfold sat_clamp, kInt32Min, kInt32Max in *.
  lia.
Qed.

(** Lemma: [sat_clamp] is idempotent. *)
Lemma sat_clamp_idem : forall x : Z,
  sat_clamp (sat_clamp x) = sat_clamp x.
Proof.
  intros x.
  unfold sat_clamp, kInt32Min, kInt32Max.
  lia.
Qed.

(** Blink [Length] algebraic data type.
    - [Fixed v]: Raw fixed-point value [v] (already scaled by 64 or raw).
    - [Percent p]: Percentage value [p] in [0..100+].
    - [Auto]: Intrinsic / automatic sizing.
    - [FillAvailable]: Stretch to available space. *)
Inductive Length : Type :=
  | Fixed (v : Z)
  | Percent (pct : Z)
  | Auto
  | FillAvailable.

(** Blink [BoxStrut] pre-aggregated sums along inline and block axes. *)
Record BoxStrut : Type := mkBoxStrut {
  inline_sum : LayoutUnit;
  block_sum  : LayoutUnit
}.

(** Blink [LogicalSize] representing aspect ratio dimensions. *)
Record LogicalSize : Type := mkLogicalSize {
  aspect_inline : LayoutUnit;
  aspect_block  : LayoutUnit
}.

(** Blink [EBoxSizing] enumeration. *)
Inductive EBoxSizing : Type :=
  | ContentBox
  | BorderBox.


(* ========================================================================== *)
(* 2. FUNCTION 1: MinimumValueForLength                                       *)
(* ========================================================================== *)

(** ** 2a. General Gallina Specification *)

(** Models [MinimumValueForLength(const Length& length, LayoutUnit maximum_value)].
    For [Percent], if [maximum_value] is negative (e.g. [kIndefiniteSize]),
    minimum value resolves to [0]. Otherwise it scales via [lu_mul_div]. *)
Definition MinimumValueForLength (len : Length) (maximum_value : LayoutUnit) : LayoutUnit :=
  match len with
  | Fixed v => sat_clamp v
  | Percent pct =>
      if Z.ltb maximum_value 0 then 0
      else lu_mul_div maximum_value pct 100
  | Auto => 0
  | FillAvailable => 0
  end.

(** ** 2b. Step-by-Step Parameter Specializations *)

(** Specialization 1: [len = Fixed v].
    Eliminates the branch on [len] and ignores [maximum_value]. *)
Definition MinimumValueForLength_Fixed (v : Z) : LayoutUnit :=
  sat_clamp v.

(** Specialization 2: [len = Fixed v] where [v] is statically known to be within
    valid 32-bit [LayoutUnit] bounds. Eliminates saturation clamping completely. *)
Definition MinimumValueForLength_Fixed_Bounded (v : Z) : LayoutUnit :=
  v.

(** Specialization 3: [len = Percent pct] with an indefinite container
    ([maximum_value = kIndefiniteSize]). Constant-folds to [0]. *)
Definition MinimumValueForLength_Percent_Indefinite : LayoutUnit :=
  0.

(** Specialization 4: [len = Percent 100] with a non-negative bounded
    [maximum_value]. Reduces to the identity on [maximum_value]. *)
Definition MinimumValueForLength_Percent_100 (maximum_value : LayoutUnit) : LayoutUnit :=
  maximum_value.

(** Specialization 5: [len = Auto]. Constant-folds to [0]. *)
Definition MinimumValueForLength_Auto : LayoutUnit :=
  0.

(** ** 2c. Formal Equivalence Proofs for MinimumValueForLength *)

Theorem spec_MinimumValueForLength_Fixed :
  forall (v : Z) (maximum_value : LayoutUnit),
    MinimumValueForLength (Fixed v) maximum_value = MinimumValueForLength_Fixed v.
Proof.
  intros v maximum_value.
  reflexivity.
Qed.

Theorem spec_MinimumValueForLength_Fixed_Bounded :
  forall (v : Z) (maximum_value : LayoutUnit),
    kInt32Min <= v <= kInt32Max ->
    MinimumValueForLength (Fixed v) maximum_value = MinimumValueForLength_Fixed_Bounded v.
Proof.
  intros v maximum_value Hbounds.
  unfold MinimumValueForLength, MinimumValueForLength_Fixed_Bounded.
  apply sat_clamp_id.
  exact Hbounds.
Qed.

Theorem spec_MinimumValueForLength_Percent_Indefinite :
  forall (pct : Z),
    MinimumValueForLength (Percent pct) kIndefiniteSize =
    MinimumValueForLength_Percent_Indefinite.
Proof.
  intros pct.
  unfold MinimumValueForLength, kIndefiniteSize, MinimumValueForLength_Percent_Indefinite.
  reflexivity.
Qed.

Theorem spec_MinimumValueForLength_Percent_100 :
  forall (maximum_value : LayoutUnit),
    0 <= maximum_value <= kInt32Max ->
    MinimumValueForLength (Percent 100) maximum_value =
    MinimumValueForLength_Percent_100 maximum_value.
Proof.
  intros maximum_value [Hnonneg Hmax].
  unfold MinimumValueForLength, MinimumValueForLength_Percent_100, lu_mul_div.
  destruct (Z.ltb_spec maximum_value 0) as [Hlt | Hge].
  - lia.
  - simpl (Z.eqb 100 0).
    assert (Hquot : Z.quot (maximum_value * 100) 100 = maximum_value).
    { apply Z.quot_mul. lia. }
    rewrite Hquot.
    apply sat_clamp_id.
    unfold kInt32Min. lia.
Qed.

Theorem spec_MinimumValueForLength_Auto :
  forall (maximum_value : LayoutUnit),
    MinimumValueForLength Auto maximum_value = MinimumValueForLength_Auto.
Proof.
  intros maximum_value.
  reflexivity.
Qed.


(* ========================================================================== *)
(* 3. FUNCTION 2: InlineSizeFromAspectRatio                                   *)
(* ========================================================================== *)

(** ** 3a. General Gallina Specification *)

(** Models [InlineSizeFromAspectRatio(border_padding, aspect_ratio, box_sizing, block_size)]. *)
Definition InlineSizeFromAspectRatio
  (border_padding : BoxStrut)
  (aspect_ratio   : LogicalSize)
  (box_sizing     : EBoxSizing)
  (block_size     : LayoutUnit) : LayoutUnit :=
  match box_sizing with
  | BorderBox =>
      let content_block := lu_sub block_size (block_sum border_padding) in
      let scaled_inline := lu_mul_div content_block
                                      (aspect_inline aspect_ratio)
                                      (aspect_block aspect_ratio) in
      let total_inline  := lu_add scaled_inline (inline_sum border_padding) in
      Z.max (inline_sum border_padding) total_inline
  | ContentBox =>
      lu_mul_div block_size
                 (aspect_inline aspect_ratio)
                 (aspect_block aspect_ratio)
  end.

(** ** 3b. Step-by-Step Parameter Specializations *)

(** Specialization 1: [box_sizing = ContentBox].
    Eliminates [border_padding] lookup, subtraction, addition, and [Z.max]. *)
Definition InlineSizeFromAspectRatio_ContentBox
  (aspect_ratio : LogicalSize)
  (block_size   : LayoutUnit) : LayoutUnit :=
  lu_mul_div block_size (aspect_inline aspect_ratio) (aspect_block aspect_ratio).

(** Specialization 2: [box_sizing = ContentBox] with a square 1:1 aspect ratio
    ([aspect_inline = k] and [aspect_block = k] for [k > 0]) and valid 32-bit
    [block_size]. Eliminates multiplication and division completely. *)
Definition InlineSizeFromAspectRatio_ContentBox_Square
  (block_size : LayoutUnit) : LayoutUnit :=
  block_size.

(** Specialization 3: [box_sizing = BorderBox] with zero border/padding
    ([inline_sum = 0], [block_sum = 0]) and non-negative inputs.
    Reduces [BorderBox] directly to [ContentBox] scaling. *)
Definition InlineSizeFromAspectRatio_BorderBox_ZeroPadding
  (aspect_ratio : LogicalSize)
  (block_size   : LayoutUnit) : LayoutUnit :=
  lu_mul_div (sat_clamp block_size)
             (aspect_inline aspect_ratio)
             (aspect_block aspect_ratio).

(** Specialization 4: [box_sizing = BorderBox] with zero border/padding AND
    a square 1:1 aspect ratio on a non-negative bounded [block_size].
    Reduces the entire function to the identity on [block_size]. *)
Definition InlineSizeFromAspectRatio_BorderBox_ZeroPadding_Square
  (block_size : LayoutUnit) : LayoutUnit :=
  block_size.

(** ** 3c. Formal Equivalence Proofs for InlineSizeFromAspectRatio *)

Theorem spec_InlineSizeFromAspectRatio_ContentBox :
  forall (bp : BoxStrut) (ar : LogicalSize) (block_size : LayoutUnit),
    InlineSizeFromAspectRatio bp ar ContentBox block_size =
    InlineSizeFromAspectRatio_ContentBox ar block_size.
Proof.
  intros bp ar block_size.
  reflexivity.
Qed.

Theorem spec_InlineSizeFromAspectRatio_ContentBox_Square :
  forall (bp : BoxStrut) (k block_size : LayoutUnit),
    k > 0 ->
    kInt32Min <= block_size <= kInt32Max ->
    InlineSizeFromAspectRatio bp (mkLogicalSize k k) ContentBox block_size =
    InlineSizeFromAspectRatio_ContentBox_Square block_size.
Proof.
  intros bp k block_size Hk Hbounds.
  unfold InlineSizeFromAspectRatio, InlineSizeFromAspectRatio_ContentBox_Square, lu_mul_div.
  simpl.
  destruct (Z.eqb_spec k 0) as [Heq | Hneq].
  - lia.
  - assert (Hquot : Z.quot (block_size * k) k = block_size).
    { apply Z.quot_mul. lia. }
    rewrite Hquot.
    apply sat_clamp_id.
    exact Hbounds.
Qed.

Lemma lu_mul_div_nonneg :
  forall val num den : Z,
    0 <= val ->
    0 <= num ->
    0 < den ->
    0 <= lu_mul_div val num den.
Proof.
  intros val num den Hval Hnum Hden.
  unfold lu_mul_div.
  destruct (Z.eqb_spec den 0) as [Heq | Hneq].
  - lia.
  - unfold sat_clamp, kInt32Min, kInt32Max.
    assert (Hprod : 0 <= val * num) by lia.
    assert (Hq : 0 <= Z.quot (val * num) den).
    { apply Z.quot_pos; lia. }
    lia.
Qed.

Theorem spec_InlineSizeFromAspectRatio_BorderBox_ZeroPadding :
  forall (ar : LogicalSize) (block_size : LayoutUnit),
    0 <= block_size <= kInt32Max ->
    0 <= aspect_inline ar ->
    0 < aspect_block ar ->
    InlineSizeFromAspectRatio (mkBoxStrut 0 0) ar BorderBox block_size =
    InlineSizeFromAspectRatio_BorderBox_ZeroPadding ar block_size.
Proof.
  intros ar block_size Hbs Hinl Hblk.
  unfold InlineSizeFromAspectRatio, InlineSizeFromAspectRatio_BorderBox_ZeroPadding.
  simpl.
  unfold lu_sub, lu_add.
  replace (block_size - 0) with block_size by lia.
  pose proof (lu_mul_div_nonneg (sat_clamp block_size) (aspect_inline ar) (aspect_block ar)) as Hnonneg.
  assert (Hclamp_pos : 0 <= sat_clamp block_size).
  { rewrite sat_clamp_id by (unfold kInt32Min; lia). lia. }
  specialize (Hnonneg Hclamp_pos Hinl Hblk).
  replace (lu_mul_div (sat_clamp block_size) (aspect_inline ar) (aspect_block ar) + 0)
    with (lu_mul_div (sat_clamp block_size) (aspect_inline ar) (aspect_block ar)) by lia.

  assert (Hden: (aspect_block ar =? 0) = false) by (apply Z.eqb_neq; lia).
  unfold lu_mul_div in *.
  rewrite Hden in *.
  rewrite sat_clamp_idem.
  rewrite Z.max_r by exact Hnonneg.
  reflexivity.
Qed.

Theorem spec_InlineSizeFromAspectRatio_BorderBox_ZeroPadding_Square :
  forall (k block_size : LayoutUnit),
    k > 0 ->
    0 <= block_size <= kInt32Max ->
    InlineSizeFromAspectRatio (mkBoxStrut 0 0) (mkLogicalSize k k) BorderBox block_size =
    InlineSizeFromAspectRatio_BorderBox_ZeroPadding_Square block_size.
Proof.
  intros k block_size Hk Hbs.
  rewrite spec_InlineSizeFromAspectRatio_BorderBox_ZeroPadding; try lia; simpl; try lia.
  unfold InlineSizeFromAspectRatio_BorderBox_ZeroPadding,
         InlineSizeFromAspectRatio_BorderBox_ZeroPadding_Square,
         lu_mul_div.
  simpl.
  assert (Hk0: (k =? 0) = false) by (apply Z.eqb_neq; lia).
  rewrite Hk0.
  assert (Hid: sat_clamp block_size = block_size) by (apply sat_clamp_id; unfold kInt32Min; lia).
  rewrite Hid.
  rewrite Z.quot_mul by lia.
  exact Hid.
Qed.

(* ========================================================================== *)
(* 4. COMPUTATIONAL TESTS (EVALUATION IN COQ)                                 *)
(* ========================================================================== *)

(** Test 1: Fixed Length of 100px (6400 raw units) with max value 500px (32000). *)
Compute (MinimumValueForLength (Fixed 6400) 32000).
(* Expected: 6400 *)

(** Test 2: 50% Length of 200px (12800 raw units). *)
Compute (MinimumValueForLength (Percent 50) 12800).
(* Expected: 6400 *)

(** Test 3: 50% Length against Indefinite Size (-64). *)
Compute (MinimumValueForLength (Percent 50) kIndefiniteSize).
(* Expected: 0 *)

(** Test 4: ContentBox 16:9 aspect ratio with block_size = 90px (5760 raw units). *)
Compute (InlineSizeFromAspectRatio
           (mkBoxStrut 640 640)
           (mkLogicalSize 16 9)
           ContentBox
           5760).
(* Expected: 10240 (160px) *)

(** Test 5: BorderBox 16:9 aspect ratio with block_size = 100px (6400 raw units),
    block border_padding = 10px (640 raw units), inline border_padding = 20px (1280 raw units).
    Content block = 90px (5760) -> Scaled inline = 160px (10240) -> Total = 180px (11520). *)
Compute (InlineSizeFromAspectRatio
           (mkBoxStrut 1280 640)
           (mkLogicalSize 16 9)
           BorderBox
           6400).
(* Expected: 11520 (180px) *)
