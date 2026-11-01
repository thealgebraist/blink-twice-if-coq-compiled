/* ========================================================================= */
/* Blink Formal Engine: Multi-Span Inline, Positioned, Float & Paint Module  */
/* Source: blink_layout_paint_formal.c                                       */
/*                                                                           */
/* Direct C99 extraction of the Rocq/Coq 9.3.0 formalizations in:            */
/*   - BlinkCSS4InlineAndPositionedLayoutEngine.v                            */
/*   - BlinkHMHybrid_33..44                                                  */
/*   - BlinkVerticalFlowLayoutSemantics.v & BlinkMarginCollapsingSemantics.v */
/* ========================================================================= */

#define _POSIX_C_SOURCE 200809L
#include "blink_layout_paint_formal.h"
#include "blink_skia_font_engine.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <ctype.h>
#include <math.h>

/* ------------------------------------------------------------------------- */
/* 1. RGBA FrameBuffer & 2D Compositing Primitives                           */
/* ------------------------------------------------------------------------- */

blink_framebuffer_t* blink_fb_create(int w, int h, uint32_t clear_color) {
    if (w <= 0 || h <= 0) return NULL;
    blink_framebuffer_t* fb = (blink_framebuffer_t*)malloc(sizeof(blink_framebuffer_t));
    if (!fb) return NULL;
    fb->width = w;
    fb->height = h;
    fb->pixels = (uint32_t*)malloc((size_t)w * (size_t)h * sizeof(uint32_t));
    if (!fb->pixels) {
        free(fb);
        return NULL;
    }
    for (int i = 0; i < w * h; i++) {
        fb->pixels[i] = clear_color;
    }
    return fb;
}

void blink_fb_destroy(blink_framebuffer_t* fb) {
    if (fb) {
        free(fb->pixels);
        free(fb);
    }
}

void blink_fb_fill_rect(blink_framebuffer_t* fb, int x, int y, int w, int h, uint32_t color) {
    if (!fb || !fb->pixels || w <= 0 || h <= 0) return;
    int x0 = (x < 0) ? 0 : x;
    int y0 = (y < 0) ? 0 : y;
    int x1 = ((x + w) > fb->width) ? fb->width : (x + w);
    int y1 = ((y + h) > fb->height) ? fb->height : (y + h);
    if (x0 >= x1 || y0 >= y1) return;

    uint32_t a = (color >> 24) & 0xFF;
    if (a == 0) return;

    if (a == 255) {
        for (int r = y0; r < y1; r++) {
            uint32_t* row = fb->pixels + (size_t)r * (size_t)fb->width;
            for (int c = x0; c < x1; c++) {
                row[c] = color;
            }
        }
    } else {
        uint32_t cr = (color >> 16) & 0xFF;
        uint32_t cg = (color >> 8) & 0xFF;
        uint32_t cb = color & 0xFF;
        uint32_t inv_a = 255 - a;

        for (int r = y0; r < y1; r++) {
            uint32_t* row = fb->pixels + (size_t)r * (size_t)fb->width;
            for (int c = x0; c < x1; c++) {
                uint32_t dst = row[c];
                uint32_t dr = (dst >> 16) & 0xFF;
                uint32_t dg = (dst >> 8) & 0xFF;
                uint32_t db = dst & 0xFF;

                uint32_t out_r = (cr * a + dr * inv_a) / 255;
                uint32_t out_g = (cg * a + dg * inv_a) / 255;
                uint32_t out_b = (cb * a + db * inv_a) / 255;
                row[c] = (0xFFu << 24) | (out_r << 16) | (out_g << 8) | out_b;
            }
        }
    }
}

void blink_fb_stroke_rect(blink_framebuffer_t* fb, int x, int y, int w, int h, int bw, uint32_t color) {
    if (!fb || w <= 0 || h <= 0 || bw <= 0) return;
    blink_fb_fill_rect(fb, x, y, w, bw, color);
    blink_fb_fill_rect(fb, x, y + h - bw, w, bw, color);
    blink_fb_fill_rect(fb, x, y, bw, h, color);
    blink_fb_fill_rect(fb, x + w - bw, y, bw, h, color);
}

void blink_fb_draw_bullet(blink_framebuffer_t* fb, int cx, int cy, int radius, uint32_t color) {
    if (!fb || !fb->pixels || radius <= 0) return;
    for (int dy = -radius; dy <= radius; dy++) {
        for (int dx = -radius; dx <= radius; dx++) {
            if (dx * dx + dy * dy <= radius * radius) {
                int px = cx + dx;
                int py = cy + dy;
                if (px >= 0 && px < fb->width && py >= 0 && py < fb->height) {
                    fb->pixels[py * fb->width + px] = color;
                }
            }
        }
    }
}

/* ------------------------------------------------------------------------- */
/* 1b. Pillar 5: Skia SkRRect SDF, Drop Shadow & Linear Gradient Rasterizers */
/* ------------------------------------------------------------------------- */

int32_t blink_clamp_corner_radius(int32_t w, int32_t h, int32_t r) {
    int32_t r_pos = (r > 0) ? r : 0;
    int32_t min_dim = (w < h) ? w : h;
    int32_t max_r = (min_dim > 0) ? (min_dim / 2) : 0;
    return (r_pos < max_r) ? r_pos : max_r;
}

int32_t blink_sdf_alpha_255(int32_t sd_q8) {
    if (sd_q8 <= -128) return 255;
    if (sd_q8 >= 128) return 0;
    return ((128 - sd_q8) * 255) / 256;
}

void blink_intersect_scissor(int px0, int py0, int px1, int py1,
                             int cx0, int cy0, int cx1, int cy1,
                             int* ox0, int* oy0, int* ox1, int* oy1) {
    int x0 = (px0 > cx0) ? px0 : cx0;
    int y0 = (py0 > cy0) ? py0 : cy0;
    int x1_raw = (px1 < cx1) ? px1 : cx1;
    int y1_raw = (py1 < cy1) ? py1 : cy1;
    if (ox0) *ox0 = x0;
    if (oy0) *oy0 = y0;
    if (ox1) *ox1 = (x1_raw > x0) ? x1_raw : x0;
    if (oy1) *oy1 = (y1_raw > y0) ? y1_raw : y0;
}

static inline float rrect_signed_dist_f(float px, float py,
                                        float x, float y, float w, float h, float r) {
    float cx = x + 0.5f * w;
    float cy = y + 0.5f * h;
    float hx = 0.5f * w - r;
    float hy = 0.5f * h - r;
    float qx = fabsf(px - cx) - hx;
    float qy = fabsf(py - cy) - hy;
    float ox = (qx > 0.0f) ? qx : 0.0f;
    float oy = (qy > 0.0f) ? qy : 0.0f;
    float outside = hypotf(ox, oy);
    float inside = fminf(fmaxf(qx, qy), 0.0f);
    return outside + inside - r;
}

static inline uint32_t rrect_coverage_u8(float sd) {
    if (sd <= -0.5f) return 255u;
    if (sd >= 0.5f) return 0u;
    int cov = (int)lroundf((0.5f - sd) * 255.0f);
    if (cov < 0) cov = 0;
    if (cov > 255) cov = 255;
    return (uint32_t)cov;
}

static inline void blend_argb_coverage(uint32_t* dst_px, uint32_t src_color, uint32_t cov_u8) {
    if (cov_u8 == 0u) return;
    uint32_t sa = (((src_color >> 24) & 0xFFu) * cov_u8 + 127u) / 255u;
    if (sa == 0u) return;
    if (sa >= 255u) {
        *dst_px = 0xFF000000u | (src_color & 0x00FFFFFFu);
        return;
    }
    uint32_t sr = (src_color >> 16) & 0xFFu;
    uint32_t sg = (src_color >> 8) & 0xFFu;
    uint32_t sb = src_color & 0xFFu;

    uint32_t dst = *dst_px;
    uint32_t dr = (dst >> 16) & 0xFFu;
    uint32_t dg = (dst >> 8) & 0xFFu;
    uint32_t db = dst & 0xFFu;
    uint32_t inv_a = 255u - sa;

    uint32_t or_c = (sr * sa + dr * inv_a + 127u) / 255u;
    uint32_t og_c = (sg * sa + dg * inv_a + 127u) / 255u;
    uint32_t ob_c = (sb * sa + db * inv_a + 127u) / 255u;
    *dst_px = 0xFF000000u | (or_c << 16) | (og_c << 8) | ob_c;
}

void blink_fb_fill_rrect(blink_framebuffer_t* fb, int x, int y, int w, int h, int radius, uint32_t color) {
    if (!fb || !fb->pixels || w <= 0 || h <= 0) return;
    if (((color >> 24) & 0xFFu) == 0u) return;

    int32_t r_eff = blink_clamp_corner_radius(w, h, radius);
    if (r_eff <= 0) {
        blink_fb_fill_rect(fb, x, y, w, h, color);
        return;
    }

    int x0, y0, x1, y1;
    blink_intersect_scissor(0, 0, fb->width, fb->height, x, y, x + w, y + h, &x0, &y0, &x1, &y1);
    if (x0 >= x1 || y0 >= y1) return;

    float fx = (float)x, fy = (float)y, fw = (float)w, fh = (float)h, fr = (float)r_eff;
    int mid_x0 = x + r_eff;
    int mid_x1 = x + w - r_eff;
    int mid_y0 = y + r_eff;
    int mid_y1 = y + h - r_eff;

    for (int row = y0; row < y1; row++) {
        uint32_t* dst_row = fb->pixels + (size_t)row * (size_t)fb->width;
        bool in_mid_y = (row >= mid_y0 && row < mid_y1);
        for (int c = x0; c < x1; c++) {
            uint32_t cov = 255u;
            if (!in_mid_y && (c < mid_x0 || c >= mid_x1)) {
                float sd = rrect_signed_dist_f((float)c + 0.5f, (float)row + 0.5f, fx, fy, fw, fh, fr);
                cov = rrect_coverage_u8(sd);
            }
            blend_argb_coverage(&dst_row[c], color, cov);
        }
    }
}

void blink_fb_stroke_rrect(blink_framebuffer_t* fb, int x, int y, int w, int h, int radius, int bw, uint32_t color) {
    if (!fb || !fb->pixels || w <= 0 || h <= 0 || bw <= 0) return;
    if (((color >> 24) & 0xFFu) == 0u) return;

    int32_t r_eff = blink_clamp_corner_radius(w, h, radius);
    if (r_eff <= 0) {
        blink_fb_stroke_rect(fb, x, y, w, h, bw, color);
        return;
    }
    if (bw * 2 >= w || bw * 2 >= h) {
        blink_fb_fill_rrect(fb, x, y, w, h, r_eff, color);
        return;
    }

    int x0, y0, x1, y1;
    blink_intersect_scissor(0, 0, fb->width, fb->height, x, y, x + w, y + h, &x0, &y0, &x1, &y1);
    if (x0 >= x1 || y0 >= y1) return;

    float fx = (float)x, fy = (float)y, fw = (float)w, fh = (float)h, fr = (float)r_eff;
    int ix = x + bw, iy = y + bw, iw = w - 2 * bw, ih = h - 2 * bw;
    int ir = (r_eff > bw) ? (r_eff - bw) : 0;
    float fix = (float)ix, fiy = (float)iy, fiw = (float)iw, fih = (float)ih, fir = (float)ir;

    int skip_x0 = ix + ir + 1;
    int skip_x1 = ix + iw - ir - 1;
    int skip_y0 = iy + ir + 1;
    int skip_y1 = iy + ih - ir - 1;

    for (int row = y0; row < y1; row++) {
        uint32_t* dst_row = fb->pixels + (size_t)row * (size_t)fb->width;
        bool in_skip_y = (row >= skip_y0 && row < skip_y1);
        for (int c = x0; c < x1; c++) {
            if (in_skip_y && c >= skip_x0 && c < skip_x1) continue;
            float px = (float)c + 0.5f;
            float py = (float)row + 0.5f;
            uint32_t cov_out = rrect_coverage_u8(rrect_signed_dist_f(px, py, fx, fy, fw, fh, fr));
            if (cov_out == 0u) continue;
            uint32_t cov_in = rrect_coverage_u8(rrect_signed_dist_f(px, py, fix, fiy, fiw, fih, fir));
            uint32_t cov_ring = (cov_out > cov_in) ? (cov_out - cov_in) : 0u;
            blend_argb_coverage(&dst_row[c], color, cov_ring);
        }
    }
}

void blink_fb_fill_rrect_gradient(blink_framebuffer_t* fb,
                                  int x, int y, int w, int h, int radius,
                                  float angle_deg,
                                  const uint32_t* colors,
                                  const int* pos_pct,
                                  int num_stops) {
    if (!fb || !fb->pixels || w <= 0 || h <= 0 || !colors || !pos_pct || num_stops < 2) return;

    int x0, y0, x1, y1;
    blink_intersect_scissor(0, 0, fb->width, fb->height, x, y, x + w, y + h, &x0, &y0, &x1, &y1);
    if (x0 >= x1 || y0 >= y1) return;

    int32_t r_eff = blink_clamp_corner_radius(w, h, radius);
    float fx = (float)x, fy = (float)y, fw = (float)w, fh = (float)h, fr = (float)r_eff;
    float cx = fx + 0.5f * fw;
    float cy = fy + 0.5f * fh;

    /* W3C CSS Images Module Level 3 §4.1.1 gradient line geometry */
    float rad = angle_deg * (3.14159265358979323846f / 180.0f);
    float dx = sinf(rad);
    float dy = -cosf(rad);
    float grad_len = fabsf(fw * dx) + fabsf(fh * dy);
    if (grad_len < 1.0f) grad_len = 1.0f;

    int mid_x0 = x + r_eff;
    int mid_x1 = x + w - r_eff;
    int mid_y0 = y + r_eff;
    int mid_y1 = y + h - r_eff;

    for (int row = y0; row < y1; row++) {
        uint32_t* dst_row = fb->pixels + (size_t)row * (size_t)fb->width;
        bool in_mid_y = (r_eff <= 0) || (row >= mid_y0 && row < mid_y1);
        float py = (float)row + 0.5f;
        for (int c = x0; c < x1; c++) {
            float px = (float)c + 0.5f;
            uint32_t cov = 255u;
            if (!in_mid_y && (c < mid_x0 || c >= mid_x1)) {
                cov = rrect_coverage_u8(rrect_signed_dist_f(px, py, fx, fy, fw, fh, fr));
                if (cov == 0u) continue;
            }

            float proj = (px - cx) * dx + (py - cy) * dy;
            float t_pct = ((proj / grad_len) + 0.5f) * 100.0f;
            if (t_pct <= (float)pos_pct[0]) {
                blend_argb_coverage(&dst_row[c], colors[0], cov);
                continue;
            }
            if (t_pct >= (float)pos_pct[num_stops - 1]) {
                blend_argb_coverage(&dst_row[c], colors[num_stops - 1], cov);
                continue;
            }

            int seg = 0;
            for (int s = 0; s + 1 < num_stops; s++) {
                if (t_pct >= (float)pos_pct[s] && t_pct <= (float)pos_pct[s + 1]) {
                    seg = s;
                    break;
                }
            }
            float span = (float)(pos_pct[seg + 1] - pos_pct[seg]);
            float u = (span > 0.001f) ? ((t_pct - (float)pos_pct[seg]) / span) : 0.0f;
            if (u < 0.0f) u = 0.0f;
            if (u > 1.0f) u = 1.0f;

            uint32_t c0 = colors[seg];
            uint32_t c1 = colors[seg + 1];
            uint32_t a = (uint32_t)lroundf((1.0f - u) * (float)((c0 >> 24) & 0xFFu) + u * (float)((c1 >> 24) & 0xFFu));
            uint32_t r = (uint32_t)lroundf((1.0f - u) * (float)((c0 >> 16) & 0xFFu) + u * (float)((c1 >> 16) & 0xFFu));
            uint32_t g = (uint32_t)lroundf((1.0f - u) * (float)((c0 >> 8) & 0xFFu)  + u * (float)((c1 >> 8) & 0xFFu));
            uint32_t b = (uint32_t)lroundf((1.0f - u) * (float)(c0 & 0xFFu)          + u * (float)(c1 & 0xFFu));
            uint32_t sample = (a << 24) | (r << 16) | (g << 8) | b;
            blend_argb_coverage(&dst_row[c], sample, cov);
        }
    }
}

void blink_fb_draw_box_shadow(blink_framebuffer_t* fb,
                              int x, int y, int w, int h, int radius,
                              int dx, int dy, int blur, int spread,
                              uint32_t color) {
    if (!fb || !fb->pixels || w <= 0 || h <= 0) return;
    if (((color >> 24) & 0xFFu) == 0u) return;

    int sx = x + dx - spread;
    int sy = y + dy - spread;
    int sw = w + 2 * spread;
    int sh = h + 2 * spread;
    if (sw <= 0 || sh <= 0) return;

    int32_t r_base = blink_clamp_corner_radius(w, h, radius);
    int32_t r_sh = blink_clamp_corner_radius(sw, sh, r_base + spread);
    int eff_blur = (blur > 0) ? blur : 0;
    int pad = eff_blur + 2;

    int x0, y0, x1, y1;
    blink_intersect_scissor(0, 0, fb->width, fb->height,
                            sx - pad, sy - pad, sx + sw + pad, sy + sh + pad,
                            &x0, &y0, &x1, &y1);
    if (x0 >= x1 || y0 >= y1) return;

    float fsx = (float)sx, fsy = (float)sy, fsw = (float)sw, fsh = (float)sh, fr = (float)r_sh;
    float blur_f = (float)eff_blur;

    for (int row = y0; row < y1; row++) {
        uint32_t* dst_row = fb->pixels + (size_t)row * (size_t)fb->width;
        float py = (float)row + 0.5f;
        for (int c = x0; c < x1; c++) {
            float px = (float)c + 0.5f;
            float sd = rrect_signed_dist_f(px, py, fsx, fsy, fsw, fsh, fr);
            uint32_t cov = 0u;
            if (eff_blur <= 0) {
                cov = rrect_coverage_u8(sd);
            } else {
                if (sd >= blur_f) continue;
                float u = (blur_f - sd) / (1.5f * blur_f);
                if (u < 0.0f) u = 0.0f;
                if (u > 1.0f) u = 1.0f;
                float smooth = u * u * (3.0f - 2.0f * u);
                cov = (uint32_t)lroundf(smooth * 255.0f);
            }
            if (cov > 0u) {
                blend_argb_coverage(&dst_row[c], color, cov);
            }
        }
    }
}

/* ------------------------------------------------------------------------- */
/* 2. Pure Formal Layout Helpers                                             */
/* ------------------------------------------------------------------------- */

static int border_style_rank(css_border_style_t s) {
    switch (s) {
        case BDR_STYLE_HIDDEN: return 100;
        case BDR_STYLE_DOUBLE: return 7;
        case BDR_STYLE_SOLID:  return 6;
        case BDR_STYLE_DASHED: return 5;
        case BDR_STYLE_DOTTED: return 4;
        case BDR_STYLE_RIDGE:  return 3;
        case BDR_STYLE_OUTSET: return 2;
        case BDR_STYLE_GROOVE: return 1;
        case BDR_STYLE_INSET:  return 1;
        case BDR_STYLE_NONE:
        default:               return 0;
    }
}

blink_collapsed_border_edge_t blink_resolve_collapsed_border(
    blink_collapsed_border_edge_t a,
    blink_collapsed_border_edge_t b) {
    if (a.style == BDR_STYLE_HIDDEN || b.style == BDR_STYLE_HIDDEN) {
        blink_collapsed_border_edge_t r = { 0, BDR_STYLE_HIDDEN, 0 };
        return r;
    }
    bool a_vis = (a.style != BDR_STYLE_NONE && a.width > 0);
    bool b_vis = (b.style != BDR_STYLE_NONE && b.width > 0);
    if (!a_vis && !b_vis) {
        blink_collapsed_border_edge_t r = { 0, BDR_STYLE_NONE, 0 };
        return r;
    }
    if (!a_vis) return b;
    if (!b_vis) return a;
    if (a.width > b.width) return a;
    if (b.width > a.width) return b;
    if (border_style_rank(a.style) >= border_style_rank(b.style)) return a;
    return b;
}

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
                            int32_t* out_size) {
    int32_t pos = 0;
    int32_t sz = 0;
    if (has_start && has_end && has_size) {
        sz = (explicit_size > 0) ? explicit_size : 0;
        pos = inset_start;
    } else if (has_start && has_end && !has_size) {
        int32_t s = cb_size - inset_start - inset_end;
        sz = (s > 0) ? s : 0;
        pos = inset_start;
    } else if (has_start && !has_end) {
        int32_t w = has_size ? explicit_size : intrinsic_size;
        sz = (w > 0) ? w : 0;
        pos = inset_start;
    } else if (!has_start && has_end) {
        int32_t w = has_size ? explicit_size : intrinsic_size;
        if (w < 0) w = 0;
        sz = w;
        pos = cb_size - inset_end - w;
    } else {
        int32_t w = has_size ? explicit_size : intrinsic_size;
        sz = (w > 0) ? w : 0;
        pos = static_pos;
    }
    if (out_pos) *out_pos = pos;
    if (out_size) *out_size = sz;
}

/* ------------------------------------------------------------------------- */
/* 3. DOM Normalization (Preserving Multi-Span Inline Subtrees!)             */
/* ------------------------------------------------------------------------- */

static bool has_hidden_class(const char* cls) {
    if (!cls) return false;
    return (strstr(cls, "mw-empty-elt") != NULL ||
            strstr(cls, "mw-editsection") != NULL ||
            strstr(cls, "noprint") != NULL ||
            strstr(cls, "shortdescription") != NULL ||
            strstr(cls, "navbox") != NULL ||
            strstr(cls, "mw-ref") != NULL);
}

static dom_node_t* find_descendant_img(dom_node_t* n) {
    if (!n) return NULL;
    if (strcmp(n->tag, "img") == 0) return n;
    for (int i = 0; i < n->num_children; i++) {
        dom_node_t* found = find_descendant_img(n->children[i]);
        if (found) return found;
    }
    return NULL;
}

void blink_normalize_dom_for_layout(dom_node_t* node) {
    if (!node) return;
    if (has_hidden_class(node->class_name) ||
        (strcmp(node->tag, "sup") == 0 && node->class_name && strstr(node->class_name, "reference") != NULL)) {
        node->style.display = DISPLAY_NONE;
        return;
    }
    if (node->class_name && strstr(node->class_name, "hatnote") != NULL) {
        node->style.font_style = 1;
        node->style.color = 0xFF54595Du;
        node->style.padding_left = 16;
        node->style.margin_top = 6;
        node->style.margin_bottom = 8;
    }

    /* Lift <a><span><img></span></a> inside <figure> to direct <img> block */
    if (strcmp(node->tag, "figure") == 0) {
        for (int i = 0; i < node->num_children; i++) {
            dom_node_t* ch = node->children[i];
            if (strcmp(ch->tag, "figcaption") != 0) {
                dom_node_t* img = find_descendant_img(ch);
                if (img && img != ch) {
                    dom_node_t* cloned_img = dom_node_create("img");
                    cloned_img->style = img->style;
                    cloned_img->dom_order = img->dom_order;
                    if (img->src) cloned_img->src = strdup(img->src);
                    dom_node_free(ch);
                    cloned_img->parent = node;
                    node->children[i] = cloned_img;
                }
            }
        }
    }

    for (int i = 0; i < node->num_children; i++) {
        blink_normalize_dom_for_layout(node->children[i]);
    }
}

/* ------------------------------------------------------------------------- */
/* 4. Float Exclusion Space (`BlinkCSS4InlineAndPositionedLayoutEngine.v`)   */
/* ------------------------------------------------------------------------- */

#define BLINK_MAX_ACTIVE_FLOATS 64

typedef struct {
    int            x0;
    int            x1;
    int            y0;
    int            y1;
    css_float_t    side;
} float_box_t;

typedef struct {
    float_box_t boxes[BLINK_MAX_ACTIVE_FLOATS];
    int         count;
} float_space_t;

static void float_space_band(const float_space_t* fs,
                             int box_left,
                             int box_right,
                             int y,
                             int h,
                             int* out_left,
                             int* out_right) {
    int bl = box_left;
    int br = box_right;
    if (fs && h > 0) {
        int y1 = y + h;
        for (int i = 0; i < fs->count; i++) {
            const float_box_t* fb = &fs->boxes[i];
            if (fb->y1 > y && fb->y0 < y1) {
                if (fb->side == FLOAT_LEFT && fb->x1 > bl) bl = fb->x1;
                if (fb->side == FLOAT_RIGHT && fb->x0 < br) br = fb->x0;
            }
        }
    }
    if (br < bl) br = bl;
    *out_left = bl;
    *out_right = br;
}

static int float_space_clear_y(const float_space_t* fs, css_clear_t clear_mode, int cur_y) {
    if (!fs || clear_mode == CLEAR_NONE) return cur_y;
    int res = cur_y;
    for (int i = 0; i < fs->count; i++) {
        const float_box_t* fb = &fs->boxes[i];
        bool match = (clear_mode == CLEAR_BOTH) ||
                     (clear_mode == CLEAR_LEFT && fb->side == FLOAT_LEFT) ||
                     (clear_mode == CLEAR_RIGHT && fb->side == FLOAT_RIGHT);
        if (match && fb->y1 > res) res = fb->y1;
    }
    return res;
}

static int float_space_next_drop_y(const float_space_t* fs, int cur_y) {
    if (!fs) return cur_y + 1;
    int best = -1;
    for (int i = 0; i < fs->count; i++) {
        const float_box_t* fb = &fs->boxes[i];
        if (fb->y1 > cur_y && (best < 0 || fb->y1 < best)) {
            best = fb->y1;
        }
    }
    return (best > cur_y) ? best : (cur_y + 1);
}

static int float_space_max_bottom(const float_space_t* fs, int cur_y) {
    if (!fs) return cur_y;
    int res = cur_y;
    for (int i = 0; i < fs->count; i++) {
        if (fs->boxes[i].y1 > res) res = fs->boxes[i].y1;
    }
    return res;
}

/* ------------------------------------------------------------------------- */
/* 5. Subtree Coordinate Shifting & Intrinsic Width Measurement              */
/* ------------------------------------------------------------------------- */

static bool is_out_of_flow(const dom_node_t* n) {
    if (!n) return false;
    return (n->style.position == POS_ABSOLUTE || n->style.position == POS_FIXED);
}

static void shift_subtree_xy(dom_node_t* n, int dx, int dy) {
    if (!n || (dx == 0 && dy == 0)) return;
    n->x += dx;
    n->y += dy;
    for (int k = 0; k < n->num_inline_frags; k++) {
        n->inline_frags[k].x += (float)dx;
        n->inline_frags[k].y += (float)dy;
        n->inline_frags[k].baseline_y += (float)dy;
    }
    for (int i = 0; i < n->num_children; i++) {
        /* POS_FIXED children are anchored to the viewport, not shifted with ancestors */
        if (n->children[i] && n->children[i]->style.position == POS_FIXED) continue;
        shift_subtree_xy(n->children[i], dx, dy);
    }
}

static float measure_inline_Run_advance(const dom_node_t* n, const dom_node_t* style_owner) {
    if (!n || n->style.display == DISPLAY_NONE || is_out_of_flow(n)) return 0.0f;
    if (strcmp(n->tag, "#text") == 0 && n->text) {
        const dom_style_t* st = &style_owner->style;
        float w = blink_skia_font_measure_text(n->text, st->font_family, st->font_size,
                                               st->font_weight >= 700 ? 1 : 0);
        return w;
    }
    float sum = (float)(n->style.padding_left + n->style.padding_right + n->style.border_width * 2);
    const dom_node_t* next_owner = (n->style.display == DISPLAY_INLINE) ? n : style_owner;
    for (int i = 0; i < n->num_children; i++) {
        sum += measure_inline_Run_advance(n->children[i], next_owner);
    }
    return sum;
}

static int measure_intrinsic_outer_width(dom_node_t* item, int max_avail_w) {
    if (!item) return 0;
    int bdr_left = (item->style.border_width > 0) ? item->style.border_width : item->style.border_left_width;
    int bdr_h = bdr_left + item->style.border_width;
    int pad_h = item->style.padding_left + item->style.padding_right;

    if (item->style.width > 0) {
        int ow = (item->style.box_sizing == BOX_SIZING_BORDER_BOX)
                     ? item->style.width
                     : (item->style.width + pad_h + bdr_h);
        if (item->style.max_width >= 0 && ow > item->style.max_width) ow = item->style.max_width;
        if (ow < item->style.min_width) ow = item->style.min_width;
        return ow;
    }

    float max_child_w = 0.0f;
    float inline_acc = 0.0f;
    for (int i = 0; i < item->num_children; i++) {
        dom_node_t* ch = item->children[i];
        if (!ch || ch->style.display == DISPLAY_NONE || is_out_of_flow(ch)) continue;
        if (strcmp(ch->tag, "br") == 0) {
            if (inline_acc > max_child_w) max_child_w = inline_acc;
            inline_acc = 0.0f;
            continue;
        }
        if (strcmp(ch->tag, "#text") == 0 || ch->style.display == DISPLAY_INLINE) {
            inline_acc += measure_inline_Run_advance(ch, (ch->style.display == DISPLAY_INLINE && strcmp(ch->tag, "#text") != 0) ? ch : item);
        } else {
            if (inline_acc > max_child_w) max_child_w = inline_acc;
            inline_acc = 0.0f;
            int sub_w = measure_intrinsic_outer_width(ch, max_avail_w) + ch->style.margin_left + ch->style.margin_right;
            if ((float)sub_w > max_child_w) max_child_w = (float)sub_w;
        }
    }
    if (inline_acc > max_child_w) max_child_w = inline_acc;

    int res = (int)ceilf(max_child_w) + pad_h + bdr_h + 4;
    if (max_avail_w > 0 && res > max_avail_w) res = max_avail_w;
    if (item->style.max_width >= 0 && res > item->style.max_width) res = item->style.max_width;
    if (res < item->style.min_width) res = item->style.min_width;
    return res;
}

/* ------------------------------------------------------------------------- */
/* 6. Pillar 3: Multi-Span Inline Formatting Context (`blink_inline_frag_t`) */
/* ------------------------------------------------------------------------- */

typedef struct {
    bool               is_br;
    bool               space_before;
    char               text[256];
    const dom_node_t*  owner;
    const dom_style_t* style;
    int                pad_l;
    int                pad_r;
} inline_tok_t;

typedef struct {
    inline_tok_t* items;
    int           count;
    int           cap;
    bool          prev_had_trailing_ws;
} inline_tok_vec_t;

static void tok_vec_push(inline_tok_vec_t* vec, const inline_tok_t* tok) {
    if (vec->count + 1 > vec->cap) {
        int ncap = (vec->cap == 0) ? 64 : (vec->cap * 2);
        inline_tok_t* np = (inline_tok_t*)realloc(vec->items, (size_t)ncap * sizeof(inline_tok_t));
        if (!np) return;
        vec->items = np;
        vec->cap = ncap;
    }
    vec->items[vec->count++] = *tok;
}

static bool is_attaching_punct(char c) {
    return (c == ',' || c == '.' || c == ';' || c == ':' ||
            c == '!' || c == '?' || c == ')' || c == ']');
}

static bool subtree_is_pure_inline(const dom_node_t* n) {
    if (!n || n->style.display == DISPLAY_NONE || has_hidden_class(n->class_name)) return true;
    if (is_out_of_flow(n)) return true;
    if (strcmp(n->tag, "meta") == 0 || strcmp(n->tag, "link") == 0 || strcmp(n->tag, "wbr") == 0) return true;
    if (strcmp(n->tag, "br") == 0 || strcmp(n->tag, "#text") == 0) return true;
    if (strcmp(n->tag, "img") == 0 || strcmp(n->tag, "figure") == 0 ||
        strcmp(n->tag, "table") == 0 || strcmp(n->tag, "ul") == 0 ||
        strcmp(n->tag, "ol") == 0 || strcmp(n->tag, "blockquote") == 0 ||
        strcmp(n->tag, "pre") == 0) return false;
    if (n->style.css_float != FLOAT_NONE) return false;
    if (n->style.display != DISPLAY_INLINE) return false;
    for (int i = 0; i < n->num_children; i++) {
        if (!subtree_is_pure_inline(n->children[i])) return false;
    }
    return true;
}

static void collect_inline_tokens(const dom_node_t* n,
                                  const dom_node_t* style_owner,
                                  inline_tok_vec_t* vec) {
    if (!n || n->style.display == DISPLAY_NONE || has_hidden_class(n->class_name)) return;
    if (is_out_of_flow(n) || n->style.css_float != FLOAT_NONE) return;

    if (strcmp(n->tag, "br") == 0) {
        inline_tok_t t;
        memset(&t, 0, sizeof(t));
        t.is_br = true;
        t.owner = style_owner;
        t.style = &style_owner->style;
        tok_vec_push(vec, &t);
        vec->prev_had_trailing_ws = false;
        return;
    }

    if (strcmp(n->tag, "#text") == 0 && n->text) {
        const dom_style_t* st = &style_owner->style;
        const char* s = n->text;

        if (st->white_space == WS_PRE) {
            /* Preserve exact leading/internal spaces and split strictly on '\n' */
            const char* p = s;
            while (*p) {
                if (*p == '\r') { p++; continue; }
                if (*p == '\n') {
                    inline_tok_t br_tok;
                    memset(&br_tok, 0, sizeof(br_tok));
                    br_tok.is_br = true;
                    br_tok.owner = style_owner;
                    br_tok.style = st;
                    tok_vec_push(vec, &br_tok);
                    vec->prev_had_trailing_ws = false;
                    p++;
                    continue;
                }
                inline_tok_t tok;
                memset(&tok, 0, sizeof(tok));
                tok.owner = style_owner;
                tok.style = st;
                tok.space_before = false;
                int ti = 0;
                while (*p && *p != '\n' && *p != '\r' && ti < (int)sizeof(tok.text) - 5) {
                    if (*p == '\t') {
                        for (int sp = 0; sp < 4; sp++) tok.text[ti++] = ' ';
                        p++;
                    } else {
                        tok.text[ti++] = *p++;
                    }
                }
                tok.text[ti] = '\0';
                if (ti > 0) tok_vec_push(vec, &tok);
            }
            return;
        }

        if (st->white_space == WS_NOWRAP) {
            bool lead_ws = isspace((unsigned char)s[0]) != 0;
            size_t slen = strlen(s);
            bool trail_ws = (slen > 0 && isspace((unsigned char)s[slen - 1]) != 0);
            inline_tok_t tok;
            memset(&tok, 0, sizeof(tok));
            tok.owner = style_owner;
            tok.style = st;
            int ti = 0;
            bool in_ws = false;
            for (size_t k = 0; k < slen && ti < (int)sizeof(tok.text) - 1; k++) {
                if (isspace((unsigned char)s[k])) {
                    if (ti > 0) in_ws = true;
                } else {
                    if (in_ws && ti < (int)sizeof(tok.text) - 1) {
                        tok.text[ti++] = ' ';
                        in_ws = false;
                    }
                    tok.text[ti++] = s[k];
                }
            }
            tok.text[ti] = '\0';
            if (ti > 0) {
                tok.space_before = (vec->prev_had_trailing_ws || lead_ws) && !is_attaching_punct(tok.text[0]);
                tok_vec_push(vec, &tok);
                vec->prev_had_trailing_ws = trail_ws;
            } else if (lead_ws || trail_ws) {
                vec->prev_had_trailing_ws = true;
            }
            return;
        }

        /* WS_NORMAL: collapse whitespace runs into inter-word breakable tokens */
        size_t slen = strlen(s);
        if (slen == 0) return;
        bool lead_ws = isspace((unsigned char)s[0]) != 0;
        bool trail_ws = isspace((unsigned char)s[slen - 1]) != 0;

        const char* p = s;
        bool first_word = true;
        while (*p) {
            while (*p && isspace((unsigned char)*p)) p++;
            if (!*p) break;
            inline_tok_t tok;
            memset(&tok, 0, sizeof(tok));
            tok.owner = style_owner;
            tok.style = st;
            int ti = 0;
            while (*p && !isspace((unsigned char)*p) && ti < (int)sizeof(tok.text) - 1) {
                tok.text[ti++] = *p++;
            }
            tok.text[ti] = '\0';
            if (first_word) {
                bool want_sp = vec->prev_had_trailing_ws || lead_ws;
                if (!want_sp && vec->count > 0 && !vec->items[vec->count - 1].is_br &&
                    vec->items[vec->count - 1].owner != style_owner &&
                    !is_attaching_punct(tok.text[0])) {
                    /* Respect explicit HTML lack of space unless pill has padding */
                    want_sp = (style_owner->style.has_bg || vec->items[vec->count - 1].owner->style.has_bg);
                }
                tok.space_before = want_sp;
                first_word = false;
            } else {
                tok.space_before = true;
            }
            tok_vec_push(vec, &tok);
        }
        if (first_word) {
            /* Pure whitespace text node between inline elements */
            if (lead_ws) vec->prev_had_trailing_ws = true;
        } else {
            vec->prev_had_trailing_ws = trail_ws;
        }
        return;
    }

    /* Inline element (`<b>`, `<i>`, `<a>`, `<code>`, `<span>`, `<sub>`, `<sup>`, `::before`, `::after`) */
    int start_idx = vec->count;
    for (int i = 0; i < n->num_children; i++) {
        collect_inline_tokens(n->children[i], n, vec);
    }
    if (vec->count > start_idx) {
        int bdr = n->style.border_width;
        if (n->style.padding_left > 0 || bdr > 0) {
            vec->items[start_idx].pad_l += n->style.padding_left + bdr;
        }
        if (n->style.padding_right > 0 || bdr > 0) {
            vec->items[vec->count - 1].pad_r += n->style.padding_right + bdr;
        }
    }
}

static void emit_line_fragments(dom_node_t* container,
                                const inline_tok_t* toks,
                                int ls,
                                int le,
                                int line_idx,
                                int band_l,
                                int band_r,
                                float cur_y,
                                float line_max_h,
                                float line_max_fsize,
                                blink_inline_frag_t** io_frags,
                                int* io_nfrags,
                                int* io_cap) {
    if (ls >= le) return;

    /* 1. Merge consecutive tokens on this line that share the exact same `owner` */
    typedef struct {
        char               text[256];
        const dom_node_t*  owner;
        const dom_style_t* style;
        int                pad_l;
        int                pad_r;
        float              gap_before;
        float              glyph_w;
        float              advance_w;
    } merged_run_t;

    merged_run_t runs[128];
    int n_runs = 0;
    float total_line_w = 0.0f;

    for (int i = ls; i < le; i++) {
        const inline_tok_t* t = &toks[i];
        if (t->is_br) continue;
        const dom_style_t* st = t->style;
        float sp_w = 0.0f;
        if (n_runs > 0 && t->space_before) {
            sp_w = blink_skia_font_measure_text(" ", st->font_family, st->font_size, 0);
        }

        /* Try merging into previous run if same owner and text fits in 255 bytes */
        if (n_runs > 0 && runs[n_runs - 1].owner == t->owner) {
            merged_run_t* prev = &runs[n_runs - 1];
            size_t cur_len = strlen(prev->text);
            size_t add_len = strlen(t->text) + (t->space_before ? 1 : 0);
            if (cur_len + add_len < sizeof(prev->text) - 1) {
                if (t->space_before) strcat(prev->text, " ");
                strcat(prev->text, t->text);
                prev->pad_r = t->pad_r;
                float new_text_w = blink_skia_font_measure_text(
                    prev->text, st->font_family, st->font_size, st->font_weight >= 700 ? 1 : 0);
                float old_adv = prev->advance_w;
                prev->glyph_w = new_text_w;
                prev->advance_w = new_text_w + (float)(prev->pad_l + prev->pad_r);
                total_line_w += (prev->advance_w - old_adv);
                continue;
            }
        }

        if (n_runs < 128) {
            merged_run_t* mr = &runs[n_runs++];
            strncpy(mr->text, t->text, sizeof(mr->text) - 1);
            mr->text[sizeof(mr->text) - 1] = '\0';
            mr->owner = t->owner;
            mr->style = st;
            mr->pad_l = t->pad_l;
            mr->pad_r = t->pad_r;
            mr->gap_before = (n_runs == 1) ? 0.0f : sp_w;
            float tw = blink_skia_font_measure_text(
                mr->text, st->font_family, st->font_size, st->font_weight >= 700 ? 1 : 0);
            mr->glyph_w = tw;
            mr->advance_w = tw + (float)(mr->pad_l + mr->pad_r);
            total_line_w += mr->gap_before + mr->advance_w;
        }
    }

    float avail_w = (float)(band_r - band_l);
    float align_dx = 0.0f;
    if (container->style.text_align == ALIGN_CENTER && total_line_w < avail_w) {
        align_dx = (avail_w - total_line_w) * 0.5f;
    } else if (container->style.text_align == ALIGN_RIGHT && total_line_w < avail_w) {
        align_dx = avail_w - total_line_w;
    }

    float pen_x = (float)band_l + align_dx;
    float base_bl = cur_y + line_max_fsize * 0.83f;

    for (int r = 0; r < n_runs; r++) {
        const merged_run_t* mr = &runs[r];
        const dom_style_t* st = mr->style;
        pen_x += mr->gap_before;

        if (*io_nfrags + 1 > *io_cap) {
            int ncap = (*io_cap == 0) ? 32 : (*io_cap * 2);
            blink_inline_frag_t* np = (blink_inline_frag_t*)realloc(
                *io_frags, (size_t)ncap * sizeof(blink_inline_frag_t));
            if (!np) return;
            *io_frags = np;
            *io_cap = ncap;
        }

        blink_inline_frag_t* fg = &(*io_frags)[(*io_nfrags)++];
        memset(fg, 0, sizeof(*fg));
        fg->x = pen_x;
        fg->y = cur_y;
        fg->w = mr->advance_w;
        fg->glyph_w = mr->glyph_w;
        fg->h = line_max_h;
        fg->line_index = line_idx;

        float bl = base_bl;
        if (st->vertical_align == VALIGN_SUPER) bl -= line_max_fsize * 0.32f;
        else if (st->vertical_align == VALIGN_SUB) bl += line_max_fsize * 0.18f;
        else if (st->vertical_align == VALIGN_MIDDLE) bl -= (line_max_fsize - st->font_size) * 0.35f;
        fg->baseline_y = bl;
        fg->vertical_align = st->vertical_align;

        strncpy(fg->text, mr->text, sizeof(fg->text) - 1);
        strncpy(fg->font_family, st->font_family, sizeof(fg->font_family) - 1);
        fg->font_size = st->font_size;
        fg->font_weight = st->font_weight;
        fg->font_style = st->font_style;
        fg->color = st->color;
        fg->has_bg = (mr->owner != container) && st->has_bg;
        fg->bg_color = st->bg_color;
        fg->pad_left = mr->pad_l;
        fg->pad_right = mr->pad_r;
        fg->pad_top = (mr->owner != container) ? st->padding_top : 0;
        fg->pad_bottom = (mr->owner != container) ? st->padding_bottom : 0;
        fg->border_width = (mr->owner != container) ? st->border_width : 0;
        fg->border_color = st->border_color;
        fg->border_radius = (mr->owner != container) ? st->border_radius : 0;
        fg->underline = st->text_underline || container->style.text_underline;
        fg->line_through = st->text_line_through || container->style.text_line_through;

        pen_x += mr->advance_w;
    }
}

static int layout_inline_formatting_context(dom_node_t* container,
                                            int box_x,
                                            int box_y,
                                            int box_w,
                                            const float_space_t* fspace) {
    free(container->inline_frags);
    container->inline_frags = NULL;
    container->num_inline_frags = 0;

    inline_tok_vec_t vec = { NULL, 0, 0, false };
    for (int i = 0; i < container->num_children; i++) {
        collect_inline_tokens(container->children[i], container, &vec);
    }

    if (vec.count == 0) {
        free(vec.items);
        return box_y;
    }

    float base_fsize = container->style.font_size;
    float base_lh_mult = (container->style.line_height > 0.5f) ? container->style.line_height : 1.38f;
    float base_line_h = base_fsize * base_lh_mult;

    blink_inline_frag_t* frags = NULL;
    int nfrags = 0, cap_frags = 0;

    float cur_y = (float)box_y;
    int idx = 0;
    int line_counter = 0;
    while (idx < vec.count) {
        /* Forced empty line from leading/consecutive `<br>` or `\n` in `<pre>` */
        if (vec.items[idx].is_br) {
            cur_y += base_line_h;
            line_counter++;
            idx++;
            continue;
        }

        int band_l = box_x, band_r = box_x + box_w;
        float_space_band(fspace, box_x, box_x + box_w, (int)floorf(cur_y), (int)ceilf(base_line_h),
                         &band_l, &band_r);
        float avail_w = (float)(band_r - band_l);

        const inline_tok_t* first_t = &vec.items[idx];
        float first_w = blink_skia_font_measure_text(
                            first_t->text, first_t->style->font_family, first_t->style->font_size,
                            first_t->style->font_weight >= 700 ? 1 : 0) +
                        (float)(first_t->pad_l + first_t->pad_r);

        /* CSS 2.2 §9.5: If even the first word doesn't fit next to active floats, drop below floats! */
        int drop_guard = 0;
        while (first_w > avail_w && (band_l > box_x || band_r < box_x + box_w) && drop_guard < 32) {
            int next_y = float_space_next_drop_y(fspace, (int)floorf(cur_y));
            cur_y = (float)next_y;
            float_space_band(fspace, box_x, box_x + box_w, (int)floorf(cur_y), (int)ceilf(base_line_h),
                             &band_l, &band_r);
            avail_w = (float)(band_r - band_l);
            drop_guard++;
        }

        int line_start = idx;
        float used_w = 0.0f;
        float line_max_h = base_line_h;
        float line_max_fsize = base_fsize;
        bool ended_by_br = false;

        while (idx < vec.count) {
            const inline_tok_t* t = &vec.items[idx];
            if (t->is_br) {
                idx++;
                ended_by_br = true;
                break;
            }
            const dom_style_t* st = t->style;
            float sp_w = (idx > line_start && t->space_before)
                             ? blink_skia_font_measure_text(" ", st->font_family, st->font_size, 0)
                             : 0.0f;
            float tw = blink_skia_font_measure_text(
                           t->text, st->font_family, st->font_size, st->font_weight >= 700 ? 1 : 0) +
                       (float)(t->pad_l + t->pad_r);

            bool can_wrap = (container->style.white_space == WS_NORMAL && st->white_space == WS_NORMAL);
            if (can_wrap && idx > line_start && (used_w + sp_w + tw > avail_w)) {
                break;
            }

            used_w += sp_w + tw;
            float tok_lh = st->font_size * ((st->line_height > 0.5f) ? st->line_height : base_lh_mult) +
                           (float)((t->owner != container) ? (st->padding_top + st->padding_bottom) : 0);
            if (tok_lh > line_max_h) line_max_h = tok_lh;
            if (st->font_size > line_max_fsize) line_max_fsize = st->font_size;
            idx++;
        }

        int line_end = ended_by_br ? (idx - 1) : idx;
        emit_line_fragments(container, vec.items, line_start, line_end, line_counter++,
                            band_l, band_r, cur_y, line_max_h, line_max_fsize,
                            &frags, &nfrags, &cap_frags);
        cur_y += line_max_h;
    }

    free(vec.items);
    container->inline_frags = frags;
    container->num_inline_frags = nfrags;
    return (int)ceilf(cur_y);
}

/* ------------------------------------------------------------------------- */
/* 7. Pillar 4: Complete Block, Float, OOF, Flex, Grid & 2D Table Layout     */
/* ------------------------------------------------------------------------- */

typedef struct {
    int viewport_w;
    int viewport_h;
    blink_layout_mode_t mode;
} layout_env_t;

static int layout_node_internal(dom_node_t* node,
                                int container_x,
                                int container_y,
                                int container_w,
                                bool establishes_bfc,
                                float_space_t* inherited_fspace,
                                const layout_env_t* env,
                                int* out_max_y);

static void collect_table_rows(dom_node_t* container, dom_node_t** rows, int* io_count, int max_rows) {
    if (!container || !rows || !io_count) return;
    for (int i = 0; i < container->num_children && *io_count < max_rows; i++) {
        dom_node_t* ch = container->children[i];
        if (!ch || ch->style.display == DISPLAY_NONE || is_out_of_flow(ch)) continue;
        if (strcmp(ch->tag, "tr") == 0 || ch->style.display == DISPLAY_TABLE_ROW) {
            rows[(*io_count)++] = ch;
        } else if (strcmp(ch->tag, "thead") == 0 || strcmp(ch->tag, "tbody") == 0 ||
                   strcmp(ch->tag, "tfoot") == 0 || ch->style.display == DISPLAY_TABLE_ROW_GROUP) {
            collect_table_rows(ch, rows, io_count, max_rows);
        }
    }
}

/* Lay out out-of-flow (`position: absolute | fixed`) descendants whose
   containing block is `cb_node` (or the root viewport for `POS_FIXED`). */
static void layout_oof_for_containing_block(dom_node_t* scan,
                                            dom_node_t* cb_node,
                                            int cb_x,
                                            int cb_y,
                                            int cb_w,
                                            int cb_h,
                                            bool is_root_cb,
                                            const layout_env_t* env,
                                            int* out_max_y) {
    if (!scan) return;
    for (int i = 0; i < scan->num_children; i++) {
        dom_node_t* ch = scan->children[i];
        if (!ch || ch->style.display == DISPLAY_NONE) continue;

        bool cb_captures_fixed = is_root_cb || (cb_node && cb_node->style.has_transform);
        bool target_abs = (ch->style.position == POS_ABSOLUTE);
        bool target_fix = (ch->style.position == POS_FIXED && cb_captures_fixed);

        if (target_abs || target_fix) {
            bool fixed_to_viewport = (ch->style.position == POS_FIXED && is_root_cb &&
                                      (!cb_node || !cb_node->style.has_transform));
            int rx = fixed_to_viewport ? 0 : cb_x;
            int ry = fixed_to_viewport ? 0 : cb_y;
            int rw = fixed_to_viewport ? env->viewport_w : cb_w;
            int rh = fixed_to_viewport ? env->viewport_h : cb_h;

            int bdr_left = (ch->style.border_width > 0) ? ch->style.border_width : ch->style.border_left_width;
            int bdr_h = bdr_left + ch->style.border_width;
            int pad_h = ch->style.padding_left + ch->style.padding_right;
            int bdr_v = ch->style.border_width * 2;
            int pad_v = ch->style.padding_top + ch->style.padding_bottom;

            bool has_expl_w = (ch->style.width >= 0);
            int expl_outer_w = 0;
            if (has_expl_w) {
                expl_outer_w = (ch->style.box_sizing == BOX_SIZING_BORDER_BOX)
                                   ? ch->style.width
                                   : (ch->style.width + pad_h + bdr_h);
            }
            int intr_w = measure_intrinsic_outer_width(ch, rw);
            int static_rel_x = (scan->x - rx) + ch->style.margin_left;
            int static_rel_y = (scan->y - ry) + ch->style.margin_top;

            int32_t rel_x = 0, resolved_w = 0;
            int32_t eff_left = ch->style.left + ch->style.margin_left;
            int32_t eff_right = ch->style.right + ch->style.margin_right;
            blink_resolve_abs_axis(rw, eff_left, ch->style.has_left, eff_right, ch->style.has_right,
                                   expl_outer_w, has_expl_w, intr_w, static_rel_x,
                                   &rel_x, &resolved_w);
            if (ch->style.max_width >= 0 && resolved_w > ch->style.max_width) resolved_w = ch->style.max_width;
            if (resolved_w < ch->style.min_width) resolved_w = ch->style.min_width;

            /* Lay out OOF box with resolved outer width at temporary y = ry */
            int saved_w = ch->style.width;
            css_box_sizing_t saved_bs = ch->style.box_sizing;
            int saved_ml = ch->style.margin_left;
            int saved_mr = ch->style.margin_right;
            ch->style.width = resolved_w;
            ch->style.box_sizing = BOX_SIZING_BORDER_BOX;
            ch->style.margin_left = 0;
            ch->style.margin_right = 0;

            int sub_max_y = 0;
            layout_node_internal(ch, rx + rel_x, ry, resolved_w, true, NULL, env, &sub_max_y);

            ch->style.width = saved_w;
            ch->style.box_sizing = saved_bs;
            ch->style.margin_left = saved_ml;
            ch->style.margin_right = saved_mr;

            int intr_h = ch->h;
            bool has_expl_h = (ch->style.height >= 0);
            int expl_outer_h = 0;
            if (has_expl_h) {
                expl_outer_h = (ch->style.box_sizing == BOX_SIZING_BORDER_BOX)
                                   ? ch->style.height
                                   : (ch->style.height + pad_v + bdr_v);
            }
            int32_t rel_y = 0, resolved_h = 0;
            int32_t res_top = ch->style.top_is_pct ? (int32_t)lroundf(ch->style.top_pct * (float)rh / 100.0f) : ch->style.top;
            int32_t res_bot = ch->style.bottom_is_pct ? (int32_t)lroundf(ch->style.bottom_pct * (float)rh / 100.0f) : ch->style.bottom;
            int32_t eff_top = res_top + ch->style.margin_top;
            int32_t eff_bot = res_bot + ch->style.margin_bottom;
            blink_resolve_abs_axis(rh, eff_top, ch->style.has_top, eff_bot, ch->style.has_bottom,
                                   expl_outer_h, has_expl_h, intr_h, static_rel_y,
                                   &rel_y, &resolved_h);

            int target_abs_y = ry + rel_y;
            shift_subtree_xy(ch, 0, target_abs_y - ch->y);
            ch->h = resolved_h;
            if (ch->y + ch->h > *out_max_y) *out_max_y = ch->y + ch->h;

            /* Notice `ch` itself is positioned (`POS_ABSOLUTE`/`POS_FIXED`), so `layout_node_internal`
               already resolved any `POS_ABSOLUTE` children inside `ch`! If `is_root_cb`, scan inside
               `ch` ONLY for nested `POS_FIXED` elements if any. */
            if (is_root_cb && !target_fix) {
                /* Nested fixed scan handled below when ch->position != POS_STATIC */
            }
            continue;
        }

        /* Do not cross into nested positioned or transformed containing blocks for `POS_ABSOLUTE`! */
        if (ch->style.position == POS_STATIC && !ch->style.has_transform) {
            layout_oof_for_containing_block(ch, cb_node, cb_x, cb_y, cb_w, cb_h, is_root_cb, env, out_max_y);
        } else if (is_root_cb && !ch->style.has_transform) {
            /* Still scan inside positioned descendants solely for `POS_FIXED` */
            for (int k = 0; k < ch->num_children; k++) {
                dom_node_t* sub = ch->children[k];
                if (sub && sub->style.position == POS_FIXED && sub->style.display != DISPLAY_NONE) {
                    /* Create a 1-child wrapper scan by recursing on ch ONLY if sub is POS_FIXED */
                    layout_oof_for_containing_block(ch, cb_node, 0, 0, env->viewport_w, env->viewport_h,
                                                    true, env, out_max_y);
                    break;
                }
            }
        }
    }
}

static void place_float_child(dom_node_t* fl,
                              int box_left,
                              int box_right,
                              int min_y,
                              float_space_t* fspace,
                              const layout_env_t* env,
                              int* out_max_y) {
    int avail_w = box_right - box_left;
    if (avail_w < 0) avail_w = 0;

    int fl_y = float_space_clear_y(fspace, fl->style.css_clear, min_y);
    int outer_w = measure_intrinsic_outer_width(fl, avail_w);
    int total_fl_w = outer_w + fl->style.margin_left + fl->style.margin_right;

    /* Drop `fl_y` until horizontal band `[bl, br]` fits `total_fl_w` (if floats overlap `fl_y`) */
    int bl = box_left, br = box_right;
    int guard = 0;
    while (guard < 32) {
        float_space_band(fspace, box_left, box_right, fl_y, 24, &bl, &br);
        if ((br - bl) >= total_fl_w || (bl == box_left && br == box_right)) break;
        fl_y = float_space_next_drop_y(fspace, fl_y);
        guard++;
    }

    int place_x = (fl->style.css_float == FLOAT_RIGHT)
                      ? (br - fl->style.margin_right - outer_w)
                      : (bl + fl->style.margin_left);

    int saved_w = fl->style.width;
    css_box_sizing_t saved_bs = fl->style.box_sizing;
    int saved_ml = fl->style.margin_left;
    int saved_mr = fl->style.margin_right;
    fl->style.width = outer_w;
    fl->style.box_sizing = BOX_SIZING_BORDER_BOX;
    fl->style.margin_left = 0;
    fl->style.margin_right = 0;

    int sub_max_y = 0;
    layout_node_internal(fl, place_x, fl_y + fl->style.margin_top, outer_w, true, NULL, env, &sub_max_y);

    fl->style.width = saved_w;
    fl->style.box_sizing = saved_bs;
    fl->style.margin_left = saved_ml;
    fl->style.margin_right = saved_mr;

    if (fl->y + fl->h > *out_max_y) *out_max_y = fl->y + fl->h;

    if (fspace && fspace->count < BLINK_MAX_ACTIVE_FLOATS) {
        float_box_t* entry = &fspace->boxes[fspace->count++];
        entry->side = fl->style.css_float;
        entry->x0 = place_x - saved_ml;
        entry->x1 = place_x + outer_w + saved_mr;
        entry->y0 = fl_y;
        entry->y1 = fl->y + fl->h + fl->style.margin_bottom;
        /* Add 8px breathing gutter on inner text-facing side if margin was 0 */
        if (entry->side == FLOAT_LEFT && saved_mr == 0) entry->x1 += 8;
        if (entry->side == FLOAT_RIGHT && saved_ml == 0) entry->x0 -= 8;
    }
}

static int clamp_size_min_max(int w, int min_w, int max_w) {
    if (max_w >= 0 && w > max_w) w = max_w;
    if (w < min_w) w = min_w;
    if (w < 0) w = 0;
    return w;
}

static int layout_node_internal(dom_node_t* node,
                                int container_x,
                                int container_y,
                                int container_w,
                                bool establishes_bfc,
                                float_space_t* inherited_fspace,
                                const layout_env_t* env,
                                int* out_max_y) {
    if (!node || node->style.display == DISPLAY_NONE) return container_y;

    blink_layout_mode_t mode = env->mode;
    int eff_padding_left = (int)blink_z_floor_device_pixel(blink_z_from_pixel(node->style.padding_left, mode), mode);
    int eff_padding_right = (int)blink_z_floor_device_pixel(blink_z_from_pixel(node->style.padding_right, mode), mode);
    int bdr_left = (node->style.border_width > 0) ? node->style.border_width : node->style.border_left_width;
    int bdr_right = node->style.border_width;
    int pad_h = eff_padding_left + eff_padding_right;
    int bdr_h = bdr_left + bdr_right;

    node->x = container_x + node->style.margin_left;
    int content_w = 0;
    if (node->style.width > 0) {
        content_w = blink_css_resolve_content_inline_size(node->style.box_sizing, node->style.width, pad_h, bdr_h);
        node->w = (node->style.box_sizing == BOX_SIZING_BORDER_BOX)
                      ? node->style.width
                      : (content_w + pad_h + bdr_h);
    } else {
        node->w = container_w - node->style.margin_left - node->style.margin_right;
        if (node->w < 0) node->w = 0;
        content_w = node->w - pad_h - bdr_h;
        if (content_w < 0) content_w = 0;
    }

    /* Apply `min-width` / `max-width` clamping */
    if (node->style.max_width >= 0 || node->style.min_width > 0) {
        int max_outer = (node->style.max_width >= 0)
                            ? ((node->style.box_sizing == BOX_SIZING_BORDER_BOX)
                                   ? node->style.max_width
                                   : (node->style.max_width + pad_h + bdr_h))
                            : -1;
        int min_outer = (node->style.min_width > 0)
                            ? ((node->style.box_sizing == BOX_SIZING_BORDER_BOX)
                                   ? node->style.min_width
                                   : (node->style.min_width + pad_h + bdr_h))
                            : 0;
        node->w = clamp_size_min_max(node->w, min_outer, max_outer);
        content_w = (node->w > pad_h + bdr_h) ? (node->w - pad_h - bdr_h) : 0;
    }

    /* Standalone `#text` fallback */
    if (strcmp(node->tag, "#text") == 0 && node->text) {
        int end_y = layout_inline_formatting_context(node, node->x, container_y, node->w, inherited_fspace);
        node->y = container_y;
        node->content_h = end_y - container_y;
        node->h = node->content_h;
        if (end_y > *out_max_y) *out_max_y = end_y;
        return end_y;
    }

    int child_start_y = container_y + node->style.padding_top + node->style.border_width;
    int child_x = node->x + eff_padding_left + bdr_left;

    float_space_t local_fspace;
    local_fspace.count = 0;
    float_space_t* active_fspace = (establishes_bfc || !inherited_fspace) ? &local_fspace : inherited_fspace;

    /* --------------------------------------------------------------------- */
    /* A. Complete Flexbox (`row` / `column`, `wrap`, `grow`, `shrink`)      */
    /* --------------------------------------------------------------------- */
    if (node->style.display == DISPLAY_FLEX) {
        dom_node_t* items[128];
        int n_items = 0;
        for (int i = 0; i < node->num_children && n_items < 128; i++) {
            dom_node_t* ch = node->children[i];
            if (!ch || ch->style.display == DISPLAY_NONE || strcmp(ch->tag, "#text") == 0 || is_out_of_flow(ch)) {
                continue;
            }
            items[n_items++] = ch;
        }

        int flex_content_h = 0;

        if (node->style.flex_direction == FLEX_DIR_COLUMN) {
            /* Column Flexbox: vertical main axis */
            int item_h[128];
            int total_grow = 0;
            int total_shrink_w = 0;
            int fixed_used_h = 0;
            int vgap = (node->style.row_gap > 0) ? node->style.row_gap : node->style.gap;

            for (int i = 0; i < n_items; i++) {
                dom_node_t* it = items[i];
                int cross_w = node->style.align_items_center
                                  ? measure_intrinsic_outer_width(it, content_w)
                                  : (content_w - it->style.margin_left - it->style.margin_right);
                if (it->style.width > 0) cross_w = measure_intrinsic_outer_width(it, content_w);
                if (cross_w < 0) cross_w = 0;

                int saved_w = it->style.width;
                css_box_sizing_t saved_bs = it->style.box_sizing;
                it->style.width = cross_w;
                it->style.box_sizing = BOX_SIZING_BORDER_BOX;
                int sub_max_y = 0;
                layout_node_internal(it, child_x, child_start_y, cross_w + it->style.margin_left + it->style.margin_right,
                                     true, NULL, env, &sub_max_y);
                it->style.width = saved_w;
                it->style.box_sizing = saved_bs;

                int bh = (it->style.height >= 0) ? it->h : it->h;
                item_h[i] = bh;
                fixed_used_h += bh + it->style.margin_top + it->style.margin_bottom;
                total_grow += (it->style.flex_grow > 0) ? it->style.flex_grow : 0;
                total_shrink_w += ((it->style.flex_shrink > 0) ? it->style.flex_shrink : 0) * (bh > 0 ? bh : 1);
            }

            int base_gaps = (n_items > 1) ? (n_items - 1) * vgap : 0;
            int explicit_main_h = -1;
            if (node->style.height >= 0) {
                explicit_main_h = (node->style.box_sizing == BOX_SIZING_BORDER_BOX)
                                      ? (node->style.height - node->style.padding_top - node->style.padding_bottom - node->style.border_width * 2)
                                      : node->style.height;
                if (explicit_main_h < 0) explicit_main_h = 0;
            }

            if (explicit_main_h >= 0) {
                int free_h = explicit_main_h - fixed_used_h - base_gaps;
                if (free_h > 0 && total_grow > 0) {
                    int dist = 0, last_g = -1;
                    for (int i = 0; i < n_items; i++) {
                        if (items[i]->style.flex_grow > 0) {
                            int sh = (free_h * items[i]->style.flex_grow) / total_grow;
                            item_h[i] += sh;
                            dist += sh;
                            last_g = i;
                        }
                    }
                    if (last_g >= 0) item_h[last_g] += (free_h - dist);
                } else if (free_h < 0 && total_shrink_w > 0) {
                    int deficit = -free_h;
                    for (int i = 0; i < n_items; i++) {
                        int sw = ((items[i]->style.flex_shrink > 0) ? items[i]->style.flex_shrink : 0) *
                                 (item_h[i] > 0 ? item_h[i] : 1);
                        if (sw > 0) {
                            int sub = (int)(((int64_t)deficit * (int64_t)sw) / (int64_t)total_shrink_w);
                            item_h[i] = (item_h[i] > sub) ? (item_h[i] - sub) : 0;
                        }
                    }
                }
            }

            int used_main = base_gaps;
            for (int i = 0; i < n_items; i++) {
                used_main += item_h[i] + items[i]->style.margin_top + items[i]->style.margin_bottom;
            }
            int avail_main = (explicit_main_h >= 0) ? explicit_main_h : used_main;
            int start_off = blink_flex_justify_start_offset(node->style.justify_content, avail_main, used_main, n_items);
            int inter_gap = blink_flex_justify_inter_gap(node->style.justify_content, avail_main, used_main, n_items, vgap);

            int cy = child_start_y + start_off;
            for (int i = 0; i < n_items; i++) {
                dom_node_t* it = items[i];
                int target_y = cy + it->style.margin_top;
                int target_x = child_x + it->style.margin_left;
                if (node->style.align_items_center && it->w < content_w) {
                    target_x = child_x + (content_w - it->w) / 2;
                }
                shift_subtree_xy(it, target_x - it->x, target_y - it->y);
                it->h = item_h[i];
                if (it->y + it->h > *out_max_y) *out_max_y = it->y + it->h;
                cy += it->style.margin_top + item_h[i] + it->style.margin_bottom + inter_gap;
            }
            flex_content_h = avail_main;
        } else {
            /* Row Flexbox with `flex-wrap`, `flex-grow`, `flex-shrink`, and `min/max-width` */
            int hyp_w[128];
            for (int i = 0; i < n_items; i++) {
                dom_node_t* ch = items[i];
                int cp = ch->style.padding_left + ch->style.padding_right;
                int cb = ((ch->style.border_width > 0) ? ch->style.border_width : ch->style.border_left_width) + ch->style.border_width;
                int bw = 0;
                if (ch->style.width > 0) {
                    bw = (ch->style.box_sizing == BOX_SIZING_BORDER_BOX) ? ch->style.width : (ch->style.width + cp + cb);
                } else if (ch->style.flex_grow <= 0 || node->style.flex_wrap) {
                    bw = measure_intrinsic_outer_width(ch, content_w);
                }
                int min_ow = (ch->style.min_width > 0)
                                 ? ((ch->style.box_sizing == BOX_SIZING_BORDER_BOX) ? ch->style.min_width : (ch->style.min_width + cp + cb))
                                 : 0;
                int max_ow = (ch->style.max_width >= 0)
                                 ? ((ch->style.box_sizing == BOX_SIZING_BORDER_BOX) ? ch->style.max_width : (ch->style.max_width + cp + cb))
                                 : -1;
                hyp_w[i] = clamp_size_min_max(bw, min_ow, max_ow);
            }

            /* Partition items into flex lines */
            int line_starts[129];
            int n_lines = 0;
            if (n_items > 0) {
                int ls = 0;
                while (ls < n_items) {
                    line_starts[n_lines++] = ls;
                    if (!node->style.flex_wrap) {
                        ls = n_items;
                        break;
                    }
                    int cur_line_used = hyp_w[ls] + items[ls]->style.margin_left + items[ls]->style.margin_right;
                    int k = ls + 1;
                    while (k < n_items) {
                        int add = node->style.gap + hyp_w[k] + items[k]->style.margin_left + items[k]->style.margin_right;
                        if (cur_line_used + add > content_w) break;
                        cur_line_used += add;
                        k++;
                    }
                    ls = k;
                }
                line_starts[n_lines] = n_items;
            }

            int line_y = child_start_y;
            for (int ln = 0; ln < n_lines; ln++) {
                int ls = line_starts[ln];
                int le = line_starts[ln + 1];
                int cnt = le - ls;

                int item_w[128];
                int total_grow = 0;
                int64_t total_shrink_scaled = 0;
                int fixed_used = 0;

                for (int i = ls; i < le; i++) {
                    item_w[i] = hyp_w[i];
                    fixed_used += item_w[i] + items[i]->style.margin_left + items[i]->style.margin_right;
                    total_grow += (items[i]->style.flex_grow > 0) ? items[i]->style.flex_grow : 0;
                    int fs = (items[i]->style.flex_shrink > 0) ? items[i]->style.flex_shrink : 0;
                    total_shrink_scaled += (int64_t)fs * (int64_t)(item_w[i] > 0 ? item_w[i] : 1);
                }

                int base_gaps = (cnt > 1) ? (cnt - 1) * node->style.gap : 0;
                int free_space = content_w - fixed_used - base_gaps;

                if (free_space > 0 && total_grow > 0) {
                    int dist = 0, last_g = -1;
                    for (int i = ls; i < le; i++) {
                        int fg = (items[i]->style.flex_grow > 0) ? items[i]->style.flex_grow : 0;
                        if (fg > 0) {
                            int sh = (free_space * fg) / total_grow;
                            item_w[i] += sh;
                            dist += sh;
                            last_g = i;
                        }
                    }
                    if (last_g >= 0) item_w[last_g] += (free_space - dist);
                } else if (free_space < 0 && total_shrink_scaled > 0) {
                    int deficit = -free_space;
                    for (int i = ls; i < le; i++) {
                        int fs = (items[i]->style.flex_shrink > 0) ? items[i]->style.flex_shrink : 0;
                        int64_t sw = (int64_t)fs * (int64_t)(hyp_w[i] > 0 ? hyp_w[i] : 1);
                        if (sw > 0) {
                            int sub = (int)(((int64_t)deficit * sw) / total_shrink_scaled);
                            item_w[i] = (item_w[i] > sub) ? (item_w[i] - sub) : 0;
                        }
                    }
                }

                /* Final `min-width` / `max-width` clamping per item */
                int used_main = base_gaps;
                for (int i = ls; i < le; i++) {
                    dom_node_t* ch = items[i];
                    int cp = ch->style.padding_left + ch->style.padding_right;
                    int cb = ((ch->style.border_width > 0) ? ch->style.border_width : ch->style.border_left_width) + ch->style.border_width;
                    int min_ow = (ch->style.min_width > 0)
                                     ? ((ch->style.box_sizing == BOX_SIZING_BORDER_BOX) ? ch->style.min_width : (ch->style.min_width + cp + cb))
                                     : 0;
                    int max_ow = (ch->style.max_width >= 0)
                                     ? ((ch->style.box_sizing == BOX_SIZING_BORDER_BOX) ? ch->style.max_width : (ch->style.max_width + cp + cb))
                                     : -1;
                    item_w[i] = clamp_size_min_max(item_w[i], min_ow, max_ow);
                    used_main += item_w[i] + ch->style.margin_left + ch->style.margin_right;
                }

                int start_off = blink_flex_justify_start_offset(node->style.justify_content, content_w, used_main, cnt);
                int inter_gap = blink_flex_justify_inter_gap(node->style.justify_content, content_w, used_main, cnt, node->style.gap);

                int cursor_x = child_x + start_off;
                int line_max_h = 0;
                for (int i = ls; i < le; i++) {
                    dom_node_t* it = items[i];
                    int saved_w = it->style.width;
                    css_box_sizing_t saved_bs = it->style.box_sizing;
                    int saved_minw = it->style.min_width;
                    int saved_maxw = it->style.max_width;
                    it->style.width = item_w[i];
                    it->style.box_sizing = BOX_SIZING_BORDER_BOX;
                    it->style.min_width = 0;
                    it->style.max_width = -1;

                    int sub_max_y = 0;
                    int item_end_y = layout_node_internal(
                        it, cursor_x, line_y + it->style.margin_top,
                        item_w[i] + it->style.margin_left + it->style.margin_right,
                        true, NULL, env, &sub_max_y);

                    it->style.width = saved_w;
                    it->style.box_sizing = saved_bs;
                    it->style.min_width = saved_minw;
                    it->style.max_width = saved_maxw;

                    int full_h = (item_end_y - line_y) + it->style.margin_bottom;
                    if (full_h > line_max_h) line_max_h = full_h;
                    cursor_x += it->style.margin_left + item_w[i] + it->style.margin_right + inter_gap;
                }

                int target_line_h = line_max_h;
                if (n_lines == 1 && node->style.height >= 0) {
                    int eh = (node->style.box_sizing == BOX_SIZING_BORDER_BOX)
                                 ? (node->style.height - node->style.padding_top - node->style.padding_bottom - node->style.border_width * 2)
                                 : node->style.height;
                    if (eh > 0) target_line_h = eh;
                }

                for (int i = ls; i < le; i++) {
                    dom_node_t* it = items[i];
                    if (node->style.align_items_center && it->h < target_line_h) {
                        shift_subtree_xy(it, 0, (target_line_h - it->h) / 2);
                    } else if (!node->style.align_items_center && it->style.height < 0) {
                        int th = target_line_h - it->style.margin_top - it->style.margin_bottom;
                        if (th > it->h) it->h = th;
                    }
                    if (it->y + it->h > *out_max_y) *out_max_y = it->y + it->h;
                }

                line_y += target_line_h;
                if (ln + 1 < n_lines) {
                    line_y += (node->style.row_gap > 0) ? node->style.row_gap : node->style.gap;
                }
            }
            flex_content_h = line_y - child_start_y;
        }

        if (node->style.height >= 0) {
            int eh = (node->style.box_sizing == BOX_SIZING_BORDER_BOX)
                         ? (node->style.height - node->style.padding_top - node->style.padding_bottom - node->style.border_width * 2)
                         : node->style.height;
            node->content_h = (eh > 0) ? eh : 0;
        } else {
            node->content_h = flex_content_h;
        }
        node->y = container_y;
        node->h = node->content_h + node->style.padding_top + node->style.padding_bottom + node->style.border_width * 2;
        goto finish_positioned_and_relative;
    }

    /* --------------------------------------------------------------------- */
    /* B. Complete CSS Grid (`minmax()`, `fr`, and `grid-column: span K`)    */
    /* --------------------------------------------------------------------- */
    if (node->style.display == DISPLAY_GRID) {
        int n_cols = (node->style.num_grid_cols > 0) ? node->style.num_grid_cols : 1;
        if (n_cols > 16) n_cols = 16;

        int track_w[16];
        int fixed_sum = (n_cols > 1) ? (n_cols - 1) * node->style.gap : 0;
        int fr_sum = 0;
        for (int c = 0; c < n_cols; c++) {
            int spec = (c < node->style.num_grid_cols) ? node->style.grid_col_widths[c] : -1;
            int min_px = (c < node->style.num_grid_cols) ? node->style.grid_col_min[c] : 0;
            if (spec > 0) {
                track_w[c] = (spec > min_px) ? spec : min_px;
                fixed_sum += track_w[c];
            } else {
                track_w[c] = min_px;
                fr_sum += (-spec > 0) ? (-spec) : 1;
            }
        }
        int rem_w = (content_w > fixed_sum) ? (content_w - fixed_sum) : 0;
        if (fr_sum > 0) {
            int acc = 0;
            int last_fr = -1;
            for (int c = 0; c < n_cols; c++) {
                int spec = (c < node->style.num_grid_cols) ? node->style.grid_col_widths[c] : -1;
                int min_px = (c < node->style.num_grid_cols) ? node->style.grid_col_min[c] : 0;
                if (spec <= 0) {
                    int w_fr = (-spec > 0) ? (-spec) : 1;
                    int raw = (rem_w * w_fr) / fr_sum;
                    track_w[c] = (raw > min_px) ? raw : min_px;
                    acc += raw;
                    last_fr = c;
                }
            }
            if (last_fr >= 0 && rem_w > acc) {
                track_w[last_fr] += (rem_w - acc);
            }
        }

        int track_x[16];
        int cx = 0;
        for (int c = 0; c < n_cols; c++) {
            track_x[c] = cx;
            cx += track_w[c] + node->style.gap;
        }

        dom_node_t* gitems[128];
        int n_gitems = 0;
        for (int i = 0; i < node->num_children && n_gitems < 128; i++) {
            dom_node_t* ch = node->children[i];
            if (!ch || ch->style.display == DISPLAY_NONE || strcmp(ch->tag, "#text") == 0 || is_out_of_flow(ch)) {
                continue;
            }
            gitems[n_gitems++] = ch;
        }

        int row_y = child_start_y;
        int cur_col = 0;
        int row_max_h = 0;
        dom_node_t* row_items[16];
        int n_row_items = 0;

        for (int idx = 0; idx < n_gitems; idx++) {
            dom_node_t* it = gitems[idx];
            int span = it->style.grid_col_span;
            if (span < 1) span = 1;
            if (span > n_cols) span = n_cols;

            if (cur_col > 0 && cur_col + span > n_cols) {
                for (int r = 0; r < n_row_items; r++) {
                    if (row_items[r]->style.height < 0 && row_items[r]->h < row_max_h) {
                        row_items[r]->h = row_max_h;
                    }
                }
                row_y += row_max_h + node->style.row_gap;
                cur_col = 0;
                row_max_h = 0;
                n_row_items = 0;
            }

            int it_x = child_x + track_x[cur_col];
            int end_col = cur_col + span - 1;
            int it_w = (track_x[end_col] + track_w[end_col]) - track_x[cur_col];

            int saved_w = it->style.width;
            css_box_sizing_t saved_bs = it->style.box_sizing;
            it->style.width = it_w;
            it->style.box_sizing = BOX_SIZING_BORDER_BOX;

            int sub_max_y = 0;
            int end_y = layout_node_internal(it, it_x, row_y, it_w, true, NULL, env, &sub_max_y);
            it->style.width = saved_w;
            it->style.box_sizing = saved_bs;

            int ih = end_y - row_y;
            if (ih > row_max_h) row_max_h = ih;
            if (n_row_items < 16) row_items[n_row_items++] = it;
            cur_col += span;
        }

        if (n_row_items > 0) {
            for (int r = 0; r < n_row_items; r++) {
                if (row_items[r]->style.height < 0 && row_items[r]->h < row_max_h) {
                    row_items[r]->h = row_max_h;
                }
            }
            row_y += row_max_h;
        }

        int measured_gh = row_y - child_start_y;
        node->content_h = (node->style.height >= 0)
                              ? ((node->style.box_sizing == BOX_SIZING_BORDER_BOX)
                                     ? (node->style.height - node->style.padding_top - node->style.padding_bottom - node->style.border_width * 2)
                                     : node->style.height)
                              : measured_gh;
        if (node->content_h < 0) node->content_h = 0;
        node->y = container_y;
        node->h = node->content_h + node->style.padding_top + node->style.padding_bottom + node->style.border_width * 2;
        goto finish_positioned_and_relative;
    }

    /* --------------------------------------------------------------------- */
    /* C. Complete 2D Table (`rowspan` + `colspan` Occupancy Grid)           */
    /* --------------------------------------------------------------------- */
    if (node->style.display == DISPLAY_TABLE) {
        dom_node_t* rows[128];
        int n_rows = 0;
        collect_table_rows(node, rows, &n_rows, 128);

        typedef struct {
            dom_node_t* cell;
            int         r0;
            int         c0;
            int         rspan;
            int         cspan;
            int         req_h;
        } placed_cell_t;

        dom_node_t* grid_occ[128][32];
        memset(grid_occ, 0, sizeof(grid_occ));
        placed_cell_t placed[1024];
        int n_placed = 0;
        int num_cols = 0;

        for (int r = 0; r < n_rows; r++) {
            int c_cursor = 0;
            dom_node_t* tr = rows[r];
            for (int ci = 0; ci < tr->num_children; ci++) {
                dom_node_t* cell = tr->children[ci];
                if (!cell || cell->style.display == DISPLAY_NONE || strcmp(cell->tag, "#text") == 0 || is_out_of_flow(cell)) {
                    continue;
                }
                while (c_cursor < 32 && grid_occ[r][c_cursor] != NULL) {
                    c_cursor++;
                }
                if (c_cursor >= 32) break;

                int cspan = blink_html_sanitize_span(cell->colspan, 32 - c_cursor);
                int rspan = blink_html_sanitize_span(cell->rowspan, n_rows - r);
                for (int rr = r; rr < r + rspan; rr++) {
                    for (int cc = c_cursor; cc < c_cursor + cspan; cc++) {
                        grid_occ[rr][cc] = cell;
                    }
                }
                if (c_cursor + cspan > num_cols) num_cols = c_cursor + cspan;

                if (n_placed < 1024) {
                    placed[n_placed].cell = cell;
                    placed[n_placed].r0 = r;
                    placed[n_placed].c0 = c_cursor;
                    placed[n_placed].rspan = rspan;
                    placed[n_placed].cspan = cspan;
                    placed[n_placed].req_h = 0;
                    n_placed++;
                }
                c_cursor += cspan;
            }
        }
        if (num_cols > 32) num_cols = 32;

        int col_x[33];
        int col_w[32];
        memset(col_x, 0, sizeof(col_x));
        memset(col_w, 0, sizeof(col_w));

        if (num_cols > 0) {
            int explicit_w[32];
            int explicit_sum = 0;
            int auto_cols = 0;
            for (int k = 0; k < num_cols; k++) explicit_w[k] = -1;

            for (int p = 0; p < n_placed; p++) {
                if (placed[p].cspan == 1 && placed[p].cell->style.width > 0 && explicit_w[placed[p].c0] < 0) {
                    explicit_w[placed[p].c0] = placed[p].cell->style.width;
                }
            }
            for (int k = 0; k < num_cols; k++) {
                if (explicit_w[k] > 0) explicit_sum += explicit_w[k];
                else auto_cols++;
            }

            if (explicit_sum > 0 && explicit_sum < content_w && auto_cols > 0) {
                int rem_w = content_w - explicit_sum;
                int auto_idx = 0;
                int cur_cx = 0;
                for (int k = 0; k < num_cols; k++) {
                    col_x[k] = cur_cx;
                    col_w[k] = (explicit_w[k] > 0)
                                   ? explicit_w[k]
                                   : blink_table_col_width_formal(rem_w, auto_cols, auto_idx++, mode);
                    cur_cx += col_w[k];
                }
                col_x[num_cols] = cur_cx;
            } else {
                for (int k = 0; k < num_cols; k++) {
                    col_x[k] = blink_table_col_start_formal(content_w, num_cols, k, mode);
                    col_w[k] = blink_table_col_width_formal(content_w, num_cols, k, mode);
                }
                col_x[num_cols] = content_w;
            }
        }

        int row_cursor_y = child_start_y;
        for (int i = 0; i < node->num_children; i++) {
            dom_node_t* ch = node->children[i];
            if (ch && strcmp(ch->tag, "caption") == 0 && ch->style.display != DISPLAY_NONE) {
                row_cursor_y = layout_node_internal(ch, child_x, row_cursor_y, content_w, true, NULL, env, out_max_y);
            }
        }

        int row_h[128];
        memset(row_h, 0, sizeof(row_h));

        /* Measure every placed cell at temporary y = 0 */
        for (int p = 0; p < n_placed; p++) {
            dom_node_t* cell = placed[p].cell;
            int cell_px_x = child_x + col_x[placed[p].c0];
            int cell_px_w = col_x[placed[p].c0 + placed[p].cspan] - col_x[placed[p].c0];

            int saved_w = cell->style.width;
            css_box_sizing_t saved_bs = cell->style.box_sizing;
            int saved_ml = cell->style.margin_left;
            int saved_mr = cell->style.margin_right;
            cell->style.width = cell_px_w;
            cell->style.box_sizing = BOX_SIZING_BORDER_BOX;
            cell->style.margin_left = 0;
            cell->style.margin_right = 0;

            int sub_max_y = 0;
            int end_y = layout_node_internal(cell, cell_px_x, 0, cell_px_w, true, NULL, env, &sub_max_y);

            cell->style.width = saved_w;
            cell->style.box_sizing = saved_bs;
            cell->style.margin_left = saved_ml;
            cell->style.margin_right = saved_mr;

            placed[p].req_h = end_y;
            if (placed[p].rspan == 1 && end_y > row_h[placed[p].r0]) {
                row_h[placed[p].r0] = end_y;
            }
        }

        /* Distribute multi-row (`rowspan > 1`) cell height requirements across spanned rows */
        for (int p = 0; p < n_placed; p++) {
            if (placed[p].rspan > 1) {
                int cur_sum = 0;
                for (int rr = placed[p].r0; rr < placed[p].r0 + placed[p].rspan; rr++) {
                    cur_sum += row_h[rr];
                }
                if (placed[p].req_h > cur_sum) {
                    int extra = placed[p].req_h - cur_sum;
                    int per = extra / placed[p].rspan;
                    int rem = extra - per * placed[p].rspan;
                    for (int rr = placed[p].r0; rr < placed[p].r0 + placed[p].rspan; rr++) {
                        row_h[rr] += per + ((rr == placed[p].r0 + placed[p].rspan - 1) ? rem : 0);
                    }
                }
            }
        }

        int row_y[129];
        row_y[0] = row_cursor_y;
        for (int r = 0; r < n_rows; r++) {
            row_y[r + 1] = row_y[r] + row_h[r];
            rows[r]->x = child_x;
            rows[r]->y = row_y[r];
            rows[r]->w = content_w;
            rows[r]->h = row_h[r];
            rows[r]->content_h = row_h[r];
        }

        /* Finalize cell `y` and `h` across spanned rows */
        for (int p = 0; p < n_placed; p++) {
            dom_node_t* cell = placed[p].cell;
            int ty = row_y[placed[p].r0];
            int th = row_y[placed[p].r0 + placed[p].rspan] - ty;
            shift_subtree_xy(cell, 0, ty - cell->y);
            cell->h = th;
            if (cell->y + cell->h > *out_max_y) *out_max_y = cell->y + cell->h;
        }

        for (int i = 0; i < node->num_children; i++) {
            dom_node_t* rg = node->children[i];
            if (!rg || rg->style.display != DISPLAY_TABLE_ROW_GROUP) continue;
            int rg_y0 = -1, rg_y1 = 0;
            for (int j = 0; j < rg->num_children; j++) {
                dom_node_t* tr = rg->children[j];
                if (tr && strcmp(tr->tag, "tr") == 0) {
                    if (rg_y0 < 0 || tr->y < rg_y0) rg_y0 = tr->y;
                    if (tr->y + tr->h > rg_y1) rg_y1 = tr->y + tr->h;
                }
            }
            if (rg_y0 >= 0) {
                rg->x = child_x;
                rg->y = rg_y0;
                rg->w = content_w;
                rg->h = rg_y1 - rg_y0;
            }
        }

        row_cursor_y = row_y[n_rows];
        int measured_h = row_cursor_y - child_start_y;
        node->content_h = (node->style.height >= 0) ? node->style.height : measured_h;
        node->y = container_y;
        node->h = node->content_h + node->style.padding_top + node->style.padding_bottom + node->style.border_width * 2;
        goto finish_positioned_and_relative;
    }

    /* --------------------------------------------------------------------- */
    /* D. Inline Formatting Container vs Block Formatting Container          */
    /* --------------------------------------------------------------------- */
    {
        bool has_inline_content = false;
        bool has_block_inflow = false;

        if (strcmp(node->tag, "img") != 0) {
            for (int i = 0; i < node->num_children; i++) {
                dom_node_t* ch = node->children[i];
                if (!ch || ch->style.display == DISPLAY_NONE || has_hidden_class(ch->class_name) || is_out_of_flow(ch)) {
                    continue;
                }
                if (ch->style.css_float != FLOAT_NONE) {
                    continue; /* Floats can precede inline content in the same container! */
                }
                if (subtree_is_pure_inline(ch)) {
                    has_inline_content = true;
                } else {
                    has_block_inflow = true;
                }
            }
        }

        if (has_inline_content && !has_block_inflow) {
            /* Place any leading float children first into `active_fspace` */
            for (int i = 0; i < node->num_children; i++) {
                dom_node_t* ch = node->children[i];
                if (ch && ch->style.display != DISPLAY_NONE && !is_out_of_flow(ch) &&
                    ch->style.css_float != FLOAT_NONE) {
                    place_float_child(ch, child_x, child_x + content_w, child_start_y,
                                      active_fspace, env, out_max_y);
                }
            }

            int end_inline_y = layout_inline_formatting_context(
                node, child_x, child_start_y, content_w, active_fspace);
            if (establishes_bfc) {
                end_inline_y = float_space_max_bottom(active_fspace, end_inline_y);
            }
            int measured_h = end_inline_y - child_start_y;
            if (node->style.height >= 0) {
                node->content_h = (node->style.box_sizing == BOX_SIZING_BORDER_BOX)
                                      ? ((node->style.height - node->style.padding_top - node->style.padding_bottom - node->style.border_width * 2 > 0)
                                             ? (node->style.height - node->style.padding_top - node->style.padding_bottom - node->style.border_width * 2)
                                             : 0)
                                      : node->style.height;
            } else {
                node->content_h = measured_h;
            }
            node->y = container_y;
            node->h = node->content_h + node->style.padding_top + node->style.padding_bottom + node->style.border_width * 2;
            goto finish_positioned_and_relative;
        }
    }

    /* --------------------------------------------------------------------- */
    /* E. Block-Level Container: Vertical Flow + Margin Collapsing + Floats  */
    /* --------------------------------------------------------------------- */
    {
        free(node->inline_frags);
        node->inline_frags = NULL;
        node->num_inline_frags = 0;

        int active_cursor_y = child_start_y;
        int running_margin_pos = 0;
        int running_margin_neg = 0;

        for (int i = 0; i < node->num_children; i++) {
            dom_node_t* ch = node->children[i];
            if (!ch || ch->style.display == DISPLAY_NONE || is_out_of_flow(ch)) continue;

            if (ch->style.css_float != FLOAT_NONE) {
                int float_min_y = active_cursor_y + running_margin_pos + running_margin_neg;
                place_float_child(ch, child_x, child_x + content_w, float_min_y,
                                  active_fspace, env, out_max_y);
                continue;
            }

            if (ch->style.css_clear != CLEAR_NONE) {
                int cleared_y = float_space_clear_y(active_fspace, ch->style.css_clear, active_cursor_y);
                if (cleared_y > active_cursor_y) {
                    active_cursor_y = cleared_y;
                    running_margin_pos = 0;
                    running_margin_neg = 0;
                }
            }

            int top_pos = (ch->style.margin_top > 0) ? ch->style.margin_top : 0;
            int top_neg = (ch->style.margin_top < 0) ? ch->style.margin_top : 0;
            int eff_pos = (top_pos > running_margin_pos) ? top_pos : running_margin_pos;
            int eff_neg = (top_neg < running_margin_neg) ? top_neg : running_margin_neg;
            int collapsed_margin = eff_pos + eff_neg;

            int child_y = active_cursor_y + collapsed_margin;
            bool child_bfc = (ch->style.display == DISPLAY_FLEX ||
                              ch->style.display == DISPLAY_GRID ||
                              ch->style.display == DISPLAY_TABLE ||
                              ch->style.display == DISPLAY_INLINE_BLOCK ||
                              ch->style.overflow_hidden);
            int child_end_y = layout_node_internal(ch, child_x, child_y, content_w,
                                                   child_bfc, active_fspace, env, out_max_y);
            active_cursor_y = child_end_y;

            running_margin_pos = (ch->style.margin_bottom > 0) ? ch->style.margin_bottom : 0;
            running_margin_neg = (ch->style.margin_bottom < 0) ? ch->style.margin_bottom : 0;
        }

        if (establishes_bfc) {
            active_cursor_y = float_space_max_bottom(active_fspace, active_cursor_y);
        }

        int measured_h = active_cursor_y - child_start_y;
        if (node->style.height >= 0) {
            if (node->style.box_sizing == BOX_SIZING_BORDER_BOX) {
                int ch = node->style.height - node->style.padding_top - node->style.padding_bottom - node->style.border_width * 2;
                node->content_h = (ch > 0) ? ch : 0;
            } else {
                node->content_h = node->style.height;
            }
        } else {
            node->content_h = measured_h;
        }
        node->y = container_y;
        node->h = node->content_h + node->style.padding_top + node->style.padding_bottom + node->style.border_width * 2;
    }

finish_positioned_and_relative:
    {
        /* Normal-flow bottom before any `position: relative` or `transform` visual shift */
        int normal_flow_next_y = node->y + node->h;

        /* If `node` establishes a positioned or transformed containing block (or is the root), lay out its OOF children! */
        bool is_root = (node->parent == NULL);
        if (is_root || node->style.position != POS_STATIC || node->style.has_transform) {
            int cb_x = node->x + bdr_left;
            int cb_y = node->y + node->style.border_width;
            int cb_w = (node->w > bdr_h) ? (node->w - bdr_h) : 0;
            int cb_h = (node->h > node->style.border_width * 2) ? (node->h - node->style.border_width * 2) : 0;
            layout_oof_for_containing_block(node, node, cb_x, cb_y, cb_w, cb_h, is_root, env, out_max_y);
        }

        /* Apply `position: relative | sticky` visual offset AFTER normal-flow and child OOF placement! */
        if (node->style.position == POS_RELATIVE || node->style.position == POS_STICKY) {
            int dx = node->style.has_left ? node->style.left
                                          : (node->style.has_right ? -node->style.right : 0);
            int dy = node->style.has_top ? node->style.top
                                         : (node->style.has_bottom ? -node->style.bottom : 0);
            shift_subtree_xy(node, dx, dy);
        }

        if (node->y + node->h > *out_max_y) *out_max_y = node->y + node->h;
        if (normal_flow_next_y > *out_max_y) *out_max_y = normal_flow_next_y;
        return normal_flow_next_y;
    }
}

static void apply_transforms_post_layout(dom_node_t* node, int* out_max_y) {
    if (!node || node->style.display == DISPLAY_NONE) return;
    if (node->style.has_transform) {
        int tx = node->style.translate_x_px +
                 (int)lroundf(node->style.translate_x_pct * (float)node->w / 100.0f);
        int ty = node->style.translate_y_px +
                 (int)lroundf(node->style.translate_y_pct * (float)node->h / 100.0f);
        if (tx != 0 || ty != 0) {
            shift_subtree_xy(node, tx, ty);
        }
    }
    if (node->y + node->h > *out_max_y) *out_max_y = node->y + node->h;
    for (int i = 0; i < node->num_children; i++) {
        apply_transforms_post_layout(node->children[i], out_max_y);
    }
}

int blink_layout_dom_tree(dom_node_t* root,
                          int viewport_x,
                          int viewport_y,
                          int viewport_w,
                          int viewport_h,
                          blink_layout_mode_t mode,
                          int* out_max_y) {
    int local_max = 0;
    int* target_max = out_max_y ? out_max_y : &local_max;
    layout_env_t env;
    env.viewport_w = viewport_w + viewport_x * 2;
    env.viewport_h = viewport_h;
    env.mode = mode;
    int end_y = layout_node_internal(root, viewport_x, viewport_y, viewport_w, true, NULL, &env, target_max);
    apply_transforms_post_layout(root, target_max);
    return end_y;
}

/* ------------------------------------------------------------------------- */
/* 8. Pillars 4 & 5: Appendix E 7-Phase Stacking Context & Skia Paint Engine */
/* ------------------------------------------------------------------------- */

static void paint_box_decoration(dom_node_t* node, blink_framebuffer_t* fb, bool suppress_cell_borders) {
    if (!node || node->style.display == DISPLAY_NONE) return;

    int r_eff = blink_clamp_corner_radius(node->w, node->h, node->style.border_radius);

    /* 0. Outer Drop Shadow (`box-shadow`, CSS Backgrounds 3 §7.1) */
    if (node->style.has_box_shadow) {
        blink_fb_draw_box_shadow(fb, node->x, node->y, node->w, node->h,
                                 r_eff,
                                 node->style.shadow_dx, node->style.shadow_dy,
                                 node->style.shadow_blur, node->style.shadow_spread,
                                 node->style.shadow_color);
    }

    /* 1. Box Background Color & CSS Linear Gradient (`SkRRect` anti-aliased) */
    if (node->style.has_bg && (node->style.bg_color >> 24) > 0) {
        blink_fb_fill_rrect(fb, node->x, node->y, node->w, node->h, r_eff, node->style.bg_color);
    }
    if (node->style.has_gradient && node->style.num_grad_stops >= 2) {
        blink_fb_fill_rrect_gradient(fb, node->x, node->y, node->w, node->h,
                                     r_eff,
                                     node->style.grad_angle_deg,
                                     node->style.grad_colors,
                                     node->style.grad_pos_pct,
                                     node->style.num_grad_stops);
    }

    /* 2. Box Borders (suppressed on table/cells when `border-collapse: collapse` draws shared grid!) */
    bool is_collapsed_table = (node->style.display == DISPLAY_TABLE && node->style.border_collapse);
    if (!suppress_cell_borders && !is_collapsed_table) {
        if (node->style.border_width > 0 &&
            node->style.border_style != BDR_STYLE_NONE &&
            node->style.border_style != BDR_STYLE_HIDDEN) {
            blink_fb_stroke_rrect(fb, node->x, node->y, node->w, node->h,
                                  r_eff, node->style.border_width, node->style.border_color);
        }
        if (node->style.border_left_width > 0) {
            if (r_eff <= 0) {
                blink_fb_fill_rect(fb, node->x, node->y, node->style.border_left_width, node->h,
                                   node->style.border_left_color);
            } else {
                int x0, y0, x1, y1;
                blink_intersect_scissor(0, 0, fb->width, fb->height,
                                        node->x, node->y, node->x + node->style.border_left_width, node->y + node->h,
                                        &x0, &y0, &x1, &y1);
                for (int row = y0; row < y1; row++) {
                    uint32_t* dst_row = fb->pixels + (size_t)row * (size_t)fb->width;
                    for (int c = x0; c < x1; c++) {
                        uint32_t cov = rrect_coverage_u8(rrect_signed_dist_f(
                            (float)c + 0.5f, (float)row + 0.5f,
                            (float)node->x, (float)node->y, (float)node->w, (float)node->h, (float)r_eff));
                        blend_argb_coverage(&dst_row[c], node->style.border_left_color, cov);
                    }
                }
            }
        }
        if (node->style.border_bottom_width > 0 && node->style.border_width == 0) {
            blink_fb_fill_rect(fb, node->x, node->y + node->h - node->style.border_bottom_width,
                               node->w, node->style.border_bottom_width, node->style.border_color);
        }
    }

    /* 3. List item bullet */
    if (node->style.display == DISPLAY_LIST_ITEM) {
        blink_fb_draw_bullet(fb, node->x - 12, node->y + (int)(node->style.font_size * 0.55f), 3, node->style.color);
    }

    /* 4. Shaded pyramid emblem for <img> thumbnails */
    if (strcmp(node->tag, "img") == 0 && node->w > 24 && node->h > 24) {
        int apex_x = node->x + node->w / 2;
        int apex_y = node->y + 14;
        int base_y = node->y + node->h - 16;
        int half_b = (node->w - 36) / 2;
        if (half_b > (base_y - apex_y)) half_b = (base_y - apex_y);
        for (int py = apex_y; py <= base_y; py++) {
            float t = (base_y > apex_y) ? (float)(py - apex_y) / (float)(base_y - apex_y) : 0.0f;
            int span = (int)(t * (float)half_b);
            blink_fb_fill_rect(fb, apex_x - span, py, span, 1, 0xFFD9B36Cu);
            blink_fb_fill_rect(fb, apex_x, py, span * 3 / 4 + 1, 1, 0xFFA67C37u);
        }
    }
}

static blink_collapsed_border_edge_t node_border_edge(const dom_node_t* n) {
    blink_collapsed_border_edge_t e = { 0, BDR_STYLE_NONE, 0 };
    if (!n) return e;
    e.width = n->style.border_width;
    e.style = n->style.border_style;
    e.color = n->style.border_color;
    return e;
}

static void paint_collapsed_table_borders(dom_node_t* table, blink_framebuffer_t* fb) {
    if (!table || !table->style.border_collapse) return;
    dom_node_t* rows[128];
    int n_rows = 0;
    collect_table_rows(table, rows, &n_rows, 128);
    if (n_rows <= 0) return;

    dom_node_t* grid_occ[128][32];
    memset(grid_occ, 0, sizeof(grid_occ));
    int num_cols = 0;
    int col_x0[32], col_x1[32];
    for (int k = 0; k < 32; k++) { col_x0[k] = 0; col_x1[k] = 0; }

    for (int r = 0; r < n_rows; r++) {
        int c_cur = 0;
        for (int ci = 0; ci < rows[r]->num_children; ci++) {
            dom_node_t* cell = rows[r]->children[ci];
            if (!cell || cell->style.display == DISPLAY_NONE || strcmp(cell->tag, "#text") == 0 || is_out_of_flow(cell)) {
                continue;
            }
            while (c_cur < 32 && grid_occ[r][c_cur] != NULL) c_cur++;
            if (c_cur >= 32) break;
            int cspan = blink_html_sanitize_span(cell->colspan, 32 - c_cur);
            int rspan = blink_html_sanitize_span(cell->rowspan, n_rows - r);
            if (cspan == 1) {
                col_x0[c_cur] = cell->x;
                col_x1[c_cur] = cell->x + cell->w;
            } else if (col_x0[c_cur] == 0) {
                int per = cell->w / cspan;
                for (int cc = 0; cc < cspan; cc++) {
                    col_x0[c_cur + cc] = cell->x + cc * per;
                    col_x1[c_cur + cc] = (cc == cspan - 1) ? (cell->x + cell->w) : (cell->x + (cc + 1) * per);
                }
            }
            for (int rr = r; rr < r + rspan; rr++) {
                for (int cc = c_cur; cc < c_cur + cspan; cc++) {
                    grid_occ[rr][cc] = cell;
                }
            }
            if (c_cur + cspan > num_cols) num_cols = c_cur + cspan;
            c_cur += cspan;
        }
    }
    if (num_cols <= 0) return;

    blink_collapsed_border_edge_t tbl_edge = node_border_edge(table);

    /* Horizontal shared grid segments `r = 0 .. n_rows` */
    for (int r = 0; r <= n_rows; r++) {
        int y_line = (r < n_rows) ? rows[r]->y : (rows[n_rows - 1]->y + rows[n_rows - 1]->h);
        for (int c = 0; c < num_cols; c++) {
            dom_node_t* above = (r > 0) ? grid_occ[r - 1][c] : NULL;
            dom_node_t* below = (r < n_rows) ? grid_occ[r][c] : NULL;
            if (above && above == below) continue; /* Inside a rowspan cell! */

            blink_collapsed_border_edge_t ea = above ? node_border_edge(above) : tbl_edge;
            blink_collapsed_border_edge_t eb = below ? node_border_edge(below) : tbl_edge;
            blink_collapsed_border_edge_t win = blink_resolve_collapsed_border(ea, eb);
            if (win.width > 0 && win.style != BDR_STYLE_NONE && win.style != BDR_STYLE_HIDDEN) {
                blink_fb_fill_rect(fb, col_x0[c], y_line - win.width / 2,
                                   col_x1[c] - col_x0[c], win.width, win.color);
            }
        }
    }

    /* Vertical shared grid segments `c = 0 .. num_cols` */
    for (int r = 0; r < n_rows; r++) {
        int y0 = rows[r]->y;
        int rh = rows[r]->h;
        for (int c = 0; c <= num_cols; c++) {
            dom_node_t* left_c = (c > 0) ? grid_occ[r][c - 1] : NULL;
            dom_node_t* right_c = (c < num_cols) ? grid_occ[r][c] : NULL;
            if (left_c && left_c == right_c) continue; /* Inside a colspan cell! */

            int x_line = (c < num_cols) ? col_x0[c] : col_x1[num_cols - 1];
            blink_collapsed_border_edge_t el = left_c ? node_border_edge(left_c) : tbl_edge;
            blink_collapsed_border_edge_t er = right_c ? node_border_edge(right_c) : tbl_edge;
            blink_collapsed_border_edge_t win = blink_resolve_collapsed_border(el, er);
            if (win.width > 0 && win.style != BDR_STYLE_NONE && win.style != BDR_STYLE_HIDDEN) {
                blink_fb_fill_rect(fb, x_line - win.width / 2, y0, win.width, rh, win.color);
            }
        }
    }
}

static void paint_inline_fragments_of(dom_node_t* node, blink_framebuffer_t* fb) {
    if (!node || node->num_inline_frags <= 0 || !node->inline_frags) return;

    /* Pass 1: Inline pill backgrounds & borders (`<code>`, `<mark>`, `.badge`) with `SkRRect` SDF! */
    for (int i = 0; i < node->num_inline_frags; i++) {
        const blink_inline_frag_t* fg = &node->inline_frags[i];
        int px = (int)floorf(fg->x);
        int pw = (int)ceilf(fg->w);
        int pill_h = (int)ceilf(fg->font_size * 1.22f) + fg->pad_top + fg->pad_bottom;
        int py = (int)lroundf(fg->baseline_y - fg->font_size * 0.85f) - fg->pad_top;
        if (fg->has_bg && (fg->bg_color >> 24) > 0) {
            blink_fb_fill_rrect(fb, px, py, pw, pill_h, fg->border_radius, fg->bg_color);
        }
        if (fg->border_width > 0) {
            blink_fb_stroke_rrect(fb, px, py, pw, pill_h, fg->border_radius, fg->border_width, fg->border_color);
        }
    }

    /* Pass 2: Crisp glyphs + `underline` + `line-through` */
    for (int i = 0; i < node->num_inline_frags; i++) {
        const blink_inline_frag_t* fg = &node->inline_frags[i];
        int style_flags = (fg->font_weight >= 700 ? BLINK_FONT_STYLE_BOLD : 0) |
                          (fg->font_style ? BLINK_FONT_STYLE_ITALIC : 0);
        float text_x = fg->x + (float)fg->pad_left;
        blink_skia_font_draw_text(fb->pixels, fb->width, fb->height,
                                  text_x, fg->baseline_y,
                                  fg->text, fg->font_family, fg->font_size,
                                  style_flags, fg->color);
        int text_w = (int)ceilf(fg->glyph_w);
        if (text_w > 0) {
            if (fg->underline) {
                blink_fb_fill_rect(fb, (int)lroundf(text_x), (int)lroundf(fg->baseline_y + 2.0f),
                                   text_w, 1, fg->color);
            }
            if (fg->line_through) {
                blink_fb_fill_rect(fb, (int)lroundf(text_x),
                                   (int)lroundf(fg->baseline_y - fg->font_size * 0.30f),
                                   text_w, 1, fg->color);
            }
        }
    }
}

static void paint_stacking_context(dom_node_t* sc_root, blink_framebuffer_t* fb);

static inline bool establishes_paint_layer(const dom_node_t* n) {
    if (!n) return false;
    return (n->style.position != POS_STATIC ||
            n->style.opacity_u8 < 255 ||
            n->style.has_transform ||
            n->style.overflow_hidden);
}

static inline int effective_z_index(const dom_node_t* n) {
    if (!n) return 0;
    return (n->style.position != POS_STATIC && n->style.has_z_index) ? n->style.z_index : 0;
}

static void paint_shift_subtree_all(dom_node_t* n, int dx, int dy) {
    if (!n || (dx == 0 && dy == 0)) return;
    n->x += dx;
    n->y += dy;
    for (int k = 0; k < n->num_inline_frags; k++) {
        n->inline_frags[k].x += (float)dx;
        n->inline_frags[k].y += (float)dy;
        n->inline_frags[k].baseline_y += (float)dy;
    }
    for (int i = 0; i < n->num_children; i++) {
        paint_shift_subtree_all(n->children[i], dx, dy);
    }
}

static void compute_subtree_visual_bounds(const dom_node_t* n,
                                          int* io_x0, int* io_y0, int* io_x1, int* io_y1) {
    if (!n || n->style.display == DISPLAY_NONE) return;
    int pad = 2;
    if (n->style.has_box_shadow) {
        int blur = (n->style.shadow_blur > 0) ? n->style.shadow_blur : 0;
        int sp = (n->style.shadow_spread > 0) ? n->style.shadow_spread : 0;
        int sh_pad = abs(n->style.shadow_dx) + abs(n->style.shadow_dy) + blur + sp + 4;
        if (sh_pad > pad) pad = sh_pad;
    }
    if (n->w > 0 || n->h > 0) {
        if (n->x - pad < *io_x0) *io_x0 = n->x - pad;
        if (n->y - pad < *io_y0) *io_y0 = n->y - pad;
        if (n->x + n->w + pad > *io_x1) *io_x1 = n->x + n->w + pad;
        if (n->y + n->h + pad > *io_y1) *io_y1 = n->y + n->h + pad;
    }
    for (int k = 0; k < n->num_inline_frags; k++) {
        const blink_inline_frag_t* fg = &n->inline_frags[k];
        int fx0 = (int)floorf(fg->x) - 4;
        int fy0 = (int)floorf(fg->baseline_y - fg->font_size * 1.2f) - fg->pad_top - 4;
        int fx1 = (int)ceilf(fg->x + fg->w) + 4;
        int fy1 = (int)ceilf(fg->baseline_y + fg->font_size * 0.5f) + fg->pad_bottom + 4;
        if (fx0 < *io_x0) *io_x0 = fx0;
        if (fy0 < *io_y0) *io_y0 = fy0;
        if (fx1 > *io_x1) *io_x1 = fx1;
        if (fy1 > *io_y1) *io_y1 = fy1;
    }
    if (!n->style.overflow_hidden) {
        for (int i = 0; i < n->num_children; i++) {
            compute_subtree_visual_bounds(n->children[i], io_x0, io_y0, io_x1, io_y1);
        }
    }
}

static blink_framebuffer_t* create_backdrop_sub_fb(const blink_framebuffer_t* fb,
                                                   int bx0, int by0, int bw, int bh) {
    if (!fb || !fb->pixels || bw <= 0 || bh <= 0) return NULL;
    blink_framebuffer_t* sub = (blink_framebuffer_t*)malloc(sizeof(blink_framebuffer_t));
    if (!sub) return NULL;
    sub->width = bw;
    sub->height = bh;
    sub->pixels = (uint32_t*)malloc((size_t)bw * (size_t)bh * sizeof(uint32_t));
    if (!sub->pixels) {
        free(sub);
        return NULL;
    }
    for (int r = 0; r < bh; r++) {
        memcpy(sub->pixels + (size_t)r * (size_t)bw,
               fb->pixels + (size_t)(by0 + r) * (size_t)fb->width + (size_t)bx0,
               (size_t)bw * sizeof(uint32_t));
    }
    return sub;
}

static void composite_sub_fb_masked(blink_framebuffer_t* dst,
                                    const blink_framebuffer_t* sub,
                                    int bx0, int by0,
                                    uint32_t opacity_u8,
                                    bool clip_rrect,
                                    int rx, int ry, int rw, int rh, int r_rad) {
    if (!dst || !sub || opacity_u8 == 0u) return;
    float frx = (float)rx, fry = (float)ry, frw = (float)rw, frh = (float)rh, fr = (float)r_rad;
    int mid_x0 = rx + r_rad;
    int mid_x1 = rx + rw - r_rad;
    int mid_y0 = ry + r_rad;
    int mid_y1 = ry + rh - r_rad;

    for (int r = 0; r < sub->height; r++) {
        int py = by0 + r;
        uint32_t* dst_row = dst->pixels + (size_t)py * (size_t)dst->width;
        const uint32_t* src_row = sub->pixels + (size_t)r * (size_t)sub->width;
        bool in_mid_y = (!clip_rrect || r_rad <= 0) || (py >= mid_y0 && py < mid_y1);

        for (int c = 0; c < sub->width; c++) {
            int px = bx0 + c;
            uint32_t w_u8 = opacity_u8;
            if (clip_rrect && r_rad > 0 && !in_mid_y && (px < mid_x0 || px >= mid_x1)) {
                uint32_t cov = rrect_coverage_u8(
                    rrect_signed_dist_f((float)px + 0.5f, (float)py + 0.5f, frx, fry, frw, frh, fr));
                w_u8 = (w_u8 * cov + 127u) / 255u;
            }
            if (w_u8 == 0u) continue;
            uint32_t s = src_row[c];
            if (w_u8 >= 255u) {
                dst_row[px] = s;
            } else {
                uint32_t d = dst_row[px];
                if (s == d) continue;
                uint32_t inv_w = 255u - w_u8;
                uint32_t sr = (s >> 16) & 0xFFu, sg = (s >> 8) & 0xFFu, sb = s & 0xFFu;
                uint32_t dr = (d >> 16) & 0xFFu, dg = (d >> 8) & 0xFFu, db = d & 0xFFu;
                uint32_t or_c = (sr * w_u8 + dr * inv_w + 127u) / 255u;
                uint32_t og_c = (sg * w_u8 + dg * inv_w + 127u) / 255u;
                uint32_t ob_c = (sb * w_u8 + db * inv_w + 127u) / 255u;
                dst_row[px] = 0xFF000000u | (or_c << 16) | (og_c << 8) | ob_c;
            }
        }
    }
}

typedef struct {
    dom_node_t** items;
    int          count;
    int          cap;
} node_list_t;

static void node_list_push(node_list_t* nl, dom_node_t* n) {
    if (nl->count + 1 > nl->cap) {
        int ncap = (nl->cap == 0) ? 16 : (nl->cap * 2);
        dom_node_t** np = (dom_node_t**)realloc(nl->items, (size_t)ncap * sizeof(dom_node_t*));
        if (!np) return;
        nl->items = np;
        nl->cap = ncap;
    }
    nl->items[nl->count++] = n;
}

static int cmp_stack_item(const void* pa, const void* pb) {
    const dom_node_t* a = *(const dom_node_t* const*)pa;
    const dom_node_t* b = *(const dom_node_t* const*)pb;
    int za = effective_z_index(a);
    int zb = effective_z_index(b);
    if (za != zb) return (za < zb) ? -1 : 1;
    if (a->dom_order != b->dom_order) return (a->dom_order < b->dom_order) ? -1 : 1;
    return 0;
}

static void collect_positioned_and_floats(dom_node_t* scan,
                                          node_list_t* neg_z,
                                          node_list_t* floats,
                                          node_list_t* auto_z,
                                          node_list_t* pos_z) {
    if (!scan) return;
    for (int i = 0; i < scan->num_children; i++) {
        dom_node_t* ch = scan->children[i];
        if (!ch || ch->style.display == DISPLAY_NONE) continue;

        if (establishes_paint_layer(ch)) {
            int z = effective_z_index(ch);
            if (z < 0) {
                node_list_push(neg_z, ch);
            } else if (z > 0) {
                node_list_push(pos_z, ch);
            } else {
                node_list_push(auto_z, ch);
            }
            /* Stacking context / paint layer paints its own subtree in Phase 2, 6, or 7! */
            continue;
        }

        if (ch->style.css_float != FLOAT_NONE) {
            node_list_push(floats, ch);
            /* Float subtree's positioned/layer children still participate in enclosing stacking context! */
            collect_positioned_and_floats(ch, neg_z, floats, auto_z, pos_z);
            continue;
        }

        /* Do not collect boxes inside pure-inline formatting runs as separate block layers */
        if (scan->num_inline_frags > 0 && subtree_is_pure_inline(ch)) {
            continue;
        }

        collect_positioned_and_floats(ch, neg_z, floats, auto_z, pos_z);
    }
}

/* Phase 3: In-flow non-layer non-float block backgrounds & borders */
static void paint_inflow_blocks(dom_node_t* scan, blink_framebuffer_t* fb, bool in_collapsed_table) {
    if (!scan) return;
    bool cur_collapsed = in_collapsed_table ||
                         (scan->style.display == DISPLAY_TABLE && scan->style.border_collapse);

    for (int i = 0; i < scan->num_children; i++) {
        dom_node_t* ch = scan->children[i];
        if (!ch || ch->style.display == DISPLAY_NONE) continue;
        if (establishes_paint_layer(ch) || ch->style.css_float != FLOAT_NONE) continue;
        if (scan->num_inline_frags > 0 && subtree_is_pure_inline(ch)) continue;

        bool is_cell_in_collapsed = in_collapsed_table &&
                                    (strcmp(ch->tag, "td") == 0 || strcmp(ch->tag, "th") == 0 ||
                                     strcmp(ch->tag, "tr") == 0);
        paint_box_decoration(ch, fb, is_cell_in_collapsed);
        paint_inflow_blocks(ch, fb, cur_collapsed);
        if (ch->style.display == DISPLAY_TABLE && ch->style.border_collapse) {
            paint_collapsed_table_borders(ch, fb);
        }
    }
}

/* Phase 5: In-flow non-layer non-float inline fragments */
static void paint_inflow_inlines(dom_node_t* scan, blink_framebuffer_t* fb) {
    if (!scan) return;
    paint_inline_fragments_of(scan, fb);
    for (int i = 0; i < scan->num_children; i++) {
        dom_node_t* ch = scan->children[i];
        if (!ch || ch->style.display == DISPLAY_NONE) continue;
        if (establishes_paint_layer(ch) || ch->style.css_float != FLOAT_NONE) continue;
        if (scan->num_inline_frags > 0 && subtree_is_pure_inline(ch)) continue;
        paint_inflow_inlines(ch, fb);
    }
}

static void paint_float_subtree(dom_node_t* fl, blink_framebuffer_t* fb) {
    if (!fl || fl->style.display == DISPLAY_NONE) return;
    paint_box_decoration(fl, fb, false);
    paint_inflow_blocks(fl, fb, fl->style.display == DISPLAY_TABLE && fl->style.border_collapse);
    if (fl->style.display == DISPLAY_TABLE && fl->style.border_collapse) {
        paint_collapsed_table_borders(fl, fb);
    }
    paint_inflow_inlines(fl, fb);
}

static void paint_stacking_context_phases_2_to_7(dom_node_t* sc_root,
                                                 blink_framebuffer_t* fb,
                                                 const node_list_t* neg_z,
                                                 const node_list_t* floats,
                                                 const node_list_t* auto_z,
                                                 const node_list_t* pos_z) {
    /* Phase 2: Positioned descendants with negative `z-index < 0` */
    for (int i = 0; i < neg_z->count; i++) {
        paint_stacking_context(neg_z->items[i], fb);
    }

    /* Phase 3: In-flow non-positioned block-level descendants */
    paint_inflow_blocks(sc_root, fb, sc_root->style.display == DISPLAY_TABLE && sc_root->style.border_collapse);
    if (sc_root->style.display == DISPLAY_TABLE && sc_root->style.border_collapse) {
        paint_collapsed_table_borders(sc_root, fb);
    }

    /* Phase 4: Non-positioned floats */
    for (int i = 0; i < floats->count; i++) {
        paint_float_subtree(floats->items[i], fb);
    }

    /* Phase 5: In-flow inline-level fragments (`<b>`, `<i>`, `<a>`, `<code>`, text) */
    paint_inflow_inlines(sc_root, fb);

    /* Phase 6: Positioned/layer descendants with `z-index: auto` or `z-index: 0` */
    for (int i = 0; i < auto_z->count; i++) {
        paint_stacking_context(auto_z->items[i], fb);
    }

    /* Phase 7: Positioned descendants with positive `z-index > 0` */
    for (int i = 0; i < pos_z->count; i++) {
        paint_stacking_context(pos_z->items[i], fb);
    }
}

static void paint_stacking_context_core(dom_node_t* sc_root, blink_framebuffer_t* fb) {
    node_list_t neg_z = { NULL, 0, 0 };
    node_list_t floats = { NULL, 0, 0 };
    node_list_t auto_z = { NULL, 0, 0 };
    node_list_t pos_z = { NULL, 0, 0 };
    collect_positioned_and_floats(sc_root, &neg_z, &floats, &auto_z, &pos_z);

    if (neg_z.count > 1) qsort(neg_z.items, (size_t)neg_z.count, sizeof(dom_node_t*), cmp_stack_item);
    if (auto_z.count > 1) qsort(auto_z.items, (size_t)auto_z.count, sizeof(dom_node_t*), cmp_stack_item);
    if (pos_z.count > 1) qsort(pos_z.items, (size_t)pos_z.count, sizeof(dom_node_t*), cmp_stack_item);

    /* Phase 1: Stacking context root shadow, background, gradient & border */
    paint_box_decoration(sc_root, fb, false);

    /* W3C CSS Overflow Module Level 3 §3.2: `overflow: hidden` clips Phases 2..7
       strictly to the element's inner padding box and inner `SkRRect` curve! */
    if (sc_root->style.overflow_hidden) {
        int bw = (sc_root->style.border_style != BDR_STYLE_NONE &&
                  sc_root->style.border_style != BDR_STYLE_HIDDEN)
                     ? sc_root->style.border_width
                     : 0;
        int bl = (bw > 0) ? bw : sc_root->style.border_left_width;
        int br = bw;
        int bt = bw;
        int bb = (bw > 0) ? bw : sc_root->style.border_bottom_width;

        int pad_x = sc_root->x + bl;
        int pad_y = sc_root->y + bt;
        int pad_w = sc_root->w - bl - br;
        int pad_h = sc_root->h - bt - bb;

        int cx0, cy0, cx1, cy1;
        blink_intersect_scissor(0, 0, fb->width, fb->height,
                                pad_x, pad_y, pad_x + pad_w, pad_y + pad_h,
                                &cx0, &cy0, &cx1, &cy1);
        if (cx1 > cx0 && cy1 > cy0) {
            blink_framebuffer_t* clip_fb = create_backdrop_sub_fb(fb, cx0, cy0, cx1 - cx0, cy1 - cy0);
            if (clip_fb) {
                paint_shift_subtree_all(sc_root, -cx0, -cy0);
                paint_stacking_context_phases_2_to_7(sc_root, clip_fb, &neg_z, &floats, &auto_z, &pos_z);
                paint_shift_subtree_all(sc_root, cx0, cy0);

                int r_outer = blink_clamp_corner_radius(sc_root->w, sc_root->h, sc_root->style.border_radius);
                int r_pad = (r_outer > bw) ? (r_outer - bw) : 0;
                r_pad = blink_clamp_corner_radius(pad_w, pad_h, r_pad);
                composite_sub_fb_masked(fb, clip_fb, cx0, cy0, 255u,
                                        r_pad > 0, pad_x, pad_y, pad_w, pad_h, r_pad);
                blink_fb_destroy(clip_fb);
            }
        }
    } else {
        paint_stacking_context_phases_2_to_7(sc_root, fb, &neg_z, &floats, &auto_z, &pos_z);
    }

    free(neg_z.items);
    free(floats.items);
    free(auto_z.items);
    free(pos_z.items);
}

static void paint_stacking_context(dom_node_t* sc_root, blink_framebuffer_t* fb) {
    if (!sc_root || sc_root->style.display == DISPLAY_NONE || !fb) return;
    if (sc_root->style.opacity_u8 <= 0) return;

    /* W3C CSS Color Module Level 4 §12.2: `opacity < 1.0` composites the entire
       stacking context atomically offscreen before blending onto the backdrop! */
    if (sc_root->style.opacity_u8 < 255) {
        int ux0 = fb->width, uy0 = fb->height, ux1 = 0, uy1 = 0;
        compute_subtree_visual_bounds(sc_root, &ux0, &uy0, &ux1, &uy1);
        int bx0, by0, bx1, by1;
        blink_intersect_scissor(0, 0, fb->width, fb->height, ux0, uy0, ux1, uy1, &bx0, &by0, &bx1, &by1);
        if (bx1 <= bx0 || by1 <= by0) return;

        blink_framebuffer_t* grp_fb = create_backdrop_sub_fb(fb, bx0, by0, bx1 - bx0, by1 - by0);
        if (!grp_fb) return;

        paint_shift_subtree_all(sc_root, -bx0, -by0);
        paint_stacking_context_core(sc_root, grp_fb);
        paint_shift_subtree_all(sc_root, bx0, by0);

        composite_sub_fb_masked(fb, grp_fb, bx0, by0, (uint32_t)sc_root->style.opacity_u8,
                                false, 0, 0, 0, 0, 0);
        blink_fb_destroy(grp_fb);
        return;
    }

    paint_stacking_context_core(sc_root, fb);
}

void blink_paint_dom_stacking_context(dom_node_t* root, blink_framebuffer_t* fb) {
    paint_stacking_context(root, fb);
}
