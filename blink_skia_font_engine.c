#include "blink_skia_font_engine.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <ApplicationServices/ApplicationServices.h>

void blink_skia_font_init(void) {
    // Initialized on demand via CoreText
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

        // W3C CSS Text 3 §7.1 Justification:
        // If not the last line of paragraph, justify to w
        CTLineRef line_to_draw = line;
        CTLineRef justified_line = NULL;
        if (start + count < total_len) {
            justified_line = CTLineCreateJustifiedLine(line, 1.0f, w);
            if (justified_line) {
                line_to_draw = justified_line;
            }
        }

        CGContextSetTextPosition(ctx, x, current_baseline);
        CTLineDraw(line_to_draw, ctx);

        if (justified_line) CFRelease(justified_line);
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
