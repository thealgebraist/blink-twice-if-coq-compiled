/* ========================================================================= */
/* Blink Image Codec & Bitmap Loader Engine                                  */
/* Header: blink_image_codec.h                                              */
/* C99 Memory-Safe Netpbm (P3/P6), BMP, and Raw RGBA Decoder & Resamplers    */
/* ========================================================================= */

#ifndef BLINK_IMAGE_CODEC_H
#define BLINK_IMAGE_CODEC_H

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Maximum allowable image dimensions for security & memory-safety bounds */
#define BLINK_IMAGE_MAX_DIM 16384
#define BLINK_IMAGE_MAX_PIXELS (64 * 1024 * 1024) /* 64 Megapixels max */

/* Pixel pack / unpack macros (Little-Endian RGBA / 32-bit word matching FrameBuffer Color)
 * Byte 0: Red   (bits 0..7)
 * Byte 1: Green (bits 8..15)
 * Byte 2: Blue  (bits 16..23)
 * Byte 3: Alpha (bits 24..31)
 */
#define BLINK_PACK_RGBA(r, g, b, a) \
    (((uint32_t)(uint8_t)(r)) | \
    (((uint32_t)(uint8_t)(g)) << 8) | \
    (((uint32_t)(uint8_t)(b)) << 16) | \
    (((uint32_t)(uint8_t)(a)) << 24))

#define BLINK_PACK_RGB(r, g, b) BLINK_PACK_RGBA((r), (g), (b), 255)

#define BLINK_GET_R(c) ((uint8_t)((c) & 0xFF))
#define BLINK_GET_G(c) ((uint8_t)(((c) >> 8) & 0xFF))
#define BLINK_GET_B(c) ((uint8_t)(((c) >> 16) & 0xFF))
#define BLINK_GET_A(c) ((uint8_t)(((c) >> 24) & 0xFF))

/* Image structure holding 32-bit RGBA pixel buffer */
typedef struct {
    int width;
    int height;
    uint32_t* pixels;
} blink_image_t;

/* Memory management */
blink_image_t* blink_image_create(int width, int height);
void           blink_image_free(blink_image_t* img);

/* Decoders / Loaders */
/* Safe Netpbm TrueColor PPM loader: supports both P6 (binary) and P3 (ASCII) */
blink_image_t* blink_image_load_ppm(const char* filepath);

/* Memory-safe uncompressed BMP loader (24-bit BGR and 32-bit BGRA/BGRX) */
blink_image_t* blink_image_load_bmp(const char* filepath);

/* Raw RGBA loader from binary file */
blink_image_t* blink_image_load_raw(const char* filepath, int width, int height);

/* Universal Memory Loader: decodes JPEG, PNG, WebP, GIF, BMP, Netpbm from memory buffer */
blink_image_t* blink_image_load_memory(const uint8_t* data, size_t size);

/* Encoders / Exporters */
bool blink_image_save_ppm(const blink_image_t* img, const char* filepath);
bool blink_image_save_bmp(const blink_image_t* img, const char* filepath);

/* Samplers / Blitters
 * Renders src image into dst_fb with clipping against destination boundaries [0, fb_w) x [0, fb_h).
 * Supports scaling (dst_w != src->width, dst_h != src->height) and alpha compositing (Porter-Duff Over).
 */
void blink_image_blit_nearest(blink_image_t* src, uint32_t* dst_fb,
                              int fb_w, int fb_h,
                              int dst_x, int dst_y,
                              int dst_w, int dst_h);

void blink_image_blit_bilinear(blink_image_t* src, uint32_t* dst_fb,
                               int fb_w, int fb_h,
                               int dst_x, int dst_y,
                               int dst_w, int dst_h);

#ifdef __cplusplus
}
#endif

#endif /* BLINK_IMAGE_CODEC_H */
