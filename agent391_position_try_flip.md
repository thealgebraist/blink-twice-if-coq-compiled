**AUDIT LOG: AGENT 391**  
**TARGET SYSTEM:** Chromium Blink Rendering Engine (`third_party/blink/renderer/core/layout`)  
**COMPONENT:** CSS Anchor Positioning — `@position-try` Coordinate Flip Reflection (`flip-block`, `flip-inline`, `flip-start`)  
**SUBJECT:** Formalization of the Reflection Involution Theorem in Layout Space

---

### 1. Executive Summary
During the resolution of CSS Anchor Positioning fallback tactics, Blink utilizes geometric transformations to evaluate candidate `position-try` rules. Specifically, the `flip-block`, `flip-inline`, and `flip-start` tactics apply reflections across axis-aligned or diagonal planes within the formatting context. 

This audit details the **Reflection Involution Theorem** as it governs Blink’s `TryValueFlips` and `LogicalOofNodeForFragmentation` coordinate space transformations. Ensuring strict adherence to involution ($\mathcal{R}(\mathcal{R}(x)) = x$) prevents floating-point drift, cyclic fallback infinite loops, and layout cache invalidation errors during multi-pass anchor resolution.

---

### 2. Mathematical Foundation: The Reflection Involution Theorem

In Euclidean and affine geometry, an **involution** is a function or transformation $f$ that is its own inverse, such that for all $x$ in the domain of $f$:
$$f(f(x)) = x$$

#### Theorem Statement (Layout Coordinate Space)
Let $\mathcal{L}$ be the 2D logical coordinate space defined by the writing mode of the containing block, spanned by the orthogonal basis vectors $\{\mathbf{e}_{inline}, \mathbf{e}_{block}\}$. Let $S \subset \mathcal{L}$ be the set of all valid CSS inset, margin, alignment, and sizing properties associated with an anchor-positioned element.

A coordinate flip operation $\mathcal{R}_k : S \to S$ (where $k \in \{\text{inline}, \text{block}, \text{start}\}$) is a linear reflection transformation represented by a matrix $\mathbf{M}_k$. 

**The theorem states that $\mathbf{M}_k$ is involutory if and only if:**
$$\mathbf{M}_k^2 = \mathbf{I}$$
where $\mathbf{I}$ is the identity matrix. Consequently, applying the same `position-try` flip tactic twice restores the exact original layout descriptor state without loss of fidelity.

---

### 3. Blink Implementation Mechanics

In Blink, anchor positioning coordinates are not flipped by mutating physical pixel values directly in the first pass. Instead, Blink performs **symbolic reflection** on the `ComputedStyle` properties via `TryTacticTransform`, followed by **geometric reflection** on the `LogicalRect` of the anchor box.

#### A. Symbolic Property Involution
Consider the set of logical properties $P = \{\text{inset-block-start}, \text{inset-block-end}, \text{inset-inline-start}, \text{inset-inline-end}\}$.

1. **`flip-block` ($\mathcal{R}_{block}$):**
   Swaps `block-start` and `block-end` bindings.
   $$\mathbf{M}_{block} = \begin{bmatrix} 1 & 0 \\ 0 & -1 \end{bmatrix}$$
   *Proof of Involution:* 
   $$\mathbf{M}_{block}^2 = \begin{bmatrix} 1 & 0 \\ 0 & -1 \end{bmatrix} \begin{bmatrix} 1 & 0 \\ 0 & -1 \end{bmatrix} = \begin{bmatrix} 1 & 0 \\ 0 & 1 \end{bmatrix} = \mathbf{I}$$

2. **`flip-inline` ($\mathcal{R}_{inline}$):**
   Swaps `inline-start` and `inline-end` bindings.
   $$\mathbf{M}_{inline} = \begin{bmatrix} -1 & 0 \\ 0 & 1 \end{bmatrix}$$
   *Proof of Involution:* $\mathbf{M}_{inline}^2 = \mathbf{I}$.

3. **`flip-start` ($\mathcal{R}_{start}$):**
   Reflects coordinates across the main diagonal running from `inline-start/block-start` to `inline-end/block-end`. This transposes the inline and block axes.
   $$\mathbf{M}_{start} = \begin{bmatrix} 0 & 1 \\ 1 & 0 \end{bmatrix}$$
   *Proof of Involution:* 
   $$\mathbf{M}_{start}^2 = \begin{bmatrix} 0 & 1 \\ 1 & 0 \end{bmatrix} \begin{bmatrix} 0 & 1 \\ 1 & 0 \end{bmatrix} = \begin{bmatrix} 1 & 0 \\ 0 & 1 \end{bmatrix} = \mathbf{I}$$

#### B. Anchor Reference Point Reflection
When an inset property uses an `anchor()` function, e.g., `top: anchor(bottom)`, the argument inside the `anchor()` function must also undergo reflection.
Let $A \in [0, 1]$ represent the normalized percentage along the anchor axis (where `start` $= 0$ and `end` $= 1$).
The reflection operator $\phi(A)$ on the anchor side is defined as:
$$\phi(A) = 1 - A$$

*Proof of Involution:*
$$\phi(\phi(A)) = 1 - (1 - A) = A$$

---

### 4. Compound Transformations & Dihedral Group $D_4$

In Blink's `CSSPositionTryDescriptors`, an author may chain tactics, such as `position-try-fallbacks: flip-block flip-inline flip-start`. 

**Audit Warning:** While individual reflections are involutions, **combinations of non-orthogonal reflections are not necessarily involutions.**

The set of generated transformations forms the Dihedral Group $D_4$ (the symmetries of a square), consisting of 8 distinct states:
*   Notice that $\mathbf{M}_{block}$ and $\mathbf{M}_{inline}$ commute:
    $$\mathbf{M}_{block}\mathbf{M}_{inline} = \mathbf{M}_{inline}\mathbf{M}_{block} = \begin{bmatrix} -1 & 0 \\ 0 & -1 \end{bmatrix}$$
    This compound operation (a $180^\circ$ rotation) **is** an involution: $(\mathbf{M}_{block}\mathbf{M}_{inline})^2 = \mathbf{I}$.

*   However, combining `flip-start` with `flip-inline` or `flip-block` does **not** commute and represents a $90^\circ$ rotation:
    $$\mathbf{R}_{90} = \mathbf{M}_{start}\mathbf{M}_{inline} = \begin{bmatrix} 0 & 1 \\ 1 & 0 \end{bmatrix}\begin{bmatrix} -1 & 0 \\ 0 & 1 \end{bmatrix} = \begin{bmatrix} 0 & 1 \\ -1 & 0 \end{bmatrix}$$
    *Failure of Involution:*
    $$\mathbf{R}_{90}^2 = \begin{bmatrix} -1 & 0 \\ 0 & -1 \end{bmatrix} \neq \mathbf{I}$$
    Here, $\mathbf{R}_{90}^4 = \mathbf{I}$ (Period 4, not Period 2).

---

### 5. Blink Engine Audit Findings & Edge Cases

As Agent 391, verification of the C++ implementation in `out_of_flow_layout_part.cc` and `try_tactic_transform.h` highlights three critical invariants required to maintain the Reflection Involution Theorem in production:

#### 1. Fixed-Point LayoutUnit Arithmetic (Subpixel Drift)
Blink uses `LayoutUnit` (fixed-point 26.6 format, i.e., $1/64\text{th}$ of a pixel) for layout geometry. 
If reflection is calculated geometrically over physical coordinates relative to an arbitrary anchor center $C$:
$$x' = 2C - x$$
If $C$ is computed via division (e.g., `anchor_rect.X() + anchor_rect.Width() / 2`), integer truncation in `LayoutUnit` breaks the involution theorem:
$$\text{Trunc}(2C) - (\text{Trunc}(2C) - x) = x \quad \text{(Holds)}$$
*However*, if $C$ is recalculated dynamically based on rounded fragment sizes during the second pass, $\mathcal{R}(\mathcal{R}(x)) = x \pm \epsilon$ (where $\epsilon = \frac{1}{64}\text{px}$). 
**Mitigation:** Blink correctly executes reflection at the *CSS Value/Logical* layer (`TryTacticTransform`) **before** resolving `LayoutUnit` geometry, preserving exact involution.

#### 2. Writing-Mode Orthogonality (`flip-start`)
When `flip-start` is applied, `width` and `height` (inline-size and block-size) are swapped. If the element contains orthogonal flows or intrinsic aspect-ratios, the intrinsic size calculation `ComputeMinMaxSizes` is invoked on the transposed axis.
For involution to hold geometrically, the intrinsic sizing algorithm must be pure and deterministic. Any state cached on the `LayoutBox` during the unflipped pass must be invalidated before evaluating the `flip-start` pass.

#### 3. Self-Alignment Keyword Reflection (`align-self` / `justify-self`)
For alignment properties, the involution mapping is:
$$\text{start} \leftrightarrow \text{end}$$
$$\text{self-start} \leftrightarrow \text{self-end}$$
$$\text{flex-start} \leftrightarrow \text{flex-end}$$
**Vulnerability:** Values like `center`, `stretch`, and `baseline` act as fixed points under $\mathcal{R}_{\text{inline}}$ and $\mathcal{R}_{\text{block}}$. However, under $\mathcal{R}_{\text{start}}$, `align-self` and `justify-self` swap entirely. If an axis contains `baseline` and is swapped to the inline axis via `flip-start`, Blink must ensure that fallback alignment normalization does not destructively overwrite the original specified keyword, which would violate $\mathcal{R}_{\text{start}}^2 = \mathbf{I}$.

---

**STATUS:** AUDIT COMPLETE.  
**CONCLUSION:** Blink's symbolic pre-layout transformation architecture (`TryTacticTransform`) successfully upholds the Reflection Involution Theorem by isolating reflections to the discrete group $D_4$ prior to subpixel `LayoutUnit` quantization.