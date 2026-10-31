#include "blink_skia_font_engine.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ApplicationServices/ApplicationServices.h>

void blink_skia_font_init(void) {
    // Initialized on demand via CoreText
}

static CTFontRef create_ct_font(const char* family, float size, int bold) {
    const char* actual_family = "Helvetica";
    if (family) {
        if (strstr(family, "serif") || strstr(family, "Georgia") || strstr(family, "Libertine")) {
            actual_family = "Georgia";
        } else if (strstr(family, "monospace") || strstr(family, "Courier") || strstr(family, "Menlo")) {
            actual_family = "Menlo";
        } else {
            actual_family = "Helvetica";
        }
    }

    CFStringRef cf_name = CFStringCreateWithCString(kCFAllocatorDefault, actual_family, kCFStringEncodingUTF8);
    CTFontRef base_font = CTFontCreateWithName(cf_name, size, NULL);
    CFRelease(cf_name);

    if (bold && base_font) {
        CTFontRef bold_font = CTFontCreateCopyWithSymbolicTraits(base_font, size, NULL,
                                                                 kCTFontTraitBold, kCTFontTraitBold);
        if (bold_font) {
            CFRelease(base_font);
            return bold_font;
        }
    }
    return base_font;
}

static CGColorRef create_cg_color(uint32_t color_argb) {
    float a = ((color_argb >> 24) & 0xFF) / 255.0f;
    float r = ((color_argb >> 16) & 0xFF) / 255.0f;
    float g = ((color_argb >> 8) & 0xFF) / 255.0f;
    float b = (color_argb & 0xFF) / 255.0f;
    return CGColorCreateGenericRGB(r, g, b, a);
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

void blink_skia_font_draw_text(uint32_t* fb, int fb_w, int fb_h,
                               float x, float baseline_y,
                               const char* text,
                               const char* font_family,
                               float font_size,
                               int weight_bold,
                               uint32_t color_argb) {
    if (!fb || !text || strlen(text) == 0) return;

    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(fb, fb_w, fb_h, 8, fb_w * 4, cs,
                                             kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
    configure_skia_context(ctx, fb_h);

    CTFontRef font = create_ct_font(font_family, font_size, weight_bold);
    CGColorRef color = create_cg_color(color_argb);

    CFStringRef cf_str = CFStringCreateWithCString(kCFAllocatorDefault, text, kCFStringEncodingUTF8);
    CFStringRef keys[] = { kCTFontAttributeName, kCTForegroundColorAttributeName };
    CFTypeRef values[] = { font, color };

    CFDictionaryRef attr = CFDictionaryCreate(kCFAllocatorDefault,
                                              (const void**)keys, (const void**)values,
                                              2,
                                              &kCFTypeDictionaryKeyCallBacks,
                                              &kCFTypeDictionaryValueCallBacks);

    CFAttributedStringRef attr_str = CFAttributedStringCreate(kCFAllocatorDefault, cf_str, attr);
    CTLineRef line = CTLineCreateWithAttributedString(attr_str);

    CGContextSetTextPosition(ctx, x, baseline_y);
    CTLineDraw(line, ctx);

    CFRelease(line);
    CFRelease(attr_str);
    CFRelease(attr);
    CFRelease(cf_str);
    CFRelease(color);
    CFRelease(font);
    CGContextRelease(ctx);
    CGColorSpaceRelease(cs);
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
    CGColorRef color = create_cg_color(color_argb);

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
    float current_y = top_y + font_size; // initial baseline

    if (line_height <= 0) {
        line_height = font_size * 1.4f;
    }

    while (start < total_len && (current_y - top_y) <= h) {
        CFIndex count = CTTypesetterSuggestLineBreak(typesetter, start, w);
        CTLineRef line = CTTypesetterCreateLine(typesetter, CFRangeMake(start, count));

        CGContextSetTextPosition(ctx, x, current_y);
        CTLineDraw(line, ctx);

        CFRelease(line);
        start += count;
        current_y += line_height;
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
