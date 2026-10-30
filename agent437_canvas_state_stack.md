**AUDIT REPORT: BLINK CANVAS 2D STATE STACK**
**Auditor:** Agent 437
**Target:** `third_party/blink/renderer/modules/canvas/canvas2d/` (`BaseRenderingContext2D`, `CanvasRenderingContext2DState`)
**Subject:** `save()` / `restore()` Pushdown Automaton Semantics & Memory Architecture

---

### 1. ARCHITECTURAL OVERVIEW
In Blink, the Canvas 2D context state is not maintained as a flat struct; it is managed as a **Last-In-First-Out (LIFO) Pushdown Stack** of Oilpan-managed ( garbage-collected) objects: `HeapVector<Member<CanvasRenderingContext2DState>> state_stack_`. 

*   **The Top of Stack (`state_stack_.back()`):** Represents the active, mutable drawing state (`ModifiableState()`).
*   **Invariant:** `state_stack_` is never empty. Index `0` is initialized at context creation with the default HTML5 Canvas state.

---

### 2. PUSHDOWN SEMANTICS

#### A. The `save()` Operation (PUSH)
When `context.save()` is invoked, the engine does not immediately clone all underlying Skia (`cc::PaintFlags`) data structures due to performance overhead. Instead, it utilizes a **Lazy / Copy-on-Write (CoW)** semantic mixed with shallow Oilpan pointer copying.

1.  **State Allocation:** A new `CanvasRenderingContext2DState` object is allocated on the Oilpan heap via `MakeGarbageCollected<CanvasRenderingContext2DState>(*CurrentState(), kDontCopyClipList)`.
2.  **Copy Semantics:**
    *   **Primitives & Matrix:** Transformation matrices (`AffineTransform`), `globalAlpha`, `lineWidth`, `shadowBlur`, etc., are copied by value.
    *   **Complex Styles:** `fillStyle` and `strokeStyle` (`CanvasStyle`) are shared via pointers/references until mutated.
    *   **Fonts:** `Font` objects and `FontDescription` are copied via Blink's internal ref-counted font cache mechanisms.
    *   **Clip List:** Deferred/Lazy copy (`kDontCopyClipList`) until a new `clip()` call mutates the top state, or tracked in parity with the underlying `cc::PaintCanvas`.
3.  **Stack Push:** The newly constructed state is appended to `state_stack_`.
4.  **Backend Synchronization:** A `save()` op is recorded into the underlying `cc::PaintCanvas` (which serializes to an `SkCanvas::save()` command in the display list). This preserves the low-level CTM (Current Transformation Matrix) and physical clip regions on the GPU/raster side.

#### B. The `restore()` Operation (POP)
When `context.restore()` is invoked, the context rolls back to the previously saved state.

1.  **Underflow Guard:** The stack size is validated: `if (state_stack_.size() <= 1) return;`. Per the WHATWG specification, popping an empty save stack (where only the base state exists) is a **silent no-op**.
2.  **Stack Pop:** `state_stack_.pop_back()` is executed. The popped `CanvasRenderingContext2DState` loses its strong reference in the vector and is queued for sweep by the Oilpan garbage collector.
3.  **State Re-binding:** `CurrentState()` now resolves to the new `state_stack_.back()`.
4.  **Backend Synchronization:** `cc::PaintCanvas::restore()` is invoked, instructing Skia to pop its internal matrix and clip stack.

---

### 3. STATE BOUNDARY AUDIT (WHAT IS PUSHED VS. IGNORED)

A critical vector for rendering bugs is misunderstanding the boundary between the **Context State** and the **Canvas Buffer/Path State**.

| **Pushed to `state_stack_` (Restorable)** | **Excluded from `state_stack_` (Persistent)** |
| :--- | :--- |
| **CTM:** Current Transformation Matrix (`AffineTransform`) | **Current Path:** `Path2D` subpaths (`beginPath`, `moveTo`, `lineTo`) |
| **Clipping Region:** Current `ClipList` | **Bitmap Buffer:** Current rendered pixels on the backing surface |
| **Styles:** `fillStyle`, `strokeStyle` (Colors, Gradients, Patterns) | **Canvas Dimensions:** `width` and `height` attributes |
| **Compositing:** `globalAlpha`, `globalCompositeOperation` | **Context Attributes:** `alpha`, `desynchronized`, `colorSpace`, `willReadFrequently` |
| **Shadows:** `shadowColor`, `shadowBlur`, `shadowOffsetX/Y` | **Hit Regions:** (Deprecated/Removed) |
| **Line Styles:** `lineWidth`, `lineCap`, `lineJoin`, `miterLimit`, `lineDash`, `lineDashOffset` | |
| **Text Styles:** `font`, `textAlign`, `textBaseline`, `direction`, `letterSpacing`, `wordSpacing` | |
| **Filtering & Smoothing:** `filter` (CSS/SVG filters), `imageSmoothingEnabled`, `imageSmoothingQuality` | |

---

### 4. EDGE CASES, DESYNC & VULNERABILITY VECTORS

During the audit of the pushdown mechanics, Agent 437 highlights four critical areas of operational complexity in Blink:

#### 1. Unbounded Stack Growth (OOM Vector)
The HTML Canvas specification does not define a hard limit on `save()` depth. A tight loop of `ctx.save()` will continuously allocate `CanvasRenderingContext2DState` objects on the Oilpan heap and record `SaveOp` commands into the `cc::PaintRecorder`. 
*   **Mitigation:** Blink relies on the PartitionAlloc/Oilpan OOM (Out-Of-Memory) crash handlers. Deeply nested saves degrade rasterization performance linearly.

#### 2. Canvas Reset / Resize (`ResetInternal`)
Modifying `canvas.width` or `canvas.height` triggers a hard reset of the state machine:
*   `state_stack_.Clear()` is called.
*   A single, fresh default `CanvasRenderingContext2DState` is pushed to index `0`.
*   The `cc::PaintCanvas` recording is flushed/discarded.

#### 3. GPU Context Loss & State Realization (`RestoreMatrixClipStack`)
Because Canvas 2D is backed by a deferred `cc::PaintRecorder` (Display List), the `cc::PaintCanvas` is periodically flushed to the GPU or destroyed upon GPU Context Loss. 
*   **Desync Risk:** When a flush or context recovery occurs, Skia's internal stack is wiped, while Blink's `state_stack_` remains intact.
*   **Resolution:** Blink executes `RestoreMatrixClipStack(cc::PaintCanvas*)`. It iterates *bottom-up* from `state_stack_.begin()` to `state_stack_.end()`, re-issuing `save()`, applying transforms, and re-applying the `ClipList` to reconstruct the exact pushdown state in the new Skia backend instance.

#### 4. Non-Invertible Matrices (CTM Poisoning)
If a state is scaled to `(0, 0)` or `NaN/Infinity` (where permitted), the CTM becomes non-invertible (`!IsTransformInvertible()`).
*   Path operations and clip applications are silently aborted while in this state.
*   **Pushdown Recovery:** Because the CTM is stored by value on the `state_stack_`, calling `restore()` cleanly recovers the context from a non-invertible state without corrupting the parent coordinate space—a behavior that previously caused state-bleed bugs in older WebKit implementations when relying purely on inverse matrix multiplication to undo transforms.

---
**END OF AUDIT // AGENT 437**