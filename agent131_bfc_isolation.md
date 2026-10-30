### 1. Conditions Establishing a Block Formatting Context (BFC)

Per CSS 2.1 §9.4.1 ("Block formatting contexts") and its extensions in CSS Display Module Level 3, an element establishes a new BFC for its contents if it satisfies any of the following conditions:

1. **Root Element**: The document root (`<html>`).
2. **Floats**: The computed `float` property is not `none` (`left` or `right`).
3. **Out-of-Flow Positioned Elements**: The computed `position` property is `absolute` or `fixed`.
4. **Atomic Inline-Level Boxes**: The computed `display` is `inline-block`, `table-cell`, or `table-caption` (extended in modern Blink to `inline-flex`, `inline-grid`).
5. **Non-Visible Block Overflow**: Block box with a computed `overflow` property other than `visible` (`hidden`, `scroll`, `auto`, `clip`).
6. **Explicit Formatting Context Roots**: `display: flow-root` (explicitly triggers BFC creation without side effects), `contain: layout` or `contain: paint`.

**Chromium Blink Implementation (`LayoutNG`)**:
In Blink's LayoutNG architecture, BFC creation is resolved during layout tree construction and enforced via `NGBlockNode::CreatesNewFormattingContext()`. When this returns `true`, Blink instantiates an isolated `NGBlockLayoutAlgorithm` with a fresh `NGConstraintSpace` where `IsNewFormattingContext()` is set to `true`.

---

### 2. Margin Collapsing Isolation

Per CSS 2.1 §8.3.1 ("Collapsing margins"), margins between adjacent block boxes only collapse if they participate in the *same* Block Formatting Context. 

**Boundary Isolation Rules**:
* **Top Boundary**: The `margin-top` of a BFC root does *not* collapse with the `margin-top` of its first in-flow block-level child.
* **Bottom Boundary**: The `margin-bottom` of a BFC root does *not* collapse with the `margin-bottom` of its last in-flow block-level child (even if `height: auto`).
* **External Participation**: While a BFC root isolates its *internal* margins from the outside, the BFC root's *own* outer margins still collapse with adjacent siblings within its parent's BFC (unless the BFC root itself is out-of-flow or floating).

**Blink Implementation**:
In `NGBlockLayoutAlgorithm`, margin collapsing is tracked via an `NGMarginStrut` passed along the `NGConstraintSpace` and returned via `NGLayoutResult::EndMarginStrut()`. When `ConstraintSpace().IsNewFormattingContext()` is true:
1. The incoming `MarginStrut` from the parent is reset to zero at the entry of the child's layout pass.
2. Any trailing `EndMarginStrut` produced by the last child is forcefully resolved (added to the BFC root's intrinsic block size) rather than being exported to the parent's layout result.

---

### 3. BFC Isolation Invariants

1. **Internal Margin Confinement (Invariant 1)**: 
   For any block box $B$ establishing a BFC, the effective outer margin strut exported by $B$ to its parent formatting context is strictly determined by $B$'s own authored margins (`margin-top`, `margin-bottom`), completely independent of the margin struts of $B$'s descendants.
2. **Internal Float Containment / Auto-Height Expansion (Invariant 2)**: 
   Per CSS 2.1 §10.6.7 ("'Auto' heights for block formatting context roots"), if a BFC root has `height: auto`, its computed block size expands to encompass the bottom-most margin edge of any descendant floats participating in that BFC. Internal floats cannot protrude into or affect sibling layout outside the BFC root (`NGExclusionSpace` is not exported across BFC boundaries).

---

### 4. Formal Verification in Rocq/Coq (`BlinkBFCIsolationSemantics.v`)

```coq
(** * BlinkBFCIsolationSemantics.v
    Formalization of Chromium Blink LayoutNG BFC Isolation vs CSS 2.1 §9.4.1 *)

Require Import Coq.Arith.Arith.
Require Import Coq.ZArith.ZArith.
Require Import Coq.Lists.List.
Require Import Coq.Bool.Bool.
Import ListNotations.
Open Scope Z_scope.

(** ** 1. CSS Property Definitions *)

Inductive Display :=
  | DisplayBlock
  | DisplayInlineBlock
  | DisplayTableCell
  | DisplayTableCaption
  | DisplayFlowRoot
  | DisplayInline.

Inductive FloatProp :=
  | FloatNone
  | FloatLeft
  | FloatRight.

Inductive Position :=
  | PosStatic
  | PosRelative
  | PosAbsolute
  | PosFixed.

Inductive Overflow :=
  | OverflowVisible
  | OverflowHidden
  | OverflowScroll
  | OverflowAuto
  | OverflowClip.

Record ComputedStyle := mkStyle {
  disp     : Display;
  flt      : FloatProp;
  pos      : Position;
  ovf      : Overflow;
  margin_t : Z;
  margin_b : Z;
  height_auto : bool;
  explicit_height : Z
}.

(** ** 2. BFC Establishment Predicate (CSS 2.1 §9.4.1 & Blink CreatesNewFormattingContext) *)

Definition establishes_bfc (is_root : bool) (s : ComputedStyle) : bool :=
  is_root ||
  match s.(flt) with FloatNone => false | _ => true end ||
  match s.(pos) with PosAbsolute | PosFixed => true | _ => false end ||
  match s.(disp) with
  | DisplayInlineBlock | DisplayTableCell | DisplayTableCaption | DisplayFlowRoot => true
  | _ => false
  end ||
  match s.(disp), s.(ovf) with
  | DisplayBlock, OverflowVisible => false
  | DisplayBlock, _ => true
  | _, _ => false
  end.

(** ** 3. Layout Tree & Margin Strut Semantics (LayoutNG Model) *)

Record MarginStrut := mkStrut {
  pos_margin : Z; (* >= 0 *)
  neg_margin : Z  (* <= 0 *)
}.

Definition empty_strut : MarginStrut := mkStrut 0 0.

Definition resolve_strut (ms : MarginStrut) : Z :=
  ms.(pos_margin) + ms.(neg_margin).

Definition append_margin (ms : MarginStrut) (m : Z) : MarginStrut :=
  if m >=? 0 then
    mkStrut (Z.max ms.(pos_margin) m) ms.(neg_margin)
  else
    mkStrut ms.(pos_margin) (Z.min ms.(neg_margin) m).

Definition collapse_struts (ms1 ms2 : MarginStrut) : MarginStrut :=
  mkStrut (Z.max ms1.(pos_margin) ms2.(pos_margin))
          (Z.min ms1.(neg_margin) ms2.(neg_margin)).

(** Abstract representation of a LayoutBox and its children *)
Inductive LayoutBox :=
  | Box (is_root : bool)
        (style : ComputedStyle)
        (internal_float_max_bottom : Z) (* Max bottom edge of internal floats *)
        (children_top_strut : MarginStrut)
        (children_bottom_strut : MarginStrut)
        (children_content_height : Z).

(** ** 4. Blink NGBlockLayoutAlgorithm Margin & Height Resolution *)

Record LayoutResult := mkResult {
  exported_top_strut    : MarginStrut;
  exported_bottom_strut : MarginStrut;
  used_block_size       : Z
}.

Definition layout_box (b : LayoutBox) : LayoutResult :=
  match b with
  | Box is_root s float_bot c_top c_bot c_height =>
      let own_top := append_margin empty_strut s.(margin_t) in
      let own_bot := append_margin empty_strut s.(margin_b) in
      if establishes_bfc is_root s then
        (* BFC Isolation: Internal struts are resolved inside the box and NOT exported *)
        let internal_height := c_height + resolve_strut c_top + resolve_strut c_bot in
        let final_height :=
          if s.(height_auto) then Z.max internal_height float_bot
          else s.(explicit_height)
        in
        mkResult own_top own_bot final_height
      else
        (* Non-BFC: Margins collapse through the box boundaries if height is auto/unblocked *)
        let exp_top := collapse_struts own_top c_top in
        let exp_bot := collapse_struts own_bot c_bot in
        let final_height :=
          if s.(height_auto) then c_height else s.(explicit_height)
        in
        mkResult exp_top exp_bot final_height
  end.

(** ** 5. Verification of BFC Isolation Invariants *)

(** Theorem 1: Overflow != visible on a Block establishes a BFC *)
Theorem non_visible_overflow_creates_bfc :
  forall is_root s,
    s.(disp) = DisplayBlock ->
    s.(ovf) <> OverflowVisible ->
    establishes_bfc is_root s = true.
Proof.
  intros is_root s Hdisp Hovf.
  unfold establishes_bfc.
  rewrite Hdisp.
  destruct (s.(ovf)) eqn:E; try contradiction;
  repeat rewrite orb_true_r; reflexivity.
Qed.

(** Theorem 2 (Invariant 1): Internal Margin Confinement.
    If a box establishes a BFC, its exported top and bottom margin struts
    are completely independent of its children's margin struts. *)
Theorem bfc_isolates_internal_margins :
  forall is_root s f_bot c_top1 c_top2 c_bot1 c_bot2 ch,
    establishes_bfc is_root s = true ->
    let res1 := layout_box (Box is_root s f_bot c_top1 c_bot1 ch) in
    let res2 := layout_box (Box is_root s f_bot c_top2 c_bot2 ch) in
    res1.(exported_top_strut) = res2.(exported_top_strut) /\
    res1.(exported_bottom_strut) = res2.(exported_bottom_strut).
Proof.
  intros is_root s f_bot c_top1 c_top2 c_bot1 c_bot2 ch Hbfc.
  simpl. rewrite Hbfc. simpl.
  split; reflexivity.
Qed.

(** Theorem 3 (Invariant 2): Auto-Height Float Containment (CSS 2.1 §10.6.7).
    A BFC root with height: auto expands its used block size to at least
    encompass its internal floats' bottom-most edge. *)
Theorem bfc_encompasses_internal_floats :
  forall is_root s f_bot c_top c_bot ch,
    establishes_bfc is_root s = true ->
    s.(height_auto) = true ->
    let res := layout_box (Box is_root s f_bot c_top c_bot ch) in
    res.(used_block_size) >= f_bot.
Proof.
  intros is_root s f_bot c_top c_bot ch Hbfc Hauto.
  simpl. rewrite Hbfc. rewrite Hauto. simpl.
  apply Z.le_ge.
  apply Z.le_max_r.
Qed.
```