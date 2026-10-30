**AUDIT REPORT: BLINK LAYOUT ENGINE (LayoutNG)**  
**Auditor:** Agent 365  
**Target:** `NGBreakToken` (specifically `NGBlockBreakToken`)  
**Subject:** Consumed Block-Size Monotonic Accumulation  
**Status:** ACTIVE  

---

### 1. Executive Summary
In the Blink rendering engine’s LayoutNG architecture, `consumed_block_size` is the foundational metric for vertical (or logical block-axis) progress across fragmentation contexts (pagination, multi-column layout). **Monotonic accumulation** dictates that as a DOM node fragments across multiple fragmentainers, the `consumed_block_size` recorded in its sequential `NGBlockBreakToken` instances must strictly increase or remain equal ($C_n \ge C_{n-1}$). 

Violation of this invariant results in severe layout pathologies, including infinite pagination loops, vertical overlapping of fragments, or premature clipping.

---

### 2. Architectural Mechanics

When a layout algorithm (e.g., `NGBlockLayoutAlgorithm`) encounters a fragmentation boundary, it halts layout for the current node, generates a physical fragment (`NGPhysicalBoxFragment`), and attaches an `NGBlockBreakToken` to resume layout in the next fragmentainer.

#### A. State Initialization (Fragment $0 \to 1$)
* **Input:** `InflowBreakToken` = `nullptr`.
* **Initial State:** Previous `consumed_block_size` ($C_0$) = `0px`.
* **Execution:** The node lays out up to the available block-size of Fragmentainer 1. 
* **Output Token ($T_1$):** Stores $C_1 = \text{Fragment}_1\text{.BlockSize()} - \text{UnconsumedPadding/Borders}$.

#### B. State Continuation (Fragment $n-1 \to n$)
* **Input:** Break token $T_{n-1}$ containing $C_{n-1}$.
* **Offset Calculation:** The algorithm uses $C_{n-1}$ to fast-forward past already-rendered content. Child offsets are shifted by $-C_{n-1}$ relative to the node's logical top.
* **Accumulation Formula:**
  $$C_n = C_{n-1} + \Delta B_n$$
  *(Where $\Delta B_n$ is the intrinsic block-size of the content consumed in the current fragmentainer, excludingcloned box decorations).*

---

### 3. The Monotonicity Invariant

For any sequence of break tokens $T_1, T_2, \dots, T_k$ generated for a single `NGLayoutInputNode`:

$$0 \le C_1 \le C_2 \le \dots \le C_k \le \text{TotalBlockSize}$$

#### Edge Cases Maintaining Monotonicity ($\Delta B_n = 0$)
Monotonicity is **non-strict** ($C_n = C_{n-1}$ is valid in specific scenarios) because a node may be forced to break before consuming any of its own block-size in the current fragmentainer:
1. **Pushed by Floats/Siblings:** The node starts at the very bottom of a fragmentainer with `0px` available space and violates no widows/orphans rules by pushing to the next column.
2. **Violating Break-Inside:** A child element has `break-inside: avoid` and is too large for the current fragmentainer, forcing an early break before the parent consumes space.
3. **Out-of-Flow (OOF) Descendants:** Only OOF elements are processed in a fragment, contributing `0px` to the inflow block-size.

*Audit Note: While $C_n = C_{n-1}$ is valid for a single step, Blink’s `NGFragmentBuilder` enforces forward progress across the whole tree to prevent infinite loops. If $C_n = C_{n-1}$ repeats without any child break tokens advancing, the engine triggers a forced-progress state.*

---

### 4. Critical Audit Vectors (Anomalies & Nuances)

Agent 365 monitors the following specific implementations in `ng_fragmentation_utils.cc` and `ng_box_fragment_builder.cc` where monotonic accumulation is most vulnerable to corruption:

#### Vector 1: `box-decoration-break: clone`
* **The Trap:** Cloned borders and padding are repainted at every fragment boundary. 
* **The Audit:** Cloned decorations must **not** be added to `consumed_block_size` as if they were content progress, otherwise the node will prematurely reach its specified `height` or `max-height` before all content is rendered. However, they do consume *fragmentainer* space. Blink must isolate *content* consumption from *visual* consumption.

#### Vector 2: Negative Margins & Relative Offsets
* **The Trap:** A child element with a large negative `margin-block-start` pulls the layout cursor backward.
* **The Audit:** If $\Delta B_n$ becomes negative due to margin collapsing or negative margins across a fragment boundary, $C_n$ could theoretically drop below $C_{n-1}$. Blink prevents this via `std::max(LayoutUnit(), fragment_block_size)` clamping before adding to the previous `consumed_block_size`. **Monotonicity is enforced via clamping.**

#### Vector 3: Monolithic Content Overflow
* **The Trap:** An unbreakable element (e.g., an image or `overflow: hidden` container) is taller than the fragmentainer.
* **The Audit:** The monolithic content overflows the fragmentainer. In the next fragmentainer, $C_n$ must jump by the *entire* size of the monolithic element, not just the height of the fragmentainer. Failure to accumulate the overflowing portion causes the subsequent fragment to overlap the monolithic element.

#### Vector 4: Grid and Flex Multi-Pass Layout
* **The Trap:** `NGFlexLayoutAlgorithm` and `NGGridLayoutAlgorithm` measure items multiple times.
* **The Audit:** Break token accumulation must only commit during the final fragment generation phase, never during intrinsic sizing passes. 

---

### 5. Diagnostic Verification (DCHECKs)

During debug builds, Agent 365 verifies the integrity of the accumulation via the following assertions in the Blink source:

```cpp
// Conceptual representation of Blink's internal audit in NGBoxFragmentBuilder::Finish()
LayoutUnit consumed_block_size = PreviousBreakToken() 
    ? PreviousBreakToken()->ConsumedBlockSize() 
    : LayoutUnit();

DCHECK_GE(intrinsic_block_size_, LayoutUnit()); // Delta cannot be negative.

LayoutUnit next_consumed_block_size = consumed_block_size + fragment_block_size;

// Monotonicity Check
DCHECK_GE(next_consumed_block_size, consumed_block_size); 
```

**Audit Conclusion:** Monotonic accumulation in `NGBlockBreakToken` is the primary pacemaker of Blink's fragmentation engine. By ensuring `consumed_block_size` never regresses, LayoutNG guarantees deterministic termination of pagination and exact geometric reconstruction of fragmented boxes. 

*Agent 365 signing off.*