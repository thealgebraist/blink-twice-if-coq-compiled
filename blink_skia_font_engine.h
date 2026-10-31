#ifndef BLINK_SKIA_FONT_ENGINE_H
#define BLINK_SKIA_FONT_ENGINE_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

void blink_skia_font_init(void);

/**
 * Draws a single text run with Skia's native macOS font scaler (CoreText).
 * x, baseline_y: text origin in top-left coordinate system.
 * color_argb: 32-bit ARGB (0xAARRGGBB).
 */
#define BLINK_FONT_STYLE_NORMAL 0
#define BLINK_FONT_STYLE_BOLD   1
#define BLINK_FONT_STYLE_ITALIC 2

void blink_skia_font_draw_text(uint32_t* fb, int fb_w, int fb_h,
                               float x, float baseline_y,
                               const char* text,
                               const char* font_family,
                               float font_size,
                               int style_flags,
                               uint32_t color_argb);

/**
 * Draws multi-line wrapped text box matching Blink/Skia line breaking and line-height.
 */
void blink_skia_font_draw_text_box(uint32_t* fb, int fb_w, int fb_h,
                                   float x, float top_y, float w, float h,
                                   const char* text,
                                   const char* font_family,
                                   float font_size,
                                   float line_height,
                                   uint32_t color_argb);

/**
 * Measures text advance in pixels using Skia/CoreText font metrics.
 */
float blink_skia_font_measure_text(const char* text,
                                   const char* font_family,
                                   float font_size,
                                   int weight_bold);

#ifdef __cplusplus
}
#endif

#endif // BLINK_SKIA_FONT_ENGINE_H

