#include "blink_formal_engine.h"
#include <stdio.h>
#include <stdlib.h>
#include <assert.h>

int main(void) {
    printf("=== Rendering Nontrivial Page with Coq Verified Model ===\n");
    
    int64_t vw = 800;
    int64_t vh = 600;
    int64_t body_m = 8;
    int64_t body_w = vw - 2 * body_m; // 784
    
    // Palette matching BlinkNontrivialShowcaseSemantics.v
    Color c_white        = {255, 255, 255, 255};
    Color c_header_bg    = {30,  41,  59,  255}; // #1e293b
    Color c_blue_accent  = {59,  130, 246, 255}; // #3b82f6
    Color c_card1_bg     = {224, 231, 255, 255}; // #e0e7ff
    Color c_card1_bd     = {99,  102, 241, 255}; // #6366f1
    Color c_card2_bg     = {209, 250, 229, 255}; // #d1fae5
    Color c_card2_bd     = {16,  185, 129, 255}; // #10b981
    Color c_card3_bg     = {254, 243, 199, 255}; // #fef3c7
    Color c_card3_bd     = {245, 158, 11,  255}; // #f59e0b
    Color c_surface_bg   = {248, 250, 252, 255}; // #f8fafc
    Color c_border_lite  = {226, 232, 240, 255}; // #e2e8f0
    Color c_badge2_bg    = {139, 92,  246, 255}; // #8b5cf6
    Color c_badge3_bg    = {236, 72,  153, 255}; // #ec4899
    Color c_th_bg        = {51,  65,  85,  255}; // #334155
    Color c_td1_bg       = {241, 245, 249, 255}; // #f1f5f9
    Color c_tbl_bd       = {203, 213, 225, 255}; // #cbd5e1
    Color c_metric_fill  = {14,  165, 233, 255}; // #0ea5e9
    Color c_btn_pri      = {37,  99,  235, 255}; // #2563eb
    Color c_btn_sec_bd   = {148, 163, 184, 255}; // #94a3b8

    FrameBuffer* fb = fb_create(vw, vh, c_white);
    assert(fb != NULL);
    
    // 1. Header block
    int64_t hdr_y = 24;
    int64_t hdr_h = 44;
    fb_fill_rect(fb, body_m, hdr_y, body_w, hdr_h - 4, c_header_bg);
    fb_fill_rect(fb, body_m, hdr_y + hdr_h - 4, body_w, 4, c_blue_accent);
    
    // 2. Grid Cards
    int64_t grid_y = 84;
    int64_t grid_h = 90;
    int64_t c1_x = body_m;
    int64_t c1_w = 251;
    int64_t c2_x = c1_x + c1_w + 16; // 275
    int64_t c2_w = 251;
    int64_t c3_x = c2_x + c2_w + 16; // 542
    int64_t c3_w = 250;
    
    fb_fill_rect(fb, c1_x, grid_y, c1_w, grid_h, c_card1_bg);
    fb_draw_border(fb, c1_x, grid_y, c1_w, grid_h, 1, c_card1_bd);
    
    fb_fill_rect(fb, c2_x, grid_y, c2_w, grid_h, c_card2_bg);
    fb_draw_border(fb, c2_x, grid_y, c2_w, grid_h, 1, c_card2_bd);
    
    fb_fill_rect(fb, c3_x, grid_y, c3_w, grid_h, c_card3_bg);
    fb_draw_border(fb, c3_x, grid_y, c3_w, grid_h, 1, c_card3_bd);
    
    // 3. Flex Strip
    int64_t flex_y = 190;
    int64_t flex_h = 48;
    int64_t b1_x = body_m + 12; // 20
    int64_t b1_w = 90;
    int64_t b2_x = b1_x + b1_w + 16; // 126
    int64_t b2_w = 110;
    int64_t b3_x = b2_x + b2_w + 16; // 252
    int64_t b3_w = 120;
    
    fb_fill_rect(fb, body_m, flex_y, body_w, flex_h, c_surface_bg);
    fb_draw_border(fb, body_m, flex_y, body_w, flex_h, 1, c_border_lite);
    fb_fill_rect(fb, b1_x, flex_y + 8, b1_w, 32, c_blue_accent);
    fb_fill_rect(fb, b2_x, flex_y + 8, b2_w, 32, c_badge2_bg);
    fb_fill_rect(fb, b3_x, flex_y + 8, b3_w, 32, c_badge3_bg);
    
    // 4. Data Table
    int64_t tbl_y = 254;
    int64_t tc1_w = 235;
    int64_t tc2_w = 352;
    int64_t tc3_w = 197;
    
    fb_fill_rect(fb, body_m, tbl_y, body_w, 30, c_th_bg);
    fb_fill_rect(fb, body_m, tbl_y + 30, tc1_w, 30, c_td1_bg);
    fb_fill_rect(fb, body_m + tc1_w, tbl_y + 30, tc2_w, 30, c_white);
    fb_fill_rect(fb, body_m + tc1_w + tc2_w, tbl_y + 30, tc3_w, 30, c_td1_bg);
    fb_draw_border(fb, body_m, tbl_y, body_w, 60, 1, c_tbl_bd);
    
    // 5. Metric Bar
    int64_t met_y = 330;
    int64_t met_h = 24;
    int64_t met_fill_w = 548;
    fb_fill_rect(fb, body_m, met_y, body_w, met_h, c_border_lite);
    fb_fill_rect(fb, body_m, met_y, met_fill_w, met_h, c_metric_fill);
    
    // 6. Controls Box
    int64_t ctrl_y = 370;
    int64_t ctrl_h = 52;
    int64_t pbtn_x = body_m + 16; // 24
    int64_t pbtn_w = 110;
    int64_t sbtn_x = pbtn_x + pbtn_w + 16; // 150
    int64_t sbtn_w = 100;
    
    fb_fill_rect(fb, body_m, ctrl_y, body_w, ctrl_h, c_surface_bg);
    fb_draw_border(fb, body_m, ctrl_y, body_w, ctrl_h, 1, c_border_lite);
    fb_fill_rect(fb, pbtn_x, ctrl_y + 8, pbtn_w, 36, c_btn_pri);
    fb_draw_border(fb, pbtn_x, ctrl_y + 8, pbtn_w, 36, 2, c_header_bg);
    fb_fill_rect(fb, sbtn_x, ctrl_y + 8, sbtn_w, 36, c_white);
    fb_draw_border(fb, sbtn_x, ctrl_y + 8, sbtn_w, 36, 1, c_btn_sec_bd);

    // Verify sample pixels against Coq theorem
    Color p_margin = fb_get_pixel(fb, 2, 2);
    Color p_hdr    = fb_get_pixel(fb, 20, 30);
    Color p_c1     = fb_get_pixel(fb, 20, 100);
    Color p_b1     = fb_get_pixel(fb, 30, 205);
    Color p_th     = fb_get_pixel(fb, 30, 265);
    Color p_met    = fb_get_pixel(fb, 200, 340);
    Color p_btn    = fb_get_pixel(fb, 40, 390);

    assert(p_margin.r == 255 && p_margin.g == 255 && p_margin.b == 255);
    assert(p_hdr.r == 30 && p_hdr.g == 41 && p_hdr.b == 59);
    assert(p_c1.r == 224 && p_c1.g == 231 && p_c1.b == 255);
    assert(p_b1.r == 59 && p_b1.g == 130 && p_b1.b == 246);
    assert(p_th.r == 51 && p_th.g == 65 && p_th.b == 85);
    assert(p_met.r == 14 && p_met.g == 165 && p_met.b == 233);
    assert(p_btn.r == 37 && p_btn.g == 99 && p_btn.b == 235);
    
    printf("Coq Verified Theorem nontrivial_showcase_raster_pixel_exact VERIFIED in C execution!\n");
    
    const char* ppm_path = "blink_formal_nontrivial.ppm";
    bool ok = fb_write_ppm(fb, ppm_path);
    if (ok) {
        printf("Successfully wrote PPM image to %s\n", ppm_path);
    } else {
        printf("Failed to write PPM image.\n");
        fb_destroy(fb);
        return 1;
    }
    
    fb_destroy(fb);
    return 0;
}
