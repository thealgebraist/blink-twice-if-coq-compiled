### Audit Report: Agent 115
**Target**: Chromium Blink Paragraph Layout vs. HTML Standard §4.4.1 & CSS 2.1 §9.4.1
**Formalization Module**: `BlinkHTMLParagraphLayoutSemantics.v`

---

### 1. Paragraph Block Formatting & Default UA Margins

#### Specification Alignment
* **HTML Standard §4.4.1 (`<p>` element)** & **§15.3.4 (Flow content)**: The `<p>` element represents a paragraph. The User Agent (UA) default stylesheet specifies:
  ```css
  p { display: block; margin-block-start: 1em; margin-block-end: 1em; margin-inline-start: 0px; margin-inline-end: 0px; }
  ```
* **CSS 2.1 §9.4.1 (Block Formatting Contexts)**: In a Block Formatting Context (BFC), boxes are laid out one after the other, vertically, beginning at the top of a containing block.
* **Blink Implementation (`html.css` & `BlockLayoutAlgorithm`)**: Blink sets `__qem` (1em) for top and bottom margins on `<p>`. Under standard root font size (`16px`), this resolves during style calculation (`ComputedStyle`) to `margin_top = 16px` and `margin_bottom = 16px`.

---

### 2. Inter-Paragraph Margin Collapsing

#### Specification Alignment
* **CSS 2.1 §8.3.1 (Collapsing margins)**: The vertical distance between two sibling boxes is determined by their `margin-bottom` and `margin-top` properties. When two positive vertical margins are adjoining (no border, padding, inline content, or clearance separating them), the resulting collapsed margin width is the maximum of the adjoining margin widths.
* **Blink Implementation (`MarginStrut`)**: Blink's NG layout engine tracks pending vertical margins using a `MarginStrut` structure passed through `ConstraintSpace`.
  * After laying out $P_1$, Blink appends `P1.margin_bottom` (`16px`) to the output `MarginStrut`.
  * Before laying out $P_2$, Blink appends `P2.margin_top` (`16px`) to the same `MarginStrut`.
  * `MarginStrut::Sum()` computes $\max(16, 16) = 16\text{px}$.
  * Thus, consecutive default paragraphs are separated by exactly $16\text{px}$, rather than $16 + 16 = 32\text{px}$.

---

### 3. Formal Layout Invariants

To verify Blink's `BlockLayoutAlgorithm` against CSS 2.1 §9.4.1 and §8.3.1 for standard flow paragraphs (non-negative margins and heights), we enforce three core invariants:
1. **Paragraph Height Non-Negativity**: The computed content box height of any paragraph in a BFC is $\ge 0$.
2. **Vertical Cursor Monotonicity**: As layout progresses through a list of paragraphs, the vertical offset cursor ($y$-coordinate) never decreases: $y_{i} \le y_{i+1}$.
3. **Inter-Paragraph Advance Exactness**: For two consecutive paragraphs $P_1$ and $P_2$ with positive default margins ($16\text{px}$), the border-box top of $P_2$ is located at exactly $\text{top}(P_1) + \text{height}(P_1) + 16$.

---

### 4. Concrete Rocq/Coq Formalization (`BlinkHTMLParagraphLayoutSemantics.v`)

The following complete, self-contained Rocq (Coq) specification formalizes Blink's `MarginStrut` collapsing semantics, BFC vertical layout cursor advancement, and proves the required invariants.

```coq
(** * BlinkHTMLParagraphLayoutSemantics.v
    Formal Audit by Agent 115:
    Chromium Blink Paragraph Layout vs HTML §4.4.1 & CSS 2.1 §9.4.1 / §8.3.1 *)

From Coq Require Import ZArith.
From Coq Require Import List.
From Coq Require Import Lia.
Import ListNotations.

Open Scope Z_scope.

(** ** 1. Basic Types and Default UA Constants (HTML §4.4.1 / §15.3.4) *)

Definition Px := Z.

(** Standard root font size 1em = 16px *)
Definition default_em_px : Px := 16.

(** A paragraph block box in normal flow *)
Record ParagraphBox : Type := mkParagraph {
  p_margin_top    : Px;
  p_content_height: Px;
  p_margin_bottom : Px;
}.

(** Well-formedness condition for standard flow paragraphs:
    content height is non-negative, and margins are non-negative (as per UA default). *)
Definition wf_paragraph (p : ParagraphBox) : Prop :=
  0 <= p_margin_top p /\
  0 <= p_content_height p /\
  0 <= p_margin_bottom p.

(** HTML UA Default <p> constructor: 1em top/bottom margins *)
Definition make_default_paragraph (content_h : Px) : ParagraphBox :=
  mkParagraph default_em_px (Z.max 0 content_h) default_em_px.

Lemma make_default_paragraph_wf : forall h,
  wf_paragraph (make_default_paragraph h).
Proof.
  intros h. unfold wf_paragraph, make_default_paragraph, default_em_px.
  simpl. split; [lia | split; lia].
Qed.

(** ** 2. Margin Collapsing Semantics (CSS 2.1 §8.3.1 & Blink MarginStrut) *)

(** CSS 2.1 §8.3.1:
    - Two positive margins collapse to their maximum.
    - Two negative margins collapse to their minimum (most negative).
    - One positive and one negative margin collapse to their sum. *)
Definition collapse_margins (m1 m2 : Px) : Px :=
  if (0 <=? m1) && (0 <=? m2) then Z.max m1 m2
  else if (m1 <=? 0) && (m2 <=? 0) then Z.min m1 m2
  else m1 + m2.

(** Verification of the 16px inter-paragraph collapsing requirement *)
Theorem inter_paragraph_default_collapse :
  collapse_margins 16 16 = 16.
Proof.
  reflexivity.
Qed.

Lemma collapse_nonneg : forall m1 m2,
  0 <= m1 -> 0 <= m2 -> 0 <= collapse_margins m1 m2.
Proof.
  intros m1 m2 H1 H2.
  unfold collapse_margins.
  assert (H1b: (0 <=? m1) = true) by (apply Z.leb_le; exact H1).
  assert (H2b: (0 <=? m2) = true) by (apply Z.leb_le; exact H2).
  rewrite H1b, H2b. simpl. lia.
Qed.

(** ** 3. BFC Layout State & Step Semantics (CSS 2.1 §9.4.1) *)

(** Represents a positioned box in the Block Formatting Context *)
Record PositionedBox : Type := mkPositionedBox {
  box_top    : Px;
  box_height : Px;
}.

(** Blink BlockLayoutAlgorithm State:
    - bfc_cursor_y: Current border-box vertical offset before applying pending margin strut.
    - prev_margin_strut: MarginStrut carried over from previous sibling's margin-bottom.
    - is_first_in_bfc: Indicates whether we are at the top of the BFC. *)
Record BFCState : Type := mkBFCState {
  bfc_cursor_y      : Px;
  prev_margin_strut : Px;
  is_first_in_bfc   : bool;
  placed_boxes      : list PositionedBox;
}.

Definition initial_bfc_state : BFCState :=
  mkBFCState 0 0 true [].

(** Layout a single paragraph inside the BFC *)
Definition layout_paragraph_step (st : BFCState) (p : ParagraphBox) : BFCState :=
  let effective_margin :=
    if is_first_in_bfc st then
      p_margin_top p
    else
      collapse_margins (prev_margin_strut st) (p_margin_top p)
  in
  let new_box_top := bfc_cursor_y st + effective_margin in
  let h := Z.max 0 (p_content_height p) in
  let new_cursor_y := new_box_top + h in
  let pos_box := mkPositionedBox new_box_top h in
  mkBFCState new_cursor_y (p_margin_bottom p) false (placed_boxes st ++ [pos_box]).

(** Layout a sequence of paragraphs *)
Definition layout_paragraphs (ps : list ParagraphBox) : BFCState :=
  fold_left layout_paragraph_step ps initial_bfc_state.

(** ** 4. Formal Invariant Proofs *)

(** Invariant 1: Paragraph height non-negativity for all placed boxes *)
Theorem placed_box_height_nonneg : forall st p,
  (Forall (fun b => 0 <= box_height b) (placed_boxes st)) ->
  (Forall (fun b => 0 <= box_height b) (placed_boxes (layout_paragraph_step st p))).
Proof.
  intros st p Hforall.
  unfold layout_paragraph_step. simpl.
  apply Forall_app. split.
  - exact Hforall.
  - constructor; [simpl; lia | constructor].
Qed.

(** State well-formedness: pending margin strut is non-negative *)
Definition wf_state (st : BFCState) : Prop :=
  0 <= prev_margin_strut st.

Lemma layout_step_preserves_wf_state : forall st p,
  wf_paragraph p ->
  wf_state (layout_paragraph_step st p).
Proof.
  intros st p [_ [_ Hmb]].
  unfold wf_state, layout_paragraph_step. simpl.
  exact Hmb.
Qed.

(** Invariant 2: Vertical Cursor Monotonicity *)
Theorem vertical_cursor_monotonicity : forall st p,
  wf_state st ->
  wf_paragraph p ->
  bfc_cursor_y st <= bfc_cursor_y (layout_paragraph_step st p).
Proof.
  intros st p Hst [Hmt [Hch Hmb]].
  unfold layout_paragraph_step, wf_state in *. simpl.
  destruct (is_first_in_bfc st).
  - lia.
  - assert (Hc: 0 <= collapse_margins (prev_margin_strut st) (p_margin_top p)).
    { apply collapse_nonneg; assumption. }
    lia.
Qed.

(** Multi-step Vertical Cursor Monotonicity across a list of paragraphs *)
Theorem fold_vertical_cursor_monotonic : forall ps st,
  wf_state st ->
  Forall wf_paragraph ps ->
  bfc_cursor_y st <= bfc_cursor_y (fold_left layout_paragraph_step ps st).
Proof.
  induction ps as [| p ps' IH]; intros st Hst Hwf.
  - simpl. lia.
  - simpl. inversion Hwf as [| x l Hp Hps']; subst.
    assert (Hstep_mono: bfc_cursor_y st <= bfc_cursor_y (layout_paragraph_step st p)).
    { apply vertical_cursor_monotonicity; assumption. }
    assert (Hstep_wf: wf_state (layout_paragraph_step st p)).
    { apply layout_step_preserves_wf_state; assumption. }
    specialize (IH (layout_paragraph_step st p) Hstep_wf Hps').
    lia.
Qed.

(** Invariant 3: Exact Inter-Paragraph Advance for Consecutive Default Paragraphs
    Proves that two consecutive default paragraphs P1 (height h1) and P2 (height h2)
    are positioned at y1 = 16 and y2 = 16 + h1 + 16 (collapsed 16px gap, not 32px). *)
Theorem consecutive_default_paragraphs_advance : forall h1 h2,
  0 <= h1 ->
  0 <= h2 ->
  let p1 := make_default_paragraph h1 in
  let p2 := make_default_paragraph h2 in
  let final_st := layout_paragraphs [p1; p2] in
  placed_boxes final_st = [
    mkPositionedBox 16 h1;
    mkPositionedBox (16 + h1 + 16) h2
  ] /\
  bfc_cursor_y final_st = 16 + h1 + 16 + h2.
Proof.
  intros h1 h2 Hh1 Hh2 p1 p2 final_st.
  unfold final_st, layout_paragraphs, p1, p2, make_default_paragraph.
  unfold initial_bfc_state, layout_paragraph_step, default_em_px, collapse_margins.
  simpl.
  replace (Z.max 0 h1) with h1 by lia.
  replace (Z.max 0 h2) with h2 by lia.
  split; reflexivity.
Qed.
```