**AUDIT REPORT: Blink CSS Layout Worklet (Houdini)**
**Auditor:** Agent 423
**Component:** `third_party/blink/renderer/core/layout/custom/` (LayoutNG Integration)
**Subject:** Custom Fragment Generation Bounds & Constraints

### 1. Executive Summary
In the Blink rendering engine, the CSS Layout API (`registerLayout`) operates within the `LayoutWorklet` global scope, strictly isolated from the main thread's DOM tree to prevent synchronous layout thrashing. Fragment generation is governed by the **LayoutNG** architecture. Custom layouts do not manipulate `LayoutObject` nodes directly; instead, they request immutable `LayoutFragment` objects via `LayoutChild.layoutNextFragment()` and return geometric bounds converted into a `NGLayoutResult`.

Below is the technical breakdown of the bounds, constraints, and sanitization layers applied during custom fragment generation.

---

### 2. Input Bounds: `ConstraintSpace` & `LayoutEdges`
Before a custom layout generates fragments, Blink establishes the parent boundary conditions via `NGConstraintSpace` and maps them to JS-accessible objects (`LayoutConstraints` and `LayoutEdges`).

*   **Fixed Size Bounds (`fixedInlineSize`, `fixedBlockSize`):**
    *   If the parent context dictates an explicit size, these values are passed as finite `double` values.
    *   **Bound Enforcement:** The custom layout *must* return an `autoBlockSize` that respects these bounds unless overridden by extrinsic sizing algorithms on the C++ side.
*   **Available Size Bounds (`availableInlineSize`, `availableBlockSize`):**
    *   Calculated as the `NGConstraintSpace` available size minus the `LayoutEdges` (border + scrollbar + padding).
    *   **Clamping:** Negative available sizes (where edges exceed container size) are strictly clamped to `0.0` before crossing the V8 bindings boundary.
    *   **Indefinite Bounds:** If the block size is indefinite (e.g., an unconstrained root or orthogonal flow), `availableBlockSize` is serialized to JS as `null`, preventing the worklet from resolving percentage-based children against an infinite bound.

---

### 3. Child Fragment Generation Bounds (`ChildLayoutConstraints`)
When the worklet invokes `child.layoutNextFragment(constraints, breakToken)`, Blink translates the JS dictionary (`CustomLayoutConstraintsOptions`) into a child `NGConstraintSpace`.

#### A. Sanitization at the V8 Boundary
Blink strictly audits the `constraints` object passed by the author script to prevent engine instability or LayoutUnit overflow:
*   **NaN and Infinity Rejection:** Any constraint parameter (`fixedInlineSize`, `percentageInlineSize`, etc.) evaluating to `NaN`, `+Infinity`, or `-Infinity` throws a `TypeError` via `ExceptionState` and halts layout execution for the current frame.
*   **Negative Value Clamping:** Negative values passed for sizing bounds are clamped to `0` at the C++ binding layer (`CustomLayoutChild::layoutNextFragment`).

#### B. Fixedpoint Conversion (`LayoutUnit`)
Blink uses subpixel layout represented by `LayoutUnit` (typically a 32-bit signed integer with 6 fractional bits, yielding a resolution of $1/64\text{th}$ of a pixel).
*   **Max Bound (`LayoutUnit::Max()`):** $\approx 33,554,431.98\text{px}$.
*   **Min Bound (`LayoutUnit::Min()`):** $\approx -33,554,432\text{px}$.
*   *Audit Note:* If a script supplies a valid `double` that exceeds `LayoutUnit::Max()`, Blink clamps the value to `LayoutUnit::Max()` during `NGConstraintSpaceBuilder` configuration to prevent integer overflow during subsequent C++ layout passes.

---

### 4. Output Bounds: Fragment Positioning & Container Sizing
The `layout()` method resolves a Promise yielding a `FragmentResultOptions` dictionary:
`{ autoBlockSize, childFragments, data, breakToken }`.

#### A. Container Bounds (`autoBlockSize`)
*   **Defaulting:** If omitted by the author, `autoBlockSize` defaults to `0`.
*   **Validation:** If `autoBlockSize` is negative, `NaN`, or `Infinity`, Blink aborts the custom layout pass and triggers the **Fallback Layout** (Standard Block Layout).
*   **Extrinsic Override:** `autoBlockSize` only dictates the *intrinsic* block size. Once returned to `NGCustomLayoutAlgorithm`, Blink applies standard CSS box-sizing rules (`min-height`, `max-height`, `height`, `aspect-ratio`). The worklet cannot violate CSS `min/max` constraints defined on the host element.

#### B. Child Fragment Positioning (`inlineOffset`, `blockOffset`)
The worklet positions generated `LayoutFragment` instances by mutating their `inlineOffset` and `blockOffset` properties (which default to `0`).
*   **Unbounded Coordinate Space:** Unlike sizing, offsets *can* be negative, allowing fragments to be positioned outside the parent's content box.
*   **Overflow Calculation:** If a child fragment's `offset + size` exceeds the host's final border-box bounds, Blink's `NGBoxFragmentBuilder` automatically expands the host's **Scrollable Overflow** and **Layout Overflow** rects.
*   **Finite Check:** Setting `inlineOffset` or `blockOffset` to `NaN` or `Infinity` throws a V8 `TypeError` immediately upon setter invocation.

---

### 5. Structural & Memory Bounds (Security Audit)
Because the worklet executes arbitrary JS during the rendering pipeline's lifecycle (`DocumentLifecycle::kInPerformLayout`), strict invariants are enforced on fragment ownership and lifecycle.

*   **Fragment Instantiation Bound:** `LayoutFragment` has no public constructor. It can only be instantiated by the C++ engine via `layoutNextFragment()`.
*   **Cross-Pass Contamination (Scope Bound):** Every `CustomLayoutFragment` holds a weak reference to the `CustomLayoutToken` associated with the specific `layout()` invocation.
    *   *Vulnerability Mitigation:* If an author caches a `LayoutFragment` in a global worklet variable and attempts to return it in a subsequent layout pass, or attempts to return a fragment generated from an unrelated `LayoutChild`, `CustomLayoutToken::IsValid()` fails. Blink rejects the fragment, throws a `DOMException` (`InvalidModificationError`), and drops to Fallback Layout.
*   **1:N Fragment Generation (Fragmentation Bound):** While the current CSS Layout API Level 1 specification only partially supports block fragmentation (`BreakToken`), a worklet *is* permitted to call `layoutNextFragment()` multiple times on a single `LayoutChild` within the same pass. However, returning duplicate references to the *exact same* `LayoutFragment` instance in the `childFragments` array is caught by a `HeapHashSet` check in `NGCustomLayoutAlgorithm` and rejected.

### 6. Failure Mode (Fallback Bounds)
If any bound is violated (unhandled JS exception, detached token, invalid `FragmentResultOptions`), `NGCustomLayoutAlgorithm` abandons the worklet output and executes `FallbackLayout()`. This processes the node using `NGBlockLayoutAlgorithm`, ensuring the render tree remains in a valid, non-corrupted state.