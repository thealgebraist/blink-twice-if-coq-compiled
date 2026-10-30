### 1. CSS Grid Track Sizing: Blink vs. W3C CSS Grid Level 1 (Section 11)

In Chromium’s Blink engine (specifically within the LayoutNG architecture, located across `ng_grid_layout_algorithm.cc` and `ng_grid_track_collection.cc`), the track sizing algorithm translates the abstract mathematical rules of **W3C CSS Grid Layout Module Level 1 (Section 11: Grid Sizing)** into a deterministic, fixed-point layout algorithm using `LayoutUnit`.

```
W3C Spec (Section 11.5)                         Blink Implementation (LayoutNG)
+-----------------------------------+           +------------------------------------------+
| 1. Initialize per-item space      |           | 1. Filter Non-Frozen Tracks              |
| 2. Sort tracks by growth potential|   ====>   | 3. Sort by: GrowthLimit - BaseSize       |
| 3. Distribute space equally       |           | 4. Clamp by max(0, Limit - Base)         |
| 4. Freeze tracks hitting limits   |           | 5. Subpixel remainder -> 1st tracks      |
+-----------------------------------+           +------------------------------------------+
```

#### Track Growth Limits (`base_size` vs. `growth_limit`)
The W3C specification defines two fundamental variables for every grid track during sizing:
*   **Base Size:** The track's current resolved minimum size, initialized to zero or the resolved value of a fixed minimum track sizing function.
*   **Growth Limit:** The maximum size the track can reach before becoming unconstrained, initialized to $\infty$ (`kIndefiniteSize` in Blink, represented as `-1` in `LayoutUnit`) or the resolved fixed maximum track sizing function.

In Blink's `NGGridSet` (the structural unit managed by `NGGridTrackCollection` that groups adjacent tracks sharing identical sizing definitions to optimize complexity from $O(\text{tracks})$ to $O(\text{sets})$), these are maintained as `LayoutUnit` members.

**Spec Invariant:** Section 11.4 dictates that *if the growth limit is less than the base size, increase the growth limit to match the base size*. 
**Blink Implementation:** Blink enforces this invariant eagerly at the end of every phase in `DistributeExtraSpaceToSets` via a helper clamp:

```cpp
if (set.GrowthLimit() != kIndefiniteSize && set.GrowthLimit() < set.BaseSize()) {
  set.SetGrowthLimit(set.BaseSize());
}
```

#### Space Distribution (`DistributeExtraSpaceToTrack` / `DistributeExtraSpaceToSets`)
Section 11.5 ("Distribute extra space across spanned tracks") defines how an item spanning multiple tracks increases their sizes to accommodate its intrinsic contribution (minimum, min-content, or max-content).

The theoretical W3C algorithm states that extra space must be distributed equally among target tracks, freezing tracks as they reach their `growth_limit` so they receive no further space during the current pass, until all space is exhausted or all tracks are frozen.

Because the W3C model implies a continuous loop, Blink implements this as a two-pass discrete sorting algorithm:

1.  **Growth Potential Calculation:** For each track (or `NGGridSet`), Blink calculates its *item-incurred increase* potential:
    $$\Delta_{\text{potential}} = \begin{cases} \text{growth\_limit} - \text{base\_size} & \text{if growth\_limit} \neq \infty \\ \infty & \text{otherwise} \end{cases}$$

2.  **Sorting / Two-Tier Processing:** When maximizing tracks or resolving intrinsic contributions, Blink segregates tracks that have a finite growth limit from those with an infinite (`kIndefiniteSize`) growth limit. 
    *   If growing `base_size` up to `growth_limit`, finite-limit tracks are sorted in ascending order of their $\Delta_{\text{potential}}$ (normalized per track within an `NGGridSet`).
    *   Blink iterates through the sorted sets. At index $i$ with $N_{\text{remaining}}$ unfrozen tracks left, it computes the equal share:
        $$\text{Share} = \frac{\text{ExtraSpace}}{N_{\text{remaining}}}$$
    *   If $\text{Share} \ge \Delta_{\text{potential}, i}$, the track absorbs $\Delta_{\text{potential}, i}$, hits its growth limit, is marked "frozen" for this distribution step, and $\text{ExtraSpace}$ is decremented by the absorbed amount. Because the array is sorted, subsequent iterations naturally recalculate a larger $\text{Share}$ for the remaining unfrozen tracks without needing to restart the loop.

3.  **Expanding Beyond Growth Limits:** If all tracks reach their `growth_limit` and $\text{ExtraSpace} > 0$ (which occurs when distributing `max-content` contributions or handling `fit-content()` limits), the spec states that space should now be distributed equally to tracks with an *infinite* growth limit, or to *all* affected tracks if all have finite limits (respecting the `fit-content` argument as a hard ceiling). Blink handles this by passing a boolean state (`is_equal_distribution`) into a secondary invocation of the distribution routine that ignores the current `growth_limit` and only clamps against the `fit_content_limit`.

#### Remainder Distribution (Subpixel Quantization)
The W3C specification assumes real numbers ($\mathbb{R}$), stating simply to "distribute the space equally." In Blink, layout operates in fixed-point math via `LayoutUnit`, which has a resolution of $\frac{1}{64}\text{px}$ (`kFixedPointDenominator = 64`).

When dividing `ExtraSpace` (represented as raw integer subpixels) across $N$ tracks, integer division yields a truncation remainder:

$$\text{Share}_{\text{base}} = \left\lfloor \frac{\text{ExtraSpace}_{\text{raw}}}{N} \right\rfloor \times \frac{1}{64}\text{px}$$

$$\text{Remainder}_{\text{raw}} = \text{ExtraSpace}_{\text{raw}} \pmod N$$

If this remainder were discarded, spanned items would fail to fit within their tracks by up to $\frac{N-1}{64}\text{px}$, triggering unintended text wrapping or overflow. If it were rounded up, the grid would exceed its container bounds.

**Blink's Solution:** Blink preserves exact conservation of space. During the distribution loop across `NGGridSet`s, `LayoutUnit::FromRawValue` is used. When $N$ tracks are eligible to receive space unconditionally (after growth-limit clamping is resolved for the subset):
1. Each track receives $\text{Share}_{\text{base}}$.
2. The first $\text{Remainder}_{\text{raw}}$ tracks (iterated in DOM/grid-order) each receive an additional quantum of `LayoutUnit::Epsilon()` ($\frac{1}{64}\text{px}$).

When operating on `NGGridSet`s (where a single set represents $M$ tracks), if a set absorbs a portion of the remainder that isn't evenly divisible by $M$, the set’s total size stores the exact sum, and individual track offsets are resolved later during `ComputeSetGeometry` using the same deterministic Bresenham-style error accumulation step.

---

### 2. Box Shadow Geometry: Blink `ShadowData` vs. CSS Backgrounds & Borders 3 (Section 7.2)

**W3C CSS Backgrounds and Borders Module Level 3 (Section 7.2: Drop Shadows: the `box-shadow` property)** defines the syntax and visual rendering model of box shadows. In Blink, this is parsed into `ShadowData` (`shadow_data.h/.cc`) and aggregated into a `ShadowList` (`shadow_list.h/.cc`).

#### Data Representation
The W3C specification defines a single shadow via the grammar:
`none | <shadow>#` where `<shadow> = inset? && <length>{2,4} && <color>?`

Blink represents a single `<shadow>` primitive via `blink::ShadowData`:
*   **`<length>{2}` (Offsets):** Stored as `gfx::Vector2dF offset_` (representing horizontal $x$ and vertical $y$ offsets).
*   **`<length>` (Blur Radius):** Stored as `float blur_`. Spec constraint: negative values are invalid at parse time.
*   **`<length>` (Spread Distance):** Stored as `float spread_`. Positive values expand the shadow; negative values contract it.
*   **`inset?`:** Stored as `ShadowStyle style_` (`kNormal` vs. `kInset`).
*   **`<color>?`:** Stored as `StyleColor color_`.

#### Blur Radius vs. Gaussian Standard Deviation ($\sigma$)
Section 7.2 specifies that for a non-zero blur radius $B$, the resulting shadow must approximate a Gaussian blur with a standard deviation $\sigma = \frac{B}{2}$, or an approximation thereof whose visual extent stays within a defined tolerance.

In Blink (delegating to Skia's `SkBlurMask` / `SkMaskFilter::MakeBlur`), the conversion from CSS blur radius to Gaussian $\sigma$ is implemented in `BlurRadiusToStdDev(float radius)`:

$$\sigma = \text{radius} \times 0.5f$$

*(Note: Historically, Blink and Skia used a scaling factor of $\approx 0.57735$ ($\frac{1}{\sqrt{3}}$) derived from SVG box-blur approximations, before aligning directly with the CSS WG resolution that standardized $\sigma = 0.5 \times \text{blur\_radius}$).*

#### Shadow Outset Supremum (Visual Overflow Calculation)
A critical divergence between the declarative W3C spec and an engine implementation is **ink overflow calculation** (Visual Overflow in Blink). The engine must know the exact bounding box of all painted pixels to size backing textures, set up compositor culling rects, and determine invalidation regions without clipping the tail of the Gaussian curve.

The W3C spec notes:
> *"A blur radius of $B$ causes the shadow’s edge to be blurred over a band of width $2B$ centered on the shadow’s edge... going from full shadow color on the inside to fully transparent on the outside."*

However, a true mathematical Gaussian function $G(x) = \frac{1}{\sqrt{2\pi\sigma^2}} e^{-\frac{x^2}{2\sigma^2}}$ has infinite support—it never truly reaches zero. Hardware and software rasterizers (Skia) truncate the Gaussian kernel when the alpha contribution falls below the 8-bit quantization threshold ($\frac{1}{255}$).

```
Shadow Edge (after Offset + Spread)
        |
        |<--- Blur Extent (R_blur) --->|
--------+------------------------------+---------
████████|▓▓▓▓▓▓▓▓▒▒▒▒▒▒▒▒░░░░░░░░......|          (Alpha -> 0)
--------+------------------------------+---------
        0                             ceil(3 * sigma)
```

In Skia and Blink, the cutoff radius $R_{\text{blur}}$ of a Gaussian blur with standard deviation $\sigma$ is bounded by **3 standard deviations** ($3\sigma$), where $\approx 99.73\%$ of the energy resides and the kernel weight drops below the 8-bit alpha representation limit:

$$R_{\text{blur}}(B) = \lceil 3\sigma \rceil = \left\lceil 3 \times \left(\frac{B}{2}\right) \right\rceil = \lceil 1.5 \times B \rceil$$

*(Implemented in Blink via `ShadowBlur::BlurExtent` / `SkMaskFilter` bounds logic).*

#### Computing the Outset Supremum Across a `ShadowList`
When an element has multiple comma-separated shadows, Blink aggregates them in `ShadowList::AdjustRectForShadow`. Because `inset` shadows are clipped entirely to the inner padding-box of the element, they contribute $0$ to outer ink overflow and are skipped during outset calculations.

For a set of $K$ normal (outset) shadows $\{S_1, S_2, \dots, S_K\}$, where each shadow $i$ has parameters $(x_i, y_i, B_i, D_i)$ corresponding to $x$-offset, $y$-offset, blur radius, and spread distance, the **Shadow Outset Supremum** (represented as `gfx::OutsetsF` or `LayoutRectOutsets`) for each cardinal edge of the reference box is calculated as the component-wise maximum:

$$\text{Outset}_{\text{top}} = \max_{i \in \text{OutsetShadows}} \left( 0, \; -y_i + R_{\text{blur}}(B_i) + D_i \right)$$

$$\text{Outset}_{\text{right}} = \max_{i \in \text{OutsetShadows}} \left( 0, \; x_i + R_{\text{blur}}(B_i) + D_i \right)$$

$$\text{Outset}_{\text{bottom}} = \max_{i \in \text{OutsetShadows}} \left( 0, \; y_i + R_{\text{blur}}(B_i) + D_i \right)$$

$$\text{Outset}_{\text{left}} = \max_{i \in \text{OutsetShadows}} \left( 0, \; -x_i + R_{\text{blur}}(B_i) + D_i \right)$$

Where:
1.  **$0$ Baseline:** The $\max(0, \dots)$ clamping ensures that a shadow shifted entirely inside the element's reference box (e.g., via a large negative spread $D_i