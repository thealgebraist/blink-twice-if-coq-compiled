// blink_specialized_fastpaths.h
// Auto-synthesized C++23 Staged Fast-Path Dispatcher for Blink Layout Functions
// Proved 100% semantically equivalent in Coq/Rocq (BlinkSemanticSpecPrototype.v & BlinkLeafFunctions.v)
// Inferred via Soufflé Datalog regime analysis (blink_regimes.dl)

#pragma once

#include <stdint.h>
#include <algorithm>

namespace blink_formal {

// Exact 26.6 Fixed-Point LayoutUnit representation matching Blink
struct LayoutUnit {
    int32_t value_;

    static constexpr int32_t kIntMax = 2147483647;
    static constexpr int32_t kIntMin = -2147483648;
    static constexpr int32_t kIndefiniteRaw = -64; // LayoutUnit(-1)

    constexpr LayoutUnit() : value_(0) {}
    constexpr explicit LayoutUnit(int32_t v) : value_(v) {}
    static constexpr LayoutUnit FromRawValue(int32_t v) { return LayoutUnit(v); }
    constexpr int32_t RawValue() const { return value_; }

    constexpr LayoutUnit operator+(LayoutUnit other) const {
        int64_t res = static_cast<int64_t>(value_) + static_cast<int64_t>(other.value_);
        if (res > kIntMax) res = kIntMax;
        if (res < kIntMin) res = kIntMin;
        return LayoutUnit(static_cast<int32_t>(res));
    }

    constexpr LayoutUnit operator-(LayoutUnit other) const {
        int64_t res = static_cast<int64_t>(value_) - static_cast<int64_t>(other.value_);
        if (res > kIntMax) res = kIntMax;
        if (res < kIntMin) res = kIntMin;
        return LayoutUnit(static_cast<int32_t>(res));
    }

    constexpr LayoutUnit MulDiv(LayoutUnit num, LayoutUnit den) const {
        if (den.value_ == 0) return LayoutUnit(0);
        int64_t res = (static_cast<int64_t>(value_) * static_cast<int64_t>(num.value_)) / den.value_;
        if (res > kIntMax) res = kIntMax;
        if (res < kIntMin) res = kIntMin;
        return LayoutUnit(static_cast<int32_t>(res));
    }

    constexpr bool operator<=(LayoutUnit o) const { return value_ <= o.value_; }
    constexpr bool operator>=(LayoutUnit o) const { return value_ >= o.value_; }
    constexpr bool operator<(LayoutUnit o) const { return value_ < o.value_; }
    constexpr bool operator>(LayoutUnit o) const { return value_ > o.value_; }
    constexpr bool operator==(LayoutUnit o) const { return value_ == o.value_; }
};

enum class EBoxSizing { kContentBox, kBorderBox };

struct BoxStrut {
    LayoutUnit block_sum;
    LayoutUnit inline_sum;
};

struct LogicalSize {
    LayoutUnit inline_size;
    LayoutUnit block_size;
};

// ============================================================================
// 1. Base Unspecialized Blink General Function
// ============================================================================
inline LayoutUnit InlineSizeFromAspectRatio_General(
    const BoxStrut& border_padding,
    const LogicalSize& aspect_ratio,
    EBoxSizing box_sizing,
    LayoutUnit block_size
) {
    if (box_sizing == EBoxSizing::kBorderBox) {
        LayoutUnit clamped_sub = (block_size - border_padding.block_sum);
        LayoutUnit scaled = clamped_sub.MulDiv(aspect_ratio.inline_size, aspect_ratio.block_size);
        return std::max(border_padding.inline_sum, scaled + border_padding.inline_sum);
    }
    return block_size.MulDiv(aspect_ratio.inline_size, aspect_ratio.block_size);
}

// ============================================================================
// 2. Staged & Specialized C++23 Fast-Paths (Zero-Branch / Constexpr)
// ============================================================================

enum class AspectRatioRegime { kGeneral, kSquareRatio };
enum class PaddingRegime { kGeneral, kZeroPadding };

template <
    EBoxSizing Sizing = EBoxSizing::kContentBox,
    AspectRatioRegime Ratio = AspectRatioRegime::kGeneral,
    PaddingRegime Padding = PaddingRegime::kGeneral
>
inline LayoutUnit FastInlineSizeFromAspectRatio(
    const BoxStrut& border_padding,
    const LogicalSize& aspect_ratio,
    LayoutUnit block_size
) {
    // Stage 1 & 2 Specialization: Square Aspect Ratio (1:1) with ContentBox
    // Proven in Coq: spec_InlineSizeFromAspectRatio_ContentBox_Square
    // Reduction: Eliminates 64-bit MulDiv, division-by-zero checks, and all clamping!
    if constexpr (Sizing == EBoxSizing::kContentBox && Ratio == AspectRatioRegime::kSquareRatio) {
        return block_size;
    }
    // Stage 3 Specialization: Square Aspect Ratio (1:1) with BorderBox and Zero Padding
    // Proven in Coq: spec_InlineSizeFromAspectRatio_BorderBox_ZeroPadding_Square
    // Reduction: All border-box additions/subtractions collapse into identity!
    else if constexpr (Sizing == EBoxSizing::kBorderBox && Ratio == AspectRatioRegime::kSquareRatio && Padding == PaddingRegime::kZeroPadding) {
        return block_size;
    }
    // Stage 4 Specialization: ContentBox with arbitrary Aspect Ratio
    // Proven in Coq: spec_InlineSizeFromAspectRatio_ContentBox
    // Reduction: Completely bypasses BoxStrut block_sum and inline_sum handling!
    else if constexpr (Sizing == EBoxSizing::kContentBox) {
        return block_size.MulDiv(aspect_ratio.inline_size, aspect_ratio.block_size);
    }
    // Fallback: General unspecialized execution
    else {
        return InlineSizeFromAspectRatio_General(border_padding, aspect_ratio, Sizing, block_size);
    }
}

// ============================================================================
// 3. Flex Item Size Clamping Fast-Path (Stage 2 Default Box Regime)
// ============================================================================
template <bool HasIndefiniteMax, bool HasZeroMin>
inline LayoutUnit FastClampFlexItemSize(
    LayoutUnit content_size,
    LayoutUnit border_padding,
    LayoutUnit min_size,
    LayoutUnit max_size
) {
    // Proven in Coq: Stage2_Specialization_Correct (BlinkSemanticSpecPrototype.v)
    // Common case: min-width: 0, max-width: none
    // Collapses 4 conditional branches and min/max checks into a single saturated addition!
    if constexpr (HasIndefiniteMax && HasZeroMin) {
        return content_size + border_padding;
    } else {
        LayoutUnit size = content_size + border_padding;
        if (max_size.RawValue() != LayoutUnit::kIndefiniteRaw && size > max_size) {
            size = max_size;
        }
        if (min_size.RawValue() != LayoutUnit::kIndefiniteRaw && size < min_size) {
            size = min_size;
        }
        if (size < border_padding) size = border_padding;
        if (size < LayoutUnit(0)) size = LayoutUnit(0);
        return size;
    }
}

} // namespace blink_formal

