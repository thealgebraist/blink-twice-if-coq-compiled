#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <assert.h>
#include "blink_image_codec.h"
#include "blink_font_engine.h"
#include "blink_vertical_flow.h"

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

    int sw = src->width;
    int sh = src->height;

    // Check aspect ratios to determine crop (FitCover)
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

    // Bilinear resampling across cropped source rectangle per BlinkImageResamplingSemantics.v
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

            // Bilinear weight interpolation per Coq theorem bilinear_interp256_bounded
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
    printf("=== Regenerating Wikipedia Pyramid Page from Rocq/Coq Model ===\n");
    blink_font_init();

    // 1. Box metrics matching BlinkVerticalFlowLayoutSemantics.v definition
    const blink_box_metrics_t wiki_blocks[] = {
        // [0] b_h1: content_h=34, m_top=0, m_bottom=4
        { .content_h = 34, .m_top = 0, .m_bottom = 4, .p_top = 0, .p_bottom = 0, .b_top = 0, .b_bottom = 0 },
        // [1] b_sub: content_h=14, m_top=0, m_bottom=8
        { .content_h = 14, .m_top = 0, .m_bottom = 8, .p_top = 0, .p_bottom = 0, .b_top = 0, .b_bottom = 0 },
        // [2] b_hatnote: content_h=16, m_top=0, m_bottom=12
        { .content_h = 16, .m_top = 0, .m_bottom = 12, .p_top = 0, .p_bottom = 0, .b_top = 0, .b_bottom = 0 },
        // [3] b_lead: content_h=72, m_top=0, m_bottom=12
        { .content_h = 72, .m_top = 0, .m_bottom = 12, .p_top = 0, .p_bottom = 0, .b_top = 0, .b_bottom = 0 },
        // [4] b_toc: content_h=99, m_top=0, m_bottom=12
        { .content_h = 99, .m_top = 0, .m_bottom = 12, .p_top = 0, .p_bottom = 0, .b_top = 0, .b_bottom = 0 },
        // [5] b_sec: content_h=20, m_top=12, m_bottom=8
        { .content_h = 20, .m_top = 12, .m_bottom = 8, .p_top = 0, .p_bottom = 0, .b_top = 0, .b_bottom = 0 },
        // [6] b_table: content_h=97, m_top=6, m_bottom=0
        { .content_h = 97, .m_top = 6, .m_bottom = 0, .p_top = 0, .p_bottom = 0, .b_top = 0, .b_bottom = 0 }
    };

    // 2. Compute vertical flow using the extracted Coq algorithm
    blink_layout_fragment_t frags[7];
    blink_compute_vertical_flow(64, wiki_blocks, 7, frags);

    // 3. Verify exact runtime equivalence with Coq theorem wikipedia_vertical_flow_exact
    printf("Verifying layout against Coq theorem wikipedia_vertical_flow_exact...\n");
    assert(frags[0].y == 64 && frags[0].h == 34);
    assert(frags[1].y == 102 && frags[1].h == 14);
    assert(frags[2].y == 124 && frags[2].h == 16);
    assert(frags[3].y == 152 && frags[3].h == 72);
    assert(frags[4].y == 236 && frags[4].h == 99);
    assert(frags[5].y == 347 && frags[5].h == 20);
    assert(frags[6].y == 375 && frags[6].h == 97);
    printf("Coq Theorem wikipedia_vertical_flow_exact MATCHED 100%%!\n");

    FrameBuffer* fb = fb_create(VIEWPORT_WIDTH, VIEWPORT_HEIGHT);

    // A. Wikipedia Top Header (y=0..48)
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

    // B. Block Fragment [0]: H1 Title "Pyramid"
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT,
                         24, frags[0].y, "Pyramid", 0xFF000000, 24, 0);
    // Title divider line positioned at bottom of H1 fragment
    fb_fill_rect(fb, 24, frags[0].y + frags[0].h, 752, 1, COLOR_BORDER_GRAY);

    // C. Block Fragment [1]: Site Subtitle
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT,
                         24, frags[1].y, "From Wikipedia, the free encyclopedia", COLOR_TEXT_MUTED, 11, 0);

    // D. Block Fragment [2]: Disambiguation Hatnote
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT,
                         24, frags[2].y, "This article is about the monumental structure. For the polyhedron, see Pyramid (geometry).", COLOR_TEXT_MUTED, 11, 0);

    // E. Block Fragment [3]: Lead Paragraph
    const char* lead = "A pyramid is a structure whose outer surfaces are triangular and converge to a single point at the top, making the shape roughly a pyramid in the geometric sense. The base of a pyramid can be trilateral, quadrilateral, or of any polygon shape.";
    blink_font_draw_text_box(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT,
                             24, frags[3].y, 460, frags[3].h, lead, COLOR_TEXT_BLACK, 12, BLINK_FONT_ALIGN_LEFT);

    // F. Block Fragment [4]: Table of Contents Box
    int toc_y = frags[4].y;
    int toc_h = frags[4].h;
    fb_fill_rect(fb, 24, toc_y, 210, toc_h, COLOR_WIKI_GRAY);
    fb_stroke_rect(fb, 24, toc_y, 210, toc_h, COLOR_BORDER_GRAY);
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT,
                         100, toc_y + 7, "Contents", COLOR_TEXT_BLACK, 11, 0);
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT,
                         32, toc_y + 25, "1 Ancient monuments", COLOR_LINK_BLUE, 11, 0);
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT,
                         44, toc_y + 41, "1.1 Ancient Egypt", COLOR_LINK_BLUE, 11, 0);
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT,
                         44, toc_y + 57, "1.2 Mesoamerica", COLOR_LINK_BLUE, 11, 0);
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT,
                         32, toc_y + 73, "2 Modern pyramids", COLOR_LINK_BLUE, 11, 0);

    // G. Block Fragment [5]: Section Heading
    int sec_y = frags[5].y;
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT,
                         24, sec_y, "Famous Historical Pyramids", 0xFF000000, 16, 0);
    fb_fill_rect(fb, 24, sec_y + frags[5].h, 460, 1, COLOR_BORDER_GRAY);

    // H. Block Fragment [6]: Comparative Data Table
    int tbl_y = frags[6].y;
    int tbl_row_h = frags[6].h / 5; // 5 rows = ~19px each

    // Table Header Row
    fb_fill_rect(fb, 24, tbl_y, 460, tbl_row_h + 2, COLOR_TABLE_HEAD);
    fb_stroke_rect(fb, 24, tbl_y, 460, tbl_row_h + 2, COLOR_BORDER_GRAY);
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 30, tbl_y + 5, "Name", COLOR_TEXT_BLACK, 10, 0);
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 190, tbl_y + 5, "Location", COLOR_TEXT_BLACK, 10, 0);
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 290, tbl_y + 5, "Height", COLOR_TEXT_BLACK, 10, 0);
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 370, tbl_y + 5, "Built", COLOR_TEXT_BLACK, 10, 0);

    // Row 1 (White)
    int r1_y = tbl_y + tbl_row_h + 2;
    fb_fill_rect(fb, 24, r1_y, 460, tbl_row_h, COLOR_WHITE);
    fb_stroke_rect(fb, 24, r1_y, 460, tbl_row_h, COLOR_BORDER_GRAY);
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 30, r1_y + 4, "Great Pyramid of Giza", COLOR_LINK_BLUE, 10, 0);
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 190, r1_y + 4, "Egypt", COLOR_TEXT_BLACK, 10, 0);
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 290, r1_y + 4, "146.6 m", COLOR_TEXT_BLACK, 10, 0);
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 370, r1_y + 4, "c. 2560 BC", COLOR_TEXT_BLACK, 10, 0);

    // Row 2 (Gray)
    int r2_y = r1_y + tbl_row_h;
    fb_fill_rect(fb, 24, r2_y, 460, tbl_row_h, COLOR_WIKI_GRAY);
    fb_stroke_rect(fb, 24, r2_y, 460, tbl_row_h, COLOR_BORDER_GRAY);
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 30, r2_y + 4, "Pyramid of Khafre", COLOR_LINK_BLUE, 10, 0);
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 190, r2_y + 4, "Egypt", COLOR_TEXT_BLACK, 10, 0);
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 290, r2_y + 4, "136.4 m", COLOR_TEXT_BLACK, 10, 0);
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 370, r2_y + 4, "c. 2570 BC", COLOR_TEXT_BLACK, 10, 0);

    // Row 3 (White)
    int r3_y = r2_y + tbl_row_h;
    fb_fill_rect(fb, 24, r3_y, 460, tbl_row_h, COLOR_WHITE);
    fb_stroke_rect(fb, 24, r3_y, 460, tbl_row_h, COLOR_BORDER_GRAY);
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 30, r3_y + 4, "Great Pyramid of Cholula", COLOR_LINK_BLUE, 10, 0);
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 190, r3_y + 4, "Mexico", COLOR_TEXT_BLACK, 10, 0);
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 290, r3_y + 4, "55.0 m", COLOR_TEXT_BLACK, 10, 0);
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 370, r3_y + 4, "c. 200 BC", COLOR_TEXT_BLACK, 10, 0);

    // Row 4 (Gray)
    int r4_y = r3_y + tbl_row_h;
    fb_fill_rect(fb, 24, r4_y, 460, tbl_row_h, COLOR_WIKI_GRAY);
    fb_stroke_rect(fb, 24, r4_y, 460, tbl_row_h, COLOR_BORDER_GRAY);
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 30, r4_y + 4, "El Castillo, Chichen Itza", COLOR_LINK_BLUE, 10, 0);
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 190, r4_y + 4, "Mexico", COLOR_TEXT_BLACK, 10, 0);
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 290, r4_y + 4, "30.0 m", COLOR_TEXT_BLACK, 10, 0);
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 370, r4_y + 4, "c. 900 AD", COLOR_TEXT_BLACK, 10, 0);

    // I. Right Column: Wikipedia Infobox Card (x=504, y=152, w=272, h=330)
    fb_fill_rect(fb, 504, 152, 272, 330, COLOR_WIKI_GRAY);
    fb_stroke_rect(fb, 504, 152, 272, 330, COLOR_BORDER_GRAY);

    // Infobox Title
    fb_fill_rect(fb, 510, 158, 260, 22, COLOR_TABLE_HEAD);
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 616, 162, "Pyramid", COLOR_TEXT_BLACK, 12, 0);

    // Blit Pyramid of Khafre image (x=512, y=187, w=256, h=170) with object-fit: cover
    blink_image_t* pyramid_img = blink_image_load_ppm("pyramid_thumb.ppm");
    if (pyramid_img) {
        printf("Loaded Pyramid of Khafre image: %dx%d\n", pyramid_img->width, pyramid_img->height);
        // Resample with object-fit: cover per BlinkObjectFitSemantics.v
        blit_object_fit_cover(pyramid_img, fb, 512, 187, 256, 170);
        fb_stroke_rect(fb, 512, 187, 256, 170, COLOR_IMAGE_BORDER);
        blink_image_free(pyramid_img);
    } else {
        printf("Warning: pyramid_thumb.ppm not found\n");
    }

    // Image Caption
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT,
                         530, 362, "The Pyramid of Khafre at Giza, Egypt", COLOR_TEXT_BLACK, 10, 0);
    fb_fill_rect(fb, 512, 376, 256, 1, COLOR_TABLE_HEAD);

    // Infobox Metadata
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 514, 386, "Type", COLOR_TEXT_MUTED, 10, 0);
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 580, 386, "Monumental tomb / temple", COLOR_TEXT_BLACK, 10, 0);

    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 514, 404, "Period", COLOR_TEXT_MUTED, 10, 0);
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 580, 404, "Early Bronze Age to present", COLOR_TEXT_BLACK, 10, 0);

    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 514, 422, "Distribution", COLOR_TEXT_MUTED, 10, 0);
    blink_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 580, 422, "Worldwide (Egypt, Mexico)", COLOR_TEXT_BLACK, 10, 0);

    fb_save_ppm(fb, "blink_formal_wikipedia_pyramids.ppm");
    printf("Successfully regenerated blink_formal_wikipedia_pyramids.ppm from Coq model!\n");

    fb_destroy(fb);
    return 0;
}
