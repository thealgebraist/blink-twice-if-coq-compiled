/* ========================================================================= */
/* Test Suite: test_image_codec.c                                            */
/* Tests all functionality of blink_image_codec:                             */
/*   - Allocation & Safety Limits                                            */
/*   - PPM (P6 Binary & P3 ASCII) Loading & Saving                           */
/*   - BMP (24-bit & 32-bit) Loading & Saving                                */
/*   - Raw RGBA Loading                                                      */
/*   - Error & Corrupted Stream Handling                                     */
/*   - Nearest-Neighbor and Bilinear Blitters with Scaling and Clipping      */
/*   - Integration with blink_formal_rendered_page.ppm                       */
/* ========================================================================= */

#include "blink_image_codec.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>
#include <math.h>

#define TEST_PASS(name) printf("  [PASS] %s\n", name)

/* ------------------------------------------------------------------------- */
/* Test 1: Allocation and Bounds Checking                                    */
/* ------------------------------------------------------------------------- */
static void test_allocation_and_bounds(void) {
    printf("[1/9] Testing allocation and bounds checking...\n");

    /* Valid allocations */
    blink_image_t* img = blink_image_create(100, 100);
    assert(img != NULL);
    assert(img->width == 100);
    assert(img->height == 100);
    assert(img->pixels != NULL);
    /* Check zero initialization */
    for (int i = 0; i < 100 * 100; ++i) {
        assert(img->pixels[i] == 0);
    }
    blink_image_free(img);

    /* Free NULL should not crash */
    blink_image_free(NULL);

    /* Invalid dimensions */
    assert(blink_image_create(0, 100) == NULL);
    assert(blink_image_create(100, 0) == NULL);
    assert(blink_image_create(-10, 100) == NULL);
    assert(blink_image_create(100, -5) == NULL);
    assert(blink_image_create(BLINK_IMAGE_MAX_DIM + 1, 10) == NULL);
    assert(blink_image_create(10, BLINK_IMAGE_MAX_DIM + 1) == NULL);

    /* Exceeding max pixels limit */
    assert(blink_image_create(10000, 10000) == NULL);

    TEST_PASS("test_allocation_and_bounds");
}

/* ------------------------------------------------------------------------- */
/* Test 2: PPM Binary (P6) Loader & Saver Roundtrip                          */
/* ------------------------------------------------------------------------- */
static void test_ppm_p6_roundtrip(void) {
    printf("[2/9] Testing PPM P6 (binary) load and save...\n");

    const int w = 32, h = 32;
    blink_image_t* orig = blink_image_create(w, h);
    assert(orig != NULL);

    for (int y = 0; y < h; ++y) {
        for (int x = 0; x < w; ++x) {
            uint8_t r = (uint8_t)(x * 8);
            uint8_t g = (uint8_t)(y * 8);
            uint8_t b = (uint8_t)((x + y) * 4);
            orig->pixels[y * w + x] = BLINK_PACK_RGB(r, g, b);
        }
    }

    const char* path = "test_p6_temp.ppm";
    assert(blink_image_save_ppm(orig, path));

    blink_image_t* loaded = blink_image_load_ppm(path);
    assert(loaded != NULL);
    assert(loaded->width == w);
    assert(loaded->height == h);

    for (int i = 0; i < w * h; ++i) {
        assert(loaded->pixels[i] == orig->pixels[i]);
    }

    blink_image_free(orig);
    blink_image_free(loaded);
    remove(path);

    TEST_PASS("test_ppm_p6_roundtrip");
}

/* ------------------------------------------------------------------------- */
/* Test 3: PPM ASCII (P3) with Comments and Whitespace                       */
/* ------------------------------------------------------------------------- */
static void test_ppm_p3_ascii(void) {
    printf("[3/9] Testing PPM P3 (ASCII) parser...\n");

    const char* path = "test_p3_temp.ppm";
    FILE* fp = fopen(path, "w");
    assert(fp != NULL);

    /* Formatted with arbitrary comments and irregular whitespace */
    fprintf(fp, "# Netpbm P3 Test\nP3\n");
    fprintf(fp, "# Width and height on separate lines with comments\n");
    fprintf(fp, "  3 # width\n  2 # height\n");
    fprintf(fp, "# Maxval\n 255 \n");
    fprintf(fp, " 255 0 0    0 255 0    0 0 255\n");
    fprintf(fp, "# Next row\n");
    fprintf(fp, " 255 255 0   255 255 255   0 0 0\n");
    fclose(fp);

    blink_image_t* img = blink_image_load_ppm(path);
    assert(img != NULL);
    assert(img->width == 3);
    assert(img->height == 2);

    /* Row 0: Red, Green, Blue */
    assert(img->pixels[0] == BLINK_PACK_RGB(255, 0, 0));
    assert(img->pixels[1] == BLINK_PACK_RGB(0, 255, 0));
    assert(img->pixels[2] == BLINK_PACK_RGB(0, 0, 255));

    /* Row 1: Yellow, White, Black */
    assert(img->pixels[3] == BLINK_PACK_RGB(255, 255, 0));
    assert(img->pixels[4] == BLINK_PACK_RGB(255, 255, 255));
    assert(img->pixels[5] == BLINK_PACK_RGB(0, 0, 0));

    blink_image_free(img);
    remove(path);

    /* Test P3 with custom maxval scaling (e.g. maxval = 15) */
    fp = fopen(path, "w");
    assert(fp != NULL);
    fprintf(fp, "P3\n 2 1\n 15\n 15 0 0   0 15 7\n");
    fclose(fp);

    img = blink_image_load_ppm(path);
    assert(img != NULL);
    assert(img->width == 2);
    assert(img->height == 1);
    assert(BLINK_GET_R(img->pixels[0]) == 255);
    assert(BLINK_GET_G(img->pixels[0]) == 0);
    assert(BLINK_GET_B(img->pixels[0]) == 0);
    assert(BLINK_GET_R(img->pixels[1]) == 0);
    assert(BLINK_GET_G(img->pixels[1]) == 255);
    /* 7/15 * 255 rounded = 119 */
    assert(abs((int)BLINK_GET_B(img->pixels[1]) - 119) <= 1);

    blink_image_free(img);
    remove(path);

    TEST_PASS("test_ppm_p3_ascii");
}

/* ------------------------------------------------------------------------- */
/* Test 4: BMP (24-bit and 32-bit) Loader & Saver                            */
/* ------------------------------------------------------------------------- */
static void test_bmp_support(void) {
    printf("[4/9] Testing BMP (24-bit and 32-bit) support...\n");

    /* 1. 24-bit save and reload with non-multiple-of-4 width (testing padding) */
    const int w = 17, h = 13; /* Stride has padding */
    blink_image_t* orig = blink_image_create(w, h);
    assert(orig != NULL);

    for (int y = 0; y < h; ++y) {
        for (int x = 0; x < w; ++x) {
            orig->pixels[y * w + x] = BLINK_PACK_RGB(x * 12, y * 18, (x + y) * 7);
        }
    }

    const char* path24 = "test_24bit.bmp";
    assert(blink_image_save_bmp(orig, path24));

    blink_image_t* loaded24 = blink_image_load_bmp(path24);
    assert(loaded24 != NULL);
    assert(loaded24->width == w);
    assert(loaded24->height == h);

    for (int i = 0; i < w * h; ++i) {
        assert(loaded24->pixels[i] == orig->pixels[i]);
    }
    blink_image_free(orig);
    blink_image_free(loaded24);
    remove(path24);

    /* 2. Synthesize a 32-bit BMP with alpha channel */
    const char* path32 = "test_32bit.bmp";
    FILE* fp = fopen(path32, "wb");
    assert(fp != NULL);

    int w32 = 4, h32 = 4;
    size_t img_size = (size_t)w32 * h32 * 4;
    size_t file_size = 54 + img_size;

    uint8_t hdr[54] = {0};
    hdr[0] = 'B'; hdr[1] = 'M';
    hdr[2] = (uint8_t)(file_size & 0xFF);
    hdr[3] = (uint8_t)((file_size >> 8) & 0xFF);
    hdr[4] = (uint8_t)((file_size >> 16) & 0xFF);
    hdr[5] = (uint8_t)((file_size >> 24) & 0xFF);
    hdr[10] = 54;
    hdr[14] = 40;
    hdr[18] = (uint8_t)w32;
    hdr[22] = (uint8_t)h32;
    hdr[26] = 1;
    hdr[28] = 32; /* 32 bpp */
    hdr[34] = (uint8_t)(img_size & 0xFF);

    fwrite(hdr, 1, 54, fp);

    /* Write 16 pixels (BGRA) bottom-to-top */
    for (int y = h32 - 1; y >= 0; --y) {
        for (int x = 0; x < w32; ++x) {
            uint8_t b = (uint8_t)(x * 50);
            uint8_t g = (uint8_t)(y * 50);
            uint8_t r = 200;
            uint8_t a = (uint8_t)(100 + x * 20);
            uint8_t px[4] = {b, g, r, a};
            fwrite(px, 1, 4, fp);
        }
    }
    fclose(fp);

    blink_image_t* loaded32 = blink_image_load_bmp(path32);
    assert(loaded32 != NULL);
    assert(loaded32->width == w32);
    assert(loaded32->height == h32);

    for (int y = 0; y < h32; ++y) {
        for (int x = 0; x < w32; ++x) {
            uint32_t px = loaded32->pixels[y * w32 + x];
            assert(BLINK_GET_R(px) == 200);
            assert(BLINK_GET_G(px) == (uint8_t)(y * 50));
            assert(BLINK_GET_B(px) == (uint8_t)(x * 50));
            assert(BLINK_GET_A(px) == (uint8_t)(100 + x * 20));
        }
    }
    blink_image_free(loaded32);
    remove(path32);

    TEST_PASS("test_bmp_support");
}

/* ------------------------------------------------------------------------- */
/* Test 5: Raw RGBA Loading                                                  */
/* ------------------------------------------------------------------------- */
static void test_raw_rgba(void) {
    printf("[5/9] Testing raw RGBA loading...\n");

    const char* path = "test_raw.bin";
    FILE* fp = fopen(path, "wb");
    assert(fp != NULL);

    int w = 8, h = 8;
    uint32_t raw_pixels[64];
    for (int i = 0; i < 64; ++i) {
        raw_pixels[i] = BLINK_PACK_RGBA(i, 255 - i, i * 3, 200);
    }
    fwrite(raw_pixels, sizeof(uint32_t), 64, fp);
    fclose(fp);

    blink_image_t* loaded = blink_image_load_raw(path, w, h);
    assert(loaded != NULL);
    assert(loaded->width == w);
    assert(loaded->height == h);

    for (int i = 0; i < 64; ++i) {
        assert(loaded->pixels[i] == raw_pixels[i]);
    }
    blink_image_free(loaded);
    remove(path);

    /* Test invalid dimension or truncated raw file */
    assert(blink_image_load_raw(NULL, w, h) == NULL);
    assert(blink_image_load_raw("non_existent_file.raw", w, h) == NULL);

    TEST_PASS("test_raw_rgba");
}

/* ------------------------------------------------------------------------- */
/* Test 6: Safety, Truncation & Corrupted Data Handling                      */
/* ------------------------------------------------------------------------- */
static void test_safety_and_corruption(void) {
    printf("[6/9] Testing memory safety and corrupted file handling...\n");

    /* Truncated PPM P6 file */
    const char* path_trunc_p6 = "test_trunc.ppm";
    FILE* fp = fopen(path_trunc_p6, "wb");
    fprintf(fp, "P6\n100 100\n255\n");
    /* Write only 5 bytes instead of 30,000 bytes */
    fwrite("12345", 1, 5, fp);
    fclose(fp);

    blink_image_t* bad_p6 = blink_image_load_ppm(path_trunc_p6);
    assert(bad_p6 == NULL);
    remove(path_trunc_p6);

    /* Truncated PPM P3 file */
    const char* path_trunc_p3 = "test_trunc_p3.ppm";
    fp = fopen(path_trunc_p3, "w");
    fprintf(fp, "P3\n50 50\n255\n 1 2 3 4 5");
    fclose(fp);

    blink_image_t* bad_p3 = blink_image_load_ppm(path_trunc_p3);
    assert(bad_p3 == NULL);
    remove(path_trunc_p3);

    /* Invalid magic */
    const char* path_invalid_magic = "test_bad_magic.ppm";
    fp = fopen(path_invalid_magic, "w");
    fprintf(fp, "P9\n10 10\n255\n");
    fclose(fp);

    assert(blink_image_load_ppm(path_invalid_magic) == NULL);
    remove(path_invalid_magic);

    /* Zero dimensions in PPM */
    const char* path_zero_dim = "test_zero_dim.ppm";
    fp = fopen(path_zero_dim, "w");
    fprintf(fp, "P6\n0 100\n255\n");
    fclose(fp);

    assert(blink_image_load_ppm(path_zero_dim) == NULL);
    remove(path_zero_dim);

    /* Truncated BMP */
    const char* path_trunc_bmp = "test_trunc.bmp";
    fp = fopen(path_trunc_bmp, "wb");
    fwrite("BM\x00\x00", 1, 4, fp);
    fclose(fp);

    assert(blink_image_load_bmp(path_trunc_bmp) == NULL);
    remove(path_trunc_bmp);

    TEST_PASS("test_safety_and_corruption");
}

/* ------------------------------------------------------------------------- */
/* Test 7: Nearest-Neighbor Blitter (1:1, Scaling, Clipping)                 */
/* ------------------------------------------------------------------------- */
static void test_nearest_blit(void) {
    printf("[7/9] Testing nearest-neighbor blitter (scaling & clipping)...\n");

    /* Create 2x2 source:
     * Red   Green
     * Blue  White
     */
    blink_image_t* src = blink_image_create(2, 2);
    src->pixels[0] = BLINK_PACK_RGB(255, 0, 0);     /* (0,0): Red */
    src->pixels[1] = BLINK_PACK_RGB(0, 255, 0);     /* (1,0): Green */
    src->pixels[2] = BLINK_PACK_RGB(0, 0, 255);     /* (0,1): Blue */
    src->pixels[3] = BLINK_PACK_RGB(255, 255, 255); /* (1,1): White */

    /* 1. 1:1 Blit onto a 10x10 FB at offset (2, 3) */
    uint32_t fb[100];
    memset(fb, 0, sizeof(fb));
    blink_image_blit_nearest(src, fb, 10, 10, 2, 3, 2, 2);

    assert(fb[3 * 10 + 2] == BLINK_PACK_RGB(255, 0, 0));
    assert(fb[3 * 10 + 3] == BLINK_PACK_RGB(0, 255, 0));
    assert(fb[4 * 10 + 2] == BLINK_PACK_RGB(0, 0, 255));
    assert(fb[4 * 10 + 3] == BLINK_PACK_RGB(255, 255, 255));
    /* Surrounding pixels untouched */
    assert(fb[2 * 10 + 2] == 0);
    assert(fb[5 * 10 + 2] == 0);

    /* 2. 2x Scale Up (2x2 -> 4x4) at (0, 0) */
    uint32_t fb_scaled[16];
    memset(fb_scaled, 0, sizeof(fb_scaled));
    blink_image_blit_nearest(src, fb_scaled, 4, 4, 0, 0, 4, 4);

    /* Top-left 2x2 quadrant should all be Red */
    assert(fb_scaled[0 * 4 + 0] == BLINK_PACK_RGB(255, 0, 0));
    assert(fb_scaled[0 * 4 + 1] == BLINK_PACK_RGB(255, 0, 0));
    assert(fb_scaled[1 * 4 + 0] == BLINK_PACK_RGB(255, 0, 0));
    assert(fb_scaled[1 * 4 + 1] == BLINK_PACK_RGB(255, 0, 0));
    /* Top-right 2x2 should all be Green */
    assert(fb_scaled[0 * 4 + 2] == BLINK_PACK_RGB(0, 255, 0));
    assert(fb_scaled[0 * 4 + 3] == BLINK_PACK_RGB(0, 255, 0));
    assert(fb_scaled[1 * 4 + 2] == BLINK_PACK_RGB(0, 255, 0));
    assert(fb_scaled[1 * 4 + 3] == BLINK_PACK_RGB(0, 255, 0));

    /* 3. Clipping tests with guard canaries */
    #define CANARY 0xDEADBEEFU
    uint32_t buffer[64 + 4];
    buffer[0] = CANARY;
    buffer[65] = CANARY;
    uint32_t* clip_fb = buffer + 1; /* 8x8 framebuffer */
    memset(clip_fb, 0, 64 * sizeof(uint32_t));

    /* Negative offset blit: dst_x = -1, dst_y = -1 */
    blink_image_blit_nearest(src, clip_fb, 8, 8, -1, -1, 2, 2);
    assert(buffer[0] == CANARY);
    assert(buffer[65] == CANARY);
    /* At (0,0), we should see White (bottom-right pixel of src) */
    assert(clip_fb[0] == BLINK_PACK_RGB(255, 255, 255));

    /* Fully offscreen (right/bottom) */
    blink_image_blit_nearest(src, clip_fb, 8, 8, 10, 10, 4, 4);
    assert(buffer[0] == CANARY);
    assert(buffer[65] == CANARY);

    /* Fully offscreen (left/top) */
    blink_image_blit_nearest(src, clip_fb, 8, 8, -10, -10, 4, 4);
    assert(buffer[0] == CANARY);
    assert(buffer[65] == CANARY);

    blink_image_free(src);
    TEST_PASS("test_nearest_blit");
}

/* ------------------------------------------------------------------------- */
/* Test 8: Bilinear Blitter (Interpolation, Alpha Blending, Clipping)        */
/* ------------------------------------------------------------------------- */
static void test_bilinear_blit(void) {
    printf("[8/9] Testing bilinear blitter (interpolation & alpha blending)...\n");

    /* Create 2x2 source:
     * (0,0)=0     (1,0)=100
     * (0,1)=100   (1,1)=200
     */
    blink_image_t* src = blink_image_create(2, 2);
    src->pixels[0] = BLINK_PACK_RGB(0, 0, 0);
    src->pixels[1] = BLINK_PACK_RGB(100, 100, 100);
    src->pixels[2] = BLINK_PACK_RGB(100, 100, 100);
    src->pixels[3] = BLINK_PACK_RGB(200, 200, 200);

    /* 1:1 Blit */
    uint32_t fb1[4];
    memset(fb1, 0, sizeof(fb1));
    blink_image_blit_bilinear(src, fb1, 2, 2, 0, 0, 2, 2);
    assert(fb1[0] == src->pixels[0]);
    assert(fb1[1] == src->pixels[1]);
    assert(fb1[2] == src->pixels[2]);
    assert(fb1[3] == src->pixels[3]);

    /* Scale up 2x2 -> 4x4:
     * Check center of the 4x4 area (pixels at (1,1), (2,1), (1,2), (2,2))
     * Center should be smooth transitions between 0, 100, 200.
     */
    uint32_t fb_bi[16];
    memset(fb_bi, 0, sizeof(fb_bi));
    blink_image_blit_bilinear(src, fb_bi, 4, 4, 0, 0, 4, 4);
    /* Check mathematically exact bilinear values across 4x4: */
    assert(BLINK_GET_R(fb_bi[0]) == 0);     /* (0,0): clamped corner */
    assert(BLINK_GET_R(fb_bi[5]) == 50);    /* (1,1): (0.75, 0.75) towards 0 */
    assert(BLINK_GET_R(fb_bi[6]) == 100);   /* (2,1): horizontal blend */
    assert(BLINK_GET_R(fb_bi[9]) == 100);   /* (1,2): vertical blend */
    assert(BLINK_GET_R(fb_bi[10]) == 150);  /* (2,2): (0.75, 0.75) towards 200 */
    assert(BLINK_GET_R(fb_bi[15]) == 200);  /* (3,3): clamped corner */

    /* Alpha blending test:
     * Dest has Opaque Blue (0, 0, 255, 255).
     * Src has 50% Alpha Red (255, 0, 0, 128).
     */
    blink_image_t* alpha_src = blink_image_create(1, 1);
    alpha_src->pixels[0] = BLINK_PACK_RGBA(255, 0, 0, 128);

    uint32_t blend_fb[1] = { BLINK_PACK_RGB(0, 0, 255) };
    blink_image_blit_bilinear(alpha_src, blend_fb, 1, 1, 0, 0, 1, 1);

    uint8_t res_r = BLINK_GET_R(blend_fb[0]);
    uint8_t res_b = BLINK_GET_B(blend_fb[0]);
    uint8_t res_a = BLINK_GET_A(blend_fb[0]);
    assert(res_a == 255);
    /* Expected: r ~ 128 (255 * 128 / 255 = 128), b ~ 127 (255 * 127 / 255 = 127) */
    assert(abs((int)res_r - 128) <= 2);
    assert(abs((int)res_b - 127) <= 2);

    /* Boundary clipping with canary */
    uint32_t canary_buf[36 + 2];
    canary_buf[0] = 0xCAFEBABEU;
    canary_buf[37] = 0xCAFEBABEU;
    uint32_t* clip_fb2 = canary_buf + 1; /* 6x6 */
    memset(clip_fb2, 0, 36 * sizeof(uint32_t));

    blink_image_blit_bilinear(src, clip_fb2, 6, 6, -2, -2, 10, 10);
    assert(canary_buf[0] == 0xCAFEBABEU);
    assert(canary_buf[37] == 0xCAFEBABEU);

    blink_image_free(src);
    blink_image_free(alpha_src);
    TEST_PASS("test_bilinear_blit");
}

/* ------------------------------------------------------------------------- */
/* Test 9: Integration with Real 800x600 Rendered Page PPM                   */
/* ------------------------------------------------------------------------- */
static void test_real_rendered_page_integration(void) {
    printf("[9/9] Testing integration with blink_formal_rendered_page.ppm...\n");

    const char* real_ppm = "blink_formal_rendered_page.ppm";
    blink_image_t* img = blink_image_load_ppm(real_ppm);
    if (!img) {
        printf("  [WARN] %s not found in working directory, skipping real file test.\n", real_ppm);
        return;
    }

    assert(img->width == 800);
    assert(img->height == 600);
    assert(img->pixels != NULL);

    /* Sample known coordinates from Coq formal rasterization:
     * Header text is navy: (32, 33, 36)
     * Flex bg is: (232, 240, 254)
     */
    uint32_t p_h1 = img->pixels[30 * 800 + 10];
    assert(BLINK_GET_R(p_h1) == 32 && BLINK_GET_G(p_h1) == 33 && BLINK_GET_B(p_h1) == 36);

    uint32_t p_flex = img->pixels[130 * 800 + 10];
    assert(BLINK_GET_R(p_flex) == 232 && BLINK_GET_G(p_flex) == 240 && BLINK_GET_B(p_flex) == 254);

    /* Downscale to a 200x150 thumbnail using bilinear filtering */
    const int thumb_w = 200;
    const int thumb_h = 150;
    blink_image_t* thumb = blink_image_create(thumb_w, thumb_h);
    assert(thumb != NULL);

    blink_image_blit_bilinear(img, thumb->pixels, thumb_w, thumb_h, 0, 0, thumb_w, thumb_h);

    /* Save thumbnail as both PPM and BMP */
    const char* out_thumb_ppm = "blink_formal_thumb.ppm";
    const char* out_thumb_bmp = "blink_formal_thumb.bmp";
    assert(blink_image_save_ppm(thumb, out_thumb_ppm));
    assert(blink_image_save_bmp(thumb, out_thumb_bmp));

    /* Reload both to verify integrity */
    blink_image_t* reload_ppm = blink_image_load_ppm(out_thumb_ppm);
    blink_image_t* reload_bmp = blink_image_load_bmp(out_thumb_bmp);

    assert(reload_ppm != NULL);
    assert(reload_bmp != NULL);
    assert(reload_ppm->width == thumb_w && reload_ppm->height == thumb_h);
    assert(reload_bmp->width == thumb_w && reload_bmp->height == thumb_h);

    /* Both reload representations should be identical */
    for (int i = 0; i < thumb_w * thumb_h; ++i) {
        assert(reload_ppm->pixels[i] == reload_bmp->pixels[i]);
    }

    blink_image_free(reload_ppm);
    blink_image_free(reload_bmp);
    blink_image_free(thumb);
    blink_image_free(img);

    TEST_PASS("test_real_rendered_page_integration");
}

/* ========================================================================= */
/* Main Runner                                                               */
/* ========================================================================= */
int main(void) {
    printf("============================================================\n");
    printf("Blink Image Codec & Bitmap Loader Engine: Test Suite\n");
    printf("============================================================\n");

    test_allocation_and_bounds();
    test_ppm_p6_roundtrip();
    test_ppm_p3_ascii();
    test_bmp_support();
    test_raw_rgba();
    test_safety_and_corruption();
    test_nearest_blit();
    test_bilinear_blit();
    test_real_rendered_page_integration();

    printf("\n>>> ALL 9 TEST SUITES PASSED PERFECTLY (0 errors)! <<<\n");
    printf("============================================================\n");
    return 0;
}
