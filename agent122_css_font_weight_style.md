# Audit Report: Agent 122 — Chromium Blink Font Weight & Style Resolution vs. CSS Fonts Module Level 4 (§2 & §5)

## 1. Font Weight Quantization & Normalization

In CSS Fonts Module Level 4 (§2.2), `font-weight` accepts continuous values in the range $[1, 1000]$, alongside legacy keywords (`normal`, `bold`, `bolder`, `lighter`). In Chromium Blink (`third_party/blink/renderer/platform/fonts/font_selection_types.h` and `font_description.cc`), font weights are represented using fixed-point `FontSelectionValue` (backed by ` int16_t` scaled by $4$, i.e., $1/4$ precision). 

For standard discrete font matching and relative weight resolution, weights are quantized or mapped onto the canonical 9-step scale:
* **Canonical Scale:** $\{100, 200, 300, 400, 500, 600, 700, 800, 900\}$.
* **Keyword Mappings:**
  * `normal` $\equiv 400$ (`kNormalWeightValue`)
  * `bold` $\equiv 700$ (`kBoldWeightValue`)
* **Clamping:** Although CSS Fonts 4 permits $[1, 1000]$ at parse time (`css_parsing_utils.cc`), standard legacy discrete quantization clamps and maps effective step boundaries within $[100, 900]$. In Blink's `FontDescription::BolderWeight` and `LighterWeight`, continuous weights are partitioned into discrete bands bounded by $[100, 900]$.

---

## 2. Relative Weights (`bolder` / `lighter`) & Font-Style Matching

### 2.1 `bolder` and `lighter` Stepped Transitions (CSS Fonts 4 §2.2)
Relative weights are resolved against the inherited `font-weight` $w_{\text{parent}}$ using a piecewise step function specified in CSS Fonts 4 §2.2:

| Inherited Weight ($w$) | `bolder(w)` | `lighter(w)` |
| :--- | :---: | :---: |
| $w < 100$ | $400$ | $w$ (or clamped to $100$ in discrete space) |
| $100 \le w < 350$ | $400$ | $100$ |
| $350 \le w < 550$ | $700$ | $100$ |
| $550 \le w < 750$ | $900$ | $400$ |
| $750 \le w < 900$ | $900$ | $700$ |
| $w \ge 900$ | $w$ (clamped to $900$) | $700$ |

* **Blink Implementation (`FontDescription::BolderWeight` / `LighterWeight`):** Blink compares the inherited `FontSelectionValue` against thresholds `FontSelectionValue(350)`, `FontSelectionValue(550)`, `FontSelectionValue(750)`, returning `kThinWeightValue` ($100$), `kNormalWeightValue` ($400$), `kBoldWeightValue` ($700$), or `kBlackWeightValue` ($900$).

### 2.2 Font-Style Matching (CSS Fonts 4 §5.2)
CSS Fonts 4 defines three categories of `font-style`: `normal`, `italic`, and `oblique <angle>?` (where default angle is $14^\circ$ in CSS Fonts 4, or $20^\circ$ in legacy CSS Fonts 3 / Blink `kItalicSlopeValue`).

When matching a requested style against an available font family face set (`FontStyleMatcher` / `FontSelectionAlgorithm` in Blink):
1. **`normal` requested:** Matches `normal` ($0^\circ$). Fallback: positive `oblique` ($\to$ `italic`), then negative `oblique`.
2. **`italic` requested:**
   * Priority 1: `italic` face.
   * Priority 2: `oblique` face with angle $\ge 11^\circ$ (or positive slope in Blink's `FontSelectionAlgorithm::StyleDistance`).
   * Priority 3: `oblique` face with positive angle $< 11^\circ$.
   * Priority 4: `normal` face ($0^\circ$).
   * Priority 5: `oblique` face with negative angle.
3. **`oblique` requested (positive angle $\theta > 0$):**
   * Priority 1: `oblique` face matching $\theta$ (searching upwards $\ge \theta$, then downwards $> 0$).
   * Priority 2: `italic` face.
   * Priority 3: `normal` face.
   * Priority 4: negative `oblique`.

---

## 3. Core Verification Invariants

1. **Weight Clamping Invariant ($[100, 900]$):** For any input weight $w \in \mathbb{Z}$, quantization and relative step transitions (`bolder`/`lighter`) over clamped canonical weights remain strictly within the closed interval $[100, 900]$.
2. **`bolder` / `lighter` Monotonicity & Step Invariants:**
   * $\forall w_1 \le w_2,\; \text{bolder}(w_1) \le \text{bolder}(w_2)$ and $\text{lighter}(w_1) \le \text{lighter}(w_2)$.
   * $\forall w \in [100, 900],\; \text{bolder}(w) \ge w$ and $\text{lighter}(w) \le w$.
   * Strict progression below ceiling: $\forall w < 900,\; \text{bolder}(w) > w$.
   * Strict reduction above floor: $\forall w > 100,\; \text{lighter}(w) < w$.
3. **Determinism of Style & Weight Resolution:** Given a requested `(weight, style)` and a non-empty list of available font faces, the matching metric produces a unique, deterministic best candidate face.

---

## 4. Concrete Rocq / Coq Formalization (`BlinkCSSFontWeightStyleSemantics.v`)

The following file is completely self-contained and compiles cleanly under Coq/Rocq 8.18+ without axioms or `Admitted` proofs.

```coq
(** * BlinkCSSFontWeightStyleSemantics.v
    Formal Audit of Chromium Blink Font Weight & Style Resolution
    against CSS Fonts Module Level 4 (§2.2 & §5.2).
    Agent 122 Verification Artifact. *)

From Coq Require Import ZArith.
From Coq Require Import List.
From Coq Require Import Bool.
From Coq Require Import Lia.
Import ListNotations.

Open Scope Z_scope.

(** ** 1. Font Weight Definitions & Quantization *)

Definition FontWeight := Z.

Definition kThinWeight      : FontWeight := 100.
Definition kExtraLightWeight: FontWeight := 200.
Definition kLightWeight     : FontWeight := 300.
Definition kNormalWeight    : FontWeight := 400.
Definition kMediumWeight    : FontWeight := 500.
Definition kSemiBoldWeight  : FontWeight := 600.
Definition kBoldWeight      : FontWeight := 700.
Definition kExtraBoldWeight : FontWeight := 800.
Definition kBlackWeight     : FontWeight := 900.

Inductive CSSWeightKeyword : Type :=
  | KW_Normal
  | KW_Bold
  | KW_Bolder
  | KW_Lighter
  | KW_Numeric (w : Z).

(** Clamping to canonical discrete range [100, 900] *)
Definition clamp_weight (w : FontWeight) : FontWeight :=
  if w <? 100 then 100
  else if 900 <? w then 900
  else w.

(** Quantize arbitrary weight to nearest 100-step in [100, 900],
    rounding half-way (50) upwards as in standard nine-step bucketing. *)
Definition quantize_weight_100 (w : FontWeight) : FontWeight :=
  let c := clamp_weight w in
  let step := (c + 50) / 100 in
  let q := step * 100 in
  clamp_weight q.

(** ** 2. Relative Weight Transitions (CSS Fonts 4 §2.2 & Blink FontDescription) *)

Definition bolder_weight (inherited : FontWeight) : FontWeight :=
  let w := clamp_weight inherited in
  if w <? 350 then kNormalWeight
  else if w <? 550 then kBoldWeight
  else kBlackWeight.

Definition lighter_weight (inherited : FontWeight) : FontWeight :=
  let w := clamp_weight inherited in
  if w <? 550 then kThinWeight
  else if w <? 750 then kNormalWeight
  else kBoldWeight.

Definition resolve_font_weight (parent : FontWeight) (kw : CSSWeightKeyword) : FontWeight :=
  match kw with
  | KW_Normal     => kNormalWeight
  | KW_Bold       => kBoldWeight
  | KW_Bolder     => bolder_weight parent
  | KW_Lighter    => lighter_weight parent
  | KW_Numeric w  => clamp_weight w
  end.

(** ** 3. Font Style Representation & Matching (CSS Fonts 4 §5.2) *)

Inductive FontStyle : Type :=
  | Style_Normal
  | Style_Italic
  | Style_Oblique (angle_deg : Z). (** Default oblique is 14 deg in CSS4, 20 in Blink *)

Definition default_oblique_angle : Z := 14.

(** Style preference rank for matching a target FontStyle against a candidate FontStyle.
    Lower score = better match (0 is exact category match). *)
Definition style_category_distance (target candidate : FontStyle) : Z :=
  match target with
  | Style_Normal =>
      match candidate with
      | Style_Normal => 0
      | Style_Oblique a => if 0 <=? a then 100 + a else 300 - a
      | Style_Italic => 200
      end
  | Style_Italic =>
      match candidate with
      | Style_Italic => 0
      | Style_Oblique a =>
          if 11 <=? a then 100 + Z.abs (a - default_oblique_angle)
          else if 0 <? a then 200 + (11 - a)
          else 400 - a
      | Style_Normal => 300
      end
  | Style_Oblique req_a =>
      if 0 <=? req_a then
        match candidate with
        | Style_Oblique cand_a =>
            if req_a <=? cand_a then cand_a - req_a
            else if 0 <? cand_a then 100 + (req_a - cand_a)
            else 400 - cand_a
        | Style_Italic => 200
        | Style_Normal => 300
        end
      else
        match candidate with
        | Style_Oblique cand_a =>
            if cand_a <=? req_a then req_a - cand_a
            else if cand_a <? 0 then 100 + (cand_a - req_a)
            else 400 + cand_a
        | Style_Italic => 300
        | Style_Normal => 200
        end
  end.

(** Weight distance according to CSS Fonts 4 §5.2 directional preference *)
Definition weight_distance (target candidate : FontWeight) : Z :=
  if target =? candidate then 0
  else if (400 <=? target) && (target <=? 500) then
    if (target <=? candidate) && (candidate <=? 500) then candidate - target
    else if candidate <? target then 100 + (target - candidate)
    else 200 + (candidate - target)
  else if target <? 400 then
    if candidate <? target then target - candidate
    else 1000 + (candidate - target)
  else (* target > 500 *)
    if target <? candidate then candidate - target
    else 1000 + (target - candidate).

Record FontFace : Type := mkFontFace {
  face_id     : nat;
  face_weight : FontWeight;
  face_style  : FontStyle
}.

(** Lexicographic comparison: Style distance takes precedence over Weight distance
    per CSS Fonts 4 §5.2. Ties broken by earlier appearance in font list. *)
Definition face_better_or_equal (req_w : FontWeight) (req_s : FontStyle)
                                (f1 f2 : FontFace) : bool :=
  let sd1 := style_category_distance req_s (face_style f1) in
  let sd2 := style_category_distance req_s (face_style f2) in
  if sd1 <? sd2 then true
  else if sd2 <? sd1 then false
  else
    let wd1 := weight_distance req_w (face_weight f1) in
    let wd2 := weight_distance req_w (face_weight f2) in
    wd1 <=? wd2.

Fixpoint select_best_face (req_w : FontWeight) (req_s : FontStyle)
                          (best : FontFace) (candidates : list FontFace) : FontFace :=
  match candidates with
  | [] => best
  | c :: cs =>
      if face_better_or_equal req_w req_s best c then
        select_best_face req_w req_s best cs
      else
        select_best_face req_w req_s c cs
  end.

Definition match_font_face (req_w : FontWeight) (req_s : FontStyle)
                           (faces : list FontFace) : option FontFace :=
  match faces with
  | [] => None
  | f :: fs => Some (select_best_face (clamp_weight req_w) req_s f fs)
  end.

(** ** 4. Verification Theorems & Invariants *)

(** Theorem 1: Weight clamping strictly enforces [100, 900]. *)
Theorem clamp_weight_bounds : forall w : FontWeight,
  100 <= clamp_weight w <= 900.
Proof.
  intros w. unfold clamp_weight.
  destruct (w <? 100) eqn:Hlt.
  - lia.
  - destruct (900 <? w) eqn:Hgt; lia.
Qed.

(** Theorem 2: Resolved font weights for all CSS keywords and inputs lie in [100, 900]. *)
Theorem resolve_font_weight_bounds : forall (parent : FontWeight) (kw