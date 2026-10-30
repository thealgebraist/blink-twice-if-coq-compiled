### 1. Atomic Inline Box Architecture (CSS 2.1 §9.2.4 vs. Blink LayoutNG)

Per **CSS 2.1 §9.2.4** (`display: inline-block`), an inline-block generates an *atomic inline-level box*. It participates in an inline formatting context (IFC) as a single opaque inline box, while establishing a new block formatting context (BFC) for its descendants.

In Chromium Blink's **LayoutNG** architecture, this duality is realized across two distinct formatting context phases:

1. **Inside (Block Container / BFC):**
   - Represented by a `NGBlockNode` wrapping a `LayoutBlockFlow` with `IsAtomicInlineLevel() == true`.
   - When the parent IFC encounters the inline-block during the line-breaking phase (`NGLineBreaker::HandleAtomicInline`), it suspends inline layout and invokes `NGBlockLayoutAlgorithm` (or a specialized algorithm like `NGFlexLayoutAlgorithm` for `inline-flex`) on the `NGBlockNode`.
   - The constraint space (`NGConstraintSpace`) passed to the child has `IsNewFormattingContext() == true` and `IsShrinkToFit() == true` (if `width: auto`).
   - This produces an immutable `NGPhysicalBoxFragment` encapsulating the resolved internal block layout, intrinsic metrics, and internal baselines.

2. **Outside (Atomic Inline in IFC):**
   - Represented in the parent's `NGInlineNode` item list as an `NGInlineItem` with `NGInlineItemType::kAtomicInline`.
   - Once `NGLineBreaker` receives the `NGLayoutResult` containing the `NGPhysicalBoxFragment`, it wraps the fragment into an `NGLogicalLineItem` inside the current `NGLineBoxFragmentBuilder`.
   - The parent IFC treats the fragment's outer size (border-box + margins) as an indivisible glyph-like advance along the inline axis. It cannot be split across lines (`NGLineBreaker` never fragments inside an atomic inline across line boxes).

---

### 2. Baseline Determination (CSS 2.1 §10.8.1 & CSS Inline 3 §3)

Per **CSS 2.1 §10.8.1** and **CSS Inline Layout Module Level 3 §3.1**:
> *The baseline of an 'inline-block' is the baseline of its last line box in the normal flow, unless it has either no in-flow line boxes or if its 'overflow' property has a computed value other than 'visible', in which case the baseline is the bottom margin edge.*

In Blink LayoutNG (`NGBoxFragmentBuilder::ComputeBaseline` and `NGBoxFragment::BaselineMetrics`):

1. **In-Flow Line Box Synthesis (`overflow: visible`):**
   - During `NGBlockLayoutAlgorithm::FinishLayout`, the builder queries its children for the last baseline (`NGBaselineAlgorithmType::kInlineBlock`).
   - It traverses physical child fragments in reverse order, skipping out-of-flow positioned boxes (absolutely/fixed positioned elements).
   - If the child is a line box (`NGPhysicalLineBoxFragment`), its alphabetic (or ideographic) baseline offset is extracted and translated into the inline-block's border-box coordinate space.
   - If the child is an in-flow block container, it recursively queries that child's last baseline.
   - The computed offset is stored in the resulting `NGPhysicalBoxFragment::LastBaseline()`.

2. **Fallback to Bottom Margin Edge (Empty / Non-Visible Overflow):**
   - If `Style(). IsScrollContainer()` is true (i.e., `overflow` computes to `hidden`, `scroll`, `auto`, or `clip`, noting CSS Inline 3 updates regarding `overflow: clip`), `NGPhysicalBoxFragment::UseLastBaselineForInlineBaseline()` returns `false` or ignores internal baselines.
   - When the parent IFC (`NGLogicalLineItems::AddChild` / `NGInlineBoxState`) queries `NGBoxFragment::BaselineMetrics()`, if no internal baseline was synthesized (no in-flow line boxes exist) or if overflow clips content, Blink synthesizes the baseline at the **under-margin edge**:
     $$\text{BaselineOffset}_{\text{margin-box}} = \text{margin}_{\text{block-start}} + \text{border-box}_{\text{block-size}} + \text{margin}_{\text{block-end}}$$
   - Relative to the border-box top edge, the baseline is placed at $\text{border-box}_{\text{block-size}} + \text{margin}_{\text{block-end}}$, which equates to the bottom margin edge.

---

### 3. Core Layout Invariants

#### Invariant 1: Atomic Inline Advance Preservation
In an inline formatting context, the inline advance contributed by an inline-block item to its enclosing line box is strictly equal to its resolved margin-box inline size. It is invariant to internal line-breaking opportunities.
$$\text{Advance}_{\text{IFC}}(\text{box}) = \max\left(0, \text{margin}_{\text{inline-start}} + \text{InlineSize}_{\text{border-box}} + \text{margin}_{\text{inline-end}}\right)$$
*(Note: While CSS allows negative margins to reduce advance, within the non-negative box metric domain of standard layout verification, the border-box inline size is strictly preserved as an atomic delta in `NGLineBreaker::position_`).*

#### Invariant 2: Baseline Offset Non-Negativity (Margin-Box Relative)
Given non-negative margins, borders, padding, and line-box metrics, the resolved baseline offset of an inline-block measured from its block-start margin edge is strictly non-negative and bounded above by its total margin-box block size:
$$0 \le \text{Baseline}_{\text{margin-box}}(\text{box}) \le \text{BlockSize}_{\text{margin-box}}(\text{box})$$

---

### 4. Formal Verification in Rocq (Coq)

Below is the complete, self-contained Rocq mechanization for `BlinkInlineBlockLayoutSemantics.v`.

```coq
(** * BlinkInlineBlockLayoutSemantics.v
    Formalization of Chromium Blink LayoutNG Inline-Block semantics
    against CSS 2.1 §9.2.4, §10.8.1 and CSS Inline 3 §3.
    Agent 134 Audit Artifact. *)

From Coq Require Import Arith.PeanoNat.
From Coq Require Import Lists.List.
From Coq Require Import Bool.Bool.
From Coq Require Import micromega.Lia.
Import ListNotations.

(** ** 1. Basic CSS / LayoutNG Metric Types *)

(** LayoutNG uses fixed-point LayoutUnit; we model non-negative layout
    quantities in [nat] to verify structural and baseline invariants. *)
Definition LayoutUnit := nat.

Inductive OverflowProperty : Type :=
  | OverflowVisible
  | OverflowHidden
  | OverflowScroll
  | OverflowAuto
  | OverflowClip.

Definition is_overflow_visible (o : OverflowProperty) : bool :=
  match o with
  | OverflowVisible => true
  | _ => false
  end.

Record BoxStrut : Type := mkBoxStrut {
  inline_start : LayoutUnit;
  inline_end   : LayoutUnit;
  block_start  : LayoutUnit;
  block_end    : LayoutUnit
}.

(** ** 2. Inside View: Block Formatting Context & Line Boxes *)

(** A line box inside the inline-block's BFC.
    Invariant: [line_baseline <= line_block_size]. *)
Record LineBoxFragment : Type := mkLineBox {
  line_block_offset : LayoutUnit; (* Offset relative to BFC content-box top *)
  line_block_size   : LayoutUnit;
  line_baseline     : LayoutUnit  (* Offset relative to line box top *)
}.

(** Well-formedness of an internal line box *)
Definition wf_line_box (lb : LineBoxFragment) : Prop :=
  line_baseline lb <= line_block_size lb.

(** ** 3. Atomic Inline Box (NGPhysicalBoxFragment for Inline-Block) *)

Record InlineBlockFragment : Type := mkInlineBlock {
  (* Border-box dimensions resolved by NGBlockLayoutAlgorithm *)
  border_box_inline_size : LayoutUnit;
  border_box_block_size  : LayoutUnit;

  (* Outer margins in the parent IFC *)
  margins : BoxStrut;

  (* Padding + Border block-start offset (content-box top offset) *)
  content_block_start : LayoutUnit;

  (* Computed style overflow *)
  overflow : OverflowProperty;

  (* In-flow line boxes generated inside this BFC, in block order *)
  inflow_lines : list LineBoxFragment
}.

(** Well-formedness of an InlineBlockFragment:
    Every internal line box fits within the border-box block size. *)
Definition wf_inline_block (ib : InlineBlockFragment) : Prop :=
  Forall (fun lb =>
    wf_line_box lb /\
    content_block_start ib + line_block_offset lb + line_block_size lb
      <= border_box_block_size ib
  ) (inflow_lines ib).

(** ** 4. Outside View: Atomic Inline Metrics in Parent IFC *)

(** Total margin-box inline size (atomic advance in NGLineBreaker) *)
Definition margin_box_inline_size (ib : InlineBlockFragment) : LayoutUnit :=
  inline_start (margins ib) +
  border_box_inline_size ib +
  inline_end (margins ib).

(** Total margin-box block size *)
Definition margin_box_block_size (ib : InlineBlockFragment) : LayoutUnit :=
  block_start (margins ib) +
  border_box_block_size ib +
  block_end (margins ib).

(** State of the parent NGLineBreaker during inline layout *)
Record IFCState : Type := mkIFCState {
  current_inline_position : LayoutUnit;
  consumed_fragments      : list InlineBlockFragment
}.

(** NGLineBreaker::HandleAtomicInline transition *)
Definition layout_atomic_inline (st : IFCState) (ib : InlineBlockFragment) : IFCState :=
  mkIFCState
    (current_inline_position st + margin_box_inline_size ib)
    (consumed_fragments st ++ [ib]).

(** ** 5. Baseline Determination Semantics (CSS 2.1 §10.8.1 / Blink) *)

(** Helper to extract the last element of a list *)
Fixpoint last_opt {A : Type} (l : list A) : option A :=
  match l with
  | [] => None
  | [x] => Some x
  | _ :: xs => last_opt xs
  end.

(** Internal baseline relative to the inline-block's border-box top.
    Returns [None] if overflow is not visible or if there are no in-flow lines. *)
Definition compute_internal_baseline (ib : InlineBlockFragment) : option LayoutUnit :=
  if is_overflow_visible (overflow ib) then
    match last_opt (inflow_lines ib) with
    | Some last_line =>
        Some (content_block_start ib +
              line_block_offset last_line +
              line_baseline last_line)
    | None => None
    end
  else
    None.

(** Resolved baseline relative to the inline-block's border-box top.
    Falls back to the bottom margin edge (border_box_block_size + margin_block_end)
    when [compute_internal_baseline] returns [None]. *)
Definition resolve_border_box_baseline (ib : InlineBlockFragment) : LayoutUnit :=
  match compute_internal_baseline ib with
  | Some b => b
  | None   => border_box_block_size ib + block_end (margins ib)
  end.

(** Resolved baseline relative to the inline-block's margin-box block-start edge.
    This is the metric used by NGInlineBoxState for line-box alignment. *)
Definition resolve_margin_box_baseline (ib : InlineBlockFragment) : LayoutUnit :=
  block_start (margins ib) + resolve_border_box_baseline ib.

(** ** 6. Theorems and Invariants *)

(** Lemma: If [last_opt l = Some x], then [x] is in [l]. *)
Lemma last_opt_In : forall {A : Type} (l : list A) (x : A),
  last_opt l = Some x -> In x l.
Proof.
  intros A l.
  induction l as [| a l' IH]; intros x H.
  - simpl in H. discriminate.
  - simpl in H. destruct l' as [| b l''].
    + inversion H; subst. left; reflexivity.
    + right. apply IH. exact H.
Qed.

(** Theorem 1 (Atomic Advance Preservation):
    Placing an inline-block in an IFC advances the line breaker's inline position
    by exactly the inline-block's margin-box inline size, preserving its internal
    border-box width atomically. *)
Theorem atomic_inline_advance_preserved :
  forall (st : IFCState) (ib : InlineBlockFragment),
    current_inline_position (layout_atomic_inline st ib) - current_inline_position st
    = margin_box_inline_size ib /\
    margin_box_inline_size ib >= border_box_inline_size ib.
Proof.
  intros st ib.
  unfold layout_atomic_inline, margin_box_inline_size.
  simpl.
  split; lia.
Qed.

(** Theorem 2 (Fallback Baseline Equivalence):
    If an inline-block has no in-flow line boxes OR non-visible overflow,
    its margin-box relative baseline equals its total margin-box block size
    (i.e. lies exactly on the bottom margin edge). *)
Theorem baseline_fallback_is_bottom_margin_edge :
  forall (ib : InlineBlockFragment),
    (inflow_lines ib = [] \/ is_overflow_visible (overflow ib) = false) ->
    resolve_margin_box_baseline ib = margin_box_block_size ib.
Proof.
  intros ib [Hempty | Hoverflow].
  - unfold resolve_margin_box_baseline, resolve_border_box_baseline,
           compute_internal_baseline, margin_box_block_size.
    rewrite Hempty. simpl.
    destruct (is_overflow_visible (overflow ib)); lia.
  - unfold resolve_margin_box_baseline, resolve_border_box_baseline,
           compute_internal_baseline, margin_box_block_size.
    rewrite Hoverflow. lia.
Qed.

(** Theorem 3 (Last Line Box Baseline Propagation):
    If an inline-block has [OverflowVisible] and a non-empty list of in-flow lines
    ending with [last_line], its resolved border-box baseline is the exact sum
    of the content-box offset, the last line's block offset, and the last line's baseline. *)
Theorem baseline_from_last_line_box :
  forall (ib : InlineBlockFragment) (prefix : list LineBoxFragment) (last_line : LineBoxFragment),
    overflow ib = OverflowVisible ->
    inflow_lines ib = prefix ++ [last_line] ->
    resolve_border_box_baseline ib =
      content_block_start ib + line_block_offset last_line + line_baseline last_line