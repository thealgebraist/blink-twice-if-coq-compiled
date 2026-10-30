#include "blink_formal_engine.h"
#include <stdlib.h>
#include <stdio.h>
#include <string.h>

/* ========================================================================= */
/* Blink Formal Layout & Rasterizer Engine (C99 Implementation)              */
/* Formally proven in BlinkInteractivePagePipelineModel.v and               */
/* BlinkFrameBufferRasterizerSemantics.v.                                    */
/* ========================================================================= */

int64_t collapse_margins(int64_t m1, int64_t m2) {
    return (m1 > m2) ? m1 : m2;
}

int64_t resolve_percent_col_width(int64_t avail_w, int64_t pct) {
    return (avail_w * pct) / 100;
}

int64_t button_inline_size(int64_t text_w, int64_t pad, int64_t border, int64_t author_w) {
    int64_t intrinsic = text_w + 2 * pad + 2 * border;
    return (author_w > 0) ? author_w : intrinsic;
}

int64_t button_block_size(int64_t text_h, int64_t pad, int64_t border, int64_t author_h) {
    int64_t intrinsic = text_h + 2 * pad + 2 * border;
    return (author_h > 0) ? author_h : intrinsic;
}

InteractivePageInput get_sample_interactive_page(void) {
    InteractivePageInput page = {
        .ipi_h1_h = 38,
        .ipi_h1_margin = { .m_top = 21, .m_bot = 21 },
        .ipi_p_h = 19,
        .ipi_p_margin = { .m_top = 16, .m_bot = 16 },
        .ipi_flex_lines = 2,
        .ipi_flex_line_h = 30,
        .ipi_flex_margin = { .m_top = 12, .m_bot = 12 },
        .ipi_tbl_col1_pct = 40,
        .ipi_tbl_col2_pct = 60,
        .ipi_tbl_row_h = 25,
        .ipi_tbl_margin = { .m_top = 10, .m_bot = 10 },
        .ipi_ul_items_h = 40,
        .ipi_ul_margin = { .m_top = 16, .m_bot = 16 },
        .ipi_btn_label_w = 60,
        .ipi_btn_label_h = 16,
        .ipi_btn_pad = 6,
        .ipi_btn_border = 2,
        .ipi_btn_margin = { .m_top = 10, .m_bot = 10 }
    };
    return page;
}

InteractiveLayoutOutput layout_interactive_page_pipeline(int64_t vw, int64_t vh, const InteractivePageInput* page) {
    int64_t body_margin = 8;
    
    /* 1. Header 1 */
    int64_t h1_y = body_margin + page->ipi_h1_margin.m_top;
    int64_t h1_h = page->ipi_h1_h;
    
    /* 2. Paragraph with margin collapse */
    int64_t coll_h1_p = collapse_margins(page->ipi_h1_margin.m_bot, page->ipi_p_margin.m_top);
    int64_t p_y = h1_y + h1_h + coll_h1_p;
    int64_t p_h = page->ipi_p_h;
    
    /* 3. Multi-line Flex container with margin collapse */
    int64_t coll_p_flex = collapse_margins(page->ipi_p_margin.m_bot, page->ipi_flex_margin.m_top);
    int64_t flex_y = p_y + p_h + coll_p_flex;
    int64_t flex_h = page->ipi_flex_lines * page->ipi_flex_line_h;
    
    /* 4. 2-Column Table with percentage columns & margin collapse */
    int64_t coll_flex_tbl = collapse_margins(page->ipi_flex_margin.m_bot, page->ipi_tbl_margin.m_top);
    int64_t tbl_y = flex_y + flex_h + coll_flex_tbl;
    int64_t tbl_h = page->ipi_tbl_row_h;
    int64_t tbl_w = vw - 2 * body_margin;
    int64_t c1_w = resolve_percent_col_width(tbl_w, page->ipi_tbl_col1_pct);
    int64_t c2_w = resolve_percent_col_width(tbl_w, page->ipi_tbl_col2_pct);
    
    /* 5. Outside marked List with margin collapse */
    int64_t coll_tbl_ul = collapse_margins(page->ipi_tbl_margin.m_bot, page->ipi_ul_margin.m_top);
    int64_t ul_y = tbl_y + tbl_h + coll_tbl_ul;
    int64_t ul_h = page->ipi_ul_items_h;
    
    /* 6. Form Button with margin collapse */
    int64_t coll_ul_btn = collapse_margins(page->ipi_ul_margin.m_bot, page->ipi_btn_margin.m_top);
    int64_t btn_y = ul_y + ul_h + coll_ul_btn;
    int64_t btn_pad = page->ipi_btn_pad;
    int64_t btn_border = page->ipi_btn_border;
    int64_t btn_w = button_inline_size(page->ipi_btn_label_w, btn_pad, btn_border, 0);
    int64_t btn_h = button_inline_size(page->ipi_btn_label_h, btn_pad, btn_border, 0);
    
    InteractiveLayoutOutput out = {
        .ilo_viewport_w = vw,
        .ilo_viewport_h = vh,
        .ilo_h1_y = h1_y,
        .ilo_h1_h = h1_h,
        .ilo_p_y = p_y,
        .ilo_p_h = p_h,
        .ilo_flex_y = flex_y,
        .ilo_flex_h = flex_h,
        .ilo_table_y = tbl_y,
        .ilo_table_h = tbl_h,
        .ilo_table_c1_w = c1_w,
        .ilo_table_c2_w = c2_w,
        .ilo_ul_y = ul_y,
        .ilo_ul_h = ul_h,
        .ilo_btn_y = btn_y,
        .ilo_btn_w = btn_w,
        .ilo_btn_h = btn_h
    };
    return out;
}

FrameBuffer* fb_create(int64_t width, int64_t height, Color bg) {
    FrameBuffer* fb = (FrameBuffer*)malloc(sizeof(FrameBuffer));
    if (!fb) return NULL;
    fb->width = width;
    fb->height = height;
    fb->pixels = (Color*)malloc(sizeof(Color) * width * height);
    if (!fb->pixels) {
        free(fb);
        return NULL;
    }
    for (int64_t i = 0; i < width * height; ++i) {
        fb->pixels[i] = bg;
    }
    return fb;
}

void fb_destroy(FrameBuffer* fb) {
    if (fb) {
        if (fb->pixels) free(fb->pixels);
        free(fb);
    }
}

void fb_fill_rect(FrameBuffer* fb, int64_t rx, int64_t ry, int64_t rw, int64_t rh, Color col) {
    if (!fb || !fb->pixels) return;
    int64_t x_start = (rx < 0) ? 0 : rx;
    int64_t y_start = (ry < 0) ? 0 : ry;
    int64_t x_end = (rx + rw > fb->width) ? fb->width : rx + rw;
    int64_t y_end = (ry + rh > fb->height) ? fb->height : ry + rh;
    
    for (int64_t y = y_start; y < y_end; ++y) {
        for (int64_t x = x_start; x < x_end; ++x) {
            fb->pixels[y * fb->width + x] = col;
        }
    }
}

void fb_draw_border(FrameBuffer* fb, int64_t rx, int64_t ry, int64_t rw, int64_t rh, int64_t bw, Color col) {
    if (!fb || !fb->pixels || bw <= 0) return;
    // Top border
    fb_fill_rect(fb, rx, ry, rw, bw, col);
    // Bottom border
    fb_fill_rect(fb, rx, ry + rh - bw, rw, bw, col);
    // Left border
    fb_fill_rect(fb, rx, ry + bw, bw, rh - 2 * bw, col);
    // Right border
    fb_fill_rect(fb, rx + rw - bw, ry + bw, bw, rh - 2 * bw, col);
}

Color fb_get_pixel(const FrameBuffer* fb, int64_t x, int64_t y) {
    Color black = {0, 0, 0, 0};
    if (!fb || !fb->pixels) return black;
    if (x < 0 || x >= fb->width || y < 0 || y >= fb->height) return black;
    return fb->pixels[y * fb->width + x];
}

void rasterize_interactive_page(FrameBuffer* fb, const InteractiveLayoutOutput* out) {
    if (!fb || !out) return;
    int64_t body_m = 8;
    int64_t body_w = out->ilo_viewport_w - 2 * body_m;
    
    Color navy_text = {32, 33, 36, 255};
    Color gray_text = {60, 64, 67, 255};
    Color flex_bg   = {232, 240, 254, 255};
    Color table_bg  = {241, 243, 244, 255};
    Color white     = {255, 255, 255, 255};
    Color border_gr = {218, 220, 224, 255};
    Color black     = {0, 0, 0, 255};
    Color blue_btn  = {26, 115, 232, 255};
    
    /* 1. Header */
    fb_fill_rect(fb, body_m, out->ilo_h1_y, body_w, out->ilo_h1_h, navy_text);
    
    /* 2. Paragraph */
    fb_fill_rect(fb, body_m, out->ilo_p_y, body_w, out->ilo_p_h, gray_text);
    
    /* 3. Flex container */
    fb_fill_rect(fb, body_m, out->ilo_flex_y, body_w, out->ilo_flex_h, flex_bg);
    
    /* 4. Table */
    fb_fill_rect(fb, body_m, out->ilo_table_y, out->ilo_table_c1_w, out->ilo_table_h, table_bg);
    fb_fill_rect(fb, body_m + out->ilo_table_c1_w, out->ilo_table_y, out->ilo_table_c2_w, out->ilo_table_h, white);
    fb_draw_border(fb, body_m, out->ilo_table_y, out->ilo_table_c1_w + out->ilo_table_c2_w, out->ilo_table_h, 1, border_gr);
    
    /* 5. Outside marked List */
    fb_fill_rect(fb, body_m, out->ilo_ul_y, body_w, out->ilo_ul_h, table_bg);
    fb_fill_rect(fb, body_m - 6, out->ilo_ul_y + 4, 4, 4, black);
    
    /* 6. Form Button */
    fb_fill_rect(fb, body_m, out->ilo_btn_y, out->ilo_btn_w, out->ilo_btn_h, blue_btn);
    fb_draw_border(fb, body_m, out->ilo_btn_y, out->ilo_btn_w, out->ilo_btn_h, 2, navy_text);
}

bool fb_write_ppm(const FrameBuffer* fb, const char* filepath) {
    if (!fb || !fb->pixels || !filepath) return false;
    FILE* fp = fopen(filepath, "wb");
    if (!fp) return false;
    fprintf(fp, "P6\n%lld %lld\n255\n", (long long)fb->width, (long long)fb->height);
    for (int64_t i = 0; i < fb->width * fb->height; ++i) {
        fputc(fb->pixels[i].r, fp);
        fputc(fb->pixels[i].g, fp);
        fputc(fb->pixels[i].b, fp);
    }
    fclose(fp);
    return true;
}
