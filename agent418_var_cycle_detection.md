**AUDIT REPORT: Blink CSS Custom Property Cycle Detection & Invalidation**
**Agent:** 418
**Target:** Chromium / Blink Rendering Engine (`third_party/blink/renderer/core/css/resolver/style_Cascade.cc`)
**Specification Reference:** CSS Custom Properties for Cascading Variables Module Level 1 (Section 2.3: Resolving Dependency Cycles)

---

### 1. Architectural Overview
In the Blink rendering engine, CSS Custom Properties (variables) are resolved lazily during the style cascade phase via the `StyleCascade` class. Because variables can reference other variables via `var()` functions, they implicitly form a Directed Graph. 

If a cycle exists in this graph, the specification mandates that all custom properties participating in the cycle must become **invalid at computed-value time (IACVT)**, which functionally resolves them to their initial (unset/guaranteed-invalid) value.

### 2. Dependency Graph & State Representation
Unlike traditional static graph resolution, Blink does not pre-build an explicit adjacency list for the DAG. Instead, it performs an **implicit Depth-First Search (DFS)** during the token resolution phase (`StyleCascade::ResolveTokensInto`).

To track the graph state during traversal, `StyleCascade` utilizes a state-tracking map (similar to classical 3-color DFS cycle detection):
*   **Unvisited (Implicit):** The property has not been requested yet in the current cascade pass.
*   **`kInProgress` (Gray):** The property is currently on the active recursion stack. It is being resolved.
*   **`kDone` (Black):** The property has been fully resolved and its tokens are cached in the `ComputedStyle`.

Alongside this, Blink maintains two critical internal flags within the recursive `Resolve` call chain:
*   `in_cycle`: A boolean flag indicating a cycle has been detected and the stack is currently unwinding through the cycle participants.
*   `cycle_start`: The `AtomicString` (name) of the custom property where the cycle was first intersected.

---

### 3. DAG Traversal & Cycle Detection Mechanics

The traversal is initiated when a standard property or custom property requests the value of a custom property via `ResolveCustomProperty()`.

#### Step 3.1: Forward Traversal (DFS)
1. Blink looks up the requested variable `--foo`.
2. It marks `--foo` as `kInProgress` and pushes it onto the call stack.
3. Blink parses `--foo`’s token stream. When it encounters `var(--bar, fallback)`:
   * It pauses parsing `--foo` and recursively invokes resolution for `--bar`.
   * `--bar` is marked `kInProgress`.

#### Step 3.2: Cycle Detection (Back-Edge Identification)
A cycle is detected if the traversal encounters a `var(--target)` where `--target` is **already marked as `kInProgress`**. This represents a back-edge in the DFS tree.

When this occurs:
1. The engine sets the internal state `cycle_start = --target`.
2. It aborts further token resolution for the current branch and returns `nullptr` (indicating resolution failure).

---

### 4. Cycle Invalidation & Fallback Suppression

The most critical aspect of the Blink audit is how the engine differentiates between a **cycle participant** and a **cycle dependent**, and how it handles `var()` fallbacks.

#### Step 4.1: Unwinding the Cycle
As the recursion stack unwinds from the back-edge detection:
1. Every property on the stack checks if `in_cycle` is active.
2. While `current_property != cycle_start`, the property knows it is part of the cycle loop.
3. **Invalidation:** Its value in the `ComputedStyle` is overwritten with the `CSSCustomPropertyDeclaration` equivalent of **guaranteed-invalid** (`CSSInvalidVariableValue`).
4. **State Update:** Its state is moved from `kInProgress` to `kDone` so subsequent independent references immediately see it as invalid without re-triggering traversal.
5. Once the unwinding reaches the frame where `current_property == cycle_start`, that property is also invalidated, and the `in_cycle` flag is cleared. The cycle is now fully contained and neutralized.

#### Step 4.2: The Fallback Trap (Crucial Spec Compliance)
Consider the following cyclic CSS:
```css
:root {
  --a: var(--b, red);
  --b: var(--a, blue);
}
```
A naive implementation might see `--a` fail to resolve, trigger `--b`'s fallback (`blue`), and resolve `--a` to `blue`, thereby breaking the cycle illegally. 

**Blink's Defense:**
When `ResolveVarInto()` detects that the resolution of `--a` failed *specifically because a cycle is currently unwinding* (the `in_cycle` flag is true), **it explicitly suppresses the evaluation of the fallback value**. 
* `--b` is forced to fail, propagating the `in_cycle` state up to `--a`.
* Both `--a` and `--b` become IACVT (guaranteed-invalid).

#### Step 4.3: Post-Cycle Dependents (DAG Edge Nodes)
Consider adding a third variable to the previous example:
```css
  --c: var(--a, green);
```
Suppose the traversal started at `--c` -> `--a` -> `--b` -> `--a`.
1. Cycle detected at `--a`. `cycle_start` = `--a`.
2. Unwinds to `--b`: Marked IACVT. Fallbacks ignored.
3. Unwinds to `--a`: Marked IACVT. Fallbacks ignored. `cycle_start` is reached, so **the cycle state is terminated**.
4. Unwinds to `--c`: `--c` sees that `--a` resolved to guaranteed-invalid, *not* an active cycle. Therefore, `--c` **is allowed to use its fallback**, successfully resolving to `green`.

---

### 5. Secondary Audit Vector: `attr()` and Unit Cycles
Blink's `StyleCascade` cycle detector is not limited to `--*` properties. It uses the exact same DAG infrastructure to catch cross-feature cycles:
*   **Font-relative lengths in font-size:** e.g., `--a: 2em; font-size: var(--a);`
*   **Line-height cycles:** Involving `lh` units referencing properties that depend on `line-height`.

Blink handles this by treating `font-size` and `line-height` as pseudo-nodes in the dependency graph during cascade resolution, applying the same `kInProgress` lockouts.

### 6. Summary of Audit Findings
*   **Time Complexity:** $\mathcal{O}(V + E)$ where $V$ is the number of unique custom properties and $E$ is the number of `var()` references. Memoization via the `kDone` state prevents exponential blowup in "diamond" dependency graphs (e.g., `--a` references `--b` and `--c`, which both reference `--d`).
*   **Vulnerability Surface:** Deeply nested non-cyclic `var()` chains could theoretically threaten the C++ call stack. Blink mitigates this by enforcing a hard recursion depth limit alongside the token count limit (`kMaxSubstitutionTokens`), preventing Stack Overflow DoS attacks via CSS. 

**Status:** Blink's implementation is robust, linear-time compliant, and strictly adheres to W3C CSSWG fallback suppression rules during cycle unwinding. *Agent 418 signing off.*