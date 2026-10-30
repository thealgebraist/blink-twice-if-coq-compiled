**Audit Report: Blink LayoutNG Break Token Propagation & Chaining Across Pages/Fragmentainers**
**Auditor:** Agent 364

In Chromium's Blink LayoutNG architecture, multi-column (`NGColumnLayoutAlgorithm`) and paged media (`NGPageLayoutAlgorithm`) rely on an immutable tree of `NGBreakToken` objects to maintain layout state across fragmentainers (columns or pages). 

Here is the technical breakdown of how break tokens are generated, chained, and propagated across fragmentainers.

---

### 1. Core Primitives
*   **`NGBreakToken` (Base)** & **`NGBlockBreakToken`**: Attached to an `NGPhysicalBoxFragment`. It encapsulates the resumes state of a `NGLayoutInputNode`, storing the `consumed_block_size`, sequence numbers, flags (e.g., `is_break_before`, `is_forced_break`), and an array of `child_break_tokens_`.
*   **`NGInlineBreakToken`**: Tracks fragmentation within an inline formatting context (storing the `item_index` and `text_offset` within `NGInlineNode`).
*   **`NGFragmentBuilder`**: Specifically `NGBoxFragmentBuilder`, which acts as the accumulator for outgoing child break tokens during a single layout pass before minting the parent's break token.

---

### 2. Upward Propagation (Intra-Page Token Generation)
When a page or column runs out of space in the block direction (`FragmentainerSpaceLeft() <= 0`), the layout algorithms abort further placement and bubble break tokens up the layout tree to the fragmentation root:

1.  **Leaf-Level Exhaustion:** A deeply nested algorithm (e.g., `NGBlockLayoutAlgorithm`) attempts to place a child. If the child violates the remaining fragmentainer space (or encounters a `BreakBefore`/`BreakAfter` appeal), it breaks.
2.  **Child Token Minting:** The child's layout pass finishes and returns an `NGLayoutResult` containing a physical fragment with an attached `NGBlockBreakToken`.
3.  **Builder Accumulation:** The parent algorithm receives this result. Inside `NGBoxFragmentBuilder::AddResult()`, if the child's physical fragment has a break token (` fragment.BreakToken()`), it is appended to the builder's `child_break_tokens_` vector.
4.  **Unplaced Siblings:** For any subsequent in-flow siblings that cannot even begin layout in the current fragmentainer, the parent algorithm creates "break-before" tokens via `NGBlockBreakToken::CreateBreakBefore()` and appends them to the builder.
5.  **Parent Token Creation:** When the parent calls `builder.ToBoxFragment()`, the builder checks if `HasBreakTokenData()` is true (e.g., `child_break_tokens_` is non-empty, or block size wasn't fully resolved). If so, it instantiates its own `NGBlockBreakToken`, embedding the `child_break_tokens_` array, and attaches it to the newly minted `NGPhysicalBoxFragment`.

This bubbles recursively up to the Fragmentainer (the Page or Column box itself).

---

### 3. Across-Page Chaining (The Fragmentation Root Loop)
The chaining across pages is orchestrated by the fragmentation context root (e.g., `NGPageLayoutAlgorithm` for printing, or `NGColumnLayoutAlgorithm` for multicol).

```
[Page 1 Physical Fragment] ---> [Page 1 BreakToken] 
                                       | (Passed as Input to Page 2 Algorithm)
                                       v
[Page 2 Physical Fragment] ---> [Page 2 BreakToken] ---> nullptr (End of Document)
```

The root algorithm executes a `while` loop to generate fragmentainers sequentially:

1.  **Initialization:** `const NGBlockBreakToken* break_token = nullptr;` (For Page/Column 1).
2.  **Fragmentainer Instantiation:** A new `NGBlockLayoutAlgorithm` is instantiated to lay out the *Fragmentainer* (the page/column box). The current `break_token` is passed to it via `NGLayoutAlgorithmParams`.
3.  **Layout Execution:** The fragmentainer lays out its children (explained in Section 4).
4.  **Chaining:** When the fragmentainer finishes, it returns an `NGLayoutResult`. The root algorithm extracts the new break token from the resulting fragment:
    ```cpp
    const auto& physical_fragment = To<NGPhysicalBoxFragment>(result->PhysicalFragment());
    break_token = To<NGBlockBreakToken>(physical_fragment.BreakToken());
    ```
5.  **Loop Continuation:** If `break_token` is non-null, the document/multicol has not finished laying out. The loop continues, creating Page $N+1$ and passing `break_token` into it. If `break_token` is `nullptr`, all content is consumed, and the loop terminates.

---

### 4. Downward Propagation (Resuming Layout in Page $N+1$)
When Page $N+1$ begins layout, it holds the `NGBlockBreakToken` from Page $N$. It must reconstruct the layout stack to resume at the exact node and offset where Page $N$ halted.

This is managed by **`NGBlockChildIterator`**.

1.  **Iterator Seeding:** The algorithm initializes `NGBlockChildIterator(Node().FirstChild(), BreakToken())`.
2.  **Tree Reconstruction via Token:** Instead of starting at `FirstChild()`, `NGBlockChildIterator::NextChild()` inspects the `child_break_tokens_` array inside the incoming `BreakToken()`.
3.  **Yielding Resumed Nodes:** The iterator yields the `NGLayoutInputNode` associated with `child_break_tokens_[0]`, pairing it directly with that specific child break token.
4.  **Recursive Descent:** The parent algorithm invokes `child.Layout(constraint_space, child_break_token)`. This passes the token down the tree. Each ancestor uses its respective token from the chain to adjust its internal state (e.g., subtracting `consumed_block_size_` from its CSS height, skipping top borders/paddings) and seeds its own `NGBlockChildIterator`.
5.  **Switching to DOM Order:** Once `NGBlockChildIterator` exhausts the `child_break_tokens_` array from the incoming token, it takes the `NGLayoutInputNode` of the *last* token (provided it was not a parallel flow, like a float or out-of-flow positioned element) and calls `.NextSibling()` to seamlessly transition back to traversing standard unvisited DOM nodes.

---

### 5. Edge Cases in Token Chaining (Audit Checkpoints)

*   **Parallel Flows (`IsAtBlockEnd`):** A block may finish its own box geometry in Page 1, but its overflowing children (or floats) require Page 2. The block's break token is marked `is_at_block_end_`. In Page 2, the parent iterator yields this block to finish its children, and *also* immediately advances to the block's next sibling in the same fragmentainer, because the block itself takes up `0px` of in-flow space in Page 2.
*   **Out-of-Flow (OOF) Descendants:** OOF elements in paged media are often laid out by `NGOutOfFlowLayoutPart` at the fragmentation root level. Their break tokens bypass standard `NGBlockChildIterator` trees and are chained directly via the fragmentainer's builder.
*   **Cloned Box Decorations (`box-decoration-break: clone`):** Affects how `consumed_block_size` is calculated in the break token, forcing each resumed fragment to re-account for border and padding struts before calculating remaining fragmentainer space.
*   **Monolithic Content:** Elements with `Contain: size` or `overflow: scroll` cannot be broken. If they fail to fit, a `break-before` token is minted to push the entire node to the next page, unless the parent is already at the top of the page (forcing an overflow to prevent infinite empty page loops).

**End of Audit.**