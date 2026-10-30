#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include <assert.h>
#include <time.h>
#include "blink_font_engine.h"

#define FB_WIDTH  640
#define FB_HEIGHT 480

static void write_ppm(const uint32_t* fb, int w, int h, const char* filename) {
    FILE* fp = fopen(filename, "wb");
    if (!fp) {
        fprintf(stderr, "Failed to open %s for writing\n", filename);
        return;
    }
    fprintf(fp, "P6\n%d %d\n255\n", w, h);
    for (int y = 0; y < h; ++y) {
        for (int x = 0; x < w; ++x) {
            uint32_t px = fb[y * w + x];
            uint8_t r = (px >> 16) & 0xFF;
            uint8_t g = (px >> 8) & 0xFF;
            uint8_t b = px & 0xFF;
            fputc(r, fp);
            fputc(g, fp);
            fputc(b, fp);
        }
    }
    fclose(fp);
    printf("Wrote PPM image to %s\n", filename);
}

int main(void) {
    printf("=================================================================\n");
    printf("Blink Font Glyph Atlas & Subpixel Text Rasterizer Verification\n");
    printf("=================================================================\n");

    /* 1. Test Font Initialization */
    printf("[1/5] Testing blink_font_init()...\n");
    blink_font_init();

    /* Verify glyph pixel lookups */
    uint8_t p_space = blink_font_get_glyph_pixel(' ', 4, 8);
    assert(p_space == 0 && "Space glyph must be 0");

    uint8_t p_A = blink_font_get_glyph_pixel('A', 3, 9);
    assert(p_A > 0 && "Glyph 'A' must have positive coverage");

    /* Verify subpixel phase coverage table interpolation */
    uint8_t cov_p0 = blink_font_get_subpixel_coverage(200, 0, 0);
    uint8_t cov_p2 = blink_font_get_subpixel_coverage(200, 100, 2);
    uint8_t cov_p4 = blink_font_get_subpixel_coverage(0, 200, 4);
    assert(cov_p0 == 200 && "Phase 0 should match c0");
    assert(cov_p4 == 200 && "Phase 4 should match c1");
    assert(cov_p2 >= 140 && cov_p2 <= 160 && "Phase 2 should average c0 and c1");
    printf("      Glyph atlas and subpixel coverage tables verified successfully.\n");

    /* 2. Test Text Measurement */
    printf("[2/5] Testing blink_font_measure_text()...\n");
    int w_single = blink_font_measure_text("Hello", 16, 0);
    assert(w_single == 40 && "5 chars * 8px = 40px");

    int w_spaced = blink_font_measure_text("Hello", 16, 2);
    assert(w_spaced == 48 && "5 chars * 8px + 4 * 2px = 48px");

    int w_multi = blink_font_measure_text("Short\nA much longer line of text\nEnd", 16, 0);
    assert(w_multi == 26 * 8 && "Multi-line measure must equal longest line");

    int w_scaled = blink_font_measure_text("ABC", 32, 0);
    assert(w_scaled == 3 * 16 && "Scaled font 32px should yield 16px char advance");
    printf("      Text measurement metrics verified.\n");

    /* 3. Test Framebuffer Allocation & Text Rasterization */
    printf("[3/5] Testing blink_font_draw_text() rasterization...\n");
    uint32_t* fb = (uint32_t*)malloc(FB_WIDTH * FB_HEIGHT * sizeof(uint32_t));
    assert(fb != NULL && "Framebuffer allocation failed");

    /* Fill background with clean off-white / light slate (0xFFF8F9FA) */
    uint32_t bg_color = 0xFFF8F9FA;
    for (int i = 0; i < FB_WIDTH * FB_HEIGHT; ++i) {
        fb[i] = bg_color;
    }

    /* Draw Header Text */
    blink_font_draw_text(fb, FB_WIDTH, FB_HEIGHT, 20, 20,
                        "Blink Font Engine - Crisp Antialiased Bitmap Atlas",
                        0xFF1A365D, 16, 0);

    /* Draw Subheader with scaled font */
    blink_font_draw_text(fb, FB_WIDTH, FB_HEIGHT, 20, 44,
                        "C99 Verified Subpixel Engine (ASCII 32..126)",
                        0xFF4A5568, 12, 0);

    /* Count non-background pixels to verify non-zero raster output */
    int non_bg_count = 0;
    for (int y = 15; y < 70; ++y) {
        for (int x = 15; x < 500; ++x) {
            if (fb[y * FB_WIDTH + x] != bg_color) {
                non_bg_count++;
            }
        }
    }
    printf("      Header text raster output produced %d non-background pixels.\n", non_bg_count);
    assert(non_bg_count > 500 && "Text rendering must produce substantial non-zero raster output");

    /* 4. Test Text Box Layout & Alignment (Left, Center, Right) */
    printf("[4/5] Testing blink_font_draw_text_box() and alignment...\n");

    /* Define three boxes with border and background */
    int box_y = 90;
    int box_w = 190;
    int box_h = 100;

    int box_x_left   = 20;
    int box_x_center = 225;
    int box_x_right  = 430;

    /* Draw decorative box borders */
    for (int b = 0; b < 3; ++b) {
        int bx = (b == 0) ? box_x_left : (b == 1 ? box_x_center : box_x_right);
        for (int y = box_y; y < box_y + box_h; ++y) {
            for (int x = bx; x < bx + box_w; ++x) {
                if (y == box_y || y == box_y + box_h - 1 || x == bx || x == bx + box_w - 1) {
                    fb[y * FB_WIDTH + x] = 0xFFCBD5E0; /* Border */
                } else {
                    fb[y * FB_WIDTH + x] = 0xFFFFFFFF; /* Box inner background */
                }
            }
        }
    }

    /* Left Align Box */
    blink_font_draw_text_box(fb, FB_WIDTH, FB_HEIGHT,
                            box_x_left + 10, box_y + 10, box_w - 20, box_h - 20,
                            "Left Align:\nCrisp metrics\nFast compositing",
                            0xFF2B6CB0, 16, BLINK_FONT_ALIGN_LEFT);

    /* Center Align Box */
    blink_font_draw_text_box(fb, FB_WIDTH, FB_HEIGHT,
                            box_x_center + 10, box_y + 10, box_w - 20, box_h - 20,
                            "Center Align:\nBalanced text\nSubpixel fidelity",
                            0xFF2C7A7B, 16, BLINK_FONT_ALIGN_CENTER);

    /* Right Align Box */
    blink_font_draw_text_box(fb, FB_WIDTH, FB_HEIGHT,
                            box_x_right + 10, box_y + 10, box_w - 20, box_h - 20,
                            "Right Align:\nTabular values\nStrict box clip",
                            0xFF975A16, 16, BLINK_FONT_ALIGN_RIGHT);

    /* Verify pixels inside each box */
    int left_box_pixels = 0, center_box_pixels = 0, right_box_pixels = 0;
    for (int y = box_y + 1; y < box_y + box_h - 1; ++y) {
        for (int x = box_x_left + 1; x < box_x_left + box_w - 1; ++x) {
            if (fb[y * FB_WIDTH + x] != 0xFFFFFFFF) left_box_pixels++;
        }
        for (int x = box_x_center + 1; x < box_x_center + box_w - 1; ++x) {
            if (fb[y * FB_WIDTH + x] != 0xFFFFFFFF) center_box_pixels++;
        }
        for (int x = box_x_right + 1; x < box_x_right + box_w - 1; ++x) {
            if (fb[y * FB_WIDTH + x] != 0xFFFFFFFF) right_box_pixels++;
        }
    }
    printf("      Left box raster pixels:   %d\n", left_box_pixels);
    printf("      Center box raster pixels: %d\n", center_box_pixels);
    printf("      Right box raster pixels:  %d\n", right_box_pixels);
    assert(left_box_pixels > 200 && center_box_pixels > 200 && right_box_pixels > 200);

    /* Draw Multi-Scale Typography Showcase */
    blink_font_draw_text(fb, FB_WIDTH, FB_HEIGHT, 20, 210,
                        "Multi-Scale Antialiased Rendering Showcase:",
                        0xFF2D3748, 14, 0);

    blink_font_draw_text(fb, FB_WIDTH, FB_HEIGHT, 20, 235,
                        "Size 10px: The quick brown fox jumps over the lazy dog 0123456789",
                        0xFF4A5568, 10, 0);

    blink_font_draw_text(fb, FB_WIDTH, FB_HEIGHT, 20, 255,
                        "Size 14px: The quick brown fox jumps over the lazy dog 0123456789",
                        0xFF2D3748, 14, 0);

    blink_font_draw_text(fb, FB_WIDTH, FB_HEIGHT, 20, 280,
                        "Size 16px: Native 8x16 1:1 Crisp Monospace ASCII 32..126",
                        0xFF1A202C, 16, 0);

    blink_font_draw_text(fb, FB_WIDTH, FB_HEIGHT, 20, 310,
                        "Size 22px: Subpixel Bilinear Resampling",
                        0xFF742A2A, 22, 1);

    blink_font_draw_text(fb, FB_WIDTH, FB_HEIGHT, 20, 345,
                        "Size 32px: High-DPI Glyph Rendering",
                        0xFF22543D, 32, 1);

    /* Draw ASCII Full Character Set Chart */
    blink_font_draw_text(fb, FB_WIDTH, FB_HEIGHT, 20, 395,
                        "ASCII 32..126 Glyph Set:", 0xFF4A5568, 12, 0);
    char ascii_line1[64] = {0};
    char ascii_line2[64] = {0};
    int idx1 = 0, idx2 = 0;
    for (int c = 32; c <= 78; ++c) ascii_line1[idx1++] = (char)c;
    for (int c = 79; c <= 126; ++c) ascii_line2[idx2++] = (char)c;

    blink_font_draw_text(fb, FB_WIDTH, FB_HEIGHT, 20, 415, ascii_line1, 0xFF1A365D, 16, 1);
    blink_font_draw_text(fb, FB_WIDTH, FB_HEIGHT, 20, 435, ascii_line2, 0xFF1A365D, 16, 1);

    /* Save PPM image for visual inspection before benchmark overlay */
    write_ppm(fb, FB_WIDTH, FB_HEIGHT, "test_font_output.ppm");

    /* 5. Performance Benchmark */
    printf("[5/5] Running High-Performance Throughput Benchmark...\n");
    const int benchmark_iterations = 50000;
    const char* bench_str = "Blink Fast Text 2026";
    int bench_len = (int)strlen(bench_str);

    uint32_t* bench_fb = (uint32_t*)malloc(FB_WIDTH * FB_HEIGHT * sizeof(uint32_t));
    assert(bench_fb != NULL);
    memcpy(bench_fb, fb, FB_WIDTH * FB_HEIGHT * sizeof(uint32_t));

    clock_t start = clock();
    for (int i = 0; i < benchmark_iterations; ++i) {
        int x_pos = (i * 7) % (FB_WIDTH - 150);
        int y_pos = (i * 11) % (FB_HEIGHT - 30);
        blink_font_draw_text(bench_fb, FB_WIDTH, FB_HEIGHT, x_pos, y_pos, bench_str, 0xFF000000, 16, 0);
    }
    clock_t end = clock();
    double elapsed_sec = (double)(end - start) / CLOCKS_PER_SEC;
    double total_glyphs = (double)benchmark_iterations * bench_len;
    double glyphs_per_sec = total_glyphs / elapsed_sec;

    printf("      Rendered %d strings (%d glyphs) in %.4f seconds.\n",
           benchmark_iterations, (int)total_glyphs, elapsed_sec);
    printf("      Performance: %.2f million glyphs/second!\n", glyphs_per_sec / 1e6);
    free(bench_fb);

    /* Total non-zero raster check */
    int total_non_bg = 0;
    for (int i = 0; i < FB_WIDTH * FB_HEIGHT; ++i) {
        if (fb[i] != bg_color) total_non_bg++;
    }
    printf("=================================================================\n");
    printf("Verification Summary:\n");
    printf("Total non-background pixels rendered: %d / %d (%.2f%% of viewport)\n",
           total_non_bg, FB_WIDTH * FB_HEIGHT,
           (double)total_non_bg * 100.0 / (FB_WIDTH * FB_HEIGHT));
    assert(total_non_bg > 5000 && "Total rendered pixels must exceed threshold");
    printf("STATUS: ALL TESTS PASSED SUCCESSFULLY (0 failures)!\n");
    printf("=================================================================\n");

    free(fb);
    return 0;
}
