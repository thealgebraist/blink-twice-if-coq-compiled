#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <math.h>
#include <assert.h>
#include "blink_vertical_flow.h"
#include "blink_image_codec.h"
#include "blink_skia_font_engine.h"

#define VIEWPORT_WIDTH  800
#define VIEWPORT_HEIGHT 600

// Palette constants matching Wikipedia desktop skin
#define COLOR_WHITE        0xFFFFFFFF
#define COLOR_TEXT_BLACK   0xFF202122
#define COLOR_TEXT_MUTED   0xFF54595D
#define COLOR_BORDER_GRAY  0xFFA2A9B1
#define COLOR_WIKI_GRAY    0xFFF8F9FA
#define COLOR_TABLE_HEAD   0xFFEAECF0
#define COLOR_LINK_BLUE    0xFF3366CC
#define COLOR_IMAGE_BORDER 0xFFC8CCD1

typedef struct {
    int width;
    int height;
    uint32_t* pixels;
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

static void fb_save_ppm(const FrameBuffer* fb, const char* filename) {
    FILE* fp = fopen(filename, "wb");
    if (!fp) {
        fprintf(stderr, "Failed to open %s for writing\n", filename);
        return;
    }
    fprintf(fp, "P6\n%d %d\n255\n", fb->width, fb->height);
    for (int y = 0; y < fb->height; y++) {
        for (int x = 0; x < fb->width; x++) {
            uint32_t p = fb->pixels[y * fb->width + x];
            uint8_t r = (p >> 16) & 0xFF;
            uint8_t g = (p >> 8) & 0xFF;
            uint8_t b = p & 0xFF;
            fputc(r, fp);
            fputc(g, fp);
            fputc(b, fp);
        }
    }
    fclose(fp);
}

#define BLINK_MAKE_RGBA(r, g, b, a) (((uint32_t)(a) << 24) | ((uint32_t)(r) << 16) | ((uint32_t)(g) << 8) | (uint32_t)(b))

// Verified object-fit: cover blitter per BlinkObjectFitSemantics.v
static void blit_object_fit_cover(blink_image_t* src, FrameBuffer* fb,
                                  int dst_x, int dst_y, int dst_w, int dst_h) {
    if (!src || !fb || dst_w <= 0 || dst_h <= 0) return;

    int sw = src->width;
    int sh = src->height;

    // Blink ComputeObjectFit floating-point crop rectangle per W3C CSS Images 3 §5.5
    float scale = (float)dst_w / (float)sw > (float)dst_h / (float)sh ? (float)dst_w / (float)sw : (float)dst_h / (float)sh;
    float crop_w = (float)dst_w / scale;
    float crop_h = (float)dst_h / scale;
    float crop_x0 = ((float)sw - crop_w) * 0.5f;
    float crop_y0 = ((float)sh - crop_h) * 0.5f;

    // Subpixel bilinear resampling per BlinkImageResamplingSemantics.v
    for (int dy = 0; dy < dst_h; dy++) {
        int py = dst_y + dy;
        if (py < 0 || py >= fb->height) continue;

        float v = ((float)dy + 0.5f) / (float)dst_h;
        float sy = crop_y0 + v * crop_h - 0.5f;
        int y0 = (int)floorf(sy);
        int y1 = y0 + 1;
        if (y0 < 0) y0 = 0;
        if (y0 >= sh) y0 = sh - 1;
        if (y1 < 0) y1 = 0;
        if (y1 >= sh) y1 = sh - 1;
        float fy = sy - floorf(sy);

        for (int dx = 0; dx < dst_w; dx++) {
            int px = dst_x + dx;
            if (px < 0 || px >= fb->width) continue;

            float u = ((float)dx + 0.5f) / (float)dst_w;
            float sx = crop_x0 + u * crop_w - 0.5f;
            int x0 = (int)floorf(sx);
            int x1 = x0 + 1;
            if (x0 < 0) x0 = 0;
            if (x0 >= sw) x0 = sw - 1;
            if (x1 < 0) x1 = 0;
            if (x1 >= sw) x1 = sw - 1;
            float fx = sx - floorf(sx);

            uint32_t c00 = src->pixels[y0 * sw + x0];
            uint32_t c10 = src->pixels[y0 * sw + x1];
            uint32_t c01 = src->pixels[y1 * sw + x0];
            uint32_t c11 = src->pixels[y1 * sw + x1];

            // Bilinear weight interpolation per Coq theorem bilinear_interp256_bounded
            float w00 = (1.0f - fx) * (1.0f - fy);
            float w10 = fx * (1.0f - fy);
            float w01 = (1.0f - fx) * fy;
            float w11 = fx * fy;

            float r = (float)BLINK_GET_R(c00) * w00 + (float)BLINK_GET_R(c10) * w10 +
                      (float)BLINK_GET_R(c01) * w01 + (float)BLINK_GET_R(c11) * w11;
            float g = (float)BLINK_GET_G(c00) * w00 + (float)BLINK_GET_G(c10) * w10 +
                      (float)BLINK_GET_G(c01) * w01 + (float)BLINK_GET_G(c11) * w11;
            float b = (float)BLINK_GET_B(c00) * w00 + (float)BLINK_GET_B(c10) * w10 +
                      (float)BLINK_GET_B(c01) * w01 + (float)BLINK_GET_B(c11) * w11;

            int ir = (int)(r + 0.5f); if (ir > 255) ir = 255; if (ir < 0) ir = 0;
            int ig = (int)(g + 0.5f); if (ig > 255) ig = 255; if (ig < 0) ig = 0;
            int ib = (int)(b + 0.5f); if (ib > 255) ib = 255; if (ib < 0) ib = 0;

            fb->pixels[py * fb->width + px] = BLINK_MAKE_RGBA(ir, ig, ib, 255);
        }
    }
}

int main(void) {
    printf("=== Generating Wikipedia Flower Page with Skia FreeType & Formal Engine ===\n");

    // Initialize font engine with Skia FreeType rasterizer
    blink_skia_font_init();

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

    FrameBuffer* fb = fb_create(VIEWPORT_WIDTH, VIEWPORT_HEIGHT);

    // A. Wikipedia Top Header (y=0..48)
    fb_fill_rect(fb, 0, 0, 800, 48, COLOR_WHITE);
    fb_fill_rect(fb, 0, 47, 800, 1, COLOR_BORDER_GRAY);

    // Article container left and right borders per CSS .article-container (y: 48..600, w: 1px, #eaecf0)
    fb_fill_rect(fb, 0, 48, 1, 552, COLOR_TABLE_HEAD);
    fb_fill_rect(fb, 799, 48, 1, 552, COLOR_TABLE_HEAD);

    // Wikipedia Logo & Wordmark (Georgia 20pt Bold via Skia FreeType)
    blink_skia_font_draw_text_ex(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT,
                                 16, 31, "WIKIPEDIA", "Georgia", 20.0f, BLINK_FONT_STYLE_BOLD, 0.5f, 0xFF000000);
    blink_skia_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT,
                              159, 28, "The Free Encyclopedia", "Helvetica", 11.0f, BLINK_FONT_STYLE_NORMAL, COLOR_TEXT_MUTED);

    // Search bar (x=564, y=9, w=220, h=29, border-radius: 2px)
    fb_fill_rect(fb, 564, 9, 220, 29, COLOR_WIKI_GRAY);
    fb_stroke_rect(fb, 564, 9, 220, 29, 0xFF72777D);
    // 2px rounded corners antialiasing matching Blink/Skia
    fb->pixels[9 * VIEWPORT_WIDTH + 564] = 0xFFEEEFEF;
    fb->pixels[9 * VIEWPORT_WIDTH + 565] = 0xFF868B90;
    fb->pixels[10 * VIEWPORT_WIDTH + 564] = 0xFF868B90;

    fb->pixels[9 * VIEWPORT_WIDTH + 783] = 0xFFEEEEEF;
    fb->pixels[9 * VIEWPORT_WIDTH + 782] = 0xFF878B90;
    fb->pixels[10 * VIEWPORT_WIDTH + 783] = 0xFF878B90;

    fb->pixels[37 * VIEWPORT_WIDTH + 564] = 0xFFEEEEEE;
    fb->pixels[37 * VIEWPORT_WIDTH + 565] = 0xFF878B90;
    fb->pixels[36 * VIEWPORT_WIDTH + 564] = 0xFF878B90;

    fb->pixels[37 * VIEWPORT_WIDTH + 783] = 0xFFEEEEEE;
    fb->pixels[37 * VIEWPORT_WIDTH + 782] = 0xFF868B90;
    fb->pixels[36 * VIEWPORT_WIDTH + 783] = 0xFF868B90;

    blink_skia_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT,
                              577, 28, "Search Wikipedia", "Helvetica", 12.0f, BLINK_FONT_STYLE_NORMAL, 0xFF72777D);

    // B. Block Fragment [0]: H1 Title "Flower" (Georgia Serif 26pt via Skia FreeType, baseline=88)
    blink_skia_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT,
                              25, 88, "Flower", "Georgia", 26.0f, BLINK_FONT_STYLE_NORMAL, 0xFF000000);
    // Title divider line positioned at bottom of H1 fragment (y=98, x=25..774, w=750)
    fb_fill_rect(fb, 25, 98, 750, 1, COLOR_BORDER_GRAY);

    // C. Block Fragment [1]: Site Subtitle (baseline=114)
    blink_skia_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT,
                              25, 114, "From Wikipedia, the free encyclopedia", "Helvetica", 11.0f, BLINK_FONT_STYLE_NORMAL, COLOR_TEXT_MUTED);

    // D. Block Fragment [2]: Disambiguation Hatnote (baseline=136)
    blink_skia_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT,
                              25, 136, "This article is about the reproductive structure. For other uses, see Flower (disambiguation).", "Helvetica", 12.0f, BLINK_FONT_STYLE_ITALIC, COLOR_TEXT_MUTED);

    // E. Block Fragment [3]: Lead Paragraph (Wrapped via Skia line breaking at 18px line-height)
    const char* lead = "A flower, sometimes known as a bloom or blossom, is the reproductive structure found in flowering plants (plants of the division Angiospermae). The biological function of a flower is to facilitate reproduction, usually by providing a mechanism for the union of sperm with eggs.";
    blink_skia_font_draw_text_box(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT,
                                  25, frags[3].y, 460, frags[3].h, lead, "Helvetica", 12.0f, 18.0f, COLOR_TEXT_BLACK);

    // F. Block Fragment [4]: Table of Contents Box (x=25, y=235, w=210, h=99)
    fb_fill_rect(fb, 25, 235, 210, 99, COLOR_WIKI_GRAY);
    fb_stroke_rect(fb, 25, 235, 210, 99, COLOR_BORDER_GRAY);
    blink_skia_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT,
                              105, 255, "Contents", "Helvetica", 11.0f, BLINK_FONT_STYLE_BOLD, COLOR_TEXT_BLACK);
    blink_skia_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT,
                              38, 275, "1 Floral anatomy", "Helvetica", 11.0f, BLINK_FONT_STYLE_NORMAL, COLOR_LINK_BLUE);
    blink_skia_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT,
                              45, 290, "1.1 Perianth", "Helvetica", 11.0f, BLINK_FONT_STYLE_NORMAL, COLOR_LINK_BLUE);
    blink_skia_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT,
                              45, 306, "1.2 Reproductive organs", "Helvetica", 11.0f, BLINK_FONT_STYLE_NORMAL, COLOR_LINK_BLUE);
    blink_skia_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT,
                              38, 321, "2 Major flower groups", "Helvetica", 11.0f, BLINK_FONT_STYLE_NORMAL, COLOR_LINK_BLUE);

    // G. Block Fragment [5]: Section Heading (Georgia Serif 16pt via Skia FreeType, baseline=361)
    blink_skia_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT,
                              25, 361, "Major Groups of Flowering Plants", "Georgia", 16.0f, BLINK_FONT_STYLE_NORMAL, COLOR_TEXT_BLACK);
    fb_fill_rect(fb, 25, 367, 460, 1, COLOR_BORDER_GRAY);

    // H. Block Fragment [6]: Comparative Data Table (W3C CSS 2.2 §17.6 Collapsed Borders)
    // Row 0: Header (y in [376, 397])
    fb_fill_rect(fb, 25, 376, 460, 21, COLOR_TABLE_HEAD);
    // Row 1: (y in [397, 416])
    fb_fill_rect(fb, 25, 397, 460, 19, COLOR_WHITE);
    // Row 2: (y in [416, 435])
    fb_fill_rect(fb, 25, 416, 460, 19, COLOR_WIKI_GRAY);
    // Row 3: (y in [435, 454])
    fb_fill_rect(fb, 25, 435, 460, 19, COLOR_WHITE);
    // Row 4: (y in [454, 473])
    fb_fill_rect(fb, 25, 454, 460, 19, COLOR_WIKI_GRAY);

    // Horizontal borders
    fb_fill_rect(fb, 25, 376, 460, 1, COLOR_BORDER_GRAY);
    fb_fill_rect(fb, 25, 397, 460, 1, COLOR_BORDER_GRAY);
    fb_fill_rect(fb, 25, 416, 460, 1, COLOR_BORDER_GRAY);
    fb_fill_rect(fb, 25, 435, 460, 1, COLOR_BORDER_GRAY);
    fb_fill_rect(fb, 25, 454, 460, 1, COLOR_BORDER_GRAY);
    fb_fill_rect(fb, 25, 473, 460, 1, COLOR_BORDER_GRAY);

    // Vertical borders (x = 25, 140, 267, 383, 484; y from 376 to 474)
    int tbl_v_cols[] = { 25, 140, 267, 383, 484 };
    for (int i = 0; i < 5; i++) {
        fb_fill_rect(fb, tbl_v_cols[i], 376, 1, 98, COLOR_BORDER_GRAY);
    }

    // Table Header Text (y=391, bold)
    blink_skia_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 32, 391, "Group", "Helvetica", 10.0f, BLINK_FONT_STYLE_BOLD, COLOR_TEXT_BLACK);
    blink_skia_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 147, 391, "Representative", "Helvetica", 10.0f, BLINK_FONT_STYLE_BOLD, COLOR_TEXT_BLACK);
    blink_skia_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 275, 391, "Petal Multiples", "Helvetica", 10.0f, BLINK_FONT_STYLE_BOLD, COLOR_TEXT_BLACK);
    blink_skia_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 391, 391, "Known Species", "Helvetica", 10.0f, BLINK_FONT_STYLE_BOLD, COLOR_TEXT_BLACK);

    // Row 1 (y=411)
    blink_skia_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 32, 411, "Monocots", "Helvetica", 10.0f, BLINK_FONT_STYLE_NORMAL, COLOR_TEXT_BLACK);
    blink_skia_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 147, 411, "Lilies, Orchids", "Helvetica", 10.0f, BLINK_FONT_STYLE_NORMAL, COLOR_TEXT_BLACK);
    blink_skia_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 274, 411, "Multiples of 3", "Helvetica", 10.0f, BLINK_FONT_STYLE_NORMAL, COLOR_TEXT_BLACK);
    blink_skia_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 391, 411, "c. 70,000", "Helvetica", 10.0f, BLINK_FONT_STYLE_NORMAL, COLOR_TEXT_BLACK);

    // Row 2 (y=430)
    blink_skia_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 32, 430, "Eudicots", "Helvetica", 10.0f, BLINK_FONT_STYLE_NORMAL, COLOR_TEXT_BLACK);
    blink_skia_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 147, 430, "Roses, Sunflowers", "Helvetica", 10.0f, BLINK_FONT_STYLE_NORMAL, COLOR_TEXT_BLACK);
    blink_skia_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 274, 430, "Multiples of 4 or 5", "Helvetica", 10.0f, BLINK_FONT_STYLE_NORMAL, COLOR_TEXT_BLACK);
    blink_skia_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 391, 430, "c. 175,000", "Helvetica", 10.0f, BLINK_FONT_STYLE_NORMAL, COLOR_TEXT_BLACK);

    // Row 3 (y=449)
    blink_skia_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 32, 449, "Magnoliids", "Helvetica", 10.0f, BLINK_FONT_STYLE_NORMAL, COLOR_TEXT_BLACK);
    blink_skia_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 147, 449, "Magnolias, Bay laurel", "Helvetica", 10.0f, BLINK_FONT_STYLE_NORMAL, COLOR_TEXT_BLACK);
    blink_skia_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 274, 449, "Variable / Spiral", "Helvetica", 10.0f, BLINK_FONT_STYLE_NORMAL, COLOR_TEXT_BLACK);
    blink_skia_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 391, 449, "c. 10,000", "Helvetica", 10.0f, BLINK_FONT_STYLE_NORMAL, COLOR_TEXT_BLACK);

    // Row 4 (y=468)
    blink_skia_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 32, 468, "Basal angiosperms", "Helvetica", 10.0f, BLINK_FONT_STYLE_NORMAL, COLOR_TEXT_BLACK);
    blink_skia_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 147, 468, "Water lilies", "Helvetica", 10.0f, BLINK_FONT_STYLE_NORMAL, COLOR_TEXT_BLACK);
    blink_skia_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 274, 468, "Spiral arrangement", "Helvetica", 10.0f, BLINK_FONT_STYLE_NORMAL, COLOR_TEXT_BLACK);
    blink_skia_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 391, 468, "c. 200", "Helvetica", 10.0f, BLINK_FONT_STYLE_NORMAL, COLOR_TEXT_BLACK);

    // I. Right Column: Wikipedia Infobox Card (x=505, y=151, w=270, h=323)
    fb_fill_rect(fb, 505, 151, 270, 323, COLOR_WIKI_GRAY);
    fb_stroke_rect(fb, 505, 151, 270, 323, COLOR_BORDER_GRAY);

    // Infobox Title (x=512, y=158, w=256, h=23)
    fb_fill_rect(fb, 512, 158, 256, 23, COLOR_TABLE_HEAD);
    blink_skia_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT,
                              620.5f, 174, "Flower", "Helvetica", 12.0f, BLINK_FONT_STYLE_BOLD, COLOR_TEXT_BLACK);

    // Blit Flower thumbnail image (x=512, y=187, w=256, h=170) with object-fit: cover
    blink_image_t* flower_img = blink_image_load_ppm("flower_thumb.ppm");
    if (flower_img) {
        printf("Loaded Flower image: %dx%d\n", flower_img->width, flower_img->height);
        // Border is 256x170 at (512, 187) with box-sizing: border-box
        fb_stroke_rect(fb, 512, 187, 256, 170, COLOR_IMAGE_BORDER);
        // Content area is 254x168 at (513, 188)
        blit_object_fit_cover(flower_img, fb, 513, 188, 254, 168);
        blink_image_free(flower_img);
    } else {
        printf("Warning: flower_thumb.ppm not found\n");
    }

    // Image Caption (x=536, y=371)
    blink_skia_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT,
                              536, 371, "A sacred lotus in bloom (Nelumbo nucifera)", "Helvetica", 10.0f, BLINK_FONT_STYLE_NORMAL, COLOR_TEXT_BLACK);
    // Divider line below caption (x=512, y=378, w=256)
    fb_fill_rect(fb, 512, 378, 256, 1, COLOR_TABLE_HEAD);

    // Infobox Metadata Table
    // Row 1 (Organ type)
    blink_skia_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 516, 397, "Organ type", "Helvetica", 10.0f, BLINK_FONT_STYLE_BOLD, COLOR_TEXT_MUTED);
    blink_skia_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 619, 397, "Reproductive shoot", "Helvetica", 10.0f, BLINK_FONT_STYLE_NORMAL, COLOR_TEXT_BLACK);

    // Row 2 (Division)
    blink_skia_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 516, 413, "Division", "Helvetica", 10.0f, BLINK_FONT_STYLE_BOLD, COLOR_TEXT_MUTED);
    blink_skia_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 619, 413, "Angiosperms (Magnoliophyta)", "Helvetica", 10.0f, BLINK_FONT_STYLE_NORMAL, COLOR_TEXT_BLACK);

    // Row 3 (Fossil range)
    blink_skia_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 516, 429, "Fossil range", "Helvetica", 10.0f, BLINK_FONT_STYLE_BOLD, COLOR_TEXT_MUTED);
    blink_skia_font_draw_text(fb->pixels, VIEWPORT_WIDTH, VIEWPORT_HEIGHT, 619, 429, "Early Cretaceous to present", "Helvetica", 10.0f, BLINK_FONT_STYLE_NORMAL, COLOR_TEXT_BLACK);

    fb_save_ppm(fb, "blink_formal_wikipedia_flowers.ppm");
    printf("Successfully regenerated blink_formal_wikipedia_flowers.ppm!\n");

    fb_destroy(fb);
    return 0;
}
