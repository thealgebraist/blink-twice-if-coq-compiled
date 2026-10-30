// blink_sample_classes.h
// Authentic C++23 Blink Layout & Geometry Classes for Blink2Coq Synthesis
#pragma once

#include <cstdint>
#include <algorithm>

namespace blink {

// 1. LayoutUnit - Fixed-point saturated coordinate representation
struct LayoutUnit {
    int32_t value{0};

    static inline constexpr int32_t Clamp(int32_t v, int32_t lo, int32_t hi) noexcept {
        if (v < lo) return lo;
        if (v > hi) return hi;
        return v;
    }
};

// 2. MarginStrut - CSS 2.1 Block margin collapsing accumulator
struct MarginStrut {
    int32_t positive_margin{0};
    int32_t negative_margin{0}; // signed non-positive (<= 0)
    int32_t quirky_positive_margin{0};
    bool is_quirky_container_start{false};

    static inline constexpr void Append(MarginStrut& ms, int32_t val, bool is_quirk) noexcept {
        if (ms.is_quirky_container_start && is_quirk) return;
        if (val < 0) {
            ms.negative_margin = std::min(val, ms.negative_margin);
        } else {
            if (is_quirk) {
                ms.quirky_positive_margin = std::max(val, ms.quirky_positive_margin);
            } else {
                ms.positive_margin = std::max(val, ms.positive_margin);
            }
        }
    }
};

// 3. PhysicalRect - 2D layout geometry and bounding box union
struct PhysicalRect {
    int32_t x{0};
    int32_t y{0};
    int32_t width{0};
    int32_t height{0};

    static inline constexpr PhysicalRect Unite(PhysicalRect a, PhysicalRect b) noexcept {
        int32_t nx = std::min(a.x, b.x);
        int32_t ny = std::min(a.y, b.y);
        int32_t r1 = a.x + a.width;
        int32_t r2 = b.x + b.width;
        int32_t b1 = a.y + a.height;
        int32_t b2 = b.y + b.height;
        int32_t nr = std::max(r1, r2);
        int32_t nb = std::max(b1, b2);
        return PhysicalRect{nx, ny, nr - nx, nb - ny};
    }
};

// 4. ShadowData & Outsets - Visual overflow geometry
struct Outsets {
    int32_t top{0};
    int32_t right{0};
    int32_t bottom{0};
    int32_t left{0};

    static inline constexpr Outsets UnionOutsets(Outsets a, Outsets b) noexcept {
        return Outsets{
            std::max(a.top, b.top),
            std::max(a.right, b.right),
            std::max(a.bottom, b.bottom),
            std::max(a.left, b.left)
        };
    }
};

// 5. WritingModeConverter - Logical to physical coordinate bijection
struct WritingModeConverter {
    int32_t writing_mode{0}; // 0 = Horizontal-TB, 1 = Vertical-RL, 2 = Vertical-LR
    int32_t container_width{0};
    int32_t container_height{0};

    static inline constexpr int32_t LogicalToPhysicalX(int32_t lx, int32_t ly, int32_t wm, int32_t cw) noexcept {
        if (wm == 1) return cw - ly; // Vertical-RL
        return lx;                  // Horizontal-TB
    }

    static inline constexpr int32_t PhysicalToLogicalX(int32_t px, int32_t py, int32_t wm, int32_t cw) noexcept {
        if (wm == 1) return py;     // Vertical-RL inverse
        return px;                  // Horizontal-TB inverse
    }
};

// 6. FlexItem - CSS Flexbox main-axis sizing determination
struct FlexItem {
    int32_t flex_base_size{0};
    int32_t min_size{0};
    int32_t max_size{0};

    static inline constexpr int32_t ResolveMainSize(int32_t base, int32_t free_space, int32_t min_sz, int32_t max_sz) noexcept {
        int32_t target = base + free_space;
        if (target < min_sz) return min_sz;
        if (target > max_sz) return max_sz;
        return target;
    }
};

// 7. GridTrackSizing - CSS Grid minmax() track resolution
struct GridTrackSizing {
    int32_t min_track_size{0};
    int32_t max_track_size{0};

    static inline constexpr int32_t ResolveMinMax(int32_t avail, int32_t min_t, int32_t max_t) noexcept {
        int32_t effective_max = (max_t < min_t) ? min_t : max_t;
        if (avail < min_t) return min_t;
        if (avail > effective_max) return effective_max;
        return avail;
    }
};

// 8. TableBorders - CSS 2.1 Collapsed table border conflict resolution
struct TableBorders {
    int32_t border_style{0}; // 0 = None, 1 = Solid, 2 = Double, 3 = Hidden
    int32_t border_width{0};

    static inline constexpr int32_t ComputeBorderPriority(int32_t style, int32_t width) noexcept {
        if (style == 3) return 100000; // Hidden dominates all
        return width * 10 + style;
    }
};

} // namespace blink
