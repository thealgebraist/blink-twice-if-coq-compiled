#ifndef BLINK_FONT_ENGINE_H
#define BLINK_FONT_ENGINE_H

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Text Alignment Constants */
#define BLINK_FONT_ALIGN_LEFT   0
#define BLINK_FONT_ALIGN_CENTER 1
#define BLINK_FONT_ALIGN_RIGHT  2

/* Base Font Glyph Metrics */
#define BLINK_FONT_BASE_WIDTH   8
#define BLINK_FONT_BASE_HEIGHT  16
#define BLINK_FONT_ASCII_START  32
#define BLINK_FONT_ASCII_END    126
#define BLINK_FONT_NUM_GLYPHS   (BLINK_FONT_ASCII_END - BLINK_FONT_ASCII_START + 1)

/**
 * Initializes the font engine, glyph atlas, and precomputes subpixel coverage tables.
 * Safe to call multiple times (idempotent).
 */
void blink_font_init(void);

/**
 * Measures the rendered pixel width of a given text string.
 * If the string contains multiple lines delimited by '\n', returns the maximum line width.
 *
 * @param text The null-terminated string to measure.
 * @param font_size Font size in pixels (height; <= 0 defaults to 16).
 * @param letter_spacing Additional spacing in pixels between characters.
 * @return Total width in pixels.
 */
int blink_font_measure_text(const char* text, int font_size, int letter_spacing);

/**
 * Draws text onto a 32-bit ARGB/RGBA framebuffer.
 *
 * @param fb Pointer to 32-bit framebuffer pixel buffer (row-major).
 * @param fb_w Framebuffer width in pixels.
 * @param fb_h Framebuffer height in pixels.
 * @param x Horizontal starting coordinate.
 * @param y Vertical starting coordinate.
 * @param text The null-terminated text string to draw.
 * @param color 32-bit color (0xAARRGGBB; if alpha is 0, treated as 0xFF opaque).
 * @param font_size Font size in pixels (height; <= 0 defaults to 16).
 * @param letter_spacing Additional spacing in pixels between characters.
 */
void blink_font_draw_text(uint32_t* fb, int fb_w, int fb_h,
                         int x, int y,
                         const char* text, uint32_t color,
                         int font_size, int letter_spacing);

/**
 * Draws text inside a specified bounding box, with word wrapping and alignment.
 * Clips drawing strictly within [x, y, x + w, y + h].
 *
 * @param fb Pointer to 32-bit framebuffer pixel buffer (row-major).
 * @param fb_w Framebuffer width in pixels.
 * @param fb_h Framebuffer height in pixels.
 * @param x Box left coordinate.
 * @param y Box top coordinate.
 * @param w Box width in pixels.
 * @param h Box height in pixels.
 * @param text The null-terminated text string to draw.
 * @param color 32-bit color (0xAARRGGBB; if alpha is 0, treated as 0xFF opaque).
 * @param font_size Font size in pixels (height; <= 0 defaults to 16).
 * @param align Horizontal alignment (BLINK_FONT_ALIGN_LEFT, CENTER, RIGHT).
 */
void blink_font_draw_text_box(uint32_t* fb, int fb_w, int fb_h,
                             int x, int y, int w, int h,
                             const char* text, uint32_t color,
                             int font_size, int align);

/**
 * Accesses a single pixel alpha/coverage from the embedded 8x16 glyph atlas.
 *
 * @param c Character code (ASCII 32..126).
 * @param gx Glyph column (0..7).
 * @param gy Glyph row (0..15).
 * @return Coverage value (0..255).
 */
uint8_t blink_font_get_glyph_pixel(char c, int gx, int gy);

/**
 * Computes subpixel coverage between two horizontal pixel columns at a given phase.
 *
 * @param c0 Left pixel coverage (0..255).
 * @param c1 Right pixel coverage (0..255).
 * @param phase_4th Subpixel phase in quarters (0 to 4).
 * @return Blended coverage value (0..255).
 */
uint8_t blink_font_get_subpixel_coverage(uint8_t c0, uint8_t c1, int phase_4th);

#ifdef __cplusplus
}
#endif

#endif /* BLINK_FONT_ENGINE_H */
