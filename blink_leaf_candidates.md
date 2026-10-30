Here are 6 high-impact leaf and near-leaf functions in Chromium’s Blink engine that sit directly on the critical path of style resolution, layout, and paint. Each operates on self-contained geometric or value types (`LayoutUnit`, `Length`, `PhysicalRect`, `gfx::SizeF`), exhibits subtle fixed-point/floating-point edge cases, and suffers from branch heavy dispatch in hot loops that can be eliminated through formally verified parameter specialization.

---

### 1. Length Valuation & Fixed-Point Conversion
* **File Path:** `third_party/blink/renderer/platform/geometry/length_functions.cc` (and `.h`)
* **C++ Signature:**
  ```cpp
  LayoutUnit MinimumValueForLength(const Length& length, LayoutUnit maximum_value);
  ```
* **Algorithmic Logic & Edge Cases:**
  Evaluates a CSS `Length` (`Fixed`, `Percent`, `Calculated`, `Auto`, `MinContent`, `FillAvailable`, etc.) against a container's `maximum_value` to produce a 26.6 fixed-point `LayoutUnit`.
  * **Sentinels:** If `maximum_value` is `kIndefiniteSize` (`-1`), percentage and `FillAvailable` lengths must resolve to `0` rather than negative fractions.
  * **Mixed-Mode Arithmetic:** `Fixed` converts `float` to `LayoutUnit` via saturated rounding. `Percent` promotes `maximum_value` to `float`, multiplies by `length.Percent() / 100.0f`, and converts back to `LayoutUnit`, inviting IEEE-754 precision loss, NaN/Inf propagation, and fixed-point clamping at `LayoutUnit::Max()` / `Min()`.
* **Formalization & Specialization Potential:**
  Called millions of times per frame during box model resolution (padding, margins, insets). The `switch (length.GetType())` and indefinite-size sentinel checks create severe branch mispredictions.
  * **Specialization Regimes:** By partially evaluating on static CSS properties (e.g., when a style regime proves `length.IsFixed()` or `length.IsPercent()` and `maximum_value >= 0`), the function collapses from a multi-branch switch and function-pointer dispatch (`CalculationValue`) into a single inline saturated fixed-point load or multiplication. Coq proofs can verify that the specialized fast-path preserves exact rounding and saturation behavior at the 26.6 boundaries.

---

### 2. Aspect-Ratio Dependent Size Resolution
* **File Path:** `third_party/blink/renderer/core/layout/length_utils.cc` (and `.h`)
* **C++ Signature:**
  ```cpp
  LayoutUnit InlineSizeFromAspectRatio(const BoxStrut& border_padding,
                                       const LogicalSize& aspect_ratio,
                                       EBoxSizing box_sizing,
                                       LayoutUnit block_size);
  ```
* **Algorithmic Logic & Edge Cases:**
  Computes the inline size of an element from its block size and aspect ratio, adjusting for `box-sizing: border-box` vs. `content-box`.
  * **Overflow & 64-bit Intermediate Scaling:** Computes `block_size * aspect_ratio.inline_size / aspect_ratio.block_size` using `LayoutUnit::MulDiv`. Because 26.6 fixed-point multiplication overflows 32-bit integers immediately, it promotes to `int64_t`, rounds to nearest, and saturates back to 32-bit `LayoutUnit`.
  * **Clamping & Degeneracy:** When `box_sizing == EBoxSizing::kBorderBox`, it subtracts `border_padding.BlockSum()` prior to scaling, and adds `border_padding.InlineSum()` afterward, requiring explicit `std::max(LayoutUnit(), ...)` guards to prevent negative intermediate dimensions from inverting the aspect ratio.
* **Formalization & Specialization Potential:**
  Aspect ratio calculations sit inside the hot Flex, Grid, and Block sizing loops.
  * **Specialization Regimes:** Specializing on `box_sizing` (`kContentBox` vs `kBorderBox`) and zero `border_padding` (common for replaced elements like `<img>` and `<video>`) eliminates all pre- and post-addition clamping branches. Formal verification is uniquely valuable here to prove the absence of intermediate `int64_t` overflow and to verify monotonicity of `MulDiv` across `LayoutUnit::Max()` saturation limits.

---

### 3. Replaced Element Natural/Intrinsic Size Negotiation (CSS 2.1 §10.3.2 / §10.6.2)
* **File Path:** `third_party/blink/renderer/core/layout/geometry/logical_size.cc` (or helper in `third_party/blink/renderer/core/layout/length_utils.cc`)
* **C++ Signature:**
  ```cpp
  LogicalSize ComputeReplacedSize(const std::optional<LogicalSize>& natural_size,
                                  const LogicalSize& aspect_ratio,
                                  const LogicalSize& default_object_size,
                                  const std::optional<LayoutUnit>& resolved_inline,
                                  const std::optional<LayoutUnit>& resolved_block);
  ```
  *(Note: In recent Blink trees, this pure mathematical core is factored into `ApplyAspectRatio` / `ComputeReplacedSize` over optional `LayoutUnit`s and `gfx::SizeF`).*
* **Algorithmic Logic & Edge Cases:**
  Implements the CSS constraint negotiation matrix for replaced elements: combining optional definite inline/block sizes, optional intrinsic sizes, and optional aspect ratios.
  * **Branch Prioritization:** 2x2x2 state space of `std::optional` presence, crossed with whether `aspect_ratio.IsEmpty()` is true.
  * **Precision & Sentinels:** Must gracefully handle degenerate aspect ratios (e.g., `0/x` or `x/0`), missing natural sizes in SVG images, and exact precedence between intrinsic dimensions vs. fallback `default_object_size` (typically 300x150px).
* **Formalization & Specialization Potential:**
  This function is a textbook decision tree over option monads and fixed-point arithmetic.
  * **Specialization Regimes:** In layout engines, the caller almost always statically knows which dimensions are constrained (e.g., `resolved_inline` is `Some`, `resolved_block` is `None` during block layout). Partial evaluation over the `std::optional` tags eliminates the entire constraint-resolution state machine, reducing the function to a single call to `BlockSizeFromAspectRatio`.

---

### 4. Scroll Into View Alignment & Clamping Geometry
* **File Path:** `third_party/blink/renderer/core/scroll/scroll_alignment.cc`
* **C++ Signature:**
  ```cpp
  PhysicalOffset ScrollAlignment::GetScrollOffsetToExpose(
      const PhysicalRect& scroll_snap_port_rect,
      const PhysicalRect& target_rect,
      const ScrollAlignment& align_x,
      const ScrollAlignment& align_y,
      const PhysicalOffset& current_scroll_offset,
      const PhysicalRect& scrollable_area_bounds);
  ```
* **Algorithmic Logic & Edge Cases:**
  A pure geometric solver that determines the exact 2D `PhysicalOffset` needed to bring `target_rect` into view within `scroll_snap_port_rect`, governed by alignment policies (`kAlignCenterAlways`, `kAlignTopAlways`, `kAlignToEdgeIfNeeded`, etc.) and whether `target_rect` is fully, partially, or not visible.
  * **Corner Cases:** When `target_rect` is larger than `scroll_snap_port_rect`, the "if needed" policies invert their edge preference compared to when `target_rect` is smaller.
  * **Saturating Arithmetic:** Computes intersections and midpoint deltas (`(port - target) / 2`) in 26.6 `LayoutUnit` space, followed by clamping against `scrollable_area_bounds`.
* **Formalization & Specialization Potential:**
  Executed repeatedly during programmatic scrolling, focus navigation, and anchor positioning.
  * **Specialization Regimes:** The `ScrollAlignment` structs contain 3-state conditions (`rect_visible`, `rect_hidden`, `rect_partial`) for each axis. By specializing on the two dominant web defaults (`scroll-Into-View: {block: 'nearest', inline: 'nearest'}` and `{block: 'center', inline: 'center'}`), the 2D policy dispatch collapses into branchless min/max interval clamping. Formal methods can prove idempotence (calling it twice yields the exact same offset) and containment invariants.

---

### 5. Box-Shadow & Outline Outset Expansion
* **File Path:** `third_party/blink/renderer/core/style/shadow_list.cc`
* **C++ Signature:**
  ```cpp
  gfx::OutsetsF ShadowList::RectOutsetsIncludingOriginal() const;
  ```
  *(Specifically its inner pure loop helper operating on `ShadowData`: `gfx::OutsetsF ComputeShadowOutset(const gfx::Vector2dF& location, float blur, float spread, ShadowStyle style)`)*
* **Algorithmic Logic & Edge Cases:**
  Computes the bounding-box expansion (`top`, `right`, `bottom`, `left` outsets) required to encompass a drop shadow or box shadow, used during visual overflow and paint invalidation rect calculation.
  * **Algorithmic Nuance:** Skips `ShadowStyle::kInset`. Converts `blur` radius to standard deviation and multiplies by the Skia mask filter footprint constant, adds `spread`, offsets by `location.x()` / `.y()`, and unions with the original box (`std::max(0.0f, ...)`).
  * **Float to LayoutUnit Hazard:** Downstream callers immediately convert this `gfx::OutsetsF` to `LayoutUnit` via `EnclosingLayoutRect`, where negative spreads or IEEE-754 `-0.0f` and denormals can trigger off-by-one pixel invalidation bugs.
* **Formalization & Specialization Potential:**
  Called on every visual overflow recalculation during style/layout updates.
  * **Specialization Regimes:** Most CSS `box-shadow` declarations use `style == kNormal`, `spread == 0.0f`, and positive `blur`. Specializing for single-shadow lists with `spread == 0` eliminates the loop, inset branches, and negative-spread clamping. Formalizing the IEEE-754 float-to-`LayoutUnit` ceiling conversion proves conservative bounding (the computed outset strictly covers the rasterized Skia blur footprint).

---

### 6. CSS Grid Track Sizing: Distributing Extra Space Across Spanned Tracks
* **File Path:** `third_party/blink/renderer/core/layout/grid/grid_track_collection.cc` (or `grid_layout_algorithm.cc` helper)
* **C++ Signature:**
  ```cpp
  LayoutUnit DistributeExtraSpaceToTrack(LayoutUnit extra_space,
                                         LayoutUnit track_base_size,
                                         LayoutUnit track_growth_limit,
                                         float flex_factor,
                                         uint32_t unmaximized_tracks_count,
                                         bool is_beyond_growth_limit);
  ```
  *(Pure core of the CSS Grid §12.5 "Distribute Extra Space" inner loop over `GridSet`s).*
* **Algorithmic Logic & Edge Cases:**
  Calculates the exact `LayoutUnit` share of leftover grid container space to allocate to a specific track during intrinsic track sizing.
  * **Sentinels:** `track_growth_limit` uses `kIndefiniteSize` (`-1`) to represent an `infinity` growth limit (e.g., `minmax(100px, max-content)` before maximization).
  * **Division & Remainder Starvation:** Divides `extra_space` by `unmaximized_tracks_count` (or scales by `flex_factor`) in 26.6 fixed-point space, clamps the delta against `track_growth_limit - track_base_size` (unless `track_growth_limit == kIndefiniteSize` or `is_beyond_growth_limit` is true), and ensures monotonic progress without exceeding `extra_space`.
* **Formalization & Specialization Potential:**
  The inner loop of Grid track sizing is one of the hottest algorithms in modern Blink layout.
  * **Specialization Regimes:** Specializing on `is_beyond_growth_limit == false` and finite vs. infinite `track_growth_limit` (which is known per-pass in the Grid algorithm) removes all sentinel checks (`track_growth_limit == kIndefiniteSize`) from the inner loop. Furthermore, Coq verification can prove conservation of space ($\sum \Delta \text{track}_i \le \text{extra\_space}$) and termination under fixed-point truncation.