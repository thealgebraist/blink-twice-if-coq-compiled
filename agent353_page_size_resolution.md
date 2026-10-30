**Agent 353 Audit Report: Blink `@page` Size Resolution, Dimension Lookup, and Non-Negativity Enforcement**

### 1. Architecture Overview
In Chromium’s Blink rendering engine, `@page` size resolution is split across three primary phases:
1. **CSS Parsing & Grammar Validation** (`third_party/blink/renderer/core/css/properties/longhands/custom/size_custom.cc`)
2. **Style Calculation & Keyword Lookup** (`third_party/blink/renderer/core/css/resolver/style_builder_converter.cc`)
3. **Pagination Layout & Physical Clamping** (`third_party/blink/renderer/core/layout/ng/ng_page_layout_algorithm.cc` / `core/page/print_context.cc`)

---

### 2. Page Dimension Lookup Mechanism

#### A. Keyword Resolution (Named Page Sizes)
When `@page { size: <page-size> <orientation>; }` uses standard keywords (e.g., `A4`, `letter`, `JIS-B5`), Blink resolves them to physical dimensions during style building.

* **Lookup Location:** `StyleBuilderConverter::ConvertPageSize` (coupled with helpers in `core/css/page_size_functions.cc` or directly inside `style_builder_converter.cc` depending on the revision).
* **Unit Normalization:** Named sizes are defined either in **millimeters (mm)** (ISO/JIS standards) or **inches (in)** (North American standards). Blink converts these statically into CSS pixels (`1in = 96px`, `1mm = 96 / 25.4 px`) using `CSSPrimitiveValue::ComputeLength<float>()` or pre-multiplied constants (`kCssPixelsPerInch`, `kCssPixelsPerMillimeter`).
* **Standard Lookup Table:**
  * `A5`: 148mm × 210mm
  * `A4`: 210mm × 297mm
  * `A3`: 297mm × 420mm
  * `B5`: 176mm × 250mm
  * `B4`: 250mm × 353mm
  * `JIS-B5`: 182mm × 257mm
  * `JIS-B4`: 257mm × 364mm
  * `letter`: 8.5in × 11in
  * `legal`: 8.5in × 14in
  * `ledger`: 11in × 17in

#### B. Orientation Application
Named keywords inherently describe a portrait box (`width < height`). Orientation keywords modify the resolved `gfx::SizeF`:
* **`portrait`**: Ensures `width = std::min(w, h)` and `height = std::max(w, h)`.
* **`landscape`**: Swaps dimensions so `width = std::max(w, h)` and `height = std::min(w, h)`.
* **Omitted orientation with keyword**: Defaults to `portrait`.

#### C. Explicit Length Resolution
When `@page { size: <length>{1,2}; }` is specified:
* **1 Value (`size: 10cm`)**: Both width and height resolve to `10cm`.
* **2 Values (`size: 8.5in 11in`)**: The first value resolves to `width`, the second to `height`.
* **Computation**: Handled via `CSSToLengthConversionData`. Relative font units (`em`, `rem`) resolve against the root element's (`:root`) computed font size (or initial font size if no root exists). Viewport units (`vw`, `vh`) are invalid or resolve against the initial print viewport size provided by `WebPrintParams`.
* **Storage**: Stored on `ComputedStyle` (specifically `StyleInitialData` or `ComputedStyleExtraFields`) as a `PageSizeType` enum (`kAuto`, `kPortrait`, `kLandscape`, `kFixed`) alongside a `gfx::SizeF` representing `PageSize()`.

---

### 3. Non-Negativity Enforcement

Blink enforces non-negativity for `@page` dimensions across **three distinct boundary layers** to handle literal negative numbers, mathematical expressions (`calc()`), and margin-box underflows.

#### Layer 1: Parse-Time Enforcement (Literal Lengths)
* **Component**: `css_parsing_utils::ConsumeLength` (invoked by `Size::ParseSingleValue`).
* **Mechanism**: The parser calls `ConsumeLength(range, context, CSSPrimitiveValue::ValueRange::kNonNegative)`.
* **Effect**: Literal negative lengths (e.g., `size: -5in 10in` or `size: -100px`) are immediately rejected as syntax errors during tokenization/parsing. The declaration is dropped.

#### Layer 2: Computed-Value Clamping (`calc()` Expressions)
* **Component**: `CSSMathExpressionNode` / `CSSMathFunctionValue` and `CSSToLengthConversionData`.
* **Vulnerability**: According to CSS Values and Units specs, `calc(10px - 50px)` is syntactically valid at parse time even when the target property requires `kNonNegative`, because unit resolution (e.g., `calc(1in - 10em)`) cannot always occur until style computation.
* **Mechanism**: During `StyleBuilderConverter::ConvertPageSize`:
  1. `CSSPrimitiveValue::ComputeLength<float>(conversion_data)` evaluates the math expression.
  2. Because the `CSSMathFunctionValue` was constructed with `CSSPrimitiveValue::ValueRange::kNonNegative`, `CSSPrimitiveValue::ClampToCSSLengthRange` (or internal `ClampTo<float>(value, 0.0)`) is triggered upon evaluation.
* **Effect**: Negative `calc()` evaluations are clamped to `0.0f` at Computed Style generation time.

#### Layer 3: Layout / Page Area Underflow Guarding (Zero-Size & Margin Collapse)
Even with non-negative `size` values (`>= 0`), a page's *content box* can become zero or negative through `@page` margins (e.g., `size: 0px` or `size: 4in; margin: 3in;`).
* **Component**: `LayoutView::PageAreaSize()`, `PrintContext`, and `NGPageLayoutAlgorithm` (LayoutNG Printing).
* **Mechanism**:
  1. **Zero Page Size Fallback**: If the specified page size is `0` in either dimension, or if `width` or `height` becomes `<= 0` after subtracting `@page` margins, Blink must prevent divide-by-zero errors during pagination fragmentation (otherwise an infinite number of 0-height pages would be generated).
  2. **Clamping**: In LayoutNG (`ng_page_layout_algorithm.cc` / `page_container_layout_algorithm.cc`), the page content area size is clamped via `std::max(LayoutUnit(1), page_area_size)` or falls back to the default printer paper size provided by the embedder (`WebPrintParams::default_page_description`) if the total page box itself is invalid/degenerate.
  3. **`gfx::SizeF` Representation**: `gfx::SizeF` internally asserts non-negativity in `set_width()` and `set_height()` via `base::ClampToRange` / `DCHECK_GE(width, 0)` in `ui/gfx/geometry/size_f.h`, acting as a low-level C++ memory/logic guard against negative float propagation.

---

### 4. Summary Checklist for Audit Verification

| Vector | Input Example | Enforcement Point | Result |
| :--- | :--- | :--- | :--- |
| **Negative Literal** | `size: -200px 300px` | `Size::ParseSingleValue` (`ValueRange::kNonNegative`) | Parse Error (Dropped) |
| **Negative `calc()`** | `size: calc(10px - 50px)` | `CSSMathFunctionValue::ComputeLengthPx` | Clamped to `0px` |
| **Zero-Size Page** | `size: 0px 0px` | `PrintContext` / `PageLayoutAlgorithm` | Clamped to `>= 1px` / Fallback to Printer Default |
| **Negative Content Box** | `size: 100px; margin: 60px;` | `PageLayoutAlgorithm` | Content box clamped to minimal positive `LayoutUnit` |
| **Invalid Keyword** | `size: A99` | `Size::ParseSingleValue` | Parse Error (Dropped) |
| **Keyword + Length** | `size: A4 100px` | `Size::ParseSingleValue` | Parse Error (Dropped) |