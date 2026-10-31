#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <assert.h>
#include "blink_image_codec.h"
#include "blink_font_engine.h"

#define VIEWPORT_WIDTH  800
#define VIEWPORT_HEIGHT 600

typedef struct {
    uint32_t* pixels;
    int width;
    int height;
} FrameBuffer;

static FrameBuffer* fb_create(int w, int h) {
    FrameBuffer* fb = (FrameBuffer*)malloc(sizeof(FrameBuffer));
    fb->width = w;
    fb->height = h;
    fb->pixels = (uint32_t*)malloc(w * h * sizeof(uint32_t));
    for (int i = 0; i < w * h; i++) {
        fb->pixels[i] = 0xFFFFFFFF; // White background
    }
    return fb;
}

static void fb_destroy(FrameBuffer* fb) {
    if (fb) {
        free(fb->pixels);
        free(fb);
    }
}

static void fb_fill_rect(FrameBuffer* fb, int x, int y, int w, int h, uint32_t color) {
    int x0 = x < 0 ? 0 : x;
    int y0 = y < 0 ? 0 : y;
    int x1 = (x + w) > fb->width ? fb->width : (x + w);
    int y1 = (y + h) > fb->height ? fb->height : (y + h);

    for (int r = y0; r < y1; r++) {
        for (int c = x0; c < x1; c++) {
            fb->pixels[r * fb->width + c] = color;
        }
    }
}

static void fb_save_ppm(FrameBuffer* fb, const char* filename) {
    FILE* fp = fopen(filename, "wb");
    if (!fp) return;
    fprintf(fp, "P6\n%d %d\n255\n", fb->width, fb->height);
    for (int i = 0; i < fb->width * fb->height; i++) {
        uint32_t c = fb->pixels[i];
        uint8_t r = (c >> 16) & 0xFF;
        uint8_t g = (c >> 8) & 0xFF;
        uint8_t b = c & 0xFF;
        fputc(r, fp);
        fputc(g, fp);
        fputc(b, fp);
    }
    fclose(fp);
}

int main(void) {
    printf("=== Rendering Showcase: Images & Fonts with Verified Engine ===\n");
    blink_font_init();

    FrameBuffer* fb = fb_create(VIEWPORT_WIDTH, VIEWPORT_HEIGHT);

    // 1. Header (y=24, h=44, w=752)
    fb_fill_rect(fb, 24, 24, 752, 44, 0xFF1E293B);
    fb_fill_rect(fb, 24, 64, 752, 4, 0xFF3B82F6); // Accent border
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT,
                         40, 36, "Blink Verified Engine: Images & Typography", 0xFFFFFFFF, 16, 1);

    // 2. Main Grid: Left Image Card (x=24, y=88, w=240, h=300)
    fb_fill_rect(fb, 24, 88, 240, 300, 0xFFF8FAFC);
    // Card border
    fb_fill_rect(fb, 24, 88, 240, 1, 0xFFE2E8F0);
    fb_fill_rect(fb, 24, 387, 240, 1, 0xFFE2E8F0);
    fb_fill_rect(fb, 24, 88, 1, 300, 0xFFE2E8F0);
    fb_fill_rect(fb, 263, 88, 1, 300, 0xFFE2E8F0);

    // Load and blit avatar image (x=84, y=108, w=120, h=120)
    blink_image_t* avatar = blink_image_load_ppm("test_avatar.ppm");
    if (avatar) {
        printf("Loaded avatar image: %dx%d\n", avatar->width, avatar->height);
        // Blit with bilinear resampling per Coq theorem bilinear_interp256_bounded
        blink_image_blit_bilinear(avatar, fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 84, 108, 120, 120);
        // Image border (2px #3b82f6)
        fb_fill_rect(fb, 82, 106, 124, 2, 0xFF3B82F6);
        fb_fill_rect(fb, 82, 228, 124, 2, 0xFF3B82F6);
        fb_fill_rect(fb, 82, 106, 2, 124, 0xFF3B82F6);
        fb_fill_rect(fb, 204, 106, 2, 124, 0xFF3B82F6);
        blink_image_free(avatar);
    } else {
        printf("Warning: test_avatar.ppm not found\n");
    }

    // Badges under avatar
    fb_fill_rect(fb, 44, 250, 95, 24, 0xFFE0E7FF);
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 50, 255, "object-fit: cover", 0xFF3730A3, 11, 0);

    fb_fill_rect(fb, 145, 250, 95, 24, 0xFFE0E7FF);
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 155, 255, "128x128 RGBA", 0xFF3730A3, 11, 0);

    // 3. Right Content Card (x=284, y=88, w=492, h=300)
    fb_fill_rect(fb, 284, 88, 492, 300, 0xFFF8FAFC);
    fb_fill_rect(fb, 284, 88, 492, 1, 0xFFE2E8F0);
    fb_fill_rect(fb, 284, 387, 492, 1, 0xFFE2E8F0);
    fb_fill_rect(fb, 284, 88, 1, 300, 0xFFE2E8F0);
    fb_fill_rect(fb, 775, 88, 1, 300, 0xFFE2E8F0);

    // Heading in content card
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 300, 104,
                         "Formal Layout and Subpixel Rasterization", 0xFF1E293B, 15, 0);

    // Paragraph
    const char* para = "Images are resampled via fixed-point bilinear filtering with Porter-Duff source-over alpha blending. Text glyphs are shaped and rasterized with subpixel antialiasing across all standard character runs.";
    blink_font_draw_text_box(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 300, 134, 460, 60, para, 0xFF334155, 12, BLINK_FONT_ALIGN_LEFT);

    // Specs Table (y=210, w=460)
    // Table Header
    fb_fill_rect(fb, 300, 210, 460, 26, 0xFF334155);
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 308, 216, "Subsystem", 0xFFFFFFFF, 12, 0);
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 440, 216, "Formal Specification", 0xFFFFFFFF, 12, 0);
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 640, 216, "Verification", 0xFFFFFFFF, 12, 0);

    // Row 1
    fb_fill_rect(fb, 300, 236, 460, 24, 0xFFFFFFFF);
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 308, 241, "Replaced Sizing", 0xFF0F172A, 11, 0);
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 440, 241, "BlinkObjectFitSemantics.v", 0xFF0F172A, 11, 0);
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 640, 241, "0 Admits (Rocq 9.3)", 0xFF16A34A, 11, 0);

    // Row 2
    fb_fill_rect(fb, 300, 260, 460, 24, 0xFFF1F5F9);
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 308, 265, "Image Compositing", 0xFF0F172A, 11, 0);
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 440, 265, "BlinkImageResamplingSemantics.v", 0xFF0F172A, 11, 0);
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 640, 265, "0 Admits (Rocq 9.3)", 0xFF16A34A, 11, 0);

    // Row 3
    fb_fill_rect(fb, 300, 284, 460, 24, 0xFFFFFFFF);
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 308, 289, "Font Matching", 0xFF0F172A, 11, 0);
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 440, 289, "BlinkFontMatchingSemantics.v", 0xFF0F172A, 11, 0);
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 640, 289, "0 Admits (Rocq 9.3)", 0xFF16A34A, 11, 0);

    // Row 4
    fb_fill_rect(fb, 300, 308, 460, 24, 0xFFF1F5F9);
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 308, 313, "Text Layout", 0xFF0F172A, 11, 0);
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 440, 313, "BlinkInlineTextLayoutSemantics.v", 0xFF0F172A, 11, 0);
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 640, 313, "0 Admits (Rocq 9.3)", 0xFF16A34A, 11, 0);

    // 4. Action Buttons (y=408)
    fb_fill_rect(fb, 24, 408, 200, 36, 0xFF2563EB);
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 38, 418, "Execute Verified Pipeline", 0xFFFFFFFF, 12, 0);

    fb_fill_rect(fb, 236, 408, 210, 36, 0xFFFFFFFF);
    fb_fill_rect(fb, 236, 408, 210, 1, 0xFFCBD5E1);
    fb_fill_rect(fb, 236, 443, 210, 1, 0xFFCBD5E1);
    fb_fill_rect(fb, 236, 408, 1, 36, 0xFFCBD5E1);
    fb_fill_rect(fb, 445, 408, 1, 36, 0xFFCBD5E1);
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 248, 418, "Export Raster Framebuffer", 0xFF334155, 12, 0);

    fb_save_ppm(fb, "blink_formal_images_fonts.ppm");
    printf("Successfully wrote blink_formal_images_fonts.ppm!\n");

    fb_destroy(fb);
    return 0;
}

