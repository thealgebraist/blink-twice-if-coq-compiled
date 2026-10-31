// blink_16_classes.h
// Authentic Chromium Blink Layout & Rendering Classes for HM Hybrid Synthesis
#pragma once

#include <cstdint>
#include <algorithm>

namespace blink {

// 1. NGBoxStrut - Strut metrics for 4-directional margins, borders, and paddings
struct NGBoxStrut {
    int32_t inline_start{0};
    int32_t inline_end{0};
    int32_t block_start{0};
    int32_t block_end{0};

    // Invariant: Non-negative struts in physical layout
    // DCHECK(inline_start >= 0 && inline_end >= 0 && block_start >= 0 && block_end >= 0)
    static inline constexpr int32_t InlineSum(int32_t is, int32_t ie) noexcept {
        return is + ie;
    }
    static inline constexpr int32_t BlockSum(int32_t bs, int32_t be) noexcept {
        return bs + be;
    }
};

// 2. NGConstraintSpace - Sizing constraints passed from parent to child layout algorithm
struct NGConstraintSpace {
    int32_t available_inline_size{0};
    int32_t available_block_size{0};
    int32_t percentage_inline_size{0};
    int32_t percentage_block_size{0};

    // DCHECK(available_inline_size >= 0 && percentage_inline_size >= 0)
    static inline constexpr int32_t ResolvePercentage(int32_t pct_base, int32_t percentage) noexcept {
        if (percentage <= 0) return 0;
        return (pct_base * percentage) / 100;
    }
};

// 3. Length - CSS Length value representation with auto/fixed/percent resolution
struct Length {
    int32_t value{0};
    int32_t type{0}; // 0 = Auto, 1 = Fixed, 2 = Percent

    // DCHECK(type >= 0 && type <= 2)
    static inline constexpr int32_t ResolveLength(int32_t val, int32_t type, int32_t max_extent) noexcept {
        if (type == 1) return val;
        if (type == 2) {
            if (val <= 0) return 0;
            return (max_extent * val) / 100;
        }
        return max_extent;
    }
};

// 4. ScrollOffset - 2D scroll positioning with container boundary clamping
struct ScrollOffset {
    int32_t x{0};
    int32_t y{0};

    // DCHECK(max_x >= 0 && max_y >= 0)
    static inline constexpr int32_t ClampScrollX(int32_t x, int32_t max_x) noexcept {
        if (x < 0) return 0;
        if (x > max_x) return max_x;
        return x;
    }
    static inline constexpr int32_t ClampScrollY(int32_t y, int32_t max_y) noexcept {
        if (y < 0) return 0;
        if (y > max_y) return max_y;
        return y;
    }
};

// 5. FontMetrics - Font vertical ascent, descent, and line gap metrics
struct FontMetrics {
    int32_t ascent{0};
    int32_t descent{0};
    int32_t line_gap{0};

    // DCHECK(ascent >= 0 && descent >= 0 && line_gap >= 0)
    static inline constexpr int32_t ComputeLineHeight(int32_t a, int32_t d, int32_t g) noexcept {
        return a + d + g;
    }
    static inline constexpr int32_t ComputeHalfLeading(int32_t line_height, int32_t font_height) noexcept {
        if (line_height <= font_height) return 0;
        return (line_height - font_height) / 2;
    }
};

// 6. MinMaxSizes - Intrinsic min-content and max-content sizing bounds
struct MinMaxSizes {
    int32_t min_size{0};
    int32_t max_size{0};

    // DCHECK(min_size <= max_size)
    static inline constexpr int32_t ClampSize(int32_t sz, int32_t min_s, int32_t max_s) noexcept {
        if (sz < min_s) return min_s;
        if (sz > max_s) return max_s;
        return sz;
    }
    static inline constexpr int32_t EncompassMin(int32_t cur_min, int32_t child_min) noexcept {
        return std::min(cur_min, child_min);
    }
    static inline constexpr int32_t EncompassMax(int32_t cur_max, int32_t child_max) noexcept {
        return std::max(cur_max, child_max);
    }
};

// 7. LineBoxStrut - Vertical inline box ascent/descent strut union
struct LineBoxStrut {
    int32_t ascent{0};
    int32_t descent{0};

    // DCHECK(ascent >= 0 && descent >= 0)
    static inline constexpr int32_t UnionAscent(int32_t a1, int32_t a2) noexcept {
        return std::max(a1, a2);
    }
    static inline constexpr int32_t UnionDescent(int32_t d1, int32_t d2) noexcept {
        return std::max(d1, d2);
    }
};

// 8. PhysicalOffset - 2D layout vector displacement and coordinate translation
struct PhysicalOffset {
    int32_t left{0};
    int32_t top{0};

    static inline constexpr int32_t TranslateX(int32_t x1, int32_t x2) noexcept {
        return x1 + x2;
    }
    static inline constexpr int32_t TranslateY(int32_t y1, int32_t y2) noexcept {
        return y1 + y2;
    }
    static inline constexpr int32_t SubtractX(int32_t x1, int32_t x2) noexcept {
        return x1 - x2;
    }
};

// 9. PhysicalSize - 2D box width and height geometry
struct PhysicalSize {
    int32_t width{0};
    int32_t height{0};

    // DCHECK(width >= 0 && height >= 0)
    static inline constexpr bool IsEmpty(int32_t w, int32_t h) noexcept {
        return (w <= 0) || (h <= 0);
    }
    static inline constexpr int32_t ScaleDimension(int32_t dim, int32_t num, int32_t den) noexcept {
        if (den <= 0) return 0;
        return (dim * num) / den;
    }
};

// 10. NGInlineItem - Atomic text segment offsets within an inline formatting context
struct NGInlineItem {
    int32_t start_offset{0};
    int32_t end_offset{0};
    int32_t item_type{0}; // 0 = Text, 1 = Control, 2 = AtomicInline

    // DCHECK(start_offset <= end_offset)
    static inline constexpr int32_t ItemLength(int32_t start, int32_t end) noexcept {
        return end - start;
    }
    static inline constexpr bool IsEmptyRange(int32_t start, int32_t end) noexcept {
        return start == end;
    }
};

// 11. BaselineOffset - Inline alignment relative to line box baseline
struct BaselineOffset {
    int32_t font_ascent{0};
    int32_t box_ascent{0};

    // DCHECK(line_h >= box_h)
    static inline constexpr int32_t AlignVertical(int32_t mode, int32_t box_h, int32_t line_h, int32_t baseline) noexcept {
        if (mode == 0) return baseline; // baseline
        if (mode == 1) return (line_h - box_h) / 2; // middle
        if (mode == 2) return line_h - box_h; // bottom
        return 0; // top
    }
};

// 12. GridSpan - 1D Grid track index range
struct GridSpan {
    int32_t start_line{0};
    int32_t end_line{0};

    // DCHECK(start_line <= end_line)
    static inline constexpr int32_t SpanSize(int32_t s, int32_t e) noexcept {
        return e - s;
    }
    static inline constexpr int32_t ShiftSpan(int32_t line, int32_t offset) noexcept {
        return line + offset;
    }
};

// 13. FlexItem - CSS Flexbox proportional grow and shrink space distribution
struct FlexItem {
    int32_t flex_base_size{0};
    int32_t flex_grow{0};
    int32_t min_size{0};
    int32_t max_size{0};

    // DCHECK(min_size <= max_size && flex_grow >= 0 && total_grow > 0 && free_space >= 0)
    static inline constexpr int32_t DistributeGrow(int32_t base, int32_t free_space, int32_t grow, int32_t total_grow) noexcept {
        if (total_grow <= 0) return base;
        return base + (free_space * grow) / total_grow;
    }
};

// 14. Color - 32-bit RGBA channel blending and opacity compositing
struct Color {
    int32_t r{0};
    int32_t g{0};
    int32_t b{0};
    int32_t a{0};

    // DCHECK(src >= 0 && src <= 255 && dst >= 0 && dst <= 255 && alpha >= 0 && alpha <= 255)
    static inline constexpr int32_t AlphaBlend(int32_t src, int32_t dst, int32_t alpha) noexcept {
        return (src * alpha + dst * (255 - alpha)) / 255;
    }
};

// 15. BorderEdge - Border side width resolution and presence dominance
struct BorderEdge {
    int32_t width{0};
    int32_t style{0}; // 0 = None, 1 = Solid, 2 = Hidden
    bool is_present{false};

    // DCHECK(width >= 0)
    static inline constexpr int32_t ResolveEdgeWidth(int32_t w, int32_t style, bool present) noexcept {
        if (!present) return 0;
        if (style == 0) return 0; // None
        if (style == 2) return 0; // Hidden
        return w;
    }
};

// 16. TextRun - Inline text advance width and discrete space accumulation
struct TextRun {
    int32_t advance{0};
    int32_t num_spaces{0};

    // DCHECK(advance >= 0 && num_spaces >= 0 && space_width >= 0)
    static inline constexpr int32_t ExpandJustifiedRun(int32_t adv, int32_t spaces, int32_t extra_per_space) noexcept {
        return adv + spaces * extra_per_space;
    }
};

} // namespace blink
