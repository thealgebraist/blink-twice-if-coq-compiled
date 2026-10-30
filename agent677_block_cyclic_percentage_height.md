# Formal Verification Report: Cyclic Percentage Height Resolution in Block Containers
**Agent ID:** 677 (W3C/WHATWG Layout Rules Verification Unit)  
**Target Module:** `third_party/blink/renderer/core/layout/layout_box.cc` (and LayoutNG equivalents in `length_utils.cc`)  
**Specification:** CSS 2.1 §10.5 ("Content height: the 'height' property") & CSS Box Sizing Module Level 3  
**Formal Theory Target:** `BlinkBlockCyclicPercentageHeightSemantics.v`  

---

## 1. Normative W3C Specification Requirements

According to **CSS 2.1 Section 10.5 (Content height: the 'height' property)** and **CSS Sizing Level 3 Section 5.2 (Percentage Sizing)**, the computation of percentage heights requires establishing whether the containing block's height is *definite* or *indefinite* (often creating a cyclic dependency when the containing block's height depends on the intrinsic height of its children).

### Normative Rules (CSS 2.1 §10.5):
1. **Percentage Specification (`<percentage>`):** Specifies a percentage height. The percentage is calculated with respect to the height of the generated box's containing block.
2. **Indefinite Containing Block Fallback (Cyclic Dependency Resolution):** 
   > *"If the height of the containing block is not specified explicitly (i.e., it depends on content height), and this element is not absolutely positioned, the value computes to `auto`."*
3. **Exception for Root and Quirks Mode:** A percentage height on the root element is relative to the initial containing block (ICB), which is always definite. In Quirks Mode, an indefinite containing block chain may traverse upwards until a definite height or the body/root element is reached. In Standards Mode, any `auto` height containing block (without external definite constraints like flex-item stretching or grid track sizing) breaks percentage resolution immediately.
4. **`auto` Height Fallback Semantics:** When a percentage height falls back to `auto` due to cyclicity, the used height of the box in normal block flow resolves to its intrinsic `content_height` (as specified in CSS 2.1 §10.6.3).

### Mathematical Formulation of the Spec Property:
Let $pct \in [0, \infty)$ be the percentage value (represented in fixed-point basis points or percentage points), $cb$ be the containing block, and $content\_height \ge 0$ be the intrinsic block content size of the box. For an in-flow block-level box in Standards Mode:

$$\text{resolve\_pct\_height}(pct, cb, content\_height) = \begin{cases} 
\lfloor \frac{pct \times \text{height}(cb)}{100} \rfloor & \text{if } \text{is\_definite}(cb) = \text{true} \\
content\_height & \text{if } \text{is\_definite}(cb) = \text{false}
\end{cases}$$

---

## 2. Chromium Blink Implementation Details & Invariants

In Chromium Blink (`third_party/blink/renderer/core/layout/layout_box.cc` and modern LayoutNG `third_party/blink/renderer/core/layout/length_utils.cc`), percentage height resolution is guarded by explicit definiteness checks to prevent layout oscillation and infinite recursion during the two-pass measure/layout phase.

### Key Blink Functions & Mechanisms:
1. **`LayoutBox::ComputePercentageLogicalHeight(const Length& height)` / `BlockLengthUnresolvable(...)`:**
   - **Sentinel Value `kIndefiniteSize` (`LayoutUnit(-1)`):** Blink uses `-1` in fixed-point `LayoutUnit` (where $1\text{px} = 64\text{ subpixels}$) to represent an indefinite or cyclic containing block dimension (`ConstraintSpace::AvailableSize().block_size == kIndefiniteSize`).
   - **Out-of-Flow Check:** If `IsOutOfFlowPositioned()` is true, the containing block's padding box height is already computed before laying out positioned descendants, making the height definite even if the CB has `height: auto`.
   - **Cyclic Detection:** For in-flow boxes in Standards Mode (`!GetDocument().InQuirksMode()`), if the containing block has `style.LogicalHeight().IsAuto()` (or is an unresolvable percentage itself) and its height is not overridden by parent layout contexts (e.g., `HasOverrideLogicalHeight()`, Flex stretched item, or Grid area), `AvailableLogicalHeight` evaluates to `kIndefiniteSize` (`-1`).
2. **Resolution Path (`ResolveMainBlockLength`):**
   - Calls `BlockLengthUnresolvable(constraint_space, length)`.
   - If `length.HasPercent()` and `available_size == kIndefiniteSize`, `BlockLengthUnresolvable` returns `true`.
   - When `true`, the caller falls back to the `auto` behavior: the box's block size is assigned `intrinsic_block_size` (`content_height`) after laying out its children.
   - When `false`, it computes `MinimumValueForLength(length, available_size)`, which performs fixed-point scaling `(pct * cb_height) / 100`.

### Core Implementation Invariants:
- **Invariant 1 (Cycle Termination):** For any finite ancestor chain of containing blocks, evaluating whether the containing block height is definite terminates in $O(d)$ steps where $d$ is DOM depth.
- **Invariant 2 (Non-Negativity of Used Height):** Despite using `-1` (`kIndefiniteSize`) internally as an intermediate sentinel for indefinite available height, the resolved used height of a box is strictly non-negative ($\ge 0$) provided `content_height >= 0` and `pct >= 0`.
- **Invariant 3 (Monotonicity):** When the containing block height is definite, increasing either `pct` or `cb_height` monotonically increases (or keeps equal) the resolved height.
- **Invariant 4 (Idempotence / Independence under Indefiniteness):** When the containing block is indefinite, the resolved height is completely invariant with respect to changes in `pct`.

---

## 3. Formal Specification & Verification in Rocq/Coq

Below is the complete, self-contained formalization `BlinkBlockCyclicPercentageHeightSemantics.v`. It models both the high-level W3C specification and Blink's `LayoutUnit(-1)` (`kIndefiniteSize`) sentinel-based implementation, proving their exact behavioral equivalence and structural layout invariants.

```coq
(** * BlinkBlockCyclicPercentageHeightSemantics.v
    Formal Verification of W3C CSS 2.1 §10.5 Cyclic Percentage Height Resolution
    Target: third_party/blink/renderer/core/layout/layout_box.cc
    Agent: 677
*)

Require Import Coq.ZArith.ZArith.
Require Import Coq.micromega.Lia.
Require Import Coq.Bool.Bool.
Require Import Coq.Lists.List.
Import ListNotations.

Open Scope Z_scope.

(** ** 1. Basic Types and Layout Primitives *)

(** In Blink, LayoutUnit is a fixed-point integer. We model dimensions in Z.
    kIndefiniteSize is represented in Blink as LayoutUnit(-1). *)
Definition LayoutUnit := Z.
Definition kIndefiniteSize : LayoutUnit := -1.

(** CSS Length representation for height *)
Inductive CssLength : Type :=
  | LenAuto : CssLength
  | LenFixed : Z -> CssLength      (* Fixed non-negative LayoutUnit *)
  | LenPercent : Z -> CssLength.   (* Percentage in [0, 100+] *)

(** Box positioning scheme *)
Inductive PositionType : Type :=
  | PosInFlow : PositionType
  | PosOutOfFlow : PositionType.   (* absolute / fixed *)

(** Document mode *)
Inductive DocumentMode : Type :=
  | StandardsMode : DocumentMode
  | QuirksMode : DocumentMode.

(** Representation of a Containing Block (CB) in the ancestor chain *)
Record ContainingBlock := mkCB {
  cb_style_height : CssLength;
  cb_override_height : option Z;   (* e.g. Flex/Grid forced definite height *)
  cb_is_root : bool                (* Root/ICB always has definite viewport height *)
}.

(** ** 2. Containing Block Definiteness & Ancestor Chain Resolution *)

(** Checks if a single Containing Block has an immediately definite height
    without inspecting parent ancestors, given a viewport height. *)
Definition is_cb_immediately_definite (cb : ContainingBlock) : bool :=
  if cb_is_root cb then true
  else match cb_override_height cb with
       | Some h => (0 <=? h)
       | None =>
           match cb_style_height cb with
           | LenFixed h => (0 <=? h)
           | _ => false
           end
       end.

(** Recursive resolution of containing block chain height (Standards Mode).
    Returns Some h (with h >= 0) if definite, or None if cyclic/indefinite. *)
Fixpoint evaluate_cb_chain (chain : list ContainingBlock) (viewport_h : Z) : option Z :=
  match chain with
  | [] =>
      (* Initial Containing Block (ICB) / Viewport *)
      if 0 <=? viewport_h then Some viewport_h else None
  | cb :: parent_chain =>
      if cb_is_root cb then
        if 0 <=? viewport_h then Some viewport_h else None
      else
        match cb_override_height cb with
        | Some h => if 0 <=? h then Some h else None
        | None =>
            match cb_style_height cb with
            | LenFixed h => if 0 <=? h then Some h else None
            | LenAuto => None (* Cyclic dependency broken: computes to Indefinite *)
            | LenPercent pct =>
                if 0 <=? pct then
                  match evaluate_cb_chain parent_chain viewport_h with
                  | Some parent_h => Some ((pct * parent_h) / 100)
                  | None => None
                  end
                else None
            end
        end
  end.

(** W3C Specification Predicate: Is the containing block height definite? *)
Definition is_definite (cb_opt : option Z) : bool :=
  match cb_opt with
  | Some h => 0 <=? h
  | None => false
  end.

(** Extract height value (defaults to 0 if None, guarded by is_definite) *)
Definition cb_val (cb_opt : option Z) : Z :=
  match cb_opt with
  | Some h => h
  | None => 0
  end.

(** ** 3. W3C Specification Function: resolve_pct_height *)

(** Mathematical Property from W3C CSS 2.1 §10.5:
    resolve_pct_height(pct, cb_height) =
      if is_definite(cb) then (pct * cb) / 100 else content_height. *)
Definition spec_resolve_pct_height (pct : Z) (cb : option Z) (content_height : Z) : Z :=
  if is_definite cb then (pct * (cb_val cb)) / 100
  else content_height.

(** ** 4. Blink Implementation Model (layout_box.cc / length_utils.cc) *)

(** Converts an evaluated CB chain option into Blink's LayoutUnit sentinel representation.
    In Blink, AvailableLogicalHeight returns kIndefiniteSize (-1) when unresolvable. *)
Definition blink_available_logical_height (cb : option Z) : LayoutUnit :=
  match cb with
  | Some h => if 0 <=? h then h else kIndefiniteSize
  | None => kIndefiniteSize
  end.

(** Blink's BlockLengthUnresolvable check (length_utils.cc):
    A percentage length is unresolvable if available_height == kIndefiniteSize (-1). *)
Definition blink_block_length_unresolvable (avail_h : LayoutUnit) : bool :=
  avail_h =? kIndefiniteSize.

(** Blink's ComputePercentageLogicalHeight / ResolveMainBlockLength implementation *)
Definition blink_resolve_pct_height (pct : Z) (avail_h : LayoutUnit) (content_height : LayoutUnit) : LayoutUnit :=
  if blink_block_length_unresolvable avail_h then
    content_height
  else
    (pct * avail_h) / 100.
```

---

## 4. Concrete Theorems and Complete Admitted-Free Proofs

We now prove five core theorems establishing:
1. **Sentinel Integrity:** `blink_available_logical_height` returns a non-negative height if and only if the containing block is definite, and returns `kIndefiniteSize` (`-1`) otherwise.
2. **Spec-Implementation Equivalence:** Blink's sentinel-based resolution is mathematically identical to the W3C CSS 2.1 §10.5 specification `spec_resolve_pct_height`.
3. **Cyclic Fallback Independence:** When the containing block is indefinite (`LenAuto` in `StandardsMode`), the resolved height equals `content_height` for any percentage `pct`.
4. **Non-Negativity Invariant Preservation:** Despite the `-1` sentinel, resolved layout height is always $\ge 0$ for valid inputs.
5. **Monotonicity under Definite Containing Blocks:** When the containing block is definite, percentage scaling is monotonic in both `pct` and `cb_height`.

```coq
(** ** 5. Formal Verification Proofs *)

(** Theorem 1: Blink's kIndefiniteSize sentinel exactly encodes indefiniteness. *)
Theorem blink_sentinel_correctness :
  forall (cb : option Z),
    blink_block_length_unresolvable (blink_available_logical_height cb) = negb (is_definite cb).
Proof.
  intros cb.
  unfold blink_block_length_unresolvable, blink_available_logical_height, is_definite, kIndefiniteSize.
  destruct cb as [h | ].
  - destruct (0 <=? h) eqn:Hle.
    + apply Z.leb_le in Hle.
      simpl.
      destruct (h =? -1) eqn:Heq.
      * apply Z.eqb_eq in Heq. lia.
      * reflexivity.
    + simpl. reflexivity.
  - simpl. reflexivity.
Qed.

(** Theorem 2: Exact Equivalence between Blink's LayoutBox implementation
    and W3C CSS 2.1 §10.5 Specification. *)
Theorem blink_matches_w3c_spec :
  forall (pct : Z) (cb : option Z) (content_height : Z),
    blink_resolve_pct_height pct (blink_available_logical_height cb) content_height =
    spec_resolve_pct_height pct cb content_height.
Proof.
  intros pct cb content_height.
  unfold blink_resolve_pct_height, spec_resolve_pct_height.
  rewrite blink_sentinel_correctness.
  unfold blink_available_logical_height, is_definite, cb_val.
  destruct cb as [h | ].
  - destruct (0 <=? h) eqn:Hle; simpl; reflexivity.
  - simpl. reflexivity.
Qed.

(** Theorem 3: Cyclic Auto Containing Block Fallback.
    If the immediate containing block has height: auto, no override height,
    and is