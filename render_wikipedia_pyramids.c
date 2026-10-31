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
    printf("=== Rendering Wikipedia Pyramid Article with Coq-Verified Engine ===\n");
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
    // Title "Pyramid" (x=24, y=60)
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT,
                         24, 60, "Pyramid", 0xFF000000, 24, 0);
    // Title rule
    fb_fill_rect(fb, 24, 96, 752, 1, COLOR_BORDER_GRAY);

    // Subtitle & Hatnote
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT,
                         24, 102, "From Wikipedia, the free encyclopedia", COLOR_TEXT_MUTED, 11, 0);
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT,
                         24, 118, "This article is about the monumental structure. For the polyhedron, see Pyramid (geometry).", COLOR_TEXT_MUTED, 11, 0);

    // 3. Left Article Body (x=24, w=460)
    // Lead paragraph
    const char* lead = "A pyramid is a structure whose outer surfaces are triangular and converge to a single point at the top, making the shape roughly a pyramid in the geometric sense. The base of a pyramid can be trilateral, quadrilateral, or of any polygon shape.";
    blink_font_draw_text_box(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT,
                             24, 136, 460, 50, lead, COLOR_TEXT_BLACK, 12, BLINK_FONT_ALIGN_LEFT);

    // Table of Contents Box (x=24, y=196, w=210, h=100)
    fb_fill_rect(fb, 24, 196, 210, 100, COLOR_WIKI_GRAY);
    fb_stroke_rect(fb, 24, 196, 210, 100, COLOR_BORDER_GRAY);
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT,
                         100, 202, "Contents", COLOR_TEXT_BLACK, 11, 0);
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT,
                         32, 220, "1 Ancient monuments", COLOR_LINK_BLUE, 11, 0);
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT,
                         44, 236, "1.1 Ancient Egypt", COLOR_LINK_BLUE, 11, 0);
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT,
                         44, 252, "1.2 Mesoamerica", COLOR_LINK_BLUE, 11, 0);
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT,
                         32, 268, "2 Modern pyramids", COLOR_LINK_BLUE, 11, 0);

    // Section Heading: "Famous Historical Pyramids" (y=306)
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT,
                         24, 306, "Famous Historical Pyramids", 0xFF000000, 16, 0);
    fb_fill_rect(fb, 24, 330, 460, 1, COLOR_BORDER_GRAY);

    // Table (x=24, y=340, w=460)
    // Table Header (y=340, h=24)
    fb_fill_rect(fb, 24, 340, 460, 24, COLOR_TABLE_HEAD);
    fb_stroke_rect(fb, 24, 340, 460, 24, COLOR_BORDER_GRAY);
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 30, 346, "Name", COLOR_TEXT_BLACK, 10, 0);
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 190, 346, "Location", COLOR_TEXT_BLACK, 10, 0);
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 290, 346, "Height", COLOR_TEXT_BLACK, 10, 0);
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 370, 346, "Built", COLOR_TEXT_BLACK, 10, 0);

    // Row 1 (y=364, h=22) White
    fb_fill_rect(fb, 24, 364, 460, 22, COLOR_WHITE);
    fb_stroke_rect(fb, 24, 364, 460, 22, COLOR_BORDER_GRAY);
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 30, 369, "Great Pyramid of Giza", COLOR_LINK_BLUE, 10, 0);
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 190, 369, "Egypt", COLOR_TEXT_BLACK, 10, 0);
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 290, 369, "146.6 m", COLOR_TEXT_BLACK, 10, 0);
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 370, 369, "c. 2560 BC", COLOR_TEXT_BLACK, 10, 0);

    // Row 2 (y=386, h=22) Gray
    fb_fill_rect(fb, 24, 386, 460, 22, COLOR_WIKI_GRAY);
    fb_stroke_rect(fb, 24, 386, 460, 22, COLOR_BORDER_GRAY);
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 30, 391, "Pyramid of Khafre", COLOR_LINK_BLUE, 10, 0);
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 190, 391, "Egypt", COLOR_TEXT_BLACK, 10, 0);
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 290, 391, "136.4 m", COLOR_TEXT_BLACK, 10, 0);
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 370, 391, "c. 2570 BC", COLOR_TEXT_BLACK, 10, 0);

    // Row 3 (y=408, h=22) White
    fb_fill_rect(fb, 24, 408, 460, 22, COLOR_WHITE);
    fb_stroke_rect(fb, 24, 408, 460, 22, COLOR_BORDER_GRAY);
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 30, 413, "Great Pyramid of Cholula", COLOR_LINK_BLUE, 10, 0);
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 190, 413, "Mexico", COLOR_TEXT_BLACK, 10, 0);
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 290, 413, "55.0 m", COLOR_TEXT_BLACK, 10, 0);
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 370, 413, "c. 200 BC", COLOR_TEXT_BLACK, 10, 0);

    // Row 4 (y=430, h=22) Gray
    fb_fill_rect(fb, 24, 430, 460, 22, COLOR_WIKI_GRAY);
    fb_stroke_rect(fb, 24, 430, 460, 22, COLOR_BORDER_GRAY);
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 30, 435, "El Castillo, Chichen Itza", COLOR_LINK_BLUE, 10, 0);
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 190, 435, "Mexico", COLOR_TEXT_BLACK, 10, 0);
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 290, 435, "30.0 m", COLOR_TEXT_BLACK, 10, 0);
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 370, 435, "c. 900 AD", COLOR_TEXT_BLACK, 10, 0);

    // 4. Right Column: Wikipedia Infobox (x=504, y=136, w=272, h=330)
    fb_fill_rect(fb, 504, 136, 272, 330, COLOR_WIKI_GRAY);
    fb_stroke_rect(fb, 504, 136, 272, 330, COLOR_BORDER_GRAY);

    // Infobox Title
    fb_fill_rect(fb, 510, 142, 260, 22, COLOR_TABLE_HEAD);
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 616, 146, "Pyramid", COLOR_TEXT_BLACK, 12, 0);

    // Blit Pyramid of Khafre image (x=512, y=168, w=256, h=170)
    blink_image_t* pyramid_img = blink_image_load_ppm("pyramid_thumb.ppm");
    if (pyramid_img) {
        printf("Loaded Pyramid of Khafre image: %dx%d\n", pyramid_img->width, pyramid_img->height);
        // Resample with Bilinear Filtering per Coq theorem bilinear_interp256_bounded
        blink_image_blit_bilinear(pyramid_img, fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 512, 168, 256, 170);
        fb_stroke_rect(fb, 512, 168, 256, 170, COLOR_IMAGE_BORDER);
        blink_image_free(pyramid_img);
    } else {
        printf("Warning: pyramid_thumb.ppm not found\n");
    }

    // Image Caption
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT,
                         530, 344, "The Pyramid of Khafre at Giza, Egypt", COLOR_TEXT_BLACK, 10, 0);
    fb_fill_rect(fb, 512, 358, 256, 1, COLOR_TABLE_HEAD);

    // Infobox Metadata
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 514, 368, "Type", COLOR_TEXT_MUTED, 10, 0);
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 580, 368, "Monumental tomb / temple", COLOR_TEXT_BLACK, 10, 0);

    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 514, 386, "Period", COLOR_TEXT_MUTED, 10, 0);
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 580, 386, "Early Bronze Age to present", COLOR_TEXT_BLACK, 10, 0);

    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 514, 404, "Distribution", COLOR_TEXT_MUTED, 10, 0);
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 580, 404, "Worldwide (Egypt, Mexico)", COLOR_TEXT_BLACK, 10, 0);

    fb_save_ppm(fb, "blink_formal_wikipedia_pyramids.ppm");
    printf("Successfully wrote blink_formal_wikipedia_pyramids.ppm!\n");

    fb_destroy(fb);
    return 0;
}
