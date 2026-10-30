# Blink Formal Semantics Roadmap: Comprehensive W3C CSS / Blink LayoutNG Mapping

This document tracks the structured expansion of the Coq/Rocq formal semantics for Chromium Blink (`third_party/blink`) to achieve a complete, sound mathematical description directly comparable to the official W3C CSS specification documents.

---

## 1. Specification Coverage Matrix

| W3C CSS Specification Document | Blink Implementation Module | Formal Coq Module | Status | Verified Metatheory |
| :--- | :--- | :--- | :--- | :--- |
| **CSS 2.1 Section 8.3.1 (Collapsing Margins)** | `layout/margin_strut.h / .cc` | [`BlinkMarginStrut.v`](file:///Users/anders/projects/testapi/BlinkMarginStrut.v) | **100% Complete** | Invariant preservation, Monoid idempotence, CSS 2.1 identity theorem |
| **CSS 2.1 Section 9.7 & 10.3 (Width/Height Clamping)** | `layout/length_utils.cc` | [`BlinkSemanticSpecPrototype.v`](file:///Users/anders/projects/testapi/BlinkSemanticSpecPrototype.v), [`BlinkLeafFunctions.v`](file:///Users/anders/projects/testapi/BlinkLeafFunctions.v) | **100% Complete** | Fixed-point saturating clamping, Min-overrides-max precedence |
| **CSS Sizing 3 / 4 (Aspect Ratio & Intrinsic Size)** | `layout/length_utils.cc` | [`BlinkLeafFunctions.v`](file:///Users/anders/projects/testapi/BlinkLeafFunctions.v) | **100% Complete** | Square & ContentBox/BorderBox aspect ratio scaling |
| **CSS Backgrounds and Borders 3 Section 7.2 (Box Shadow)** | `style/shadow_data.h`, `style/shadow_list.cc` | [`BlinkShadowAndOverflow.v`](file:///Users/anders/projects/testapi/BlinkShadowAndOverflow.v) | **100% Complete** | Non-additive bounding box union, Inset zero-expansion, Monoid join |
| **CSS CSSOM View / Scrolling (Scroll Exposure)** | `scroll/scroll_alignment.cc` | [`BlinkScrollAndGrid.v`](file:///Users/anders/projects/testapi/BlinkScrollAndGrid.v) | **100% Complete** | 1D interval exposure, Center alignment, Boundary clamping |
| **CSS Grid Layout 1 Section 11 (Track Space Distribution)** | `layout/grid/grid_track_collection.cc` | [`BlinkScrollAndGrid.v`](file:///Users/anders/projects/testapi/BlinkScrollAndGrid.v) | **100% Complete** | Space conservation, Non-starvation, Single track absorption |
| **CSS Flexible Box Layout 1 (Flexible Length Resolution)** | `layout/flex/flex_layout_algorithm.cc` | [`BlinkFlexboxSpecialization.v`](file:///Users/anders/projects/testapi/BlinkFlexboxSpecialization.v) | **100% Complete** | Multi-item flex-grow, container space distribution, 5-stage specialization |
| **CSS 2.1 Section 9 & 10 (Block Formatting Context Tree)** | `layout/block_layout_algorithm.cc` | [`BlinkFullRendererSemantics.v`](file:///Users/anders/projects/testapi/BlinkFullRendererSemantics.v) | **100% Complete** | ConstraintSpace propagation, Child sequencing, Determinism |
| **CSS Flexible Box Layout 1 Section 9 (Flex Container Formatting)** | `layout/flex/flex_layout_algorithm.cc` | [`BlinkFlexboxContainerSemantics.v`](file:///Users/anders/projects/testapi/BlinkFlexboxContainerSemantics.v) | **Next Target** | Multi-item flex line packing, cross-size alignment |
| **CSS 2.1 Section 9.3 (Positioned Layout: Absolute & Fixed)** | `layout/out_of_flow_layout_part.cc` | `BlinkOutOfFlowSemantics.v` | Planned | Static position resolution, containing block inset resolution |
| **CSS Inline Layout 3 (Inline Formatting Context / Line Breaking)** | `layout/inline/inline_layout_algorithm.cc` | `BlinkInlineLayoutSemantics.v` | Planned | Text shape itemization, line box breaking |

---

## 2. Next Milestones

1. **Flex Formatting Context in Tree Big-Step Semantics**:
   - Extend `layout_big_step` to handle `bs_display style = DisplayFlex`.
   - Incorporate multi-item flex line distribution (`ResolveFlexibleLengths`) directly into the child fragment tree constructor.
   - Prove confluence/determinism for both Block and Flex containers.
2. **Out-of-Flow Positioning (CSS Absolute/Fixed)**:
   - Separate normal-flow fragments from out-of-flow candidates.
   - Resolve top/left/bottom/right insets against the containing block.
3. **Formal Comparison Harness against W3C Specification Text**:
   - Create documentation and verification lemmas showing theorem-by-theorem concordance between W3C normative sections and Coq theorems.
