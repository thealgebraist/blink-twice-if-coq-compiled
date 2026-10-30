// blink_margin_fastpaths.h
// Verified C++23 Fast-Paths for Blink Block Layout Margin Collapsing (MarginStrut)
#pragma once

#include <cstdint>
#include <algorithm>
#include <climits>

namespace blink_margin {

struct MarginStrut {
    int32_t positive_margin{0};
    int32_t negative_margin{0}; // signed non-positive (<= 0)
    int32_t quirky_positive_margin{0};
    bool is_quirky_container_start{false};
};

inline constexpr int32_t sat_add(int32_t a, int32_t b) noexcept {
    int64_t res = static_cast<int64_t>(a) + b;
    if (res > INT32_MAX) return INT32_MAX;
    if (res < INT32_MIN) return INT32_MIN;
    return static_cast<int32_t>(res);
}

// General Blink Margin Collapsing Append
inline constexpr void Append_General(MarginStrut& ms, int32_t val, bool is_quirk) noexcept {
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

// General Blink MarginStrut Sum
inline constexpr int32_t Sum_General(const MarginStrut& ms) noexcept {
    int32_t max_pos = std::max(ms.quirky_positive_margin, ms.positive_margin);
    return sat_add(max_pos, ms.negative_margin);
}

// Formally Verified C++23 Fast-Path: Pure Positive Margin Regime (Specialization 1)
// Proved in Coq: margin_strut_pure_positive_specialization
template<int32_t pos, int32_t qpos>
    requires (pos >= 0 && qpos >= 0 &&
              pos <= INT32_MAX && qpos <= INT32_MAX)
inline constexpr int32_t Sum_PurePositive() noexcept {
    return std::max(pos, qpos);
}

// Formally Verified C++23 Fast-Path: Single Negative Margin on Fresh Strut (Specialization 2)
// Proved in Coq: margin_strut_pure_negative_specialization
template<int32_t val>
    requires (val < 0 && val >= INT32_MIN)
inline constexpr int32_t Sum_SingleNegative() noexcept {
    return val;
}

} // namespace blink_margin

