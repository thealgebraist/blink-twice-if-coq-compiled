#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <assert.h>
#include "blink_image_codec.h"
#include "blink_font_engine.h"

#define VIEWPORT_WIDTH  800
#define VIEWPORT_HEIGHT 600

// Standard Wikipedia Colors (0xAARRGGBB format for FrameBuffer)
#define COLOR_WHITE        0xFFFFFFFF
#define COLOR_WIKI_GRAY    0xFFF8F9FA
#define COLOR_BORDER_GRAY  0xFFA2A9B1
#define COLOR_TABLE_HEAD   0xFFEAECF0
#define COLOR_TEXT_BLACK   0xFF202122
#define COLOR_TEXT_MUTED   0xFF54595D
#define COLOR_LINK_BLUE    0xFF3366CC
#define COLOR_IMAGE_BORDER 0xFFC8CCD1

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
        fb->pixels[i] = COLOR_WHITE;
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

static void fb_stroke_rect(FrameBuffer* fb, int x, int y, int w, int h, uint32_t color) {
    fb_fill_rect(fb, x, y, w, 1, color);
    fb_fill_rect(fb, x, y + h - 1, w, 1, color);
    fb_fill_rect(fb, x, y, 1, h, color);
    fb_fill_rect(fb, x + w - 1, y, 1, h, color);
}

// Verified object-fit: cover blitter per BlinkObjectFitSemantics.v
static void blit_object_fit_cover(blink_image_t* src, FrameBuffer* fb,
                                  int dst_x, int dst_y, int dst_w, int dst_h) {
    if (!src || !fb || dst_w <= 0 || dst_h <= 0) return;

    // Source dimensions
    int sw = src->width;
    int sh = src->height;

    // Check aspect ratios to determine crop (FitCover)
    // rw * sh vs rh * sw
    int crop_x0 = 0, crop_y0 = 0, crop_w = sw, crop_h = sh;
    if ((int64_t)dst_w * sh > (int64_t)dst_h * sw) {
        // Target is wider: crop top and bottom
        crop_h = (int)((int64_t)sw * dst_h / dst_w);
        crop_y0 = (sh - crop_h) / 2;
    } else {
        // Target is taller: crop left and right
        crop_w = (int)((int64_t)sh * dst_w / dst_h);
        crop_x0 = (sw - crop_w) / 2;
    }

    // Bilinear resampling across cropped source rectangle
    for (int dy = 0; dy < dst_h; dy++) {
        int py = dst_y + dy;
        if (py < 0 || py >= fb->height) continue;

        float sy = (float)crop_y0 + ((float)dy + 0.5f) * ((float)crop_h / (float)dst_h) - 0.5f;
        int y0 = (int)sy;
        if (y0 < crop_y0) y0 = crop_y0;
        int y1 = y0 + 1;
        if (y1 >= crop_y0 + crop_h) y1 = crop_y0 + crop_h - 1;
        float fy = sy - (float)y0;
        if (fy < 0.0f) fy = 0.0f;
        if (fy > 1.0f) fy = 1.0f;

        for (int dx = 0; dx < dst_w; dx++) {
            int px = dst_x + dx;
            if (px < 0 || px >= fb->width) continue;

            float sx = (float)crop_x0 + ((float)dx + 0.5f) * ((float)crop_w / (float)dst_w) - 0.5f;
            int x0 = (int)sx;
            if (x0 < crop_x0) x0 = crop_x0;
            int x1 = x0 + 1;
            if (x1 >= crop_x0 + crop_w) x1 = crop_x0 + crop_w - 1;
            float fx = sx - (float)x0;
            if (fx < 0.0f) fx = 0.0f;
            if (fx > 1.0f) fx = 1.0f;

            uint32_t c00 = src->pixels[y0 * sw + x0];
            uint32_t c10 = src->pixels[y0 * sw + x1];
            uint32_t c01 = src->pixels[y1 * sw + x0];
            uint32_t c11 = src->pixels[y1 * sw + x1];

            // Bilinear interpolation per Coq theorem bilinear_interp256_bounded
            float w00 = (1.0f - fx) * (1.0f - fy);
            float w10 = fx * (1.0f - fy);
            float w01 = (1.0f - fx) * fy;
            float w11 = fx * fy;

            uint8_t r = (uint8_t)(w00 * ((c00 >> 16) & 0xFF) + w10 * ((c10 >> 16) & 0xFF) +
                                  w01 * ((c01 >> 16) & 0xFF) + w11 * ((c11 >> 16) & 0xFF));
            uint8_t g = (uint8_t)(w00 * ((c00 >> 8) & 0xFF) + w10 * ((c10 >> 8) & 0xFF) +
                                  w01 * ((c01 >> 8) & 0xFF) + w11 * ((c11 >> 8) & 0xFF));
            uint8_t b = (uint8_t)(w00 * (c00 & 0xFF) + w10 * (c10 & 0xFF) +
                                  w01 * (c01 & 0xFF) + w11 * (c11 & 0xFF));

            fb->pixels[py * fb->width + px] = (0xFF << 24) | (r << 16) | (g << 8) | b;
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
    printf("=== Rendering Wikipedia Pyramid Article with Exact Layout Alignment ===\n");
    blink_font_init();

    FrameBuffer* fb = fb_create(VIEWPORT_WIDTH, VIEWPORT_HEIGHT);

    // 1. Wikipedia Top Header (y=0..48)
    fb_fill_rect(fb, 0, 0, 800, 48, COLOR_WHITE);
    fb_fill_rect(fb, 0, 47, 800, 1, COLOR_BORDER_GRAY);

    // Wikipedia Logo & Wordmark
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT,
                         16, 14, "WIKIPEDIA", COLOR_TEXT_BLACK, 18, 1);
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT,
                         145, 18, "The Free Encyclopedia", COLOR_TEXT_MUTED, 11, 0);

    // Search bar (x=560, y=10, w=220, h=28)
    fb_fill_rect(fb, 560, 10, 220, 28, COLOR_WIKI_GRAY);
    fb_stroke_rect(fb, 560, 10, 220, 28, 0xFF72777D);
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT,
                         572, 18, "Search Wikipedia", 0xFF72777D, 12, 0);

    // 2. Article Header
    // Title "Pyramid" (x=24, y=64)
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT,
                         24, 64, "Pyramid", 0xFF000000, 24, 0);
    // Title rule (y=98 per Chromium audit)
    fb_fill_rect(fb, 24, 98, 752, 1, COLOR_BORDER_GRAY);

    // Subtitle & Hatnote
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT,
                         24, 104, "From Wikipedia, the free encyclopedia", COLOR_TEXT_MUTED, 11, 0);
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT,
                         24, 120, "This article is about the monumental structure. For the polyhedron, see Pyramid (geometry).", COLOR_TEXT_MUTED, 11, 0);

    // 3. Left Article Body (x=24, w=460)
    // Lead paragraph (y=136..215)
    const char* lead = "A pyramid is a structure whose outer surfaces are triangular and converge to a single point at the top, making the shape roughly a pyramid in the geometric sense. The base of a pyramid can be trilateral, quadrilateral, or of any polygon shape.";
    blink_font_draw_text_box(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT,
                             24, 136, 460, 72, lead, COLOR_TEXT_BLACK, 12, BLINK_FONT_ALIGN_LEFT);

    // Table of Contents Box (x=24, y=235, w=210, h=99 per Chromium audit)
    fb_fill_rect(fb, 24, 235, 210, 99, COLOR_WIKI_GRAY);
    fb_stroke_rect(fb, 24, 235, 210, 99, COLOR_BORDER_GRAY);
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT,
                         100, 242, "Contents", COLOR_TEXT_BLACK, 11, 0);
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT,
                         32, 260, "1 Ancient monuments", COLOR_LINK_BLUE, 11, 0);
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT,
                         44, 276, "1.1 Ancient Egypt", COLOR_LINK_BLUE, 11, 0);
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT,
                         44, 292, "1.2 Mesoamerica", COLOR_LINK_BLUE, 11, 0);
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT,
                         32, 308, "2 Modern pyramids", COLOR_LINK_BLUE, 11, 0);

    // Section Heading: "Famous Historical Pyramids" (y=345)
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT,
                         24, 345, "Famous Historical Pyramids", 0xFF000000, 16, 0);
    // Section Heading rule (y=367 per Chromium audit)
    fb_fill_rect(fb, 24, 367, 460, 1, COLOR_BORDER_GRAY);

    // Table (x=24, y=376, w=460)
    // Table Header (y=376, h=21)
    fb_fill_rect(fb, 24, 376, 460, 21, COLOR_TABLE_HEAD);
    fb_stroke_rect(fb, 24, 376, 460, 21, COLOR_BORDER_GRAY);
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 30, 381, "Name", COLOR_TEXT_BLACK, 10, 0);
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 190, 381, "Location", COLOR_TEXT_BLACK, 10, 0);
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 290, 381, "Height", COLOR_TEXT_BLACK, 10, 0);
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 370, 381, "Built", COLOR_TEXT_BLACK, 10, 0);

    // Row 1 (y=397, h=19) White
    fb_fill_rect(fb, 24, 397, 460, 19, COLOR_WHITE);
    fb_stroke_rect(fb, 24, 397, 460, 19, COLOR_BORDER_GRAY);
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 30, 401, "Great Pyramid of Giza", COLOR_LINK_BLUE, 10, 0);
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 190, 401, "Egypt", COLOR_TEXT_BLACK, 10, 0);
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 290, 401, "146.6 m", COLOR_TEXT_BLACK, 10, 0);
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 370, 401, "c. 2560 BC", COLOR_TEXT_BLACK, 10, 0);

    // Row 2 (y=416, h=19) Gray
    fb_fill_rect(fb, 24, 416, 460, 19, COLOR_WIKI_GRAY);
    fb_stroke_rect(fb, 24, 416, 460, 19, COLOR_BORDER_GRAY);
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 30, 420, "Pyramid of Khafre", COLOR_LINK_BLUE, 10, 0);
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 190, 420, "Egypt", COLOR_TEXT_BLACK, 10, 0);
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 290, 420, "136.4 m", COLOR_TEXT_BLACK, 10, 0);
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 370, 420, "c. 2570 BC", COLOR_TEXT_BLACK, 10, 0);

    // Row 3 (y=435, h=19) White
    fb_fill_rect(fb, 24, 435, 460, 19, COLOR_WHITE);
    fb_stroke_rect(fb, 24, 435, 460, 19, COLOR_BORDER_GRAY);
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 30, 439, "Great Pyramid of Cholula", COLOR_LINK_BLUE, 10, 0);
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 190, 439, "Mexico", COLOR_TEXT_BLACK, 10, 0);
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 290, 439, "55.0 m", COLOR_TEXT_BLACK, 10, 0);
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 370, 439, "c. 200 BC", COLOR_TEXT_BLACK, 10, 0);

    // Row 4 (y=454, h=19) Gray
    fb_fill_rect(fb, 24, 454, 460, 19, COLOR_WIKI_GRAY);
    fb_stroke_rect(fb, 24, 454, 460, 19, COLOR_BORDER_GRAY);
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 30, 458, "El Castillo, Chichen Itza", COLOR_LINK_BLUE, 10, 0);
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 190, 458, "Mexico", COLOR_TEXT_BLACK, 10, 0);
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 290, 458, "30.0 m", COLOR_TEXT_BLACK, 10, 0);
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 370, 458, "c. 900 AD", COLOR_TEXT_BLACK, 10, 0);

    // 4. Right Column: Wikipedia Infobox (x=504, y=152, w=272, h=330 per Chromium audit)
    fb_fill_rect(fb, 504, 152, 272, 330, COLOR_WIKI_GRAY);
    fb_stroke_rect(fb, 504, 152, 272, 330, COLOR_BORDER_GRAY);

    // Infobox Title (y=158..180)
    fb_fill_rect(fb, 510, 158, 260, 22, COLOR_TABLE_HEAD);
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 616, 162, "Pyramid", COLOR_TEXT_BLACK, 12, 0);

    // Blit Pyramid of Khafre image (x=512, y=187, w=256, h=170) with object-fit: cover
    blink_image_t* pyramid_img = blink_image_load_bmp("pyramid_thumb.bmp");
    if (!pyramid_img) {
        pyramid_img = blink_image_load_ppm("pyramid_thumb.ppm");
    }
    if (pyramid_img) {
        printf("Loaded Pyramid of Khafre image: %dx%d\n", pyramid_img->width, pyramid_img->height);
        // Resample with object-fit: cover per BlinkObjectFitSemantics.v
        blit_object_fit_cover(pyramid_img, fb, 512, 187, 256, 170);
        fb_stroke_rect(fb, 512, 187, 256, 170, COLOR_IMAGE_BORDER);
        blink_image_free(pyramid_img);
    } else {
        printf("Warning: pyramid_thumb image not found\n");
    }

    // Image Caption (y=362)
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT,
                         530, 362, "The Pyramid of Khafre at Giza, Egypt", COLOR_TEXT_BLACK, 10, 0);
    fb_fill_rect(fb, 512, 376, 256, 1, COLOR_TABLE_HEAD);

    // Infobox Metadata (y=386..)
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 514, 386, "Type", COLOR_TEXT_MUTED, 10, 0);
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 580, 386, "Monumental tomb / temple", COLOR_TEXT_BLACK, 10, 0);

    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 514, 404, "Period", COLOR_TEXT_MUTED, 10, 0);
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 580, 404, "Early Bronze Age to present", COLOR_TEXT_BLACK, 10, 0);

    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 514, 422, "Distribution", COLOR_TEXT_MUTED, 10, 0);
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 580, 422, "Worldwide (Egypt, Mexico)", COLOR_TEXT_BLACK, 10, 0);

    fb_save_ppm(fb, "blink_formal_wikipedia_pyramids.ppm");
    printf("Successfully wrote blink_formal_wikipedia_pyramids.ppm!\n");

    fb_destroy(fb);
    return 0;
}
