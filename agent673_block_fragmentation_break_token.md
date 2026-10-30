# Formal Verification Report: Block Fragmentation Break Token Continuation in Chromium Blink

**Agent:** 673 (W3C/WHATWG Layout Rules & Chromium Blink Verification)  
**Topic:** Block Fragmentation Break Token Continuation Across Fragmentainers  
**Chromium Source:** `third_party/blink/renderer/core/layout/block_break_token.cc`  
**Specification:** CSS Fragmentation Module Level 3 (§4 & §5)  
**Formal Theory Target:** `BlinkBlockFragmentationBreakTokenSemantics.v`  
**Core Mathematical Property:** $\forall \text{token}, \text{consumed\_block\_size}(\text{token}) \le \text{total\_block\_size} \land \text{remaining} = \text{total} - \text{consumed}$

---

## 1. Normative W3C Specification Requirements

The layout of boxes across multiple fragmentainers (columns, pages, or regions) is governed by the **CSS Fragmentation Module Level 3** specification. When a block box cannot fit completely within the current fragmentainer, it splits into multiple box fragments.

### 1.1. CSS Fragmentation 3 §4: Fragmentation Model and Layout
* **Progress Guarantee:** Fragmentation must make monotonic progress through the document content. Specifically, when a box is broken, the portion of the box laid out in the subsequent fragmentainer begins immediately after the break point established in the preceding fragmentainer.
* **Coordinate Space:** Layout calculations inside a fragmented flow often evaluate intrinsics and extrinsic block sizes against a hypothetical "unfragmented" flow or accumulate consumed block size across fragmentainers to resolve percentages, `min-height`, `max-height`, and `height` properties.

### 1.2. CSS Fragmentation 3 §5: Box Model for Breaking
* **Consumed Block Size (§5.1 - Breaking into Varying-size Fragmentainers):** As a box fragments across multiple fragmentainers, each fragment consumes a portion of the box's total specified or intrinsic block size. The cumulative block size consumed by all prior fragments (excluding cloned borders/paddings where applicable) is tracked as the **consumed block size**.
* **Remaining Block Size:** When determining the block size of a box fragment in fragmentainer $k$, the remaining unconstrained block size is bounded by:
  $$\text{Remaining Block Size}_k = \max(0, \text{Total Block Size} - \sum_{i=0}^{k-1} \text{Fragment Block Size}_i)$$
* **Clamping and Overflow:** If a box has a definite `block-size` (or `max-block-size`), the sum of the content block sizes of its fragments must equal the resolved total block size (unless forced breaks or content overflow extend the box beyond its specified size, in which case the total size expands to match the final consumed size upon completion). At any intermediate break token where the box has not yet exhausted its specified block size, the invariant `consumed_block_size <= total_block_size` holds strictly.

---

## 2. Blink Implementation Details and Invariants

In Chromium's Blink rendering engine (LayoutNG architecture), fragmentation state is passed between layout passes of sequential fragmentainers using immutable `BreakToken` objects. For block-level boxes, this is implemented in `BlockBreakToken` (`third_party/blink/renderer/core/layout/block_break_token.h` and `.cc`).

### 2.1. Architecture of `BlockBreakToken`
`BlockBreakToken` inherits from `BreakToken` and encapsulates the state required to resume layout of a `LayoutInputNode` in the next fragmentainer. Its primary data payload (stored in `BlockBreakTokenData`) includes:
* `consumed_block_size` (`LayoutUnit`): The cumulative block-size consumed by all fragments of this box generated in prior fragmentainers.
* `sequence_number` (`unsigned`): A monotonically increasing index identifying the fragment sequence.
* `monolithic_overflow` (`LayoutUnit`): Unbreakable overflow that spilled past the fragmentainer boundary.
* Bitfields: `is_break_before_`, `is_forced_break_`, `is_caused_by_column_spanner_`, `is_at_block_end_`, and `has_seen_all_children_`.

### 2.2. State Transitions in `block_break_token.cc` and `box_fragment_builder.cc`
1. **Creation (`BlockBreakToken::Create`):**
   When `BoxFragmentBuilder::Finish()` detects that a node broke (e.g., `DidBreakSelf()` or child break tokens exist), it instantiates a `BlockBreakToken` passing its `BlockBreakTokenData`.
   ```cpp
   // Conceptual summary of state accumulation during FragmentBuilder finalization:
   LayoutUnit previously_consumed = PreviousBreakToken() 
       ? PreviousBreakToken()->ConsumedBlockSize() 
       : LayoutUnit();
   LayoutUnit consumed_block_size = previously_consumed + fragment_block_size;
   ```
2. **Break-Before Semantics (`CreateBreakBefore`):**
   If a box breaks *before* its first fragment can be placed in the current fragmentainer (`is_break_before_ == true`), `BlockBreakToken::CreateBreakBefore` initializes `BlockBreakTokenData` with `consumed_block_size = 0`.
3. **Resumption and Remaining Size Computation (`fragmentation_utils.cc`):**
   When laying out fragment $k$ given `PreviousBreakToken()` $T_{k-1}$:
   * The engine extracts `previously_consumed = T_{k-1}->ConsumedBlockSize()`.
   * When resolving the box's block-size against a definite CSS `height` / `block-size` ($H_{\text{total}}$), the remaining block size needed to satisfy the CSS property is computed as:
     $$\text{remaining} = \max(0, H_{\text{total}} - \text{previously\_consumed})$$
   * In the absence of overflow expansion (`is_at_block_end_ == false`), the fragment clamps its contribution to the available fragmentainer space $F_{\text{avail}}$, ensuring that each fragment consumes $\Delta = \min(\text{remaining}, F_{\text{avail}})$ (assuming $\text{F}_{\text{avail}} \ge 0$).
   * Consequently, $\text{consumed\_block\_size}(T_k) = \text{previously\_consumed} + \Delta \le H_{\text{total}}$.

---

## 3. Formal Specification Definitions in Rocq/Coq

Below is the formalization of `BlockBreakToken` and the fragmentainer continuation step semantics in Rocq/Coq. Layout units are modeled using arbitrary-precision integers (`Z`), matching the exact fixed-point arithmetic invariants of Blink's `LayoutUnit` (within non-saturating bounds).

```coq
(** * BlinkBlockFragmentationBreakTokenSemantics.v *)
From Coq Require Import ZArith.
From Coq Require Import Lia.
From Coq Require Import Bool.
From Coq Require Import List.
Import ListNotations.

Open Scope Z_scope.

(** ** 1. Basic Types and Data Structures *)

(** LayoutUnit is represented as an integer (fixed-point 1/64th pixel in Blink). *)
Definition LayoutUnit := Z.

(** Structure representing Blink's BlockBreakTokenData and flags
    (third_party/blink/renderer/core/layout/block_break_token.h) *)
Record BlockBreakToken : Type := mkBlockBreakToken {
  consumed_block_size : LayoutUnit;
  sequence_number : nat;
  is_break_before : bool;
  is_at_block_end : bool;
  has_seen_all_children : bool
}.

(** Specification of a Block Box undergoing fragmentation. *)
Record FragmentedBoxSpec : Type := mkFragmentedBoxSpec {
  total_block_size : LayoutUnit;
  box_non_negative : 0 <= total_block_size
}.

(** Specification of a Fragmentainer's available block space. *)
Record FragmentainerSpace : Type := mkFragmentainerSpace {
  available_size : LayoutUnit;
  space_non_negative : 0 <= available_size
}.

(** ** 2. Break Token Constructors & Operations *)

(** Equivalent to BlockBreakToken::CreateBreakBefore in block_break_token.cc *)
Definition create_break_before : BlockBreakToken := {|
  consumed_block_size := 0;
  sequence_number := 0%nat;
  is_break_before := true;
  is_at_block_end := false;
  has_seen_all_children := false
|}.

(** Computes the remaining block size to be laid out for a box,
    given an optional incoming BlockBreakToken. *)
Definition remaining_block_size (total : LayoutUnit) (opt_token : option BlockBreakToken) : LayoutUnit :=
  match opt_token with
  | None => total
  | Some token => total - consumed_block_size token
  end.

(** Computes the block size of the fragment produced in the current fragmentainer
    when constrained by the remaining box size and available fragmentainer space. *)
Definition compute_fragment_size (rem : LayoutUnit) (avail : LayoutUnit) : LayoutUnit :=
  Z.min rem avail.

(** Equivalent to BoxFragmentBuilder::Finish creating a next BlockBreakToken
    via BlockBreakToken::Create in block_break_token.cc.
    Returns (fragment_size, option next_token).
    If all block size is consumed, no break token is needed for box sizing (returns None),
    or returns a terminal token depending on child state. Here we model the continuation token
    generated while layout is ongoing or just completing the box size. *)
Definition step_fragmentation 
  (total : LayoutUnit) 
  (prev_token : option BlockBreakToken) 
  (avail : LayoutUnit) : (LayoutUnit * BlockBreakToken) :=
  let prev_consumed := match prev_token with
                       | None => 0
                       | Some t => consumed_block_size t
                       end in
  let prev_seq := match prev_token with
                  | None => 0%nat
                  | Some t => if is_break_before t then sequence_number t else S (sequence_number t)
                  end in
  let rem := total - prev_consumed in
  let frag_size := compute_fragment_size rem avail in
  let next_consumed := prev_consumed + frag_size in
  let at_end := Z.eqb next_consumed total in
  let next_token := {|
    consumed_block_size := next_consumed;
    sequence_number := prev_seq;
    is_break_before := false;
    is_at_block_end := at_end;
    has_seen_all_children := at_end
  |} in
  (frag_size, next_token).

(** Multi-step fragmentation across a list of fragmentainer available sizes. *)
Fixpoint run_fragmentation_trace
  (total : LayoutUnit)
  (prev_token : option BlockBreakToken)
  (spaces : list LayoutUnit) : list (LayoutUnit * BlockBreakToken) :=
  match spaces with
  | [] => []
  | avail :: rest =>
      let (frag, next_tok) := step_fragmentation total prev_token avail in
      (frag, next_tok) :: run_fragmentation_trace total (Some next_tok) rest
  end.

(** ** 3. Validity Predicates and Layout Invariants *)

(** Well-formedness invariant of a BlockBreakToken with respect to a total_block_size. *)
Definition valid_break_token (total : LayoutUnit) (token : BlockBreakToken) : Prop :=
  0 <= consumed_block_size token /\
  consumed_block_size token <= total /\
  (is_break_before token = true -> consumed_block_size token = 0) /\
  (is_at_block_end token = true <-> consumed_block_size token = total).

Definition valid_opt_break_token (total : LayoutUnit) (opt_token : option BlockBreakToken) : Prop :=
  match opt_token with
  | None => 0 <= total
  | Some token => valid_break_token total token
  end.
```

---

## 4. Concrete Theorems and Complete Rocq/Coq Proofs

This section provides the complete, admitted-free proofs establishing the core mathematical properties:
1. `consumed_block_size(token) <= total_block_size`
2. `remaining = total - consumed`
3. Monotonicity of `consumed_block_size` across fragmentainer steps
4. Exact conservation of block size (`consumed + remaining = total`) across single and multi-fragmentainer traces.

```coq
(** ** 4. Formal Theorems and Proofs *)

(** Theorem 1: A BreakBefore token always satisfies the break token validity invariant
    for any non-negative total block size. *)
Theorem create_break_before_valid :
  forall (total : LayoutUnit),
    0 <= total ->
    valid_break_token total create_break_before.
Proof.
  intros total Htotal.
  unfold valid_break_token, create_break_before; simpl.
  repeat split; try lia.
  - intros Hfalse; discriminate Hfalse.
  - intros Hzero.
    (* If total = 0, is_at_block_end is false for a break-before token because
       nothing has been placed yet, or if we check the boolean equality: *)
Abort.

(** Note on BreakBefore: In Blink, CreateBreakBefore sets is_at_block_end = false
    even if total == 0 because the box hasn't started layout. We refine the predicate
    to reflect that is_at_block_end only applies when is_break_before is false. *)

Definition wf_break_token (total : LayoutUnit) (token : BlockBreakToken) : Prop :=
  0 <= consumed_block_size token /\
  consumed_block_size token <= total /\
  (is_break_before token = true -> consumed_block_size token = 0) /\
  (is_break_before token = false -> (is_at_block_end token = true <-> consumed_block_size token = total)).

Definition wf_opt_break_token (total : LayoutUnit) (opt_token : option BlockBreakToken) : Prop :=
  match opt_token with
  | None => 0 <= total
  | Some token => wf_break_token total token
  end.

(** Theorem 1 (Refined): CreateBreakBefore satisfies wf_break_token. *)
Theorem create_break_before_wf :
  forall (total : LayoutUnit),
    0 <= total ->
    wf_break_token total create_break_before.
Proof.
  intros total Htotal.
  unfold wf_break_token, create_break_before; simpl.
  repeat split; try lia; intros H; try discriminate.
Qed.

(** Theorem 2: Core Invariant Preservation across a single Fragmentation Step.
    Proves that:
    1. consumed_block_size(next_token) <= total_block_size
    2. remaining = total - consumed_block_size(next_token) >= 0
    3. consumed_block_size increases monotonically
    4. fragment_size + prev_consumed = next_consumed *)
Theorem step_fragmentation_preserves_invariants :
  forall (total avail : LayoutUnit) (prev_opt : option BlockBreakToken)
         (frag_