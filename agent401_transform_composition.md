**AUDIT LOG: AGENT 401**
**SUBSYSTEM:** Blink Compositor (`cc` / `gfx::Transform`)
**SUBJECT:** Affine Translation Addition & Composition

### 1. Architectural Context
Within the Chromium Blink Compositor (`cc::TransformTree`), 2D affine transforms are frequently utilized as a fast-path optimization over full 4x4 3D homogeneous matrices (`gfx::AxisTransform2d` or flat `gfx::Transform`). 

An affine transformation in 2D space consists of a 2x2 linear transformation matrix $A$ (representing scale, rotation, and skew) and a 2x1 translation vector $T$:

$$M = \begin{bmatrix} a & c & t_x \\ b & d & t_y \\ 0 & 0 & 1 \end{bmatrix}$$

### 2. The Composition Audit: "Translation Addition"
When auditing transform composition (multiplying a parent transform $M_1$ by a local child transform $M_2$), a common vulnerability or logic error is **naive translation addition**—assuming the resulting translation is simply $T_1 + T_2$. 

In the compositor pipeline, order of operations is strictly defined by matrix multiplication ($M_{total} = M_1 \times M_2$).

#### Case A: General Affine Composition (Pre-Translation / Local Space)
When a child layer applies a translation $T_2$ within the coordinate space of a parent $M_1$ that contains scale, rotation, or skew, the child's translation vector must first be transformed by the parent's linear matrix $A_1$ before being added to the parent's translation $T_1$.

$$\begin{bmatrix} A_1 & T_1 \\ 0 & 1 \end{bmatrix} \times \begin{bmatrix} A_2 & T_2 \\ 0 & 1 \end{bmatrix} = \begin{bmatrix} A_1 A_2 & (A_1 T_2) + T_1 \\ 0 & 1 \end{bmatrix}$$

**Component Expansion (`gfx::Transform::PreConcat`):**
*   $t_{x\_new} = (a_1 \cdot t_{x2} + c_1 \cdot t_{y2}) + t_{x1}$
*   $t_{y\_new} = (b_1 \cdot t_{x2} + d_1 \cdot t_{y2}) + t_{y1}$

*Audit Note:* Direct addition ($T_1 + T_2$) fails here if $A_1 \neq I$.

#### Case B: Post-Translation (Parent / Screen Space)
If the compositor applies a translation *after* the local transform $M_1$ (e.g., applying a screen-space scroll offset $T_2$ to an already transformed layer), the linear matrix $A_2$ is the Identity matrix ($I$).

$$\begin{bmatrix} I & T_2 \\ 0 & 1 \end{bmatrix} \times \begin{bmatrix} A_1 & T_1 \\ 0 & 1 \end{bmatrix} = \begin{bmatrix} A_1 & T_2 + T_1 \\ 0 & 1 \end{bmatrix}$$

**Component Expansion (`gfx::Transform::PostTranslate`):**
*   $t_{x\_new} = t_{x1} + t_{x2}$
*   $t_{y\_new} = t_{y1} + t_{y2}$

*Audit Note:* Here, pure translation addition is mathematically sound because $T_2$ is not subject to the linear basis of $A_1$.

#### Case C: Pure Translation Fast-Path
When the compositor flags both $M_1$ and $M_2$ as `IsIdentityOrTranslation()` ($A_1 = I$ and $A_2 = I$), the composition degrades to simple vector addition regardless of multiplication order (commutativity holds):

$$T_{total} = T_1 + T_2 = \begin{bmatrix} t_{x1} + t_{x2} \\ t_{y1} + t_{y2} \end{bmatrix}$$

### 3. Implementation Verification (`ui/gfx/geometry`)
In the Chromium codebase, this distinction is enforced via specific methods on `gfx::Transform`:

1.  **`Translate(x, y)` (Pre-multiply):** Mutates the translation components by projecting $(x, y)$ through the current basis vectors. Used when accumulating CSS `transform: scale(...) translate(...)` from left to right.
2.  **`PostTranslate(x, y)` (Post-multiply):** Directly adds $(x, y)$ to the existing $m_{03}$ and $m_{13}$ (or $t_x, t_y$) components. Used extensively in `cc::TransformTree::UpdateLocalTransform` when applying `scroll_offset` or `position` shifts in the parent's coordinate space.

### 4. Precision & Edge Cases
*   **Floating-Point Drift:** Repeatedly adding and subtracting translations (e.g., during compositor-driven scroll deltas) using `float` can lead to sub-pixel precision loss. Blink mitigates this by computing absolute transforms from the `TransformNode` source properties per frame rather than accumulating frame-over-frame deltas into the same matrix.
*   **2D Axis Alignment:** If a transform is strictly scale + translation (`gfx::AxisTransform2d`), `PreScale` followed by `PreTranslate` reduces to $T_{total} = (S_1 \odot T_2) + T_1$ (Hadamard product), bypassing full dot-product calculations for performance.

**STATUS:** Audit complete. Affine translation addition conforms to expected linear algebra invariants within `gfx` and `cc`.