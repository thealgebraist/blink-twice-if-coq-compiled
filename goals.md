# Project Goals: Full Coq Semantic Formalization of Chromium Blink (HTML/CSS)

## 1. Primary Mission & Overall Goal
The primary objective of this project is the **complete, bottom-up formalization of the Chromium Blink C++ layout and rendering codebase in Rocq/Coq**, covering the entire specification and implementation spectrum of HTML and CSS.

The ultimate end-state is an end-to-end verified, mathematically sound, and executable formal model that serves as a **certified drop-in replacement for Blink's layout and rendering engine**.

---

## 2. Core Architectural Pillars

### Pillar 1: Total Executability & Pixel-by-Pixel Blink Equivalence
The formalization must not remain abstract relational semantics; it must be **constructive, computational, and executable**:
1. **Computable Pipeline**: All layout, text shaping, cascade, and fragment assembly functions must be pure, constructive Gallina definitions (`Definition`, `Fixpoint`) executable via `Compute` and `vm_compute`.
2. **Pixel-by-Pixel Fidelity**: The model must produce raster framebuffers for HTML/CSS pages that are **pixel-by-pixel identical** to the visual output rendered by headless Chromium Blink.
3. **Subpixel Mathematics**: All dimensional calculations must faithfully implement Blink's 26.6 fixed-point arithmetic (`LayoutUnit`, `kFixedPointDenominator = 64`, $\epsilon = 0.015625\text{px}$), including:
   - Arithmetic right-shift division toward negative infinity.
   - Blink pixel snapping: $\text{snap}(x) = \lfloor (x + 32) / 64 \rfloor$.
   - Sibling box tiling without gaps: $\text{snap\_size}(w, x) = \text{snap}(x + w) - \text{snap}(x)$.
4. **Rasterization & Framebuffer**: The capstone pipeline must serialize rendered physical fragments into a 2D pixel grid (`FrameBuffer`: width, height, linear array of RGBA uint32 pixels) exportable directly to PNG/PPM images.

### Pillar 2: Low-Level Compilability (Assembly, LLVM IR, C99, C++23)
The Coq codebase must be structured for direct, unhindered compilation into high-performance low-level systems code:
1. **Compilable Architectures**: The formal model must be extractable into C99, C++23, LLVM IR, or native Assembly (via Coq Extraction, CompCert, or CertiCoq).
2. **Drop-in Engine Replacement**: It should be possible to compile the extracted LLVM IR or C99/C++23 code into a standalone binary or shared library (`libblink_formal.so`) that replaces Chromium's `core/layout/` and `core/paint/` entirely.
3. **Memory & Control Flow Alignment**: Data structures must map naturally to C structs, flat arrays, and bounded integers (`int64_t`, `int32_t`, `uint8_t`), avoiding non-constructive axioms or unbounded non-deterministic search.

### Pillar 3: Zero-Admit Rigor (Strict Formal Soundness)
1. **0 Admits Policy**: Absolutely no `admit`, `Admitted`, or unproven axioms in any theory file across the repository. Every lemma and theorem must be mechanically checked and fully closed with `Qed`.
2. **Clean Compilation**: Every theory module must compile cleanly with `coqc -Q . ""` without warnings or broken dependencies.
3. **Formal Invariant Verification**: Every subsystem must prove:
   - **Bounds Safety**: Coordinates, inline sizes, block sizes, and alpha blends remain bounded within their valid ranges ($[0, \text{container}]$, $[0, 255]$, etc.).
   - **Monotonicity**: Cursors, line heights, track collections, and row offsets strictly advance.
   - **Conservation Laws**: Space distribution satisfies $\sum \text{sizes} = \text{available\_space}$ (or bounds free space cleanly).
   - **Geometric Disjointness**: Sibling cells in table grids, list markers outside items, and adjacent flex lines do not illegally overlap.

---

## 3. Subsystem Roadmap & Scope

| Subsystem | Chromium Source Reference | W3C / WHATWG Specifications | Key Formal Focus |
|---|---|---|---|
| **Geometry & Math** | `core/layout/geometry/layout_unit.h` | CSS Values 3 §5.1 | 26.6 fixed-point, snapping, `BoxStrut`, `PhysicalRect` |
| **CSS Cascade & Units** | `core/css/style_cascade.cc` | CSS Cascading 4, Values 3 | Specificity, layer override (`inline > author > ua`), unit conversion (`px`, `em`, `rem`, `%`) |
| **Block & BFC** | `core/layout/block/` | CSS 2.1 §9.4.1, §8.3.1 | Margin collapse (`MarginStrut`), clearance, float exclusion, clamping |
| **Inline & Text** | `core/layout/inline/` | CSS Inline 3, Text 3, UAX #9 | Text runs, line box stacking, BiDi levels, hyphenation, font metrics |
| **Table Layout** | `core/layout/table/` | CSS 2.1 §17, CSS Table 3 | Auto/fixed sizing, $M \times N$ grid, `colspan`/`rowspan`, collapsed borders, incompressibility |
| **Flexbox** | `core/layout/flex/` | CSS Flexible Box 1 | Main/cross axes, multi-line wrapping, `align-content`, baseline alignment |
| **CSS Grid** | `core/layout/grid/` | CSS Grid 1 & 2 | Track growth, `fr` distribution, subgrid axis inheritance, 10,000 clamp |
| **Positioning & Transforms** | `core/layout/`, `platform/transforms/` | CSS Positioned 3, Transforms 1 | Inset resolution, relative shifts, sticky scroller, 2D affine matrix |
| **Paint & Stacking** | `core/paint/` | CSS 2.1 App. E, Backgrounds 3 | Stacking tree ($z$-index sort), border painting, background clip, alpha blend |
| **Fragment Tree & Pipeline** | `core/layout/box_fragment_builder.cc` | CSS Box Model 3, HTML Living Std | Physical fragment assembly, origin $(0, 0)$, capstone page models |

---

## 4. Instructions for LLM Agents Working on Formalization

When tasked with auditing or formalizing any Blink component:
1. **Always Read This Goals File**: Anchor every definition to the ultimate objective of executable, extractable, pixel-exact layout code.
2. **Prioritize Constructive Computation**: Write definitions as executable functions. If an algorithm computes a value in Blink C++, write the Gallina equivalent that actually evaluates it on concrete inputs.
3. **Prove Real Invariants**: Do not write trivial or tautological lemmas. Prove the exact mathematical and geometric guarantees the Blink C++ implementation relies on.
4. **Follow Zero Admits**: Never leave `admit` or `Admitted`. If a proof requires helper lemmas, write and prove them.
5. **Pixel Snapping Consistency**: Whenever spatial coordinates are mapped to output pixels, employ `LayoutUnit` fixed-point 64ths and `snap(x) = (x + 32) / 64`.

