#include "blink_skia_font_engine.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>
#include <math.h>
#include <ApplicationServices/ApplicationServices.h>
#include <ft2build.h>
#include FT_FREETYPE_H

static FT_Library s_ft_lib = NULL;
static FT_Face s_ft_georgia_reg = NULL;
static FT_Face s_ft_georgia_bold = NULL;
static FT_Face s_ft_georgia_italic = NULL;

static uint8_t s_gamma_table[256];
static bool s_gamma_initialized = false;

static void init_gamma_table(void) {
    if (s_gamma_initialized) return;
    for (int i = 0; i < 256; i++) {
        float f = (float)i / 255.0f;
        // Skia grayscale font gamma exponent: 1.4f (SK_GAMMA_EXPONENT per Blink font rasterizer)
        float g = powf(f, 1.0f / 1.4f);
        int v = (int)roundf(g * 255.0f);
        if (v < 0) v = 0;
        if (v > 255) v = 255;
        s_gamma_table[i] = (uint8_t)v;
    }
    s_gamma_initialized = true;
}

static void init_freetype_if_needed(void) {
    init_gamma_table();
    if (s_ft_lib) return;
    if (FT_Init_FreeType(&s_ft_lib) != 0) return;
    FT_New_Face(s_ft_lib, "/System/Library/Fonts/Supplemental/Georgia.ttf", 0, &s_ft_georgia_reg);
    FT_New_Face(s_ft_lib, "/System/Library/Fonts/Supplemental/Georgia Bold.ttf", 0, &s_ft_georgia_bold);
    FT_New_Face(s_ft_lib, "/System/Library/Fonts/Supplemental/Georgia Italic.ttf", 0, &s_ft_georgia_italic);
}

static bool is_georgia_family(const char* family) {
    return family && (strstr(family, "Georgia") || strstr(family, "serif") || strstr(family, "Libertine"));
}

static bool draw_text_skia_freetype(uint32_t* fb, int fb_w, int fb_h,
                                    float x, float baseline_y,
                                    const char* text,
                                    const char* font_family,
                                    float font_size,
                                    int style_flags,
                                    float letter_spacing,
                                    uint32_t color_argb) {
    init_freetype_if_needed();
    if (!s_ft_lib || !is_georgia_family(font_family)) {
        return false;
    }

    FT_Face face = s_ft_georgia_reg;
    if (style_flags & BLINK_FONT_STYLE_BOLD) {
        if (s_ft_georgia_bold) face = s_ft_georgia_bold;
    } else if (style_flags & BLINK_FONT_STYLE_ITALIC) {
        if (s_ft_georgia_italic) face = s_ft_georgia_italic;
    }
    if (!face) return false;

    FT_Set_Pixel_Sizes(face, 0, (FT_UInt)roundf(font_size));

    float pen_x = x;
    FT_UInt prev_glyph = 0;

    uint8_t fg_r = (color_argb >> 16) & 0xFF;
    uint8_t fg_g = (color_argb >> 8) & 0xFF;
    uint8_t fg_b = color_argb & 0xFF;

    for (int i = 0; text[i]; i++) {
        FT_UInt g = FT_Get_Char_Index(face, (unsigned char)text[i]);
        if (FT_HAS_KERNING(face) && prev_glyph && g) {
            FT_Vector kern;
            FT_Get_Kerning(face, prev_glyph, g, FT_KERNING_DEFAULT, &kern);
            pen_x += kern.x / 64.0f;
        }

        FT_Vector delta;
        delta.x = (FT_Pos)((pen_x - floorf(pen_x)) * 64.0f);
        delta.y = (FT_Pos)((baseline_y - floorf(baseline_y)) * 64.0f);
        FT_Set_Transform(face, NULL, &delta);

        FT_Load_Glyph(face, g, FT_LOAD_NO_HINTING);
        FT_Render_Glyph(face->glyph, FT_RENDER_MODE_NORMAL);

        FT_Bitmap* bm = &face->glyph->bitmap;
        int gx = (int)floorf(pen_x) + face->glyph->bitmap_left;
        int gy = (int)floorf(baseline_y) - face->glyph->bitmap_top;

        for (unsigned int r = 0; r < bm->rows; r++) {
            int py = gy + r;
            if (py < 0 || py >= fb_h) continue;
            for (unsigned int c = 0; c < bm->width; c++) {
                int px = gx + c;
                if (px < 0 || px >= fb_w) continue;
                uint8_t raw_cov = bm->buffer[r * bm->pitch + c];
                if (raw_cov == 0) continue;

                // Apply Skia font gamma table per theorem blit_glyph_coverage_bounds
                uint8_t cov = s_gamma_table[raw_cov];

                uint32_t bg = fb[py * fb_w + px];
                uint8_t bg_r = (bg >> 16) & 0xFF;
                uint8_t bg_g = (bg >> 8) & 0xFF;
                uint8_t bg_b = bg & 0xFF;

                // Blending theorem per BlinkGlyphRasterizerSemantics.v
                uint8_t out_r = (fg_r * cov + bg_r * (255 - cov) + 127) / 255;
                uint8_t out_g = (fg_g * cov + bg_g * (255 - cov) + 127) / 255;
                uint8_t out_b = (fg_b * cov + bg_b * (255 - cov) + 127) / 255;

                fb[py * fb_w + px] = (0xFF << 24) | (out_r << 16) | (out_g << 8) | out_b;
            }
        }
        pen_x += face->glyph->advance.x / 64.0f + letter_spacing;
        prev_glyph = g;
    }
    return true;
}

void blink_skia_font_init(void) {
    init_freetype_if_needed();
}

static CTFontRef create_ct_font(const char* family, float size, int style_flags) {
    CTFontRef base_font = NULL;

    if (family && (strstr(family, "-apple-system") || strstr(family, "BlinkMacSystemFont") ||
                   strstr(family, "SF Pro") || strstr(family, "system-ui"))) {
        // Blink's exact font instantiation for macOS system font in FontPlatformDataMac.mm
        base_font = CTFontCreateUIFontForLanguage(kCTFontUIFontSystem, size, NULL);
    } else if (family && (strstr(family, "serif") || strstr(family, "Georgia") || strstr(family, "Libertine"))) {
        CFStringRef cf_name = CFSTR("Georgia");
        base_font = CTFontCreateWithName(cf_name, size, NULL);
    } else if (family && (strstr(family, "monospace") || strstr(family, "Courier") || strstr(family, "Menlo"))) {
        CFStringRef cf_name = CFSTR("Menlo");
        base_font = CTFontCreateWithName(cf_name, size, NULL);
    } else {
        // Default sans-serif resolves to system font in modern macOS Blink
        base_font = CTFontCreateUIFontForLanguage(kCTFontUIFontSystem, size, NULL);
    }

    CTFontSymbolicTraits traits = 0;
    if (style_flags & 1) traits |= kCTFontTraitBold;
    if (style_flags & 2) traits |= kCTFontTraitItalic;

    if (traits != 0 && base_font) {
        CTFontRef styled_font = CTFontCreateCopyWithSymbolicTraits(base_font, size, NULL,
                                                                   traits, traits);
        if (styled_font) {
            CFRelease(base_font);
            return styled_font;
        }
    }
    return base_font;
}

static CGColorRef create_cg_color(CGColorSpaceRef cs, uint32_t color_argb) {
    CGFloat comp[4] = {
        ((color_argb >> 16) & 0xFF) / 255.0f,
        ((color_argb >> 8) & 0xFF) / 255.0f,
        (color_argb & 0xFF) / 255.0f,
        ((color_argb >> 24) & 0xFF) / 255.0f
    };
    return CGColorCreate(cs, comp);
}

static void configure_skia_context(CGContextRef ctx, int fb_h) {
    // Top-left origin coordinate flip
    CGContextTranslateCTM(ctx, 0, fb_h);
    CGContextScaleCTM(ctx, 1.0f, -1.0f);

    // Skia font antialiasing parameters
    CGContextSetAllowsFontSmoothing(ctx, true);
    CGContextSetShouldSmoothFonts(ctx, true);
    CGContextSetAllowsAntialiasing(ctx, true);
    CGContextSetShouldAntialias(ctx, true);
    CGContextSetAllowsFontSubpixelPositioning(ctx, true);
    CGContextSetShouldSubpixelPositionFonts(ctx, true);
    CGContextSetAllowsFontSubpixelQuantization(ctx, true);
    CGContextSetShouldSubpixelQuantizeFonts(ctx, true);

    // Text matrix to draw right-side up in flipped context
    CGContextSetTextMatrix(ctx, CGAffineTransformMakeScale(1.0f, -1.0f));
}

void blink_skia_font_draw_text_ex(uint32_t* fb, int fb_w, int fb_h,
                                  float x, float baseline_y,
                                  const char* text,
                                  const char* font_family,
                                  float font_size,
                                  int style_flags,
                                  float letter_spacing,
                                  uint32_t color_argb) {
    if (!fb || !text || strlen(text) == 0) return;

    if (draw_text_skia_freetype(fb, fb_w, fb_h, x, baseline_y, text, font_family, font_size, style_flags, letter_spacing, color_argb)) {
        return;
    }

    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(fb, fb_w, fb_h, 8, fb_w * 4, cs,
                                             kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
    configure_skia_context(ctx, fb_h);

    CTFontRef font = create_ct_font(font_family, font_size, style_flags);
    CGColorRef color = create_cg_color(cs, color_argb);

    CFStringRef cf_str = CFStringCreateWithCString(kCFAllocatorDefault, text, kCFStringEncodingUTF8);
    
    CFStringRef keys[3];
    CFTypeRef values[3];
    int num_keys = 2;
    keys[0] = kCTFontAttributeName;
    values[0] = font;
    keys[1] = kCTForegroundColorAttributeName;
    values[1] = color;
    
    CFNumberRef cf_kern = NULL;
    if (letter_spacing != 0.0f) {
        cf_kern = CFNumberCreate(kCFAllocatorDefault, kCFNumberFloatType, &letter_spacing);
        keys[2] = kCTKernAttributeName;
        values[2] = cf_kern;
        num_keys = 3;
    }

    CFDictionaryRef attr = CFDictionaryCreate(kCFAllocatorDefault,
                                              (const void**)keys, (const void**)values,
                                              num_keys,
                                              &kCFTypeDictionaryKeyCallBacks,
                                              &kCFTypeDictionaryValueCallBacks);

    CFAttributedStringRef attr_str = CFAttributedStringCreate(kCFAllocatorDefault, cf_str, attr);
    CTLineRef line = CTLineCreateWithAttributedString(attr_str);

    CGContextSetTextPosition(ctx, x, baseline_y);
    CTLineDraw(line, ctx);

    if (cf_kern) CFRelease(cf_kern);
    CFRelease(line);
    CFRelease(attr_str);
    CFRelease(attr);
    CFRelease(cf_str);
    CFRelease(color);
    CFRelease(font);
    CGContextRelease(ctx);
    CGColorSpaceRelease(cs);
}

void blink_skia_font_draw_text(uint32_t* fb, int fb_w, int fb_h,
                               float x, float baseline_y,
                               const char* text,
                               const char* font_family,
                               float font_size,
                               int style_flags,
                               uint32_t color_argb) {
    blink_skia_font_draw_text_ex(fb, fb_w, fb_h, x, baseline_y, text, font_family, font_size, style_flags, 0.0f, color_argb);
}

void blink_skia_font_draw_text_box(uint32_t* fb, int fb_w, int fb_h,
                                   float x, float top_y, float w, float h,
                                   const char* text,
                                   const char* font_family,
                                   float font_size,
                                   float line_height,
                                   uint32_t color_argb) {
    if (!fb || !text || strlen(text) == 0 || w <= 0 || h <= 0) return;

    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(fb, fb_w, fb_h, 8, fb_w * 4, cs,
                                             kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
    configure_skia_context(ctx, fb_h);

    CTFontRef font = create_ct_font(font_family, font_size, 0);
    CGColorRef color = create_cg_color(cs, color_argb);

    CFStringRef cf_str = CFStringCreateWithCString(kCFAllocatorDefault, text, kCFStringEncodingUTF8);
    CFStringRef keys[] = { kCTFontAttributeName, kCTForegroundColorAttributeName };
    CFTypeRef values[] = { font, color };

    CFDictionaryRef attr = CFDictionaryCreate(kCFAllocatorDefault,
                                              (const void**)keys, (const void**)values,
                                              2,
                                              &kCFTypeDictionaryKeyCallBacks,
                                              &kCFTypeDictionaryValueCallBacks);

    CFAttributedStringRef attr_str = CFAttributedStringCreate(kCFAllocatorDefault, cf_str, attr);
    CTTypesetterRef typesetter = CTTypesetterCreateWithAttributedString(attr_str);

    CFIndex start = 0;
    CFIndex total_len = CFAttributedStringGetLength(attr_str);

    // W3C CSS Inline 3 §3 Half-Leading distribution:
    // Leading L = line_height - (ascent + descent)
    // First line baseline = top_y + half_leading + ascent
    CGFloat ascent = CTFontGetAscent(font);
    CGFloat descent = CTFontGetDescent(font);
    if (line_height <= 0) {
        line_height = font_size * 1.5f;
    }
    CGFloat font_box_h = ascent + descent;
    CGFloat half_leading = (line_height - font_box_h) / 2.0f;
    if (half_leading < 0) half_leading = 0;

    // Blink FontMetrics integer baseline offset:
    // In Chromium Blink LayoutNG, inline box baseline is placed at top_y + round(ascent)
    float current_baseline = top_y + roundf(ascent);

    while (start < total_len && (current_baseline - top_y - ascent) <= h) {
        CFIndex count = CTTypesetterSuggestLineBreak(typesetter, start, w);
        // W3C CSS Text 3 §4.1.2 & §7.1: Trim trailing whitespace before justification
        CFIndex visible_count = count;
        while (visible_count > 0 && CFStringGetCharacterAtIndex(cf_str, start + visible_count - 1) == ' ') {
            visible_count--;
        }
        CTLineRef line = CTTypesetterCreateLine(typesetter, CFRangeMake(start, visible_count));

        // W3C CSS Text 3 §7.1 & Blink ShapeResultSpacing Justification:
        // When text-align: justify is active, only space opportunities are expanded.
        // Inter-letter spacing within words remains pristine per CSS Text 3 §7.3.
        if (start + count < total_len) {
            int space_count = 0;
            for (CFIndex i = 0; i < visible_count; i++) {
                if (CFStringGetCharacterAtIndex(cf_str, start + i) == ' ') {
                    space_count++;
                }
            }
            if (space_count > 0) {
                CGFloat natural_w = CTLineGetTypographicBounds(line, NULL, NULL, NULL);
                CGFloat excess = (CGFloat)w - natural_w;
                if (excess > 0) {
                    CGFloat extra_space = excess / (CGFloat)space_count;
                    CGFloat cur_x = x;
                    CFIndex word_start = start;
                    for (CFIndex i = 0; i <= visible_count; i++) {
                        if (i == visible_count || CFStringGetCharacterAtIndex(cf_str, start + i) == ' ') {
                            CFIndex word_len = (start + i) - word_start;
                            if (word_len > 0) {
                                CTLineRef word_line = CTTypesetterCreateLine(typesetter, CFRangeMake(word_start, word_len));
                                CGContextSetTextPosition(ctx, cur_x, current_baseline);
                                CTLineDraw(word_line, ctx);
                                cur_x += CTLineGetTypographicBounds(word_line, NULL, NULL, NULL);
                                CFRelease(word_line);
                            }
                            if (i < visible_count) {
                                CTLineRef sp_line = CTTypesetterCreateLine(typesetter, CFRangeMake(start + i, 1));
                                cur_x += CTLineGetTypographicBounds(sp_line, NULL, NULL, NULL) + extra_space;
                                CFRelease(sp_line);
                            }
                            word_start = start + i + 1;
                        }
                    }
                    CFRelease(line);
                    start += count;
                    current_baseline += line_height;
                    continue;
                }
            }
        }

        CGContextSetTextPosition(ctx, x, current_baseline);
        CTLineDraw(line, ctx);
        CFRelease(line);

        start += count;
        current_baseline += line_height;
    }

    CFRelease(typesetter);
    CFRelease(attr_str);
    CFRelease(attr);
    CFRelease(cf_str);
    CFRelease(color);
    CFRelease(font);
    CGContextRelease(ctx);
    CGColorSpaceRelease(cs);
}

float blink_skia_font_measure_text(const char* text,
                                   const char* font_family,
                                   float font_size,
                                   int weight_bold) {
    if (!text || strlen(text) == 0) return 0.0f;

    init_freetype_if_needed();
    if (s_ft_lib && is_georgia_family(font_family)) {
        FT_Face face = (weight_bold && s_ft_georgia_bold) ? s_ft_georgia_bold : s_ft_georgia_reg;
        if (face) {
            FT_Set_Pixel_Sizes(face, 0, (FT_UInt)roundf(font_size));
            float advance = 0.0f;
            FT_UInt prev_glyph = 0;
            for (int i = 0; text[i]; i++) {
                FT_UInt g = FT_Get_Char_Index(face, (unsigned char)text[i]);
                if (FT_HAS_KERNING(face) && prev_glyph && g) {
                    FT_Vector kern;
                    FT_Get_Kerning(face, prev_glyph, g, FT_KERNING_DEFAULT, &kern);
                    advance += kern.x / 64.0f;
                }
                FT_Load_Glyph(face, g, FT_LOAD_NO_HINTING);
                advance += face->glyph->advance.x / 64.0f;
                prev_glyph = g;
            }
            return advance;
        }
    }

    CTFontRef font = create_ct_font(font_family, font_size, weight_bold);
    CFStringRef cf_str = CFStringCreateWithCString(kCFAllocatorDefault, text, kCFStringEncodingUTF8);
    CFStringRef keys[] = { kCTFontAttributeName };
    CFTypeRef values[] = { font };

    CFDictionaryRef attr = CFDictionaryCreate(kCFAllocatorDefault,
                                              (const void**)keys, (const void**)values,
                                              1,
                                              &kCFTypeDictionaryKeyCallBacks,
                                              &kCFTypeDictionaryValueCallBacks);

    CFAttributedStringRef attr_str = CFAttributedStringCreate(kCFAllocatorDefault, cf_str, attr);
    CTLineRef line = CTLineCreateWithAttributedString(attr_str);

    double width = CTLineGetTypographicBounds(line, NULL, NULL, NULL);

    CFRelease(line);
    CFRelease(attr_str);
    CFRelease(attr);
    CFRelease(cf_str);
    CFRelease(font);

    return (float)width;
}
