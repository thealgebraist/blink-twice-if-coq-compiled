// blink_shadow_fastpaths.h
// Verified C++23 Fast-Paths for Blink Visual Overflow & Shadow Outset Computation
#pragma once

#include <cstdint>
#include <algorithm>
#include <climits>

namespace blink_shadow {

struct Outsets {
    int32_t top{0};
    int32_t right{0};
    int32_t bottom{0};
    int32_t left{0};
};

struct ShadowData {
    int32_t style; // 0 = Normal/Outset, 1 = Inset
    int32_t spread;
    int32_t blur;
    int32_t offset_x;
    int32_t offset_y;
};

// Exact Saturating Add
inline constexpr int32_t sat_add(int32_t a, int32_t b) noexcept {
    int64_t res = static_cast<int64_t>(a) + b;
    if (res > INT32_MAX) return INT32_MAX;
    if (res < INT32_MIN) return INT32_MIN;
    return static_cast<int32_t>(res);
}

// Exact Saturating Sub
inline constexpr int32_t sat_sub(int32_t a, int32_t b) noexcept {
    int64_t res = static_cast<int64_t>(a) - b;
    if (res > INT32_MAX) return INT32_MAX;
    if (res < INT32_MIN) return INT32_MIN;
    return static_cast<int32_t>(res);
}

// General Shadow Outset Routine (matching Blink logic)
inline constexpr Outsets ComputeShadowOutsets_General(const ShadowData& shadow) noexcept {
    if (shadow.style == 1) { // Inset
        return Outsets{0, 0, 0, 0};
    }
    int32_t extent = sat_add(shadow.spread, shadow.blur);
    int32_t top = std::max(0, sat_sub(extent, shadow.offset_y));
    int32_t right = std::max(0, sat_add(extent, shadow.offset_x));
    int32_t bottom = std::max(0, sat_add(extent, shadow.offset_y));
    int32_t left = std::max(0, sat_sub(extent, shadow.offset_x));
    return Outsets{top, right, bottom, left};
}

// Formally Verified C++23 Fast-Path: Inset Shadow (Specialization 1)
// Proved in Coq: shadow_inset_zero_expansion
template<ShadowData shadow>
    requires (shadow.style == 1)
inline constexpr Outsets ComputeShadowOutsets_Specialized() noexcept {
    return Outsets{0, 0, 0, 0};
}

// Formally Verified C++23 Fast-Path: Symmetric Zero-Offset Outset Shadow (Specialization 2)
// Proved in Coq: shadow_zero_offset_symmetric
template<ShadowData shadow>
    requires (shadow.style == 0 && shadow.offset_x == 0 && shadow.offset_y == 0 &&
              shadow.spread >= 0 && shadow.blur >= 0 &&
              static_cast<int64_t>(shadow.spread) + shadow.blur <= INT32_MAX)
inline constexpr Outsets ComputeShadowOutsets_Specialized() noexcept {
    int32_t extent = shadow.spread + shadow.blur;
    return Outsets{extent, extent, extent, extent};
}

} // namespace blink_shadow

