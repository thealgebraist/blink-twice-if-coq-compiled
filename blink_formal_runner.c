#include "blink_formal_engine.h"
#include <stdio.h>
#include <assert.h>

int main(void) {
    printf("=== Blink Formal Engine: Drop-in Replacement Execution ===\n");
    
    // 1. Obtain verified input matching Coq sample_interactive_page
    InteractivePageInput page = get_sample_interactive_page();
    
    // 2. Execute layout pipeline (800x600 viewport)
    InteractiveLayoutOutput out = layout_interactive_page_pipeline(800, 600, &page);
    
    printf("Viewport: %lld x %lld\n", (long long)out.ilo_viewport_w, (long long)out.ilo_viewport_h);
    printf("H1:       y=%lld, h=%lld\n", (long long)out.ilo_h1_y, (long long)out.ilo_h1_h);
    printf("P:        y=%lld, h=%lld\n", (long long)out.ilo_p_y, (long long)out.ilo_p_h);
    printf("Flex:     y=%lld, h=%lld\n", (long long)out.ilo_flex_y, (long long)out.ilo_flex_h);
    printf("Table:    y=%lld, h=%lld (c1_w=%lld, c2_w=%lld)\n", 
           (long long)out.ilo_table_y, (long long)out.ilo_table_h, 
           (long long)out.ilo_table_c1_w, (long long)out.ilo_table_c2_w);
    printf("List:     y=%lld, h=%lld\n", (long long)out.ilo_ul_y, (long long)out.ilo_ul_h);
    printf("Button:   y=%lld, w=%lld, h=%lld\n", 
           (long long)out.ilo_btn_y, (long long)out.ilo_btn_w, (long long)out.ilo_btn_h);
    
    // Exact assertion checks matching Coq theorem sample_interactive_page_execution
    assert(out.ilo_h1_y == 29 && out.ilo_h1_h == 38);
    assert(out.ilo_p_y == 88 && out.ilo_p_h == 19);
    assert(out.ilo_flex_y == 123 && out.ilo_flex_h == 60);
    assert(out.ilo_table_y == 195 && out.ilo_table_h == 25);
    assert(out.ilo_table_c1_w == 313 && out.ilo_table_c2_w == 470);
    assert(out.ilo_ul_y == 236 && out.ilo_ul_h == 40);
    assert(out.ilo_btn_y == 292 && out.ilo_btn_w == 76 && out.ilo_btn_h == 32);
    
    printf("\nAll layout coordinates MATCH Coq theorem sample_interactive_page_execution exactly!\n\n");
    
    // 3. Rasterize into 2D discrete FrameBuffer
    Color white = {255, 255, 255, 255};
    FrameBuffer* fb = fb_create(out.ilo_viewport_w, out.ilo_viewport_h, white);
    assert(fb != NULL);
    
    rasterize_interactive_page(fb, &out);
    
    // 4. Verify pixel values against Coq theorem sample_interactive_page_raster_pixel_exact
    Color p_margin = fb_get_pixel(fb, 2, 2);
    Color p_h1     = fb_get_pixel(fb, 10, 30);
    Color p_p      = fb_get_pixel(fb, 10, 90);
    Color p_flex   = fb_get_pixel(fb, 10, 130);
    Color p_tbl_c1 = fb_get_pixel(fb, 10, 200);
    Color p_tbl_c2 = fb_get_pixel(fb, 330, 200);
    Color p_bullet = fb_get_pixel(fb, 3, 240);
    Color p_list   = fb_get_pixel(fb, 10, 240);
    Color p_btn_bd = fb_get_pixel(fb, 8, 292);
    Color p_btn_in = fb_get_pixel(fb, 12, 296);
    
    printf("Sampling Rasterizer Framebuffer:\n");
    printf("  Margin (2, 2):     RGBA(%u, %u, %u, %u) [Expected: 255, 255, 255, 255]\n", p_margin.r, p_margin.g, p_margin.b, p_margin.a);
    printf("  H1 (10, 30):       RGBA(%u, %u, %u, %u) [Expected: 32, 33, 36, 255]\n", p_h1.r, p_h1.g, p_h1.b, p_h1.a);
    printf("  Flex (10, 130):    RGBA(%u, %u, %u, %u) [Expected: 232, 240, 254, 255]\n", p_flex.r, p_flex.g, p_flex.b, p_flex.a);
    printf("  Tbl Col1 (10, 200):RGBA(%u, %u, %u, %u) [Expected: 241, 243, 244, 255]\n", p_tbl_c1.r, p_tbl_c1.g, p_tbl_c1.b, p_tbl_c1.a);
    printf("  Tbl Col2 (330, 200):RGBA(%u, %u, %u, %u) [Expected: 255, 255, 255, 255]\n", p_tbl_c2.r, p_tbl_c2.g, p_tbl_c2.b, p_tbl_c2.a);
    printf("  Bullet (3, 240):   RGBA(%u, %u, %u, %u) [Expected: 0, 0, 0, 255]\n", p_bullet.r, p_bullet.g, p_bullet.b, p_bullet.a);
    printf("  Button Border:     RGBA(%u, %u, %u, %u) [Expected: 32, 33, 36, 255]\n", p_btn_bd.r, p_btn_bd.g, p_btn_bd.b, p_btn_bd.a);
    printf("  Button Interior:   RGBA(%u, %u, %u, %u) [Expected: 26, 115, 232, 255]\n", p_btn_in.r, p_btn_in.g, p_btn_in.b, p_btn_in.a);
    
    assert(p_margin.r == 255 && p_margin.g == 255 && p_margin.b == 255);
    assert(p_h1.r == 32 && p_h1.g == 33 && p_h1.b == 36);
    assert(p_flex.r == 232 && p_flex.g == 240 && p_flex.b == 254);
    assert(p_tbl_c1.r == 241 && p_tbl_c1.g == 243 && p_tbl_c1.b == 244);
    assert(p_tbl_c2.r == 255 && p_tbl_c2.g == 255 && p_tbl_c2.b == 255);
    assert(p_bullet.r == 0 && p_bullet.g == 0 && p_bullet.b == 0);
    assert(p_btn_bd.r == 32 && p_btn_bd.g == 33 && p_btn_bd.b == 36);
    assert(p_btn_in.r == 26 && p_btn_in.g == 115 && p_btn_in.b == 232);
    
    printf("\nAll FrameBuffer pixels MATCH Coq theorem sample_interactive_page_raster_pixel_exact!\n");
    
    // 5. Export to PPM image
    const char* out_ppm = "blink_formal_rendered_page.ppm";
    bool ok = fb_write_ppm(fb, out_ppm);
    if (ok) {
        printf("Successfully wrote 800x600 PPM raster image to: %s\n", out_ppm);
    } else {
        printf("Failed to write PPM image.\n");
    }
    
    fb_destroy(fb);
    return 0;
}

