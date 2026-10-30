**AUDIT REPORT: Blink LayoutNG Block Fragmentation**
**Auditor:** Agent 368
**Subject:** Soundness of Paged Fragmentation Assembly & Conservation of Total Block Size
**Target:** Chromium / Blink Rendering Engine (`third_party/blink/renderer/core/layout/ng/`)

---

### 1. Executive Summary
In Blink’s LayoutNG architecture, paged media and multi-column layouts rely on **Block Fragmentation**. A single DOM node (`LayoutObject`) can be split across multiple fragmentainers (pages/columns), generating multiple immutable `NGPhysicalBoxFragment` instances. 

**Conservation of Total Block Size** is the invariant stating that the sum of the block-sizes of all generated fragments for a given node, minus any fragmentation-induced cloned decorations, must equal the node's intrinsic or specified total block-size (subject to legitimate expansion rules). Violating this invariant results in sliced content, infinite pagination loops, or phantom whitespace.

---

### 2. The Conservation Equation

Let $B_{\text{total}}$ be the unfragmented block-size of a box. When fragmented across $N$ pages, the engine generates fragments $F_1, F_2, \dots, F_N$. 

The strict conservation invariant is defined as:

$$\sum_{i=1}^{N} \text{BlockSize}(F_i) = B_{\text{intrinsic}} + \Delta B_{\text{clones}} + \Delta B_{\text{expansion}}$$

Where:
*   **$B_{\text{intrinsic}}$**: The computed `border-box` block-size of the element if laid out in a continuous, unfragmented flow.
*   **$\Delta B_{\text{clones}}$**: Additional block-size introduced by `box-decoration-break: clone`, calculated as $(N - 1) \times (B_{\text{border}} + B_{\text{padding}})$.
*   **$\Delta B_{\text{expansion}}$**: Legitimate block-size growth caused by forced breaks (`break-before: page`), widow/orphan adjustments, or `min-height` constraints stretching the final fragment.

---

### 3. State Tracking Mechanism (`NGBlockBreakToken`)

Blink does not stitch fragments together post-layout to verify size; instead, it enforces conservation **inductively** during layout via `NGBlockBreakToken`.

To maintain soundness, the break token acts as a state-accumulation ledger passed from Fragmentainer $i$ to Fragmentainer $i+1$. The critical payload datum is **`consumed_block_size`**.

#### The Inductive Step (`NGBlockLayoutAlgorithm`)
1.  **Initialization:** Upon entering `Layout()` for fragment $F_i$, the algorithm reads `consumed_block_size` from the incoming `NGBlockBreakToken` (0 if $i = 1$).
2.  **Space Resolution:** The algorithm calculates the remaining block-size required to satisfy specified CSS `height` or `min-height`:
    $$\text{RemainingBlockSize} = \max(0, B_{\text{specified}} - \text{consumed\_block\_size})$$
3.  **Fragmentation:** The node lays out children until the fragmentainer space runs out (`NGFragmentBuilder::DidBreak()`). The fragment’s local block-size ($b_i$) is clamped to the available fragmentainer space.
4.  **Ledger Update:** Before emitting $F_i$, the builder mints a new `NGBlockBreakToken` with:
    $$\text{consumed\_block\_size}_{i} = \text{consumed\_block\_size}_{i-1} + b_i - \text{ClonedDecorations}_i$$

---

### 4. Boundary Conditions & Edge Case Auditing

Soundness frequently degrades at edge cases. Agent 368 highlights four areas where the conservation law is stressed:

#### A. `box-decoration-break: slice` vs. `clone`
*   **Slice (Default):** Border and padding are applied *only* to $F_1$ (top) and $F_N$ (bottom). Their sizes are directly integrated into `consumed_block_size`. Total size is strictly conserved.
*   **Clone:** Every fragment $F_i$ receives full top and bottom border/padding. 
    *   *Audit Finding:* If `consumed_block_size` accidentally accumulates cloned borders, a box with a fixed CSS `height: 500px` will prematurely terminate its content layout because the cloned borders "eat" into the 500px budget. Blink prevents this by subtracting cloned decoration offsets when computing content consumption, ensuring content-box conservation.

#### B. Monolithic Content & Overflow
Elements that cannot be broken (e.g., `overflow: hidden`, replaced elements like `<img>`, or lines of text) are **monolithic**.
*   If a monolithic element of size $M$ is pushed to the next page because it doesn't fit the remaining space $R$ on the current page, the parent container's fragment $F_i$ stops early, leaving $R$ unconsumed.
*   *Soundness check:* Does the parent container lose $R$ from its total size? No. The parent clamps its fragment $b_i$ to the break point, and `consumed_block_size` only increments by the *actual* used space. The remaining size carries over to $F_{i+1}$.

#### C. Out-of-Flow (OOF) Positioned Descendants
In Paged Media, `position: absolute` elements are laid out *after* the fragmentation tree is partially built, handled by `NGOutOfFlowLayoutPart`.
*   *Vulnerability:* An OOF element with `top: 2000px; height: 500px` in a 1000px page size must start on Page 3. 
*   *Conservation Mechanics:* Blink creates phantom fragmentainers or resolves the OOF offset against the accumulated `consumed_block_size` of the containing block's fragments. The OOF element's own `consumed_block_size` is tracked independently of the normal flow to prevent polluting the containing block's intrinsic size calculation.

#### D. Margin Truncation at Fragmentainer Boundaries
Per CSS Fragmentation Level 3, unforced breaks truncate margins adjacent to the fragmentainer boundary (`margin-top` at the top of a page after an unforced break collapses to zero).
*   *Impact on Conservation:* Margin truncation reduces the *visual* distance between boxes, meaning total outer-size is *not* conserved ($\Delta B_{\text{margins}} < 0$), though **border-box** conservation holds. Blink handles this via `NGConstraintSpace::IsAtFragmentainerStart()`, zeroing out the margin strut before it can contribute to the parent's `intrinsic_block_size`.

---

### 5. Verification Assertions (DCHECKs)

During debug builds, Blink enforces assembly soundness via specific assertions in `ng_box_fragment_builder.cc` and `ng_fragmentation_utils.cc`:

1.  **Progress Guarantee (No Infinite Loops):**
    ```cpp
    DCHECK_GT(consumed_block_size, previous_break_token->ConsumedBlockSize());
    ```
    *Exception:* If a fragment was forced to break before placing any content (violating progress), `IsBreakBefore()` must be flagged to prevent the engine from spinning up infinite empty pages.

2.  **Final Assembly Resolution:**
    When `has_seen_all_children` is true on fragment $F_N$, the engine runs `ComputeBlockSizeForFragment()`. The final fragment's size is resolved as:
    ```cpp
    LayoutUnit final_block_size = total_block_size - previously_consumed_block_size;
    ```
    This subtraction is the ultimate guarantor of conservation. By deriving the final fragment's size directly from the remainder of the total computed size, floating-point/subpixel (`LayoutUnit`) rounding errors are absorbed into $F_N$, ensuring $\sum b_i == B_{\text{total}}$ holds to the exact subpixel (1/64th of a pixel).

### 6. Conclusion
**Audit Status: SOUND.**
Blink’s LayoutNG enforces conservation of total block size not by post-hoc validation, but by **deductive remainder resolution**. By passing an immutable ledger (`consumed_block_size`) forward via break tokens and resolving the final fragment size as the delta between the global CSS constraint and the ledger sum, total block-size is mathematically conserved across page boundaries.