### Audit Report: Agent 194 — Chromium Blink Absolute Auto Margins Centering vs. CSS Positioned Layout 3 §5.2

#### 1. Free Space Computation & Auto Margin Distribution
In CSS Positioned Layout Module Level 3 §5.2 ("Abspos Auto Margins"), when an absolutely positioned box has both `left` and `right` insets specified (non-`auto`), as well as a definite `width`, any remaining space in the containing block is distributed to `auto` horizontal margins.

In Chromium Blink (`ng_absolute_utils.cc` / ` ComputeAbsoluteSize`), the horizontal constraint equation is evaluated in `LayoutUnit` (fixed-point integer arithmetic):
1. **Free Space Calculation**:
   $$\text{free\_space} = \text{cb\_width} - (\text{left} + \text{width} + \text{right})$$
   *(Note: Here, $\text{width}$ represents the border-box width of the element).*

2. **Margin Distribution**:
   When both `margin-left` and `margin-right` are `auto`:
   - **Non-negative Free Space ($\text{free\_space} \ge 0$)**: The element is centered within the available inset space. Because Blink uses integer division (truncating towards zero), any odd remainder unit is assigned to the trailing margin (in LTR, `margin-right`) or preserved via exact remainder subtraction:
     $$\text{margin\_left} = \lfloor \text{free\_space} / 2 \rfloor$$
     $$\text{margin\_right} = \text{free\_space} - \text{margin\_left}$$
   - **Negative Free Space ($\text{free\_space} < 0$)**: If the box is larger than the space between the insets, CSS specifies that `margin-left` is set to $0$ (in LTR) and the remaining negative space is absorbed by `margin-right`:
     $$\text{margin\_left} = 0$$
     $$\text{margin\_right} = \text{free\_space}$$

---

#### 2. Verified Invariants
1. **Conservation of Free Space (Boundedness)**:
   $$\text{margin\_left} + \text{margin\_right} \le \text{free\_space}$$
   *(In exact arithmetic and Blink's subtraction-based remainder assignment, $\text{margin\_left} + \text{margin\_right} = \text{free\_space}$ holds strictly).*
2. **Centering within Insets (when $\text{free\_space} \ge 0$)**:
   The distance from the element's border-box to the `left` and `right` insets differs by at most $1$ subpixel unit (`LayoutUnit` epsilon), guaranteeing exact visual centering up to subpixel quantization:
   $$0 \le \text{margin\_right} - \text{margin\_left} \le 1$$
3. **Containing Block Exact Partition**:
   $$\text{left} + \text{margin\_left} + \text{width} + \text{margin\_right} + \text{right} = \text{cb\_width}$$

---

#### 3. Concrete Rocq / Coq Formalization (`BlinkAbsoluteAutoMarginsSemantics.v`)

```coq
(** * BlinkAbsoluteAutoMarginsSemantics.v
    Formal audit of Chromium Blink Absolute Auto Margins Centering
    against CSS Positioned Layout Module Level 3 §5.2. *)

From Coq Require Import ZArith.
From Coq Require Import Lia.
Open Scope Z_scope.

(** ** 1. Data Types and Layout State *)

Record AbsposHorizontalInputs := mkInputs {
  cb_width : Z;
  left_inset : Z;
  right_inset : Z;
  box_width : Z;
  margin_left_is_auto : bool;
  margin_right_is_auto : bool;
  specified_margin_left : Z;
  specified_margin_right : Z;
}.

Record ResolvedMargins := mkMargins {
  margin_left : Z;
  margin_right : Z;
}.

(** ** 2. Free Space and Margin Computation (LTR Direction) *)

Definition compute_free_space (inp : AbsposHorizontalInputs) : Z :=
  inp.(cb_width) - (inp.(left_inset) + inp.(box_width) + inp.(right_inset)).

(** Models Blink's ComputeAbsoluteSize auto-margin resolution in LTR mode. *)
Definition resolve_abspos_margins_ltr (inp : AbsposHorizontalInputs) : ResolvedMargins :=
  let free := compute_free_space inp in
  match inp.(margin_left_is_auto), inp.(margin_right_is_auto) with
  | true, true =>
      if Z.geb free 0 then
        let ml := Z.div free 2 in
        let mr := free - ml in
        mkMargins ml mr
      else
        mkMargins 0 free
  | true, false =>
      let mr := inp.(specified_margin_right) in
      mkMargins (free - mr) mr
  | false, true =>
      let ml := inp.(specified_margin_left) in
      mkMargins ml (free - ml)
  | false, false =>
      (* Over-constrained case: CSS ignores right_inset or absorbs into margin, 
         but for fixed margins we return specified values. *)
      mkMargins inp.(specified_margin_left) inp.(specified_margin_right)
  end.

(** ** 3. Formal Verification of Invariants *)

(** Invariant 1: When both margins are auto, the sum of resolved margins 
    never exceeds free space (and in fact equals free space). *)
Theorem auto_margins_sum_le_free :
  forall (inp : AbsposHorizontalInputs),
    inp.(margin_left_is_auto) = true ->
    inp.(margin_right_is_auto) = true ->
    let res := resolve_abspos_margins_ltr inp in
    let free := compute_free_space inp in
    res.(margin_left) + res.(margin_right) <= free.
Proof.
  intros inp Hml Hmr res free.
  unfold res, resolve_abspos_margins_ltr.
  rewrite Hml, Hmr.
  destruct (Z.geb free 0) eqn:Hfree; simpl; lia.
Qed.

Theorem auto_margins_sum_exact :
  forall (inp : AbsposHorizontalInputs),
    inp.(margin_left_is_auto) = true ->
    inp.(margin_right_is_auto) = true ->
    let res := resolve_abspos_margins_ltr inp in
    let free := compute_free_space inp in
    res.(margin_left) + res.(margin_right) = free.
Proof.
  intros inp Hml Hmr res free.
  unfold res, resolve_abspos_margins_ltr.
  rewrite Hml, Hmr.
  destruct (Z.geb free 0) eqn:Hfree; simpl; lia.
Qed.

(** Invariant 2: Exact centering within insets up to integer quantization (1 unit)
    when free space is non-negative. *)
Theorem auto_margins_centered_within_insets :
  forall (inp : AbsposHorizontalInputs),
    inp.(margin_left_is_auto) = true ->
    inp.(margin_right_is_auto) = true ->
    compute_free_space inp >= 0 ->
    let res := resolve_abspos_margins_ltr inp in
    0 <= res.(margin_right) - res.(margin_left) <= 1 /\
    res.(margin_left) >= 0 /\
    res.(margin_right) >= 0.
Proof.
  intros inp Hml Hmr Hfree_ge res.
  unfold res, resolve_abspos_margins_ltr.
  rewrite Hml, Hmr.
  set (free := compute_free_space inp) in *.
  assert (Hgeb : Z.geb free 0 = true) by (apply Z.geb_le; lia).
  rewrite Hgeb; simpl.
  pose proof (Z.div_mod free 2 ltac:(lia)) as Hdiv.
  pose proof (Z.mod_pos_bound free 2 ltac:(lia)) as Hmod.
  lia.
Qed.

(** Invariant 3: Exact symmetry when free space is even and non-negative. *)
Theorem auto_margins_exact_symmetry_when_even :
  forall (inp : AbsposHorizontalInputs),
    inp.(margin_left_is_auto) = true ->
    inp.(margin_right_is_auto) = true ->
    compute_free_space inp >= 0 ->
    (compute_free_space inp) mod 2 = 0 ->
    let res := resolve_abspos_margins_ltr inp in
    res.(margin_left) = res.(margin_right).
Proof.
  intros inp Hml Hmr Hfree_ge Heven res.
  unfold res, resolve_abspos_margins_ltr.
  rewrite Hml, Hmr.
  set (free := compute_free_space inp) in *.
  assert (Hgeb : Z.geb free 0 = true) by (apply Z.geb_le; lia).
  rewrite Hgeb; simpl.
  pose proof (Z.div_mod free 2 ltac:(lia)) as Hdiv.
  lia.
Qed.

(** Invariant 4: Global containing block partition equation holds. *)
Theorem abspos_containing_block_partition :
  forall (inp : AbsposHorizontalInputs),
    inp.(margin_left_is_auto) = true ->
    inp.(margin_right_is_auto) = true ->
    let res := resolve_abspos_margins_ltr inp in
    inp.(left_inset) + res.(margin_left) + inp.(box_width) + res.(margin_right) + inp.(right_inset) = inp.(cb_width).
Proof.
  intros inp Hml Hmr res.
  pose proof (auto_margins_sum_exact inp Hml Hmr) as Hsum.
  simpl in Hsum.
  unfold compute_free_space in Hsum.
  lia.
Qed.
```