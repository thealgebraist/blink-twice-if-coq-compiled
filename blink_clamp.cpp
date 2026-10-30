#include <stdint.h>
#include <stdio.h>
#include <limits.h>
#include <algorithm>

// Exact Chromium Blink LayoutUnit & Clamping Logic
struct LayoutUnit {
    int32_t value_;

    static constexpr int32_t kIntMax = 2147483647;
    static constexpr int32_t kIntMin = -2147483648;
    static constexpr int32_t kIndefiniteRaw = -64; // LayoutUnit(-1)

    static LayoutUnit FromRaw(int32_t v) { return LayoutUnit{v}; }
    int32_t Raw() const { return value_; }

    LayoutUnit operator+(LayoutUnit other) const {
        int64_t res = (int64_t)value_ + (int64_t)other.value_;
        if (res > kIntMax) res = kIntMax;
        if (res < kIntMin) res = kIntMin;
        return LayoutUnit{(int32_t)res};
    }
};

// C++ Implementation of Blink Flex Item Clamping
extern "C" int32_t Blink_ClampFlexItemMainSize_Cpp(
    int32_t hypothetical_content_size,
    int32_t border_padding,
    int32_t min_size,
    int32_t max_size
) {
    LayoutUnit content = LayoutUnit::FromRaw(hypothetical_content_size);
    LayoutUnit bp = LayoutUnit::FromRaw(border_padding);
    LayoutUnit size = content + bp;

    if (max_size != LayoutUnit::kIndefiniteRaw) {
        if (size.Raw() > max_size) {
            size = LayoutUnit::FromRaw(max_size);
        }
    }

    if (min_size != LayoutUnit::kIndefiniteRaw) {
        if (size.Raw() < min_size) {
            size = LayoutUnit::FromRaw(min_size);
        }
    }

    if (size.Raw() < bp.Raw()) {
        size = bp;
    }

    if (size.Raw() < 0) {
        size = LayoutUnit::FromRaw(0);
    }

    return size.Raw();
}

