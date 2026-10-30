**AUDIT REPORT: Blink Font Variation Axis Coordinate Clamping**
**Auditor:** Agent 346
**Target:** Chromium / Blink Rendering Engine (`third_party/blink/renderer/platform/fonts/`)
**Subject:** Variable Font Axis Coordinate Normalization and Clamping Pipeline

---

### 1. Executive Summary
In Blink, font variation axis coordinates defined via CSS (`font-variation-settings` or standard descriptors like `font-weight`, `font-width`, `font-style`) undergo a multi-stage validation and clamping pipeline before being committed to the underlying shaping (HarfBuzz) and rasterization (Skia/FreeType/CoreText/DirectWrite) engines. 

Axis coordinate clamping strictly follows the CSS Fonts Module Level 4 specification and the OpenType `fvar` (Font Variations) table constraints. Clamping does **not** occur during CSS parsing (except for syntax limits); rather, it is deferred until **font realization** when the actual font binary’s `fvar` table is accessible in memory.

---

### 2. The Clamping Pipeline

#### Phase 1: CSS Parsing & Cascade (Unclamped Storage)
* **Location:** `blink/renderer/core/css/properties/longhands/longhands_custom.cc` & `FontVariationSettings`
* **Mechanism:** When Blink parses `font-variation-settings: "wght" 1200, "custom" -500`, it validates only that the axis tag is a 4-character ASCII string (`0x20` to `0x7E`) and the value is a valid `<number>`.
* **Clamping Status:** **None.** Values are stored as raw `float` values inside `FontVariationSettings` (a `RefCounted` vector of `FontVariationAxis` objects). If duplicate tags exist, cascade/deduplication rules apply (last specified wins), and the array is sorted lexicographically by the 4-byte `uint32_t` tag to ensure deterministic cache keys for `FontDescription`.

#### Phase 2: Font Description & Registered vs. Custom Axes
* **Location:** `blink/renderer/platform/fonts/font_description.cc`
* **Mechanism:** Standard CSS properties (`font-weight`, `font-stretch`, `font-style`, `font-optical-sizing`) are mapped to their respective OpenType tags (`wght`, `wdth`, `slnt`/`ital`, `opsz`).
* **Clamping Status:** CSS-level range clamping applies here for standard properties (e.g., `font-weight` is clamped to `[1, 1000]` by the CSS parser). However, values in `font-variation-settings` bypass CSS property range limits and override standard properties during the shaping setup.

#### Phase 3: Font Instantiation & `fvar` Interrogation (The Clamping Boundary)
* **Location:** `blink/renderer/platform/fonts/FontCustomPlatformData.cc` and `FontPlatformData` initialization.
* **Mechanism:** Before creating the `SkTypeface` instance, Blink inspects the base typeface's `fvar` table via Skia (`SkTypeface::getVariationDesignPosition` and `SkTypeface::getVariationDesignParameters`).
* **Clamping Execution:**
  For every axis requested by the `FontDescription`:
  1. **Tag Resolution:** The requested 4-byte tag is matched against the axes array returned by `getVariationDesignParameters(SkFontParameters::Variation::Axis[], ...)`.
  2. **Unrecognized Tags:** If an axis tag specified in CSS does not exist in the font’s `fvar` table, the coordinate is silently dropped/ignored.
  3. **Range Enforcement:** If the tag matches an `fvar` axis, the user-supplied coordinate $V_{req}$ is clamped against the axis's `min` ($V_{min}$) and `max` ($V_{max}$) values defined in the font binary:
     $$V_{clamped} = \max(V_{min}, \min(V_{req}, V_{max}))$$
     In C++ (Blink/Skia boundary), this is executed via `std::clamp(requested_value, axis.min, axis.max)` (or `SkTPin`).

#### Phase 4: `avar` (Axis Variations) Non-Linear Normalization
* **Location:** Handled downstream by Skia / FreeType / HarfBuzz (`hb_font_set_variations`).
* **Mechanism:** Once clamped to the `[minValue, maxValue]` user-space coordinates, the coordinates are normalized to the standard OpenType variation space of `[-1.0, 1.0]` using the `defaultValue` ($V_{def}$):
  * If $V_{clamped} < V_{def}$: 
    $$V_{norm} = \frac{V_{clamped} - V_{def}}{V_{def} - V_{min}}$$
  * If $V_{clamped} > V_{def}$: 
    $$V_{norm} = \frac{V_{clamped} - V_{def}}{V_{max} - V_{def}}$$
  * If $V_{clamped} == V_{def}$: 
    $$V_{norm} = 0.0$$
* **Secondary Clamping:** If the font contains an `avar` table, $V_{norm}$ is mapped through the piecewise linear segment maps. The output of the `avar` mapping is strictly clamped to `[-1.0, 1.0]` in 2.14 fixed-point format (`F2Dot14`) to prevent malformed `avar` tables from causing out-of-bounds glyph interpolation (gvar/CFF2).

---

### 3. Edge Cases & Security Auditing Notes

1. **Inverted `fvar` Ranges ($V_{min} > V_{max}$):**
   * **Audit Finding:** Malformed fonts may declare `minValue > maxValue` in the `fvar` table. 
   * **Mitigation:** Calling `std::clamp(val, min, max)` when `min > max` triggers Undefined Behavior (UB) in C++ (`DCHECK` failure in debug builds). Blink/Skia guards against this during `fvar` parsing: if `axis.min > axis.max` or `axis.def < axis.min` or `axis.def > axis.max`, the axis is either sanitized (collapsed to `defaultValue`) or the `fvar` table is rejected entirely by OTS (OpenType Sanitizer) or Skia's font parser.

2. **`NaN` and `Infinity` Injection:**
   * **Audit Finding:** CSS `calc()` expressions (e.g., `font-variation-settings: "wght" calc(1 / 0)`) can theoretically produce `Infinity` or `NaN`.
   * **Mitigation:** CSS Values and Units Level 4 mandates clamping `Infinity` to the maximum/minimum representable `float` and resolving `NaN` to `0` at the CSS value computation stage before values ever reach `FontVariationSettings`.

3. **Fixed-Point Conversion Overflow (`16.16` Fixed Point):**
   * **Audit Finding:** OpenType `fvar` stores coordinates as `Fixed` (`16.16` signed fixed-point, range `[-32768.0, 32767.99998]`). CSS stores numbers as IEEE 754 `float` (or `double`).
   * **Mitigation:** Because clamping occurs *against* the float-converted `fvar` `min` and `max` values (which are inherently bounded by `16.16` limits), a CSS float like `1e30f` is safely clamped down to the `16.16` boundary *before* being cast back to fixed-point for FreeType/HarfBuzz consumption. This prevents integer overflow during float-to-fixed conversions (`SkFloatToFixed`).

4. **HarfBuzz vs. Skia Desynchronization:**
   * **Audit Finding:** If HarfBuzz shapes text using unclamped coordinates while Skia rasterizes using clamped coordinates, glyph advance widths will mismatch rendered outlines.
   * **Mitigation:** Blink instantiates the `SkTypeface` with the clamped `SkFontArguments::VariationPosition` *first*, and then extracts the variation coordinates directly from the realized `SkTypeface` (or passes the identical normalized `hb_variation_t` array) when configuring `hb_font_t` inside `HarfBuzzFace`. Both engines receive identical clamped coordinates.

---
**Audit Conclusion:** Blink's variation axis coordinate clamping is memory-safe, deterministic, and compliant with CSS Fonts L4 and OpenType 1.9 specifications. **Status: SECURE.**