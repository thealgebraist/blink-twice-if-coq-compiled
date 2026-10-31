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
#define PAGE_HEIGHT     600
#define FULL_HEIGHT     1800

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

    float scale = (float)dst_w / (float)sw > (float)dst_h / (float)sh ? (float)dst_w / (float)sw : (float)dst_h / (float)sh;
    float crop_w = (float)dst_w / scale;
    float crop_h = (float)dst_h / scale;
    float crop_x0 = ((float)sw - crop_w) * 0.5f;
    float crop_y0 = ((float)sh - crop_h) * 0.5f;

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

// ----------------------------------------------------------------------------
// Render Page 1 (Overview, Infobox, Contents, Clades)
// ----------------------------------------------------------------------------
static void render_flower_page_1(FrameBuffer* fb, int base_y) {
    // 1. Box metrics matching BlinkVerticalFlowLayoutSemantics.v definition
    const blink_box_metrics_t wiki_blocks[] = {
        { .content_h = 34, .m_top = 0, .m_bottom = 4, .p_top = 0, .p_bottom = 0, .b_top = 0, .b_bottom = 0 },
        { .content_h = 14, .m_top = 0, .m_bottom = 8, .p_top = 0, .p_bottom = 0, .b_top = 0, .b_bottom = 0 },
        { .content_h = 16, .m_top = 0, .m_bottom = 12, .p_top = 0, .p_bottom = 0, .b_top = 0, .b_bottom = 0 },
        { .content_h = 72, .m_top = 0, .m_bottom = 12, .p_top = 0, .p_bottom = 0, .b_top = 0, .b_bottom = 0 },
        { .content_h = 99, .m_top = 0, .m_bottom = 12, .p_top = 0, .p_bottom = 0, .b_top = 0, .b_bottom = 0 },
        { .content_h = 20, .m_top = 12, .m_bottom = 8, .p_top = 0, .p_bottom = 0, .b_top = 0, .b_bottom = 0 },
        { .content_h = 97, .m_top = 6, .m_bottom = 0, .p_top = 0, .p_bottom = 0, .b_top = 0, .b_bottom = 0 }
    };
    blink_layout_fragment_t frags[7];
    blink_compute_vertical_flow(base_y + 64, wiki_blocks, 7, frags);

    // Header
    fb_fill_rect(fb, 0, base_y, 800, 48, COLOR_WHITE);
    fb_fill_rect(fb, 0, base_y + 47, 800, 1, COLOR_BORDER_GRAY);

    // Article container borders
    fb_fill_rect(fb, 0, base_y + 48, 1, 552, COLOR_TABLE_HEAD);
    fb_fill_rect(fb, 799, base_y + 48, 1, 552, COLOR_TABLE_HEAD);

    // Wikipedia Logo & Wordmark (Georgia 20pt Bold via Skia FreeType)
    blink_skia_font_draw_text_ex(fb->pixels, fb->width, fb->height,
                                 16, base_y + 31, "WIKIPEDIA", "Georgia", 20.0f, BLINK_FONT_STYLE_BOLD, 0.5f, 0xFF000000);
    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height,
                              159, base_y + 28, "The Free Encyclopedia", "Helvetica", 11.0f, BLINK_FONT_STYLE_NORMAL, COLOR_TEXT_MUTED);

    // Search bar
    fb_fill_rect(fb, 564, base_y + 9, 220, 29, COLOR_WIKI_GRAY);
    fb_stroke_rect(fb, 564, base_y + 9, 220, 29, 0xFF72777D);
    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height,
                              577, base_y + 28, "Search Wikipedia", "Helvetica", 12.0f, BLINK_FONT_STYLE_NORMAL, 0xFF72777D);

    // H1 Title
    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height,
                              25, base_y + 88, "Flower", "Georgia", 26.0f, BLINK_FONT_STYLE_NORMAL, 0xFF000000);
    fb_fill_rect(fb, 25, base_y + 98, 750, 1, COLOR_BORDER_GRAY);

    // Subtitle & Hatnote
    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height,
                              25, base_y + 114, "From Wikipedia, the free encyclopedia", "Helvetica", 11.0f, BLINK_FONT_STYLE_NORMAL, COLOR_TEXT_MUTED);
    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height,
                              25, base_y + 136, "This article is about the reproductive structure. For other uses, see Flower (disambiguation).", "Helvetica", 12.0f, BLINK_FONT_STYLE_ITALIC, COLOR_TEXT_MUTED);

    // Lead paragraph
    const char* lead = "A flower, sometimes known as a bloom or blossom, is the reproductive structure found in flowering plants (plants of the division Angiospermae). The biological function of a flower is to facilitate reproduction, usually by providing a mechanism for the union of sperm with eggs.";
    blink_skia_font_draw_text_box(fb->pixels, fb->width, fb->height,
                                  25, frags[3].y, 460, frags[3].h, lead, "Helvetica", 12.0f, 18.0f, COLOR_TEXT_BLACK);

    // TOC
    fb_fill_rect(fb, 25, base_y + 235, 210, 99, COLOR_WIKI_GRAY);
    fb_stroke_rect(fb, 25, base_y + 235, 210, 99, COLOR_BORDER_GRAY);
    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height, 105, base_y + 255, "Contents", "Helvetica", 11.0f, BLINK_FONT_STYLE_BOLD, COLOR_TEXT_BLACK);
    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height, 38, base_y + 275, "1 Floral anatomy", "Helvetica", 11.0f, BLINK_FONT_STYLE_NORMAL, COLOR_LINK_BLUE);
    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height, 45, base_y + 290, "1.1 Perianth", "Helvetica", 11.0f, BLINK_FONT_STYLE_NORMAL, COLOR_LINK_BLUE);
    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height, 45, base_y + 306, "1.2 Reproductive organs", "Helvetica", 11.0f, BLINK_FONT_STYLE_NORMAL, COLOR_LINK_BLUE);
    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height, 38, base_y + 321, "2 Major flower groups", "Helvetica", 11.0f, BLINK_FONT_STYLE_NORMAL, COLOR_LINK_BLUE);

    // H2 Section Heading
    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height,
                              25, base_y + 361, "Major Groups of Flowering Plants", "Georgia", 16.0f, BLINK_FONT_STYLE_NORMAL, COLOR_TEXT_BLACK);
    fb_fill_rect(fb, 25, base_y + 367, 460, 1, COLOR_BORDER_GRAY);

    // Table
    fb_fill_rect(fb, 25, base_y + 376, 460, 21, COLOR_TABLE_HEAD);
    fb_fill_rect(fb, 25, base_y + 397, 460, 19, COLOR_WHITE);
    fb_fill_rect(fb, 25, base_y + 416, 460, 19, COLOR_WIKI_GRAY);
    fb_fill_rect(fb, 25, base_y + 435, 460, 19, COLOR_WHITE);
    fb_fill_rect(fb, 25, base_y + 454, 460, 19, COLOR_WIKI_GRAY);

    fb_fill_rect(fb, 25, base_y + 376, 460, 1, COLOR_BORDER_GRAY);
    fb_fill_rect(fb, 25, base_y + 397, 460, 1, COLOR_BORDER_GRAY);
    fb_fill_rect(fb, 25, base_y + 416, 460, 1, COLOR_BORDER_GRAY);
    fb_fill_rect(fb, 25, base_y + 435, 460, 1, COLOR_BORDER_GRAY);
    fb_fill_rect(fb, 25, base_y + 454, 460, 1, COLOR_BORDER_GRAY);
    fb_fill_rect(fb, 25, base_y + 473, 460, 1, COLOR_BORDER_GRAY);

    int tbl_v_cols[] = { 25, 140, 267, 383, 484 };
    for (int i = 0; i < 5; i++) {
        fb_fill_rect(fb, tbl_v_cols[i], base_y + 376, 1, 98, COLOR_BORDER_GRAY);
    }

    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height, 32, base_y + 391, "Group", "Helvetica", 10.0f, BLINK_FONT_STYLE_BOLD, COLOR_TEXT_BLACK);
    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height, 147, base_y + 391, "Representative", "Helvetica", 10.0f, BLINK_FONT_STYLE_BOLD, COLOR_TEXT_BLACK);
    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height, 275, base_y + 391, "Petal Multiples", "Helvetica", 10.0f, BLINK_FONT_STYLE_BOLD, COLOR_TEXT_BLACK);
    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height, 391, base_y + 391, "Known Species", "Helvetica", 10.0f, BLINK_FONT_STYLE_BOLD, COLOR_TEXT_BLACK);

    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height, 32, base_y + 411, "Monocots", "Helvetica", 10.0f, BLINK_FONT_STYLE_NORMAL, COLOR_TEXT_BLACK);
    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height, 147, base_y + 411, "Lilies, Orchids", "Helvetica", 10.0f, BLINK_FONT_STYLE_NORMAL, COLOR_TEXT_BLACK);
    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height, 274, base_y + 411, "Multiples of 3", "Helvetica", 10.0f, BLINK_FONT_STYLE_NORMAL, COLOR_TEXT_BLACK);
    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height, 391, base_y + 411, "c. 70,000", "Helvetica", 10.0f, BLINK_FONT_STYLE_NORMAL, COLOR_TEXT_BLACK);

    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height, 32, base_y + 430, "Eudicots", "Helvetica", 10.0f, BLINK_FONT_STYLE_NORMAL, COLOR_TEXT_BLACK);
    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height, 147, base_y + 430, "Roses, Sunflowers", "Helvetica", 10.0f, BLINK_FONT_STYLE_NORMAL, COLOR_TEXT_BLACK);
    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height, 274, base_y + 430, "Multiples of 4 or 5", "Helvetica", 10.0f, BLINK_FONT_STYLE_NORMAL, COLOR_TEXT_BLACK);
    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height, 391, base_y + 430, "c. 175,000", "Helvetica", 10.0f, BLINK_FONT_STYLE_NORMAL, COLOR_TEXT_BLACK);

    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height, 32, base_y + 449, "Magnoliids", "Helvetica", 10.0f, BLINK_FONT_STYLE_NORMAL, COLOR_TEXT_BLACK);
    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height, 147, base_y + 449, "Magnolias, Bay laurel", "Helvetica", 10.0f, BLINK_FONT_STYLE_NORMAL, COLOR_TEXT_BLACK);
    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height, 274, base_y + 449, "Variable / Spiral", "Helvetica", 10.0f, BLINK_FONT_STYLE_NORMAL, COLOR_TEXT_BLACK);
    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height, 391, base_y + 449, "c. 10,000", "Helvetica", 10.0f, BLINK_FONT_STYLE_NORMAL, COLOR_TEXT_BLACK);

    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height, 32, base_y + 468, "Basal angiosperms", "Helvetica", 10.0f, BLINK_FONT_STYLE_NORMAL, COLOR_TEXT_BLACK);
    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height, 147, base_y + 468, "Water lilies", "Helvetica", 10.0f, BLINK_FONT_STYLE_NORMAL, COLOR_TEXT_BLACK);
    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height, 274, base_y + 468, "Spiral arrangement", "Helvetica", 10.0f, BLINK_FONT_STYLE_NORMAL, COLOR_TEXT_BLACK);
    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height, 391, base_y + 468, "c. 200", "Helvetica", 10.0f, BLINK_FONT_STYLE_NORMAL, COLOR_TEXT_BLACK);

    // Infobox
    fb_fill_rect(fb, 505, base_y + 151, 270, 323, COLOR_WIKI_GRAY);
    fb_stroke_rect(fb, 505, base_y + 151, 270, 323, COLOR_BORDER_GRAY);
    fb_fill_rect(fb, 512, base_y + 158, 256, 23, COLOR_TABLE_HEAD);
    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height,
                              620.5f, base_y + 174, "Flower", "Helvetica", 12.0f, BLINK_FONT_STYLE_BOLD, COLOR_TEXT_BLACK);

    blink_image_t* flower_img = blink_image_load_ppm("flower_thumb.ppm");
    if (flower_img) {
        fb_stroke_rect(fb, 512, base_y + 187, 256, 170, COLOR_IMAGE_BORDER);
        blit_object_fit_cover(flower_img, fb, 513, base_y + 188, 254, 168);
        blink_image_free(flower_img);
    }
    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height,
                              536, base_y + 371, "A sacred lotus in bloom (Nelumbo nucifera)", "Helvetica", 10.0f, BLINK_FONT_STYLE_NORMAL, COLOR_TEXT_BLACK);
    fb_fill_rect(fb, 512, base_y + 378, 256, 1, COLOR_TABLE_HEAD);

    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height, 516, base_y + 397, "Organ type", "Helvetica", 10.0f, BLINK_FONT_STYLE_BOLD, COLOR_TEXT_MUTED);
    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height, 619, base_y + 397, "Reproductive shoot", "Helvetica", 10.0f, BLINK_FONT_STYLE_NORMAL, COLOR_TEXT_BLACK);
    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height, 516, base_y + 413, "Division", "Helvetica", 10.0f, BLINK_FONT_STYLE_BOLD, COLOR_TEXT_MUTED);
    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height, 619, base_y + 413, "Angiosperms (Magnoliophyta)", "Helvetica", 10.0f, BLINK_FONT_STYLE_NORMAL, COLOR_TEXT_BLACK);
    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height, 516, base_y + 429, "Fossil range", "Helvetica", 10.0f, BLINK_FONT_STYLE_BOLD, COLOR_TEXT_MUTED);
    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height, 619, base_y + 429, "Early Cretaceous to present", "Helvetica", 10.0f, BLINK_FONT_STYLE_NORMAL, COLOR_TEXT_BLACK);
}

// ----------------------------------------------------------------------------
// Render Page 2 (Perianth, Anatomy Diagram, Reproductive Organs)
// ----------------------------------------------------------------------------
static void render_flower_page_2(FrameBuffer* fb, int base_y) {
    // Header
    fb_fill_rect(fb, 0, base_y, 800, 48, COLOR_WHITE);
    fb_fill_rect(fb, 0, base_y + 47, 800, 1, COLOR_BORDER_GRAY);

    // Article container borders
    fb_fill_rect(fb, 0, base_y + 48, 1, 552, COLOR_TABLE_HEAD);
    fb_fill_rect(fb, 799, base_y + 48, 1, 552, COLOR_TABLE_HEAD);

    // Wordmark and Page Badge
    blink_skia_font_draw_text_ex(fb->pixels, fb->width, fb->height,
                                 16, base_y + 31, "WIKIPEDIA", "Georgia", 20.0f, BLINK_FONT_STYLE_BOLD, 0.5f, 0xFF000000);
    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height,
                              159, base_y + 28, "Flower \xE2\x80\x94 Anatomy & Morphology", "Helvetica", 11.0f, BLINK_FONT_STYLE_NORMAL, COLOR_TEXT_MUTED);

    // Badge "Page 2 of 3" (x=710, y=13, w=74, h=21)
    fb_fill_rect(fb, 710, base_y + 13, 74, 21, COLOR_WIKI_GRAY);
    fb_stroke_rect(fb, 710, base_y + 13, 74, 21, COLOR_IMAGE_BORDER);
    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height,
                              718, base_y + 28, "Page 2 of 3", "Helvetica", 11.0f, BLINK_FONT_STYLE_NORMAL, COLOR_TEXT_MUTED);

    // Left Column Content:
    // H2 Section 1.1: Perianth
    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height,
                              25, base_y + 79, "1.1 Perianth: Calyx and Corolla", "Georgia", 16.0f, BLINK_FONT_STYLE_NORMAL, COLOR_TEXT_BLACK);
    fb_fill_rect(fb, 25, base_y + 85, 460, 1, COLOR_BORDER_GRAY);

    // Paragraph 1: Perianth description (4 lines, box w=460)
    const char* p1 = "Together, the calyx (sepals) and corolla (petals) constitute the perianth, the outer non-reproductive envelope of the flower. The calyx protects the developing floral tissues in the bud stage, while the pigmented corolla exhibits spectral absorption and UV reflection patterns designed to attract specialized animal pollinators.";
    blink_skia_font_draw_text_box(fb->pixels, fb->width, fb->height,
                                  25, base_y + 95, 460, 72, p1, "Helvetica", 12.0f, 18.0f, COLOR_TEXT_BLACK);

    // Table 1: Floral Symmetry & Perianth Architecture (y in [176, 254])
    fb_fill_rect(fb, 25, base_y + 176, 460, 21, COLOR_TABLE_HEAD);
    fb_fill_rect(fb, 25, base_y + 197, 460, 19, COLOR_WHITE);
    fb_fill_rect(fb, 25, base_y + 216, 460, 19, COLOR_WIKI_GRAY);
    fb_fill_rect(fb, 25, base_y + 235, 460, 19, COLOR_WHITE);

    fb_fill_rect(fb, 25, base_y + 176, 460, 1, COLOR_BORDER_GRAY);
    fb_fill_rect(fb, 25, base_y + 197, 460, 1, COLOR_BORDER_GRAY);
    fb_fill_rect(fb, 25, base_y + 216, 460, 1, COLOR_BORDER_GRAY);
    fb_fill_rect(fb, 25, base_y + 235, 460, 1, COLOR_BORDER_GRAY);
    fb_fill_rect(fb, 25, base_y + 254, 460, 1, COLOR_BORDER_GRAY);

    int t1_cols[] = { 25, 106, 209, 346, 484 };
    for (int i = 0; i < 5; i++) {
        fb_fill_rect(fb, t1_cols[i], base_y + 176, 1, 79, COLOR_BORDER_GRAY);
    }

    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height, 32, base_y + 191, "Symmetry", "Helvetica", 10.0f, BLINK_FONT_STYLE_BOLD, COLOR_TEXT_BLACK);
    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height, 113, base_y + 191, "Botanical Term", "Helvetica", 10.0f, BLINK_FONT_STYLE_BOLD, COLOR_TEXT_BLACK);
    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height, 216, base_y + 191, "Floral Planes", "Helvetica", 10.0f, BLINK_FONT_STYLE_BOLD, COLOR_TEXT_BLACK);
    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height, 353, base_y + 191, "Example Taxa", "Helvetica", 10.0f, BLINK_FONT_STYLE_BOLD, COLOR_TEXT_BLACK);

    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height, 32, base_y + 211, "Radial", "Helvetica", 10.0f, BLINK_FONT_STYLE_NORMAL, COLOR_TEXT_BLACK);
    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height, 113, base_y + 211, "Actinomorphic", "Helvetica", 10.0f, BLINK_FONT_STYLE_NORMAL, COLOR_TEXT_BLACK);
    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height, 216, base_y + 211, "Multiple (>2) planes", "Helvetica", 10.0f, BLINK_FONT_STYLE_NORMAL, COLOR_TEXT_BLACK);
    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height, 353, base_y + 211, "Lilies, Wild roses", "Helvetica", 10.0f, BLINK_FONT_STYLE_NORMAL, COLOR_TEXT_BLACK);

    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height, 32, base_y + 230, "Bilateral", "Helvetica", 10.0f, BLINK_FONT_STYLE_NORMAL, COLOR_TEXT_BLACK);
    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height, 113, base_y + 230, "Zygomorphic", "Helvetica", 10.0f, BLINK_FONT_STYLE_NORMAL, COLOR_TEXT_BLACK);
    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height, 216, base_y + 230, "Single plane only", "Helvetica", 10.0f, BLINK_FONT_STYLE_NORMAL, COLOR_TEXT_BLACK);
    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height, 353, base_y + 230, "Orchids, Snapdragons", "Helvetica", 10.0f, BLINK_FONT_STYLE_NORMAL, COLOR_TEXT_BLACK);

    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height, 32, base_y + 249, "Asymmetric", "Helvetica", 10.0f, BLINK_FONT_STYLE_NORMAL, COLOR_TEXT_BLACK);
    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height, 113, base_y + 249, "Irregular", "Helvetica", 10.0f, BLINK_FONT_STYLE_NORMAL, COLOR_TEXT_BLACK);
    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height, 216, base_y + 249, "No plane of symmetry", "Helvetica", 10.0f, BLINK_FONT_STYLE_NORMAL, COLOR_TEXT_BLACK);
    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height, 353, base_y + 249, "Canna, Marantaceae", "Helvetica", 10.0f, BLINK_FONT_STYLE_NORMAL, COLOR_TEXT_BLACK);

    // H2 Section 1.2: Reproductive Organs
    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height,
                              25, base_y + 282, "1.2 Reproductive Organs: Androecium & Gynoecium", "Georgia", 16.0f, BLINK_FONT_STYLE_NORMAL, COLOR_TEXT_BLACK);
    fb_fill_rect(fb, 25, base_y + 288, 460, 1, COLOR_BORDER_GRAY);

    // Paragraph 2 (4 lines)
    const char* p2 = "The fertile organs comprise the male androecium (stamens bearing pollen sacs) and the female gynoecium (one or more carpels enclosing ovules). Double fertilization within the ovary produces the diploid zygote and triploid nutritive endosperm.";
    blink_skia_font_draw_text_box(fb->pixels, fb->width, fb->height,
                                  25, base_y + 298, 460, 72, p2, "Helvetica", 12.0f, 18.0f, COLOR_TEXT_BLACK);

    // Table 2: Reproductive Anatomy (y in [379, 457])
    fb_fill_rect(fb, 25, base_y + 379, 460, 21, COLOR_TABLE_HEAD);
    fb_fill_rect(fb, 25, base_y + 400, 460, 19, COLOR_WHITE);
    fb_fill_rect(fb, 25, base_y + 419, 460, 19, COLOR_WIKI_GRAY);
    fb_fill_rect(fb, 25, base_y + 438, 460, 19, COLOR_WHITE);

    fb_fill_rect(fb, 25, base_y + 379, 460, 1, COLOR_BORDER_GRAY);
    fb_fill_rect(fb, 25, base_y + 400, 460, 1, COLOR_BORDER_GRAY);
    fb_fill_rect(fb, 25, base_y + 419, 460, 1, COLOR_BORDER_GRAY);
    fb_fill_rect(fb, 25, base_y + 438, 460, 1, COLOR_BORDER_GRAY);
    fb_fill_rect(fb, 25, base_y + 457, 460, 1, COLOR_BORDER_GRAY);

    int t2_cols[] = { 25, 109, 248, 484 };
    for (int i = 0; i < 4; i++) {
        fb_fill_rect(fb, t2_cols[i], base_y + 379, 1, 79, COLOR_BORDER_GRAY);
    }

    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height, 32, base_y + 394, "Organ", "Helvetica", 10.0f, BLINK_FONT_STYLE_BOLD, COLOR_TEXT_BLACK);
    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height, 116, base_y + 394, "Components", "Helvetica", 10.0f, BLINK_FONT_STYLE_BOLD, COLOR_TEXT_BLACK);
    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height, 255, base_y + 394, "Cytological Function", "Helvetica", 10.0f, BLINK_FONT_STYLE_BOLD, COLOR_TEXT_BLACK);

    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height, 32, base_y + 414, "Stamen", "Helvetica", 10.0f, BLINK_FONT_STYLE_NORMAL, COLOR_TEXT_BLACK);
    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height, 116, base_y + 414, "Anther & Filament", "Helvetica", 10.0f, BLINK_FONT_STYLE_NORMAL, COLOR_TEXT_BLACK);
    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height, 255, base_y + 414, "Microsporogenesis producing pollen", "Helvetica", 10.0f, BLINK_FONT_STYLE_NORMAL, COLOR_TEXT_BLACK);

    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height, 32, base_y + 433, "Carpel", "Helvetica", 10.0f, BLINK_FONT_STYLE_NORMAL, COLOR_TEXT_BLACK);
    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height, 116, base_y + 433, "Stigma, Style, Ovary", "Helvetica", 10.0f, BLINK_FONT_STYLE_NORMAL, COLOR_TEXT_BLACK);
    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height, 255, base_y + 433, "Megasporogenesis and seed set", "Helvetica", 10.0f, BLINK_FONT_STYLE_NORMAL, COLOR_TEXT_BLACK);

    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height, 32, base_y + 452, "Receptacle", "Helvetica", 10.0f, BLINK_FONT_STYLE_NORMAL, COLOR_TEXT_BLACK);
    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height, 116, base_y + 452, "Torus / Pedicel apex", "Helvetica", 10.0f, BLINK_FONT_STYLE_NORMAL, COLOR_TEXT_BLACK);
    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height, 255, base_y + 452, "Attachment axis for floral whorls", "Helvetica", 10.0f, BLINK_FONT_STYLE_NORMAL, COLOR_TEXT_BLACK);

    // Right Column: Infobox Diagram Card (x=505, y=64, w=270, h=406)
    fb_fill_rect(fb, 505, base_y + 64, 270, 406, COLOR_WIKI_GRAY);
    fb_stroke_rect(fb, 505, base_y + 64, 270, 406, COLOR_BORDER_GRAY);

    fb_fill_rect(fb, 512, base_y + 71, 256, 23, COLOR_TABLE_HEAD);
    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height,
                              573.5f, base_y + 86, "Floral Anatomy Diagram", "Helvetica", 11.0f, BLINK_FONT_STYLE_BOLD, COLOR_TEXT_BLACK);

    blink_image_t* diag_img = blink_image_load_ppm("flower_diagram.ppm");
    if (diag_img) {
        fb_stroke_rect(fb, 512, base_y + 98, 256, 160, COLOR_IMAGE_BORDER);
        blit_object_fit_cover(diag_img, fb, 513, base_y + 99, 254, 158);
        blink_image_free(diag_img);
    }
    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height,
                              540, base_y + 272, "Longitudinal floral section showing whorls", "Helvetica", 10.0f, BLINK_FONT_STYLE_NORMAL, COLOR_TEXT_BLACK);
    fb_fill_rect(fb, 512, base_y + 279, 256, 1, COLOR_TABLE_HEAD);

    // Infobox metadata rows
    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height, 516, base_y + 298, "Petal", "Helvetica", 10.0f, BLINK_FONT_STYLE_BOLD, COLOR_TEXT_MUTED);
    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height, 613, base_y + 298, "Corolla attraction lobe", "Helvetica", 10.0f, BLINK_FONT_STYLE_NORMAL, COLOR_TEXT_BLACK);

    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height, 516, base_y + 314, "Sepal", "Helvetica", 10.0f, BLINK_FONT_STYLE_BOLD, COLOR_TEXT_MUTED);
    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height, 613, base_y + 314, "Calyx protective leaf", "Helvetica", 10.0f, BLINK_FONT_STYLE_NORMAL, COLOR_TEXT_BLACK);

    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height, 516, base_y + 330, "Stamen", "Helvetica", 10.0f, BLINK_FONT_STYLE_BOLD, COLOR_TEXT_MUTED);
    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height, 613, base_y + 330, "Anther + pollen filament", "Helvetica", 10.0f, BLINK_FONT_STYLE_NORMAL, COLOR_TEXT_BLACK);

    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height, 516, base_y + 346, "Pistil", "Helvetica", 10.0f, BLINK_FONT_STYLE_BOLD, COLOR_TEXT_MUTED);
    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height, 613, base_y + 346, "Stigma, style & ovary", "Helvetica", 10.0f, BLINK_FONT_STYLE_NORMAL, COLOR_TEXT_BLACK);

    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height, 516, base_y + 362, "Receptacle", "Helvetica", 10.0f, BLINK_FONT_STYLE_BOLD, COLOR_TEXT_MUTED);
    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height, 613, base_y + 362, "Thickened stem base", "Helvetica", 10.0f, BLINK_FONT_STYLE_NORMAL, COLOR_TEXT_BLACK);

    // Page Footer Nav Line
    fb_fill_rect(fb, 25, base_y + 470, 750, 1, COLOR_TABLE_HEAD);
    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height,
                              25, base_y + 490, "\xE2\x86\x90 Page 1 (Overview & Classification)", "Helvetica", 11.0f, BLINK_FONT_STYLE_NORMAL, COLOR_LINK_BLUE);
    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height,
                              348, base_y + 490, "Page 2 of 3", "Helvetica", 11.0f, BLINK_FONT_STYLE_NORMAL, COLOR_TEXT_MUTED);
    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height,
                              537, base_y + 490, "Continued on Page 3 (Ecology & Evolution) \xE2\x86\x92", "Helvetica", 11.0f, BLINK_FONT_STYLE_NORMAL, COLOR_LINK_BLUE);
}

// ----------------------------------------------------------------------------
// Render Page 3 (Evolution, Clades Table, Pollination Syndromes, Footer)
// ----------------------------------------------------------------------------
static void render_flower_page_3(FrameBuffer* fb, int base_y) {
    // Header
    fb_fill_rect(fb, 0, base_y, 800, 48, COLOR_WHITE);
    fb_fill_rect(fb, 0, base_y + 47, 800, 1, COLOR_BORDER_GRAY);

    // Article container borders
    fb_fill_rect(fb, 0, base_y + 48, 1, 552, COLOR_TABLE_HEAD);
    fb_fill_rect(fb, 799, base_y + 48, 1, 552, COLOR_TABLE_HEAD);

    // Wordmark and Page Badge
    blink_skia_font_draw_text_ex(fb->pixels, fb->width, fb->height,
                                 16, base_y + 31, "WIKIPEDIA", "Georgia", 20.0f, BLINK_FONT_STYLE_BOLD, 0.5f, 0xFF000000);
    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height,
                              159, base_y + 28, "Flower \xE2\x80\x94 Taxonomy & Evolution", "Helvetica", 11.0f, BLINK_FONT_STYLE_NORMAL, COLOR_TEXT_MUTED);

    // Badge "Page 3 of 3" (x=710, y=13, w=74, h=21)
    fb_fill_rect(fb, 710, base_y + 13, 74, 21, COLOR_WIKI_GRAY);
    fb_stroke_rect(fb, 710, base_y + 13, 74, 21, COLOR_IMAGE_BORDER);
    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height,
                              718, base_y + 28, "Page 3 of 3", "Helvetica", 11.0f, BLINK_FONT_STYLE_NORMAL, COLOR_TEXT_MUTED);

    // Section 2: Major Groups of Flowering Plants & Evolution
    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height,
                              25, base_y + 79, "2 Major Groups of Flowering Plants & Evolution", "Georgia", 16.0f, BLINK_FONT_STYLE_NORMAL, COLOR_TEXT_BLACK);
    fb_fill_rect(fb, 25, base_y + 85, 750, 1, COLOR_BORDER_GRAY);

    const char* p1 = "Flowering plants emerged during the early Cretaceous period, approximately 130 million years ago, rapidly diversifying to dominate terrestrial flora in an evolutionary radiation Charles Darwin famously termed an \"abominable mystery\". Living angiosperms comprise four primary lineages exhibiting distinct anatomical specializations.";
    blink_skia_font_draw_text_box(fb->pixels, fb->width, fb->height,
                                  25, base_y + 95, 750, 54, p1, "Helvetica", 12.0f, 18.0f, COLOR_TEXT_BLACK);

    // Table 1: Clades Table (y in [156, 253])
    fb_fill_rect(fb, 25, base_y + 156, 750, 21, COLOR_TABLE_HEAD);
    fb_fill_rect(fb, 25, base_y + 177, 750, 19, COLOR_WHITE);
    fb_fill_rect(fb, 25, base_y + 196, 750, 19, COLOR_WIKI_GRAY);
    fb_fill_rect(fb, 25, base_y + 215, 750, 19, COLOR_WHITE);
    fb_fill_rect(fb, 25, base_y + 234, 750, 19, COLOR_WIKI_GRAY);

    fb_fill_rect(fb, 25, base_y + 156, 750, 1, COLOR_BORDER_GRAY);
    fb_fill_rect(fb, 25, base_y + 177, 750, 1, COLOR_BORDER_GRAY);
    fb_fill_rect(fb, 25, base_y + 196, 750, 1, COLOR_BORDER_GRAY);
    fb_fill_rect(fb, 25, base_y + 215, 750, 1, COLOR_BORDER_GRAY);
    fb_fill_rect(fb, 25, base_y + 234, 750, 1, COLOR_BORDER_GRAY);
    fb_fill_rect(fb, 25, base_y + 253, 750, 1, COLOR_BORDER_GRAY);

    int t1_cols[] = { 25, 134, 327, 539, 774 };
    for (int i = 0; i < 5; i++) {
        fb_fill_rect(fb, t1_cols[i], base_y + 156, 1, 98, COLOR_BORDER_GRAY);
    }

    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height, 32, base_y + 171, "Angiosperm Clade", "Helvetica", 10.0f, BLINK_FONT_STYLE_BOLD, COLOR_TEXT_BLACK);
    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height, 141, base_y + 171, "Distinguishing Traits", "Helvetica", 10.0f, BLINK_FONT_STYLE_BOLD, COLOR_TEXT_BLACK);
    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height, 334, base_y + 171, "Floral Architecture", "Helvetica", 10.0f, BLINK_FONT_STYLE_BOLD, COLOR_TEXT_BLACK);
    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height, 546, base_y + 171, "Global Diversity", "Helvetica", 10.0f, BLINK_FONT_STYLE_BOLD, COLOR_TEXT_BLACK);

    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height, 32, base_y + 191, "Monocotyledonae", "Helvetica", 10.0f, BLINK_FONT_STYLE_NORMAL, COLOR_TEXT_BLACK);
    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height, 141, base_y + 191, "Single cotyledon, parallel venation", "Helvetica", 10.0f, BLINK_FONT_STYLE_NORMAL, COLOR_TEXT_BLACK);
    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height, 334, base_y + 191, "Trimerous perianth (multiples of 3)", "Helvetica", 10.0f, BLINK_FONT_STYLE_NORMAL, COLOR_TEXT_BLACK);
    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height, 546, base_y + 191, "c. 70,000 species (Poaceae, Orchidaceae)", "Helvetica", 10.0f, BLINK_FONT_STYLE_NORMAL, COLOR_TEXT_BLACK);

    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height, 32, base_y + 210, "Eudicotyledonae", "Helvetica", 10.0f, BLINK_FONT_STYLE_NORMAL, COLOR_TEXT_BLACK);
    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height, 141, base_y + 210, "Tricolpate pollen, reticulate venation", "Helvetica", 10.0f, BLINK_FONT_STYLE_NORMAL, COLOR_TEXT_BLACK);
    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height, 334, base_y + 210, "Tetramerous / Pentamerous (4 or 5)", "Helvetica", 10.0f, BLINK_FONT_STYLE_NORMAL, COLOR_TEXT_BLACK);
    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height, 546, base_y + 210, "c. 175,000 species (Asteraceae, Rosaceae)", "Helvetica", 10.0f, BLINK_FONT_STYLE_NORMAL, COLOR_TEXT_BLACK);

    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height, 32, base_y + 229, "Magnoliidae", "Helvetica", 10.0f, BLINK_FONT_STYLE_NORMAL, COLOR_TEXT_BLACK);
    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height, 141, base_y + 229, "Ethereal oil cells, branched veins", "Helvetica", 10.0f, BLINK_FONT_STYLE_NORMAL, COLOR_TEXT_BLACK);
    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height, 334, base_y + 229, "Spiral / Trimerous whorls, many stamens", "Helvetica", 10.0f, BLINK_FONT_STYLE_NORMAL, COLOR_TEXT_BLACK);
    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height, 546, base_y + 229, "c. 10,000 species (Magnoliaceae, Lauraceae)", "Helvetica", 10.0f, BLINK_FONT_STYLE_NORMAL, COLOR_TEXT_BLACK);

    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height, 32, base_y + 248, "Basal Angiosperms", "Helvetica", 10.0f, BLINK_FONT_STYLE_NORMAL, COLOR_TEXT_BLACK);
    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height, 141, base_y + 248, "Ancient relicts, laminar stamens", "Helvetica", 10.0f, BLINK_FONT_STYLE_NORMAL, COLOR_TEXT_BLACK);
    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height, 334, base_y + 248, "Spiral arrangement, undifferentiated", "Helvetica", 10.0f, BLINK_FONT_STYLE_NORMAL, COLOR_TEXT_BLACK);
    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height, 546, base_y + 248, "c. 200 species (Amborellales, Nymphaeales)", "Helvetica", 10.0f, BLINK_FONT_STYLE_NORMAL, COLOR_TEXT_BLACK);

    // Section 3: Pollination Syndromes & Coevolutionary Mutualisms
    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height,
                              25, base_y + 279, "3 Pollination Syndromes & Coevolutionary Mutualisms", "Georgia", 16.0f, BLINK_FONT_STYLE_NORMAL, COLOR_TEXT_BLACK);
    fb_fill_rect(fb, 25, base_y + 285, 750, 1, COLOR_BORDER_GRAY);

    const char* p2 = "Angiosperm flowers have coevolved with diverse biotic and abiotic pollination vectors. Floral phenotypic suites\xe2\x80\x94" "encompassing corolla morphology, pigment reflectance, olfactory chemistry, and nectar composition\xe2\x80\x94" "correlate with specific pollinator guilds.";
    blink_skia_font_draw_text_box(fb->pixels, fb->width, fb->height,
                                  25, base_y + 295, 750, 36, p2, "Helvetica", 12.0f, 18.0f, COLOR_TEXT_BLACK);

    // Table 2: Syndromes Table (y in [338, 435])
    fb_fill_rect(fb, 25, base_y + 338, 750, 21, COLOR_TABLE_HEAD);
    fb_fill_rect(fb, 25, base_y + 359, 750, 19, COLOR_WHITE);
    fb_fill_rect(fb, 25, base_y + 378, 750, 19, COLOR_WIKI_GRAY);
    fb_fill_rect(fb, 25, base_y + 397, 750, 19, COLOR_WHITE);
    fb_fill_rect(fb, 25, base_y + 416, 750, 19, COLOR_WIKI_GRAY);

    fb_fill_rect(fb, 25, base_y + 338, 750, 1, COLOR_BORDER_GRAY);
    fb_fill_rect(fb, 25, base_y + 359, 750, 1, COLOR_BORDER_GRAY);
    fb_fill_rect(fb, 25, base_y + 378, 750, 1, COLOR_BORDER_GRAY);
    fb_fill_rect(fb, 25, base_y + 397, 750, 1, COLOR_BORDER_GRAY);
    fb_fill_rect(fb, 25, base_y + 416, 750, 1, COLOR_BORDER_GRAY);
    fb_fill_rect(fb, 25, base_y + 435, 750, 1, COLOR_BORDER_GRAY);

    int t2_cols[] = { 25, 167, 287, 591, 774 };
    for (int i = 0; i < 5; i++) {
        fb_fill_rect(fb, t2_cols[i], base_y + 338, 1, 98, COLOR_BORDER_GRAY);
    }

    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height, 32, base_y + 353, "Pollinator Vector", "Helvetica", 10.0f, BLINK_FONT_STYLE_BOLD, COLOR_TEXT_BLACK);
    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height, 174, base_y + 353, "Syndrome Term", "Helvetica", 10.0f, BLINK_FONT_STYLE_BOLD, COLOR_TEXT_BLACK);
    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height, 294, base_y + 353, "Floral Adaptations & Visual Signals", "Helvetica", 10.0f, BLINK_FONT_STYLE_BOLD, COLOR_TEXT_BLACK);
    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height, 598, base_y + 353, "Representative Taxa", "Helvetica", 10.0f, BLINK_FONT_STYLE_BOLD, COLOR_TEXT_BLACK);

    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height, 32, base_y + 373, "Apoidea (Bees)", "Helvetica", 10.0f, BLINK_FONT_STYLE_NORMAL, COLOR_TEXT_BLACK);
    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height, 174, base_y + 373, "Melittophily", "Helvetica", 10.0f, BLINK_FONT_STYLE_NORMAL, COLOR_TEXT_BLACK);
    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height, 294, base_y + 373, "Yellow / blue / UV guide patterns, sweet nectar", "Helvetica", 10.0f, BLINK_FONT_STYLE_NORMAL, COLOR_TEXT_BLACK);
    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height, 598, base_y + 373, "Apple, Clover, Rosemary", "Helvetica", 10.0f, BLINK_FONT_STYLE_NORMAL, COLOR_TEXT_BLACK);

    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height, 32, base_y + 392, "Lepidoptera (Moths)", "Helvetica", 10.0f, BLINK_FONT_STYLE_NORMAL, COLOR_TEXT_BLACK);
    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height, 174, base_y + 392, "Phalaenophily", "Helvetica", 10.0f, BLINK_FONT_STYLE_NORMAL, COLOR_TEXT_BLACK);
    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height, 294, base_y + 392, "White corolla, nocturnal fragrance emission", "Helvetica", 10.0f, BLINK_FONT_STYLE_NORMAL, COLOR_TEXT_BLACK);
    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height, 598, base_y + 392, "Tobacco, Evening primrose", "Helvetica", 10.0f, BLINK_FONT_STYLE_NORMAL, COLOR_TEXT_BLACK);

    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height, 32, base_y + 411, "Trochilidae (Birds)", "Helvetica", 10.0f, BLINK_FONT_STYLE_NORMAL, COLOR_TEXT_BLACK);
    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height, 174, base_y + 411, "Ornithophily", "Helvetica", 10.0f, BLINK_FONT_STYLE_NORMAL, COLOR_TEXT_BLACK);
    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height, 294, base_y + 411, "Vivid red tubular corolla, copious dilute nectar", "Helvetica", 10.0f, BLINK_FONT_STYLE_NORMAL, COLOR_TEXT_BLACK);
    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height, 598, base_y + 411, "Fuchsia, Hibiscus, Sage", "Helvetica", 10.0f, BLINK_FONT_STYLE_NORMAL, COLOR_TEXT_BLACK);

    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height, 32, base_y + 430, "Anemophily (Wind)", "Helvetica", 10.0f, BLINK_FONT_STYLE_NORMAL, COLOR_TEXT_BLACK);
    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height, 174, base_y + 430, "Abiotic Vector", "Helvetica", 10.0f, BLINK_FONT_STYLE_NORMAL, COLOR_TEXT_BLACK);
    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height, 294, base_y + 430, "Reduced perianth, versatile pendulous anthers", "Helvetica", 10.0f, BLINK_FONT_STYLE_NORMAL, COLOR_TEXT_BLACK);
    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height, 598, base_y + 430, "Grasses, Birches, Oaks", "Helvetica", 10.0f, BLINK_FONT_STYLE_NORMAL, COLOR_TEXT_BLACK);

    // Category Box (x in [25, 774], y in [446, 471])
    fb_fill_rect(fb, 25, base_y + 446, 750, 26, COLOR_WIKI_GRAY);
    fb_stroke_rect(fb, 25, base_y + 446, 750, 26, COLOR_BORDER_GRAY);
    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height,
                              39, base_y + 462, "Categories:", "Helvetica", 10.0f, BLINK_FONT_STYLE_BOLD, COLOR_TEXT_MUTED);
    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height,
                              102, base_y + 462, "Flowers \xE2\x80\xA2 Plant anatomy \xE2\x80\xA2 Angiosperm morphology \xE2\x80\xA2 Botany \xE2\x80\xA2 Reproductive biology", "Helvetica", 10.0f, BLINK_FONT_STYLE_NORMAL, COLOR_TEXT_MUTED);

    // Page Footer Nav Line
    fb_fill_rect(fb, 25, base_y + 480, 750, 1, COLOR_TABLE_HEAD);
    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height,
                              25, base_y + 500, "\xE2\x86\x90 Page 2 (Anatomy & Morphology)", "Helvetica", 11.0f, BLINK_FONT_STYLE_NORMAL, COLOR_LINK_BLUE);
    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height,
                              309, base_y + 500, "Page 3 of 3 (End of Article)", "Helvetica", 11.0f, BLINK_FONT_STYLE_NORMAL, COLOR_TEXT_MUTED);
    blink_skia_font_draw_text(fb->pixels, fb->width, fb->height,
                              550, base_y + 500, "Wikipedia: Featured Article \xE2\x80\xA2 CC BY-SA 4.0", "Helvetica", 11.0f, BLINK_FONT_STYLE_NORMAL, COLOR_LINK_BLUE);
}

int main(void) {
    printf("=== Generating Wikipedia Flower Full Multi-Page Article (3 Pages) ===\n");
    blink_skia_font_init();

    // 1. Render Page 1 (800x600)
    FrameBuffer* p1 = fb_create(VIEWPORT_WIDTH, PAGE_HEIGHT);
    render_flower_page_1(p1, 0);
    fb_save_ppm(p1, "blink_formal_wikipedia_flowers_p1.ppm");
    // Also save as default blink_formal_wikipedia_flowers.ppm for backward compatibility
    fb_save_ppm(p1, "blink_formal_wikipedia_flowers.ppm");
    fb_destroy(p1);
    printf("Saved Page 1: blink_formal_wikipedia_flowers_p1.ppm\n");

    // 2. Render Page 2 (800x600)
    FrameBuffer* p2 = fb_create(VIEWPORT_WIDTH, PAGE_HEIGHT);
    render_flower_page_2(p2, 0);
    fb_save_ppm(p2, "blink_formal_wikipedia_flowers_p2.ppm");
    fb_destroy(p2);
    printf("Saved Page 2: blink_formal_wikipedia_flowers_p2.ppm\n");

    // 3. Render Page 3 (800x600)
    FrameBuffer* p3 = fb_create(VIEWPORT_WIDTH, PAGE_HEIGHT);
    render_flower_page_3(p3, 0);
    fb_save_ppm(p3, "blink_formal_wikipedia_flowers_p3.ppm");
    fb_destroy(p3);
    printf("Saved Page 3: blink_formal_wikipedia_flowers_p3.ppm\n");

    // 4. Render Full Continuous 3-Page Stack (800x1800)
    FrameBuffer* full = fb_create(VIEWPORT_WIDTH, FULL_HEIGHT);
    render_flower_page_1(full, 0);
    render_flower_page_2(full, 600);
    render_flower_page_3(full, 1200);
    fb_save_ppm(full, "blink_formal_wikipedia_flowers_full.ppm");
    fb_destroy(full);
    printf("Saved Full Continuous Article: blink_formal_wikipedia_flowers_full.ppm (800x1800)\n");

    return 0;
}
