#ifndef BLINK_FORMAL_ENGINE_H
#define BLINK_FORMAL_ENGINE_H

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ========================================================================= */
/* Blink Formal Layout & Rasterizer Engine (Extracted from Rocq/Coq)         */
/* Verified with 0 admits in BlinkInteractivePagePipelineModel.v and         */
/* BlinkFrameBufferRasterizerSemantics.v.                                    */
/* ========================================================================= */

typedef struct {
    int64_t m_top;
    int64_t m_bot;
} MarginBox;

typedef struct {
    int64_t ipi_h1_h;
    MarginBox ipi_h1_margin;
    int64_t ipi_p_h;
    MarginBox ipi_p_margin;
    int64_t ipi_flex_lines;
    int64_t ipi_flex_line_h;
    MarginBox ipi_flex_margin;
    int64_t ipi_tbl_col1_pct;
    int64_t ipi_tbl_col2_pct;
    int64_t ipi_tbl_row_h;
    MarginBox ipi_tbl_margin;
    int64_t ipi_ul_items_h;
    MarginBox ipi_ul_margin;
    int64_t ipi_btn_label_w;
    int64_t ipi_btn_label_h;
    int64_t ipi_btn_pad;
    int64_t ipi_btn_border;
    MarginBox ipi_btn_margin;
} InteractivePageInput;

typedef struct {
    int64_t ilo_viewport_w;
    int64_t ilo_viewport_h;
    int64_t ilo_h1_y;
    int64_t ilo_h1_h;
    int64_t ilo_p_y;
    int64_t ilo_p_h;
    int64_t ilo_flex_y;
    int64_t ilo_flex_h;
    int64_t ilo_table_y;
    int64_t ilo_table_h;
    int64_t ilo_table_c1_w;
    int64_t ilo_table_c2_w;
    int64_t ilo_ul_y;
    int64_t ilo_ul_h;
    int64_t ilo_btn_y;
    int64_t ilo_btn_w;
    int64_t ilo_btn_h;
} InteractiveLayoutOutput;

typedef struct {
    uint8_t r;
    uint8_t g;
    uint8_t b;
    uint8_t a;
} Color;

typedef struct {
    int64_t width;
    int64_t height;
    Color* pixels;
} FrameBuffer;

/* Core Formal Layout & Sizing Functions */
int64_t collapse_margins(int64_t m1, int64_t m2);
int64_t resolve_percent_col_width(int64_t avail_w, int64_t pct);
int64_t button_inline_size(int64_t text_w, int64_t pad, int64_t border, int64_t author_w);
int64_t button_block_size(int64_t text_h, int64_t pad, int64_t border, int64_t author_h);

InteractiveLayoutOutput layout_interactive_page_pipeline(int64_t vw, int64_t vh, const InteractivePageInput* page);
InteractivePageInput get_sample_interactive_page(void);

/* Rasterizer & 2D Discrete FrameBuffer */
FrameBuffer* fb_create(int64_t width, int64_t height, Color bg);
void fb_destroy(FrameBuffer* fb);
void fb_fill_rect(FrameBuffer* fb, int64_t rx, int64_t ry, int64_t rw, int64_t rh, Color col);
void fb_draw_border(FrameBuffer* fb, int64_t rx, int64_t ry, int64_t rw, int64_t rh, int64_t bw, Color col);
Color fb_get_pixel(const FrameBuffer* fb, int64_t x, int64_t y);

void rasterize_interactive_page(FrameBuffer* fb, const InteractiveLayoutOutput* out);
bool fb_write_ppm(const FrameBuffer* fb, const char* filepath);

#ifdef __cplusplus
}
#endif

#endif /* BLINK_FORMAL_ENGINE_H */
