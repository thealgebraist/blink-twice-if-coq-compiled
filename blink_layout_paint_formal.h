/* ========================================================================= */
/* Blink Formal Engine: Multi-Span Inline, Positioned, Float & Paint Module  */
/* Header: blink_layout_paint_formal.h                                       */
/*                                                                           */
/* Direct C99 extraction of the Rocq/Coq 9.3.0 formalizations in:            */
/*   - BlinkCSS4InlineAndPositionedLayoutEngine.v                            */
/*   - BlinkHMHybrid_33..44 (Selectors L4, Inline, Floats, z-index, Flex,    */
/*     Grid minmax/spans, Table 2D rowspan+colspan & Collapsed Borders)      */
/*   - BlinkVerticalFlowLayoutSemantics.v & BlinkMarginCollapsingSemantics.v */
/* ========================================================================= */

#ifndef BLINK_LAYOUT_PAINT_FORMAL_H
#define BLINK_LAYOUT_PAINT_FORMAL_H

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include "blink_dual_mode_z.h"
#include "blink_html_css_formal.h"

#ifdef __cplusplus
extern "C" {
#endif

/* ------------------------------------------------------------------------- */
/* 1. RGBA FrameBuffer & 2D Compositing Primitives                           */
/* ------------------------------------------------------------------------- */

typedef struct {
    int       width;
    int       height;
    uint32_t* pixels;
} blink_framebuffer_t;

blink_framebuffer_t* blink_fb_create(int w, int h, uint32_t clear_color);
void blink_fb_destroy(blink_framebuffer_t* fb);
void blink_fb_fill_rect(blink_framebuffer_t* fb, int x, int y, int w, int h, uint32_t color);
void blink_fb_stroke_rect(blink_framebuffer_t* fb, int x, int y, int w, int h, int bw, uint32_t color);
void blink_fb_draw_bullet(blink_framebuffer_t* fb, int cx, int cy, int radius, uint32_t color);

/* ------------------------------------------------------------------------- */
/* 2. Pure Formal Layout Helpers (Exact Mirrors of Gallina Definitions)      */
/* ------------------------------------------------------------------------- */

typedef struct {
    int32_t            width;
    css_border_style_t style;
    uint32_t           color;
} blink_collapsed_border_edge_t;

/* CSS 2.2 §17.6.2.1 Border Conflict Resolution (`resolve_collapsed_border`) */
blink_collapsed_border_edge_t blink_resolve_collapsed_border(
    blink_collapsed_border_edge_t a,
    blink_collapsed_border_edge_t b);

/* CSS Positioned Layout Level 3 §4 Inset Constraint Solver (`resolve_abs_axis`) */
void blink_resolve_abs_axis(int32_t cb_size,
                            int32_t inset_start,
                            bool has_start,
                            int32_t inset_end,
                            bool has_end,
                            int32_t explicit_size,
                            bool has_size,
                            int32_t intrinsic_size,
                            int32_t static_pos,
                            int32_t* out_pos,
                            int32_t* out_size);

/* ------------------------------------------------------------------------- */
/* 3. End-to-End DOM Normalization, Formal Layout & Appendix E Stacking Paint*/
/* ------------------------------------------------------------------------- */

/* Preserves multi-span inline formatting runs while normalizing hidden noise */
void blink_normalize_dom_for_layout(dom_node_t* root);

/* Executes Block + FloatExclusionSpace + Multi-Span Inline + Flex + Grid +
   2D Table + Out-of-Flow Positioned layout across the entire DOM tree.      */
int blink_layout_dom_tree(dom_node_t* root,
                          int viewport_x,
                          int viewport_y,
                          int viewport_w,
                          int viewport_h,
                          blink_layout_mode_t mode,
                          int* out_max_y);

/* Paints the laid-out DOM tree into `fb` following CSS 2.2 Appendix E
   7-phase stacking context & `z-index` paint order.                         */
void blink_paint_dom_stacking_context(dom_node_t* root, blink_framebuffer_t* fb);

#ifdef __cplusplus
}
#endif

#endif /* BLINK_LAYOUT_PAINT_FORMAL_H */
