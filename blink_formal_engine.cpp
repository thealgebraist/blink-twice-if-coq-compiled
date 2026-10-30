#include "blink_formal_engine.h"
#include <iostream>
#include <vector>
#include <memory>
#include <string_view>

/* ========================================================================= */
/* Blink Formal Layout Engine - C++23 Drop-In Class Definitions             */
/* Enables direct replacement of Blink core/layout/ algorithms with          */
/* certified Coq formal models.                                              */
/* ========================================================================= */

namespace blink::formal {

class PhysicalSize {
public:
    int64_t width{0};
    int64_t height{0};
    constexpr PhysicalSize(int64_t w, int64_t h) noexcept : width(w), height(h) {}
};

class PhysicalOffset {
public:
    int64_t x{0};
    int64_t y{0};
    constexpr PhysicalOffset(int64_t px, int64_t py) noexcept : x(px), y(py) {}
};

class PhysicalRect {
public:
    PhysicalOffset offset;
    PhysicalSize size;
    constexpr PhysicalRect(int64_t x, int64_t y, int64_t w, int64_t h) noexcept
        : offset(x, y), size(w, h) {}
};

class VerifiedPagePipeline {
public:
    static InteractiveLayoutOutput Layout(int64_t viewport_w, int64_t viewport_h, const InteractivePageInput& page) noexcept {
        return layout_interactive_page_pipeline(viewport_w, viewport_h, &page);
    }
    
    static std::unique_ptr<FrameBuffer, decltype(&fb_destroy)> Rasterize(const InteractiveLayoutOutput& layout) {
        Color white{255, 255, 255, 255};
        std::unique_ptr<FrameBuffer, decltype(&fb_destroy)> fb(
            fb_create(layout.ilo_viewport_w, layout.ilo_viewport_h, white),
            fb_destroy
        );
        if (fb) {
            rasterize_interactive_page(fb.get(), &layout);
        }
        return fb;
    }
};

} // namespace blink::formal

