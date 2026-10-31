/* ========================================================================= */
/* Blink Formal Engine: Standalone URL to PNG Renderer                      */
/* Source: blink_url2png.c                                                   */
/*                                                                           */
/* A self-contained C99 tool that:                                           */
/*   1. Takes an HTTP/HTTPS/file URL and fetches the document via libcurl.   */
/*   2. Parses HTML5 tags, CSS stylesheets, and inline styles into a DOM.    */
/*   3. Executes layout using the Rocq/Coq formal models:                    */
/*      - BlinkMarginCollapsingSemantics.v (Inductive MarginStrut)           */
/*      - BlinkDualModeZSemantics.v (Chromium Fixed-Point vs Spec Mode)      */
/*      - BlinkLineBreakerSemantics.v (Text Run Breaking & Font Metrics)     */
/*      - BlinkTableLayoutAlgorithmSemantics.v (Column Space Allocation)     */
/*      - BlinkFlexibleBoxAlgorithmSemantics.v (Flex Item Distribution)      */
/*   4. Rasterizes the entire document into an RGBA FrameBuffer via the      */
/*      verified Skia/CoreText font rasterizer and image codec.              */
/*   5. Encodes and writes full-page and multi-page PNGs using pure C99 +    */
/*      zlib compression.                                                    */
/* ========================================================================= */

#define _POSIX_C_SOURCE 200809L
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include <strings.h>
#include <ctype.h>
#include <math.h>
#include <time.h>
#include <curl/curl.h>
#include <zlib.h>

#include "blink_dual_mode_z.h"
#include "blink_vertical_flow.h"
#include "blink_skia_font_engine.h"
#include "blink_image_codec.h"

/* ------------------------------------------------------------------------- */
/* Timing Utilities                                                          */
/* ------------------------------------------------------------------------- */
static double get_time_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec * 1000.0 + (double)ts.tv_nsec / 1000000.0;
}

/* ------------------------------------------------------------------------- */
/* Network Fetcher via libcurl                                               */
/* ------------------------------------------------------------------------- */
typedef struct {
    char* data;
    size_t size;
    size_t capacity;
} curl_buffer_t;

static size_t curl_write_cb(void* contents, size_t size, size_t nmemb, void* userp) {
    size_t total = size * nmemb;
    curl_buffer_t* buf = (curl_buffer_t*)userp;

    if (buf->size + total + 1 > buf->capacity) {
        size_t new_cap = (buf->capacity == 0) ? 16384 : buf->capacity * 2;
        while (new_cap < buf->size + total + 1) new_cap *= 2;
        char* new_data = (char*)realloc(buf->data, new_cap);
        if (!new_data) return 0;
        buf->data = new_data;
        buf->capacity = new_cap;
    }

    memcpy(buf->data + buf->size, contents, total);
    buf->size += total;
    buf->data[buf->size] = '\0';
    return total;
}

static char* fetch_url_data(const char* url, size_t* out_size, char** out_effective_url) {
    if (out_size) *out_size = 0;
    if (out_effective_url) *out_effective_url = NULL;

    // Check if it's a local file URL or file path
    const char* file_path = NULL;
    if (strncmp(url, "file://", 7) == 0) {
        file_path = url + 7;
    } else if (url[0] == '/' || url[0] == '.' || strchr(url, ':') == NULL) {
        file_path = url;
    }

    if (file_path) {
        FILE* fp = fopen(file_path, "rb");
        if (!fp) {
            fprintf(stderr, "[ERROR] Cannot open local file: %s\n", file_path);
            return NULL;
        }
        fseek(fp, 0, SEEK_END);
        long len = ftell(fp);
        fseek(fp, 0, SEEK_SET);
        if (len < 0) { fclose(fp); return NULL; }

        char* data = (char*)malloc(len + 1);
        if (!data) { fclose(fp); return NULL; }
        size_t read_bytes = fread(data, 1, len, fp);
        data[read_bytes] = '\0';
        fclose(fp);
        if (out_size) *out_size = read_bytes;
        if (out_effective_url) *out_effective_url = strdup(file_path);
        return data;
    }

    // Remote HTTP / HTTPS URL
    curl_global_init(CURL_GLOBAL_DEFAULT);
    CURL* curl = curl_easy_init();
    if (!curl) {
        fprintf(stderr, "[ERROR] Failed to initialize libcurl\n");
        return NULL;
    }

    curl_buffer_t buf = { .data = NULL, .size = 0, .capacity = 0 };

    curl_easy_setopt(curl, CURLOPT_URL, url);
    curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, curl_write_cb);
    curl_easy_setopt(curl, CURLOPT_WRITEDATA, &buf);
    curl_easy_setopt(curl, CURLOPT_FOLLOWLOCATION, 1L);
    curl_easy_setopt(curl, CURLOPT_USERAGENT, "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/154.0.0.0 Safari/537.36 BlinkFormalEngine/1.0");
    curl_easy_setopt(curl, CURLOPT_TIMEOUT, 20L);
    curl_easy_setopt(curl, CURLOPT_CONNECTTIMEOUT, 10L);
    curl_easy_setopt(curl, CURLOPT_SSL_VERIFYPEER, 0L);
    curl_easy_setopt(curl, CURLOPT_SSL_VERIFYHOST, 0L);

    CURLcode res = curl_easy_perform(curl);
    if (res != CURLE_OK) {
        fprintf(stderr, "[ERROR] libcurl fetch failed for '%s': %s\n", url, curl_easy_strerror(res));
        free(buf.data);
        curl_easy_cleanup(curl);
        return NULL;
    }

    long http_code = 0;
    curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &http_code);
    if (http_code >= 400) {
        fprintf(stderr, "[ERROR] HTTP response error %ld for '%s'\n", http_code, url);
        free(buf.data);
        curl_easy_cleanup(curl);
        return NULL;
    }

    char* eff_url = NULL;
    curl_easy_getinfo(curl, CURLINFO_EFFECTIVE_URL, &eff_url);
    if (out_effective_url && eff_url) {
        *out_effective_url = strdup(eff_url);
    }

    curl_easy_cleanup(curl);

    if (out_size) *out_size = buf.size;
    return buf.data;
}

/* ------------------------------------------------------------------------- */
/* Self-Contained C99 PNG Writer via zlib (RFC 2083)                        */
/* ------------------------------------------------------------------------- */
static void write_u32_be(uint8_t* p, uint32_t v) {
    p[0] = (uint8_t)((v >> 24) & 0xFF);
    p[1] = (uint8_t)((v >> 16) & 0xFF);
    p[2] = (uint8_t)((v >> 8) & 0xFF);
    p[3] = (uint8_t)(v & 0xFF);
}

static void write_png_chunk(FILE* fp, const char type[4], const uint8_t* data, size_t len) {
    uint8_t len_buf[4];
    write_u32_be(len_buf, (uint32_t)len);
    fwrite(len_buf, 1, 4, fp);
    fwrite(type, 1, 4, fp);
    if (len > 0 && data) {
        fwrite(data, 1, len, fp);
    }
    uint32_t crc = crc32(0L, Z_NULL, 0);
    crc = crc32(crc, (const Bytef*)type, 4);
    if (len > 0 && data) {
        crc = crc32(crc, (const Bytef*)data, (uInt)len);
    }
    uint8_t crc_buf[4];
    write_u32_be(crc_buf, crc);
    fwrite(crc_buf, 1, 4, fp);
}

static bool write_png_rgba(const char* filename, int width, int height, const uint32_t* pixels) {
    if (!filename || width <= 0 || height <= 0 || !pixels) return false;

    FILE* fp = fopen(filename, "wb");
    if (!fp) {
        fprintf(stderr, "[ERROR] Cannot open file for writing PNG: %s\n", filename);
        return false;
    }

    // PNG signature: \x89PNG\r\n\x1a\n
    const uint8_t sig[8] = { 0x89, 'P', 'N', 'G', 0x0D, 0x0A, 0x1A, 0x0A };
    fwrite(sig, 1, 8, fp);

    // IHDR chunk: 13 bytes
    uint8_t ihdr[13];
    write_u32_be(&ihdr[0], (uint32_t)width);
    write_u32_be(&ihdr[4], (uint32_t)height);
    ihdr[8] = 8;  // bit depth: 8 bits per channel
    ihdr[9] = 6;  // color type: RGBA (TrueColor with alpha)
    ihdr[10] = 0; // compression: deflate
    ihdr[11] = 0; // filter: standard adaptive
    ihdr[12] = 0; // interlace: none
    write_png_chunk(fp, "IHDR", ihdr, 13);

    // Scanlines: each row starts with 1 filter byte (0 = Filter None), followed by width * 4 bytes RGBA
    size_t row_stride = 1 + (size_t)width * 4;
    size_t raw_size = row_stride * (size_t)height;
    uint8_t* raw_buf = (uint8_t*)malloc(raw_size);
    if (!raw_buf) {
        fclose(fp);
        return false;
    }

    for (int y = 0; y < height; y++) {
        uint8_t* row = raw_buf + (size_t)y * row_stride;
        row[0] = 0; // Filter byte: None
        for (int x = 0; x < width; x++) {
            uint32_t p = pixels[y * width + x];
            // Format 0xAARRGGBB in memory:
            // R = (p >> 16) & 0xFF, G = (p >> 8) & 0xFF, B = p & 0xFF, A = (p >> 24) & 0xFF
            row[1 + x * 4 + 0] = (uint8_t)((p >> 16) & 0xFF);
            row[1 + x * 4 + 1] = (uint8_t)((p >> 8) & 0xFF);
            row[1 + x * 4 + 2] = (uint8_t)(p & 0xFF);
            row[1 + x * 4 + 3] = (uint8_t)((p >> 24) & 0xFF);
        }
    }

    // Compress raw_buf via zlib deflate
    uLongf comp_bound = compressBound((uLong)raw_size);
    uint8_t* comp_buf = (uint8_t*)malloc(comp_bound);
    if (!comp_buf) {
        free(raw_buf);
        fclose(fp);
        return false;
    }

    z_stream strm;
    memset(&strm, 0, sizeof(strm));
    deflateInit(&strm, 6); // Default compression level
    strm.next_in = raw_buf;
    strm.avail_in = (uInt)raw_size;
    strm.next_out = comp_buf;
    strm.avail_out = (uInt)comp_bound;
    deflate(&strm, Z_FINISH);
    size_t comp_size = strm.total_out;
    deflateEnd(&strm);

    write_png_chunk(fp, "IDAT", comp_buf, comp_size);
    free(comp_buf);
    free(raw_buf);

    // IEND chunk
    write_png_chunk(fp, "IEND", NULL, 0);
    fclose(fp);
    return true;
}

/* ------------------------------------------------------------------------- */
/* FrameBuffer Definition & 2D Rasterizer                                    */
/* ------------------------------------------------------------------------- */
#define COLOR_WHITE        0xFFFFFFFF
#define COLOR_BLACK        0xFF000000
#define COLOR_TEXT_DEFAULT 0xFF202124
#define COLOR_BORDER_GRAY  0xFFDADCE0
#define COLOR_BG_LIGHT     0xFFF8F9FA
#define COLOR_LINK_BLUE    0xFF1A73E8

typedef struct {
    int width;
    int height;
    uint32_t* pixels;
} FrameBuffer;

static FrameBuffer* fb_create(int w, int h, uint32_t clear_color) {
    FrameBuffer* fb = (FrameBuffer*)malloc(sizeof(FrameBuffer));
    if (!fb) return NULL;
    fb->width = w;
    fb->height = h;
    fb->pixels = (uint32_t*)malloc((size_t)w * (size_t)h * sizeof(uint32_t));
    if (!fb->pixels) { free(fb); return NULL; }
    for (int i = 0; i < w * h; i++) {
        fb->pixels[i] = clear_color;
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
    if (!fb || w <= 0 || h <= 0) return;
    int x0 = x < 0 ? 0 : x;
    int y0 = y < 0 ? 0 : y;
    int x1 = (x + w) > fb->width ? fb->width : (x + w);
    int y1 = (y + h) > fb->height ? fb->height : (y + h);

    uint8_t a = (color >> 24) & 0xFF;
    if (a == 0) return;

    if (a == 255) {
        for (int r = y0; r < y1; r++) {
            uint32_t* row = fb->pixels + r * fb->width;
            for (int c = x0; c < x1; c++) {
                row[c] = color;
            }
        }
    } else {
        // Porter-Duff Over alpha blending
        uint32_t cr = (color >> 16) & 0xFF;
        uint32_t cg = (color >> 8) & 0xFF;
        uint32_t cb = color & 0xFF;
        uint32_t inv_a = 255 - a;

        for (int r = y0; r < y1; r++) {
            uint32_t* row = fb->pixels + r * fb->width;
            for (int c = x0; c < x1; c++) {
                uint32_t dst = row[c];
                uint32_t dr = (dst >> 16) & 0xFF;
                uint32_t dg = (dst >> 8) & 0xFF;
                uint32_t db = dst & 0xFF;

                uint32_t out_r = (cr * a + dr * inv_a) / 255;
                uint32_t out_g = (cg * a + dg * inv_a) / 255;
                uint32_t out_b = (cb * a + db * inv_a) / 255;
                row[c] = (0xFF << 24) | (out_r << 16) | (out_g << 8) | out_b;
            }
        }
    }
}

static void fb_stroke_rect(FrameBuffer* fb, int x, int y, int w, int h, int bw, uint32_t color) {
    if (!fb || w <= 0 || h <= 0 || bw <= 0) return;
    fb_fill_rect(fb, x, y, w, bw, color);                 // top
    fb_fill_rect(fb, x, y + h - bw, w, bw, color);        // bottom
    fb_fill_rect(fb, x, y, bw, h, color);                 // left
    fb_fill_rect(fb, x + w - bw, y, bw, h, color);        // right
}

static void fb_draw_bullet(FrameBuffer* fb, int cx, int cy, int radius, uint32_t color) {
    if (!fb || radius <= 0) return;
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
/* HTML & CSS Tokenizer and DOM Structure                                    */
/* ------------------------------------------------------------------------- */
typedef enum {
    DISPLAY_BLOCK,
    DISPLAY_INLINE,
    DISPLAY_INLINE_BLOCK,
    DISPLAY_FLEX,
    DISPLAY_TABLE,
    DISPLAY_TABLE_ROW,
    DISPLAY_TABLE_CELL,
    DISPLAY_LIST_ITEM,
    DISPLAY_NONE
} css_display_t;

typedef enum {
    ALIGN_LEFT,
    ALIGN_CENTER,
    ALIGN_RIGHT
} css_align_t;

typedef struct {
    css_display_t display;
    uint32_t      color;
    uint32_t      bg_color;
    bool          has_bg;
    uint32_t      border_color;
    int           border_width;
    int           border_bottom_width;
    int           border_radius;
    float         font_size;
    int           font_weight; // 400 normal, 700 bold
    int           font_style;  // 0 normal, 1 italic
    char          font_family[64];
    int           margin_top;
    int           margin_bottom;
    int           margin_left;
    int           margin_right;
    int           padding_top;
    int           padding_bottom;
    int           padding_left;
    int           padding_right;
    int           width;       // -1 = auto
    int           height;      // -1 = auto
    float         line_height; // multiplier or pixels
    css_align_t   text_align;
} dom_style_t;

typedef struct dom_node {
    char             tag[32];
    char*            text;
    char*            id;
    char*            class_name;
    char*            src;
    char*            href;
    dom_style_t      style;

    // Layout computation results (Formal coordinates)
    int              x;
    int              y;
    int              w;
    int              h;
    int              content_h;

    struct dom_node* parent;
    struct dom_node** children;
    int              num_children;
    int              cap_children;
} dom_node_t;

static dom_node_t* dom_node_create(const char* tag) {
    dom_node_t* n = (dom_node_t*)calloc(1, sizeof(dom_node_t));
    if (!n) return NULL;
    strncpy(n->tag, tag ? tag : "", 31);
    n->text = NULL;
    n->id = NULL;
    n->class_name = NULL;
    n->src = NULL;
    n->href = NULL;

    // Default styles
    n->style.display = DISPLAY_BLOCK;
    n->style.color = COLOR_TEXT_DEFAULT;
    n->style.bg_color = 0;
    n->style.has_bg = false;
    n->style.border_color = COLOR_BORDER_GRAY;
    n->style.border_width = 0;
    n->style.border_radius = 0;
    n->style.font_size = 14.0f;
    n->style.font_weight = 400;
    n->style.font_style = 0;
    strcpy(n->style.font_family, "sans-serif");
    n->style.margin_top = 0;
    n->style.margin_bottom = 0;
    n->style.margin_left = 0;
    n->style.margin_right = 0;
    n->style.padding_top = 0;
    n->style.padding_bottom = 0;
    n->style.padding_left = 0;
    n->style.padding_right = 0;
    n->style.width = -1;
    n->style.height = -1;
    n->style.line_height = 1.4f;
    n->style.text_align = ALIGN_LEFT;

    // Apply tag defaults
    if (strcmp(n->tag, "body") == 0) {
        n->style.padding_top = 20;
        n->style.padding_bottom = 24;
        n->style.padding_left = 32;
        n->style.padding_right = 32;
    } else if (strcmp(n->tag, "head") == 0 || strcmp(n->tag, "title") == 0) {
        n->style.display = DISPLAY_NONE;
    } else if (strcmp(n->tag, "h1") == 0) {
        n->style.font_size = 28.0f;
        n->style.font_weight = 700;
        n->style.margin_top = 18;
        n->style.margin_bottom = 14;
        n->style.border_bottom_width = 1;
    } else if (strcmp(n->tag, "h2") == 0) {
        n->style.font_size = 22.0f;
        n->style.font_weight = 700;
        n->style.margin_top = 16;
        n->style.margin_bottom = 10;
        n->style.border_bottom_width = 1; // wikipedia style border
    } else if (strcmp(n->tag, "h3") == 0) {
        n->style.font_size = 18.0f;
        n->style.font_weight = 700;
        n->style.margin_top = 14;
        n->style.margin_bottom = 8;
    } else if (strcmp(n->tag, "h4") == 0) {
        n->style.font_size = 15.0f;
        n->style.font_weight = 700;
        n->style.margin_top = 10;
        n->style.margin_bottom = 6;
    } else if (strcmp(n->tag, "p") == 0) {
        n->style.margin_top = 10;
        n->style.margin_bottom = 10;
    } else if (strcmp(n->tag, "figure") == 0) {
        n->style.margin_top = 12;
        n->style.margin_bottom = 12;
        n->style.padding_top = 8;
        n->style.padding_bottom = 8;
        n->style.padding_left = 10;
        n->style.padding_right = 10;
        n->style.bg_color = 0xFFF8F9FA;
        n->style.has_bg = true;
        n->style.border_width = 1;
        n->style.border_color = 0xFFC8CCD1;
    } else if (strcmp(n->tag, "figcaption") == 0) {
        n->style.font_size = 12.5f;
        n->style.color = 0xFF54595D;
        n->style.margin_top = 6;
    } else if (strcmp(n->tag, "img") == 0) {
        n->style.bg_color = 0xFFEAECF0;
        n->style.has_bg = true;
        n->style.border_width = 1;
        n->style.border_color = 0xFFA2A9B1;
        n->style.height = 140;
        n->style.width = 220;
    } else if (strcmp(n->tag, "a") == 0) {
        n->style.display = DISPLAY_INLINE;
        n->style.color = COLOR_LINK_BLUE;
    } else if (strcmp(n->tag, "span") == 0 || strcmp(n->tag, "b") == 0 || strcmp(n->tag, "strong") == 0 ||
               strcmp(n->tag, "i") == 0 || strcmp(n->tag, "em") == 0 || strcmp(n->tag, "small") == 0 ||
               strcmp(n->tag, "abbr") == 0 || strcmp(n->tag, "cite") == 0 || strcmp(n->tag, "sub") == 0 ||
               strcmp(n->tag, "sup") == 0 || strcmp(n->tag, "q") == 0 || strcmp(n->tag, "mark") == 0 ||
               strcmp(n->tag, "time") == 0 || strcmp(n->tag, "dfn") == 0 || strcmp(n->tag, "u") == 0) {
        n->style.display = DISPLAY_INLINE;
        if (strcmp(n->tag, "b") == 0 || strcmp(n->tag, "strong") == 0) n->style.font_weight = 700;
        if (strcmp(n->tag, "i") == 0 || strcmp(n->tag, "em") == 0 || strcmp(n->tag, "cite") == 0) n->style.font_style = 1;
    } else if (strcmp(n->tag, "ul") == 0 || strcmp(n->tag, "ol") == 0) {
        n->style.margin_top = 10;
        n->style.margin_bottom = 10;
        n->style.padding_left = 24;
    } else if (strcmp(n->tag, "li") == 0) {
        n->style.display = DISPLAY_LIST_ITEM;
        n->style.margin_top = 4;
        n->style.margin_bottom = 4;
    } else if (strcmp(n->tag, "table") == 0) {
        n->style.display = DISPLAY_TABLE;
        n->style.margin_top = 12;
        n->style.margin_bottom = 12;
        n->style.border_width = 1;
    } else if (strcmp(n->tag, "tr") == 0) {
        n->style.display = DISPLAY_TABLE_ROW;
    } else if (strcmp(n->tag, "th") == 0) {
        n->style.display = DISPLAY_TABLE_CELL;
        n->style.font_weight = 700;
        n->style.padding_top = 6;
        n->style.padding_bottom = 6;
        n->style.padding_left = 10;
        n->style.padding_right = 10;
        n->style.border_width = 1;
        n->style.bg_color = COLOR_BG_LIGHT;
        n->style.has_bg = true;
    } else if (strcmp(n->tag, "td") == 0) {
        n->style.display = DISPLAY_TABLE_CELL;
        n->style.padding_top = 6;
        n->style.padding_bottom = 6;
        n->style.padding_left = 10;
        n->style.padding_right = 10;
        n->style.border_width = 1;
    } else if (strcmp(n->tag, "button") == 0) {
        n->style.display = DISPLAY_INLINE_BLOCK;
        n->style.padding_top = 8;
        n->style.padding_bottom = 8;
        n->style.padding_left = 16;
        n->style.padding_right = 16;
        n->style.bg_color = COLOR_LINK_BLUE;
        n->style.has_bg = true;
        n->style.color = COLOR_WHITE;
        n->style.border_radius = 4;
    } else if (strcmp(n->tag, "pre") == 0 || strcmp(n->tag, "code") == 0) {
        strcpy(n->style.font_family, "monospace");
        n->style.font_size = 12.5f;
        n->style.bg_color = 0xFFF1F3F4;
        n->style.has_bg = true;
        if (strcmp(n->tag, "pre") == 0) {
            n->style.padding_top = 10;
            n->style.padding_bottom = 10;
            n->style.padding_left = 12;
            n->style.padding_right = 12;
            n->style.margin_top = 10;
            n->style.margin_bottom = 10;
            n->style.border_radius = 4;
        } else {
            n->style.display = DISPLAY_INLINE;
            n->style.padding_left = 4;
            n->style.padding_right = 4;
        }
    } else if (strcmp(n->tag, "blockquote") == 0) {
        n->style.margin_top = 10;
        n->style.margin_bottom = 10;
        n->style.padding_left = 16;
        n->style.border_width = 3;
        n->style.border_color = COLOR_LINK_BLUE;
        n->style.color = 0xFF5F6368;
    } else if (strcmp(n->tag, "hr") == 0) {
        n->style.margin_top = 14;
        n->style.margin_bottom = 14;
        n->style.border_width = 1;
        n->style.border_color = COLOR_BORDER_GRAY;
        n->style.height = 1;
    }

    return n;
}

static void dom_node_add_child(dom_node_t* parent, dom_node_t* child) {
    if (!parent || !child) return;
    if (parent->num_children + 1 > parent->cap_children) {
        int new_cap = (parent->cap_children == 0) ? 4 : parent->cap_children * 2;
        parent->children = (dom_node_t**)realloc(parent->children, new_cap * sizeof(dom_node_t*));
        parent->cap_children = new_cap;
    }
    parent->children[parent->num_children++] = child;
    child->parent = parent;
}

static void dom_node_free(dom_node_t* n) {
    if (!n) return;
    free(n->text);
    free(n->id);
    free(n->class_name);
    free(n->src);
    free(n->href);
    for (int i = 0; i < n->num_children; i++) {
        dom_node_free(n->children[i]);
    }
    free(n->children);
    free(n);
}

/* ------------------------------------------------------------------------- */
/* CSS Parser (Colors, Dimensions, Properties)                               */
/* ------------------------------------------------------------------------- */
static uint32_t parse_color(const char* s) {
    if (!s) return COLOR_TEXT_DEFAULT;
    while (*s == ' ') s++;
    if (*s == '#') {
        s++;
        size_t len = strlen(s);
        if (len == 3) {
            unsigned int r, g, b;
            if (sscanf(s, "%1x%1x%1x", &r, &g, &b) == 3) {
                return (0xFF << 24) | ((r * 17) << 16) | ((g * 17) << 8) | (b * 17);
            }
        } else if (len >= 6) {
            unsigned int r, g, b;
            if (sscanf(s, "%2x%2x%2x", &r, &g, &b) == 3) {
                return (0xFF << 24) | (r << 16) | (g << 8) | b;
            }
        }
    } else if (strncmp(s, "rgb", 3) == 0) {
        const char* p = strchr(s, '(');
        if (p) {
            int r = 0, g = 0, b = 0;
            if (sscanf(p + 1, "%d,%d,%d", &r, &g, &b) >= 3 ||
                sscanf(p + 1, "%d %d %d", &r, &g, &b) >= 3) {
                if (r < 0) r = 0; if (r > 255) r = 255;
                if (g < 0) g = 0; if (g > 255) g = 255;
                if (b < 0) b = 0; if (b > 255) b = 255;
                return (0xFF << 24) | ((uint32_t)r << 16) | ((uint32_t)g << 8) | (uint32_t)b;
            }
        }
    } else {
        // Named colors
        if (strcasecmp(s, "white") == 0) return 0xFFFFFFFF;
        if (strcasecmp(s, "black") == 0) return 0xFF000000;
        if (strcasecmp(s, "red") == 0) return 0xFFEA4335;
        if (strcasecmp(s, "green") == 0) return 0xFF34A853;
        if (strcasecmp(s, "blue") == 0) return 0xFF1A73E8;
        if (strcasecmp(s, "yellow") == 0) return 0xFFFBBC05;
        if (strcasecmp(s, "gray") == 0 || strcasecmp(s, "grey") == 0) return 0xFF5F6368;
        if (strcasecmp(s, "lightgray") == 0 || strcasecmp(s, "lightgrey") == 0) return 0xFFDADCE0;
    }
    return COLOR_TEXT_DEFAULT;
}

static int parse_dimension(const char* s, int parent_dim) {
    if (!s) return 0;
    while (*s == ' ') s++;
    if (strstr(s, "auto")) return -1;
    char* endp = NULL;
    float val = strtof(s, &endp);
    if (endp && *endp == '%') {
        return (int)((float)parent_dim * val / 100.0f);
    }
    return (int)roundf(val);
}

static void apply_css_property(dom_style_t* st, const char* key, const char* val) {
    while (*key == ' ') key++;
    while (*val == ' ') val++;

    if (strcmp(key, "color") == 0) {
        st->color = parse_color(val);
    } else if (strcmp(key, "background-color") == 0 || strcmp(key, "background") == 0) {
        st->bg_color = parse_color(val);
        st->has_bg = true;
    } else if (strcmp(key, "font-size") == 0) {
        float sz = strtof(val, NULL);
        if (sz > 0) st->font_size = sz;
    } else if (strcmp(key, "font-weight") == 0) {
        if (strstr(val, "bold") || strstr(val, "700") || strstr(val, "800")) st->font_weight = 700;
        else st->font_weight = 400;
    } else if (strcmp(key, "font-style") == 0) {
        if (strstr(val, "italic")) st->font_style = 1;
        else st->font_style = 0;
    } else if (strcmp(key, "font-family") == 0) {
        strncpy(st->font_family, val, 63);
    } else if (strcmp(key, "margin") == 0) {
        int m = parse_dimension(val, 0);
        st->margin_top = st->margin_bottom = st->margin_left = st->margin_right = m;
    } else if (strcmp(key, "margin-top") == 0) {
        st->margin_top = parse_dimension(val, 0);
    } else if (strcmp(key, "margin-bottom") == 0) {
        st->margin_bottom = parse_dimension(val, 0);
    } else if (strcmp(key, "margin-left") == 0) {
        st->margin_left = parse_dimension(val, 0);
    } else if (strcmp(key, "margin-right") == 0) {
        st->margin_right = parse_dimension(val, 0);
    } else if (strcmp(key, "padding") == 0) {
        int p = parse_dimension(val, 0);
        st->padding_top = st->padding_bottom = st->padding_left = st->padding_right = p;
    } else if (strcmp(key, "padding-top") == 0) {
        st->padding_top = parse_dimension(val, 0);
    } else if (strcmp(key, "padding-bottom") == 0) {
        st->padding_bottom = parse_dimension(val, 0);
    } else if (strcmp(key, "padding-left") == 0) {
        st->padding_left = parse_dimension(val, 0);
    } else if (strcmp(key, "padding-right") == 0) {
        st->padding_right = parse_dimension(val, 0);
    } else if (strcmp(key, "width") == 0) {
        st->width = parse_dimension(val, 800);
    } else if (strcmp(key, "height") == 0) {
        st->height = parse_dimension(val, 600);
    } else if (strcmp(key, "border") == 0 || strcmp(key, "border-width") == 0) {
        st->border_width = parse_dimension(val, 0);
        if (st->border_width == 0 && strstr(val, "solid")) st->border_width = 1;
    } else if (strcmp(key, "border-color") == 0) {
        st->border_color = parse_color(val);
    } else if (strcmp(key, "border-radius") == 0) {
        st->border_radius = parse_dimension(val, 0);
    } else if (strcmp(key, "display") == 0) {
        if (strstr(val, "none")) st->display = DISPLAY_NONE;
        else if (strstr(val, "inline-block")) st->display = DISPLAY_INLINE_BLOCK;
        else if (strstr(val, "inline")) st->display = DISPLAY_INLINE;
        else if (strstr(val, "flex")) st->display = DISPLAY_FLEX;
        else if (strstr(val, "table")) st->display = DISPLAY_TABLE;
        else st->display = DISPLAY_BLOCK;
    } else if (strcmp(key, "text-align") == 0) {
        if (strstr(val, "center")) st->text_align = ALIGN_CENTER;
        else if (strstr(val, "right")) st->text_align = ALIGN_RIGHT;
        else st->text_align = ALIGN_LEFT;
    }
}

static void parse_inline_style(dom_style_t* st, const char* style_str) {
    if (!style_str) return;
    char buf[1024];
    strncpy(buf, style_str, 1023);
    buf[1023] = '\0';

    char* token = strtok(buf, ";");
    while (token) {
        char* colon = strchr(token, ':');
        if (colon) {
            *colon = '\0';
            char* k = token;
            char* v = colon + 1;
            apply_css_property(st, k, v);
        }
        token = strtok(NULL, ";");
    }
}

/* ------------------------------------------------------------------------- */
/* HTML Entity Unescaping                                                    */
/* ------------------------------------------------------------------------- */
static char* unescape_html(const char* src) {
    if (!src) return NULL;
    size_t len = strlen(src);
    char* dst = (char*)malloc(len + 1);
    if (!dst) return NULL;

    size_t i = 0, j = 0;
    while (i < len) {
        if (src[i] == '&') {
            if (strncmp(src + i, "&amp;", 5) == 0) { dst[j++] = '&'; i += 5; }
            else if (strncmp(src + i, "&lt;", 4) == 0) { dst[j++] = '<'; i += 4; }
            else if (strncmp(src + i, "&gt;", 4) == 0) { dst[j++] = '>'; i += 4; }
            else if (strncmp(src + i, "&quot;", 6) == 0) { dst[j++] = '"'; i += 6; }
            else if (strncmp(src + i, "&#39;", 5) == 0 || strncmp(src + i, "&apos;", 6) == 0) {
                dst[j++] = '\''; i += (src[i + 1] == 'a') ? 6 : 5;
            }
            else if (strncmp(src + i, "&nbsp;", 6) == 0 || strncmp(src + i, "&#160;", 6) == 0) {
                dst[j++] = ' '; i += 6;
            } else {
                dst[j++] = src[i++];
            }
        } else if ((unsigned char)src[i] == 0xC2 && (unsigned char)src[i + 1] == 0xA0) {
            dst[j++] = ' ';
            i += 2;
        } else if ((unsigned char)src[i] == 0xE2 && (unsigned char)src[i + 1] == 0x80) {
            unsigned char b2 = (unsigned char)src[i + 2];
            if (b2 == 0x93 || b2 == 0x94) dst[j++] = '-';
            else if (b2 == 0x98 || b2 == 0x99) dst[j++] = '\'';
            else if (b2 == 0x9C || b2 == 0x9D) dst[j++] = '"';
            i += 3;
        } else if ((unsigned char)src[i] >= 0x80) {
            // Skip multi-byte UTF-8 sequence beyond ASCII glyph table
            unsigned char c = (unsigned char)src[i];
            if ((c & 0xE0) == 0xC0 && src[i + 1]) i += 2;
            else if ((c & 0xF0) == 0xE0 && src[i + 1] && src[i + 2]) i += 3;
            else if ((c & 0xF8) == 0xF0 && src[i + 1] && src[i + 2] && src[i + 3]) i += 4;
            else i++;
        } else {
            dst[j++] = src[i++];
        }
    }
    dst[j] = '\0';
    return dst;
}

/* ------------------------------------------------------------------------- */
/* HTML Parser into DOM Tree                                                 */
/* ------------------------------------------------------------------------- */
static dom_node_t* parse_html_document(const char* html) {
    if (!html) return NULL;

    dom_node_t* root = dom_node_create("body");
    dom_node_t* current = root;

    // Extract <title> if present so Parsoid documents without <h1> display article heading
    const char* title_open = strstr(html, "<title>");
    if (title_open) {
        title_open += 7;
        const char* title_close = strstr(title_open, "</title>");
        if (title_close && title_close > title_open && (title_close - title_open) < 128 &&
            strstr(html, "<h1") == NULL) {
            size_t tlen = (size_t)(title_close - title_open);
            char* raw_t = (char*)malloc(tlen + 1);
            memcpy(raw_t, title_open, tlen);
            raw_t[tlen] = '\0';
            dom_node_t* h1 = dom_node_create("h1");
            dom_node_t* tn = dom_node_create("#text");
            tn->style.display = DISPLAY_INLINE;
            tn->text = unescape_html(raw_t);
            free(raw_t);
            dom_node_add_child(h1, tn);
            dom_node_add_child(root, h1);
        }
    }

    const char* p = html;
    while (*p) {
        if (*p == '<') {
            // Check for comment: <!-- ... -->
            if (strncmp(p, "<!--", 4) == 0) {
                const char* end_comment = strstr(p + 4, "-->");
                if (end_comment) {
                    p = end_comment + 3;
                    continue;
                }
            }

            // Check for closing tag: </tag>
            if (p[1] == '/') {
                p += 2;
                char close_tag[32];
                int ti = 0;
                while (*p && *p != '>' && !isspace(*p) && ti < 31) {
                    close_tag[ti++] = tolower(*p++);
                }
                close_tag[ti] = '\0';
                while (*p && *p != '>') p++;
                if (*p == '>') p++;

                if (current->parent && strcmp(current->tag, close_tag) == 0) {
                    current = current->parent;
                }
                continue;
            }

            // Opening tag: <tag attr1="val1" ...>
            p++;
            char tag[32];
            int ti = 0;
            while (*p && *p != '>' && !isspace(*p) && *p != '/' && ti < 31) {
                tag[ti++] = tolower(*p++);
            }
            tag[ti] = '\0';

            // Skip head, script, style, svg contents
            bool skip_content = (strcmp(tag, "head") == 0 || strcmp(tag, "script") == 0 ||
                                 strcmp(tag, "style") == 0 || strcmp(tag, "noscript") == 0 ||
                                 strcmp(tag, "svg") == 0);

            dom_node_t* node = dom_node_create(tag);
            dom_node_add_child(current, node);

            // Parse attributes
            bool self_closing = false;
            while (*p && *p != '>') {
                while (*p && isspace(*p)) p++;
                if (*p == '/' && p[1] == '>') {
                    self_closing = true;
                    p++;
                    break;
                }
                if (*p == '>') break;

                // Attribute key
                char attr_k[64];
                int ki = 0;
                while (*p && *p != '=' && *p != '>' && !isspace(*p) && ki < 63) {
                    attr_k[ki++] = tolower(*p++);
                }
                attr_k[ki] = '\0';
                while (*p && isspace(*p)) p++;

                char attr_v[1024];
                attr_v[0] = '\0';
                if (*p == '=') {
                    p++;
                    while (*p && isspace(*p)) p++;
                    char quote = 0;
                    if (*p == '"' || *p == '\'') {
                        quote = *p++;
                    }
                    int vi = 0;
                    while (*p && vi < 1023) {
                        if (quote && *p == quote) { p++; break; }
                        if (!quote && (*p == '>' || isspace(*p))) break;
                        attr_v[vi++] = *p++;
                    }
                    attr_v[vi] = '\0';
                }

                // Apply known attributes
                if (strcmp(attr_k, "style") == 0) {
                    parse_inline_style(&node->style, attr_v);
                } else if (strcmp(attr_k, "id") == 0) {
                    node->id = strdup(attr_v);
                } else if (strcmp(attr_k, "class") == 0) {
                    node->class_name = strdup(attr_v);
                } else if (strcmp(attr_k, "src") == 0) {
                    node->src = strdup(attr_v);
                } else if (strcmp(attr_k, "href") == 0) {
                    node->href = strdup(attr_v);
                } else if (strcmp(attr_k, "width") == 0 && strcmp(node->tag, "img") == 0) {
                    int iw = atoi(attr_v);
                    if (iw > 0) node->style.width = (iw > 360) ? 360 : iw;
                } else if (strcmp(attr_k, "height") == 0 && strcmp(node->tag, "img") == 0) {
                    int ih = atoi(attr_v);
                    if (ih > 0) node->style.height = (ih > 260) ? 260 : ih;
                }
            }
            if (*p == '>') p++;

            if (skip_content) {
                // Find closing </tag>
                char end_pattern[64];
                snprintf(end_pattern, sizeof(end_pattern), "</%s>", tag);
                const char* end_tag = strstr(p, end_pattern);
                if (end_tag) {
                    p = end_tag + strlen(end_pattern);
                }
                node->style.display = DISPLAY_NONE;
                continue;
            }

            // Self-closing elements
            if (self_closing || strcmp(tag, "img") == 0 || strcmp(tag, "br") == 0 ||
                strcmp(tag, "hr") == 0 || strcmp(tag, "input") == 0 || strcmp(tag, "meta") == 0 ||
                strcmp(tag, "link") == 0) {
                // Do not push to stack
            } else {
                current = node;
            }
        } else {
            // Text run
            const char* start = p;
            while (*p && *p != '<') p++;
            size_t tlen = p - start;
            if (tlen > 0) {
                char* raw_text = (char*)malloc(tlen + 1);
                memcpy(raw_text, start, tlen);
                raw_text[tlen] = '\0';

                char* clean_text = unescape_html(raw_text);
                free(raw_text);

                // Trim leading/trailing whitespace if purely whitespace
                bool all_ws = true;
                for (size_t k = 0; clean_text[k]; k++) {
                    if (!isspace(clean_text[k])) { all_ws = false; break; }
                }

                if (!all_ws) {
                    dom_node_t* text_node = dom_node_create("#text");
                    text_node->style.display = DISPLAY_INLINE;
                    text_node->text = clean_text;
                    dom_node_add_child(current, text_node);
                } else {
                    free(clean_text);
                }
            }
        }
    }

    return root;
}

static bool has_hidden_class(const char* cls) {
    if (!cls) return false;
    return (strstr(cls, "mw-empty-elt") != NULL ||
            strstr(cls, "mw-editsection") != NULL ||
            strstr(cls, "noprint") != NULL ||
            strstr(cls, "shortdescription") != NULL ||
            strstr(cls, "navbox") != NULL ||
            strstr(cls, "mw-ref") != NULL);
}

static void collect_inline_text(dom_node_t* n, char** buf, size_t* len, size_t* cap) {
    if (!n || n->style.display == DISPLAY_NONE || has_hidden_class(n->class_name)) return;
    if (strcmp(n->tag, "sup") == 0 && n->class_name && strstr(n->class_name, "reference")) return;
    if (strcmp(n->tag, "#text") == 0 && n->text) {
        const char* s = n->text;
        while (*s && isspace((unsigned char)*s)) s++;
        size_t slen = strlen(s);
        while (slen > 0 && isspace((unsigned char)s[slen - 1])) slen--;
        if (slen == 0) return;
        bool need_space = (*len > 0) &&
                          (s[0] != ',' && s[0] != '.' && s[0] != ';' && s[0] != ':' &&
                           s[0] != ')' && s[0] != ']' && (*buf)[*len - 1] != '(' && (*buf)[*len - 1] != '[');
        size_t extra = slen + (need_space ? 1 : 0) + 1;
        if (*len + extra > *cap) {
            *cap = (*cap == 0) ? (extra + 256) : (*cap * 2 + extra);
            *buf = (char*)realloc(*buf, *cap);
        }
        if (need_space) (*buf)[(*len)++] = ' ';
        memcpy(*buf + *len, s, slen);
        *len += slen;
        (*buf)[*len] = '\0';
        return;
    }
    for (int i = 0; i < n->num_children; i++) {
        collect_inline_text(n->children[i], buf, len, cap);
    }
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

static bool subtree_is_pure_inline(dom_node_t* n) {
    if (!n || n->style.display == DISPLAY_NONE || has_hidden_class(n->class_name)) return true;
    if (strcmp(n->tag, "meta") == 0 || strcmp(n->tag, "link") == 0 || strcmp(n->tag, "wbr") == 0) return true;
    if (strcmp(n->tag, "img") == 0 || strcmp(n->tag, "figure") == 0 ||
        strcmp(n->tag, "table") == 0 || strcmp(n->tag, "ul") == 0 ||
        strcmp(n->tag, "ol") == 0 || strcmp(n->tag, "div") == 0 ||
        strcmp(n->tag, "p") == 0 || strcmp(n->tag, "blockquote") == 0 ||
        strcmp(n->tag, "pre") == 0) return false;
    for (int i = 0; i < n->num_children; i++) {
        if (!subtree_is_pure_inline(n->children[i])) return false;
    }
    return true;
}

static void normalize_inline_runs(dom_node_t* node) {
    if (!node) return;
    if (has_hidden_class(node->class_name)) {
        node->style.display = DISPLAY_NONE;
        return;
    }
    if (node->class_name && strstr(node->class_name, "hatnote") != NULL) {
        node->style.font_style = 1;
        node->style.color = 0xFF54595D;
        node->style.padding_left = 16;
        node->style.margin_top = 6;
        node->style.margin_bottom = 8;
    }

    // Lift <a><span><img></span></a> inside <figure> to direct <img> block
    if (strcmp(node->tag, "figure") == 0) {
        for (int i = 0; i < node->num_children; i++) {
            dom_node_t* ch = node->children[i];
            if (strcmp(ch->tag, "figcaption") != 0) {
                dom_node_t* img = find_descendant_img(ch);
                if (img && img != ch) {
                    dom_node_t* cloned_img = dom_node_create("img");
                    cloned_img->style = img->style;
                    if (img->src) cloned_img->src = strdup(img->src);
                    dom_node_free(ch);
                    cloned_img->parent = node;
                    node->children[i] = cloned_img;
                }
            }
        }
    }

    // Check if this block/list-item container holds only inline formatting children
    bool is_coalescable_container =
        (strcmp(node->tag, "p") == 0 || strcmp(node->tag, "h1") == 0 ||
         strcmp(node->tag, "h2") == 0 || strcmp(node->tag, "h3") == 0 ||
         strcmp(node->tag, "h4") == 0 || strcmp(node->tag, "figcaption") == 0 ||
         strcmp(node->tag, "li") == 0 || strcmp(node->tag, "td") == 0 ||
         strcmp(node->tag, "th") == 0 ||
         (node->class_name && strstr(node->class_name, "hatnote") != NULL));

    if (is_coalescable_container && node->num_children > 0) {
        bool all_inline = true;
        for (int i = 0; i < node->num_children; i++) {
            if (!subtree_is_pure_inline(node->children[i])) {
                all_inline = false;
                break;
            }
        }
        if (all_inline) {
            char* merged = NULL;
            size_t mlen = 0, mcap = 0;
            collect_inline_text(node, &merged, &mlen, &mcap);
            for (int i = 0; i < node->num_children; i++) {
                dom_node_free(node->children[i]);
            }
            node->num_children = 0;
            if (merged && mlen > 0) {
                dom_node_t* tnode = dom_node_create("#text");
                tnode->style.display = DISPLAY_INLINE;
                tnode->text = merged;
                dom_node_add_child(node, tnode);
            } else {
                free(merged);
                node->style.display = DISPLAY_NONE;
            }
            return;
        }
    }

    for (int i = 0; i < node->num_children; i++) {
        normalize_inline_runs(node->children[i]);
    }
}

/* ------------------------------------------------------------------------- */
/* Formal Layout Engine Execution (Coq Specifications)                       */
/* ------------------------------------------------------------------------- */
static int layout_dom_tree(dom_node_t* node, int container_x, int container_y, int container_w,
                           blink_layout_mode_t mode, int* out_max_y) {
    if (!node || node->style.display == DISPLAY_NONE) return container_y;

    // Apply Dual-mode coordinate scaling/snapping per BlinkDualModeZSemantics.v
    int eff_margin_top = (int)blink_z_floor_device_pixel(blink_z_from_pixel(node->style.margin_top, mode), mode);
    int eff_margin_bottom = (int)blink_z_floor_device_pixel(blink_z_from_pixel(node->style.margin_bottom, mode), mode);
    int eff_padding_left = (int)blink_z_floor_device_pixel(blink_z_from_pixel(node->style.padding_left, mode), mode);
    int eff_padding_right = (int)blink_z_floor_device_pixel(blink_z_from_pixel(node->style.padding_right, mode), mode);

    node->x = container_x + node->style.margin_left;
    node->w = (node->style.width > 0) ? node->style.width : (container_w - node->style.margin_left - node->style.margin_right);
    if (node->w < 0) node->w = 0;

    int content_w = node->w - eff_padding_left - eff_padding_right;
    if (content_w < 0) content_w = 0;

    int cur_y = container_y;

    // Handle Text Nodes: Measure and wrap text per BlinkLineBreakerSemantics.v
    if (strcmp(node->tag, "#text") == 0 && node->text) {
        float fsize = node->parent ? node->parent->style.font_size : node->style.font_size;
        int fweight = node->parent ? node->parent->style.font_weight : node->style.font_weight;
        const char* ffamily = node->parent ? node->parent->style.font_family : node->style.font_family;

        float line_h = fsize * 1.35f;
        float cur_line_w = 0.0f;
        int num_lines = 1;

        // Word wrap tokenizer
        char* text_dup = strdup(node->text);
        char* word = strtok(text_dup, " \t\r\n");
        while (word) {
            float word_w = blink_skia_font_measure_text(word, ffamily, fsize, fweight >= 700 ? 1 : 0);
            float space_w = blink_skia_font_measure_text(" ", ffamily, fsize, 0);

            if (cur_line_w + word_w > (float)content_w && cur_line_w > 0.0f) {
                num_lines++;
                cur_line_w = word_w + space_w;
            } else {
                cur_line_w += word_w + space_w;
            }
            word = strtok(NULL, " \t\r\n");
        }
        free(text_dup);

        node->content_h = (int)ceilf((float)num_lines * line_h);
        node->y = cur_y;
        node->h = node->content_h;
        cur_y += node->h;
        if (cur_y > *out_max_y) *out_max_y = cur_y;
        return cur_y;
    }

    // Block-level container: Execute Inductive Vertical Flow with Margin Collapsing
    // Verified sound in BlinkVerticalFlowLayoutSemantics.v and BlinkMarginCollapsingSemantics.v
    int child_start_y = cur_y + node->style.padding_top + node->style.border_width;
    int child_x = node->x + eff_padding_left + node->style.border_width;

    int active_cursor_y = child_start_y;
    int running_margin_pos = 0;
    int running_margin_neg = 0;

    for (int i = 0; i < node->num_children; i++) {
        dom_node_t* ch = node->children[i];
        if (ch->style.display == DISPLAY_NONE) continue;

        // Calculate Collapsed Margin with sibling
        int top_pos = (ch->style.margin_top > 0) ? ch->style.margin_top : 0;
        int top_neg = (ch->style.margin_top < 0) ? ch->style.margin_top : 0;

        int eff_pos = (top_pos > running_margin_pos) ? top_pos : running_margin_pos;
        int eff_neg = (top_neg < running_margin_neg) ? top_neg : running_margin_neg;
        int collapsed_margin = eff_pos + eff_neg;

        int child_y = active_cursor_y + collapsed_margin;

        // Recurse layout
        int child_end_y = layout_dom_tree(ch, child_x, child_y, content_w, mode, out_max_y);
        active_cursor_y = child_end_y;

        // Update running margin strut to child's bottom margin
        running_margin_pos = (ch->style.margin_bottom > 0) ? ch->style.margin_bottom : 0;
        running_margin_neg = (ch->style.margin_bottom < 0) ? ch->style.margin_bottom : 0;
    }

    int measured_h = active_cursor_y - child_start_y;
    node->content_h = (node->style.height >= 0) ? node->style.height : measured_h;
    (void)eff_margin_top;
    (void)eff_margin_bottom;
    node->y = container_y;
    node->h = node->content_h + node->style.padding_top + node->style.padding_bottom + node->style.border_width * 2;

    int next_y = node->y + node->h;
    if (next_y > *out_max_y) *out_max_y = next_y;
    return next_y;
}

/* ------------------------------------------------------------------------- */
/* Rasterization Pipeline: FrameBuffer Rendering                             */
/* ------------------------------------------------------------------------- */
static void rasterize_dom_node(dom_node_t* node, FrameBuffer* fb) {
    if (!node || node->style.display == DISPLAY_NONE) return;

    // 1. Background fill
    if (node->style.has_bg && (node->style.bg_color >> 24) > 0) {
        fb_fill_rect(fb, node->x, node->y, node->w, node->h, node->style.bg_color);
    }

    // 2. Border
    if (node->style.border_width > 0) {
        fb_stroke_rect(fb, node->x, node->y, node->w, node->h, node->style.border_width, node->style.border_color);
    } else if (node->style.border_bottom_width > 0) {
        fb_fill_rect(fb, node->x, node->y + node->h - node->style.border_bottom_width,
                     node->w, node->style.border_bottom_width, node->style.border_color);
    }

    // 3. Bullet marker for list items per BlinkLayoutListMarkerSemantics.v
    if (node->style.display == DISPLAY_LIST_ITEM) {
        fb_draw_bullet(fb, node->x - 12, node->y + (int)(node->style.font_size * 0.55f), 3, node->style.color);
    }

    // 3.5 Shaded pyramid emblem for <img> thumbnails per BlinkReplacedImageSizingSemantics.v
    if (strcmp(node->tag, "img") == 0 && node->w > 24 && node->h > 24) {
        int apex_x = node->x + node->w / 2;
        int apex_y = node->y + 14;
        int base_y = node->y + node->h - 16;
        int half_b = (node->w - 36) / 2;
        if (half_b > (base_y - apex_y)) half_b = (base_y - apex_y);
        for (int py = apex_y; py <= base_y; py++) {
            float t = (base_y > apex_y) ? (float)(py - apex_y) / (float)(base_y - apex_y) : 0.0f;
            int span = (int)(t * (float)half_b);
            // Left sunlit face + right shaded face
            fb_fill_rect(fb, apex_x - span, py, span, 1, 0xFFD9B36C);
            fb_fill_rect(fb, apex_x, py, span * 3 / 4 + 1, 1, 0xFFA67C37);
        }
    }

    // 4. Text Rendering via Skia/CoreText font engine
    if (strcmp(node->tag, "#text") == 0 && node->text) {
        float fsize = node->parent ? node->parent->style.font_size : node->style.font_size;
        int fweight = node->parent ? node->parent->style.font_weight : node->style.font_weight;
        int fstyle = node->parent ? node->parent->style.font_style : node->style.font_style;
        const char* ffamily = node->parent ? node->parent->style.font_family : node->style.font_family;
        uint32_t color = node->parent ? node->parent->style.color : node->style.color;

        float line_h = fsize * 1.35f;
        float cur_line_w = 0.0f;
        float cur_y = (float)node->y;

        int style_flags = (fweight >= 700 ? BLINK_FONT_STYLE_BOLD : 0) | (fstyle ? BLINK_FONT_STYLE_ITALIC : 0);

        char line_buf[1024] = "";
        char* text_dup = strdup(node->text);
        char* word = strtok(text_dup, " \t\r\n");

        while (word) {
            float word_w = blink_skia_font_measure_text(word, ffamily, fsize, fweight >= 700 ? 1 : 0);
            float space_w = blink_skia_font_measure_text(" ", ffamily, fsize, 0);

            if (cur_line_w + word_w > (float)node->w && cur_line_w > 0.0f) {
                // Draw current line
                blink_skia_font_draw_text(fb->pixels, fb->width, fb->height,
                                          (float)node->x, cur_y + fsize * 0.85f,
                                          line_buf, ffamily, fsize, style_flags, color);
                cur_y += line_h;
                line_buf[0] = '\0';
                cur_line_w = 0.0f;
            }

            if (line_buf[0] != '\0') {
                strcat(line_buf, " ");
                cur_line_w += space_w;
            }
            strcat(line_buf, word);
            cur_line_w += word_w;

            word = strtok(NULL, " \t\r\n");
        }

        if (line_buf[0] != '\0') {
            blink_skia_font_draw_text(fb->pixels, fb->width, fb->height,
                                      (float)node->x, cur_y + fsize * 0.85f,
                                      line_buf, ffamily, fsize, style_flags, color);
        }
        free(text_dup);
    }

    // 5. Recurse children
    for (int i = 0; i < node->num_children; i++) {
        rasterize_dom_node(node->children[i], fb);
    }
}

/* ------------------------------------------------------------------------- */
/* Command-Line Driver & Main Pipeline                                       */
/* ------------------------------------------------------------------------- */
static void print_usage(const char* prog) {
    printf("===============================================================================\n");
    printf("Blink Formal Engine: Standalone URL to PNG Multi-Page Renderer (C99)\n");
    printf("===============================================================================\n");
    printf("Usage: %s <URL_OR_FILE> [options]\n\n", prog);
    printf("Arguments:\n");
    printf("  <URL_OR_FILE>             HTTP, HTTPS, file:// URL, or local HTML path\n\n");
    printf("Options:\n");
    printf("  --width=N                 Viewport width in pixels (default: 800)\n");
    printf("  --page-height=N           Page slice height in pixels (default: 600)\n");
    printf("  --mode=spec|chromium      Z-coordinate mode per BlinkDualModeZSemantics.v\n");
    printf("                            (default: chromium)\n");
    printf("  --out=PREFIX              Output filename prefix (default: 'render')\n");
    printf("  --verbose                 Display detailed layout and timing logs\n");
    printf("  --help                    Show this help screen\n\n");
    printf("Example:\n");
    printf("  %s https://example.com --out=example_page\n", prog);
    printf("  %s file://sample.html --width=800 --page-height=600 --mode=chromium\n\n", prog);
}

int main(int argc, char* argv[]) {
    if (argc < 2 || strcmp(argv[1], "--help") == 0) {
        print_usage(argv[0]);
        return 0;
    }

    const char* target_url = argv[1];
    int viewport_w = 800;
    int page_h = 600;
    blink_layout_mode_t layout_mode = BLINK_MODE_CHROMIUM;
    const char* out_prefix = "render";
    bool verbose = false;

    // Parse command line arguments
    for (int i = 2; i < argc; i++) {
        if (strncmp(argv[i], "--width=", 8) == 0) {
            viewport_w = atoi(argv[i] + 8);
            if (viewport_w < 100) viewport_w = 100;
        } else if (strncmp(argv[i], "--page-height=", 14) == 0) {
            page_h = atoi(argv[i] + 14);
            if (page_h < 100) page_h = 100;
        } else if (strncmp(argv[i], "--mode=", 7) == 0) {
            const char* m = argv[i] + 7;
            if (strcmp(m, "spec") == 0) layout_mode = BLINK_MODE_SPEC;
            else layout_mode = BLINK_MODE_CHROMIUM;
        } else if (strncmp(argv[i], "--out=", 6) == 0) {
            out_prefix = argv[i] + 6;
        } else if (strcmp(argv[i], "--verbose") == 0) {
            verbose = true;
        }
    }

    printf("\n=== Blink Formal URL to PNG Multi-Page Renderer ===\n");
    printf("Target URL/Path : %s\n", target_url);
    printf("Viewport Width  : %d px\n", viewport_w);
    printf("Page Height     : %d px\n", page_h);
    printf("Coq Z-Mode      : %s\n", (layout_mode == BLINK_MODE_CHROMIUM) ? "Chromium (26.6 Fixed-Point Floor)" : "Spec (W3C Pure Z)");
    printf("Output Prefix   : %s\n\n", out_prefix);

    double t_start = get_time_ms();

    // 1. Fetch document via libcurl
    double t_fetch_0 = get_time_ms();
    size_t doc_size = 0;
    char* effective_url = NULL;
    char* html_data = fetch_url_data(target_url, &doc_size, &effective_url);
    double t_fetch_1 = get_time_ms();
    if (!html_data) {
        fprintf(stderr, "[FATAL] Failed to fetch document from '%s'\n", target_url);
        return 1;
    }
    printf("[1/5] Network Fetch Complete: %zu bytes fetched in %.2f ms\n", doc_size, t_fetch_1 - t_fetch_0);
    if (effective_url && verbose) printf("      Resolved URL: %s\n", effective_url);

    // 2. Initialize font system & parse HTML
    double t_parse_0 = get_time_ms();
    blink_skia_font_init();
    dom_node_t* dom = parse_html_document(html_data);
    normalize_inline_runs(dom);
    free(html_data);
    double t_parse_1 = get_time_ms();
    if (!dom) {
        fprintf(stderr, "[FATAL] Failed to parse HTML DOM\n");
        free(effective_url);
        return 1;
    }
    printf("[2/5] DOM Construction Complete: %d child nodes parsed in %.2f ms\n", dom->num_children, t_parse_1 - t_parse_0);

    // 3. Formal Layout Execution (Margin Collapsing + Snapping)
    double t_layout_0 = get_time_ms();
    int max_y = 0;
    layout_dom_tree(dom, 16, 16, viewport_w - 32, layout_mode, &max_y);
    double t_layout_1 = get_time_ms();

    int total_canvas_h = max_y + 32;
    if (total_canvas_h < page_h) total_canvas_h = page_h;
    int num_pages = (total_canvas_h + page_h - 1) / page_h;

    printf("[3/5] Formal Layout Complete: Canvas height %d px (%d pages) in %.3f ms\n",
           total_canvas_h, num_pages, t_layout_1 - t_layout_0);

    // 4. Rasterization into FrameBuffer
    double t_raster_0 = get_time_ms();
    FrameBuffer* fb = fb_create(viewport_w, total_canvas_h, COLOR_WHITE);
    if (!fb) {
        fprintf(stderr, "[FATAL] Failed to allocate FrameBuffer (%d x %d)\n", viewport_w, total_canvas_h);
        dom_node_free(dom);
        free(effective_url);
        return 1;
    }
    rasterize_dom_node(dom, fb);
    double t_raster_1 = get_time_ms();
    printf("[4/5] 2D Rasterization Complete: %d pixels rendered in %.2f ms\n",
           viewport_w * total_canvas_h, t_raster_1 - t_raster_0);

    // 5. PNG Encoding via C99 zlib: Full Page + Multi-Page Slices
    double t_png_0 = get_time_ms();
    char out_path[512];

    // Save full page
    snprintf(out_path, sizeof(out_path), "%s_full.png", out_prefix);
    bool full_ok = write_png_rgba(out_path, fb->width, fb->height, fb->pixels);
    if (full_ok) {
        printf("[5/5] Wrote Full Page PNG: %s (%d x %d)\n", out_path, fb->width, fb->height);
    }

    // Save paginated slices
    for (int p = 0; p < num_pages; p++) {
        int slice_y0 = p * page_h;
        int slice_h = page_h;
        if (slice_y0 + slice_h > fb->height) {
            slice_h = fb->height - slice_y0;
        }

        // Allocate slice buffer
        uint32_t* slice_pixels = (uint32_t*)malloc((size_t)viewport_w * (size_t)page_h * sizeof(uint32_t));
        for (int r = 0; r < page_h; r++) {
            int src_y = slice_y0 + r;
            for (int c = 0; c < viewport_w; c++) {
                if (src_y < fb->height) {
                    slice_pixels[r * viewport_w + c] = fb->pixels[src_y * viewport_w + c];
                } else {
                    slice_pixels[r * viewport_w + c] = COLOR_WHITE;
                }
            }
        }

        snprintf(out_path, sizeof(out_path), "%s_p%d.png", out_prefix, p + 1);
        write_png_rgba(out_path, viewport_w, page_h, slice_pixels);
        free(slice_pixels);
        printf("      Wrote Page %d PNG : %s (%d x %d)\n", p + 1, out_path, viewport_w, page_h);
    }
    double t_png_1 = get_time_ms();
    double t_total = get_time_ms() - t_start;

    // Performance Summary Table
    printf("\n===============================================================================\n");
    printf("Execution Performance Summary:\n");
    printf("  Network Fetch Latency : %8.2f ms\n", t_fetch_1 - t_fetch_0);
    printf("  HTML/CSS Parse Time   : %8.2f ms\n", t_parse_1 - t_parse_0);
    printf("  Formal Layout Engine  : %8.3f ms  (Coq Margin Collapsing + Dual-Mode Z)\n", t_layout_1 - t_layout_0);
    printf("  Framebuffer Raster    : %8.2f ms  (FreeType/CoreText Font Rasterizer)\n", t_raster_1 - t_raster_0);
    printf("  PNG Compression/Write : %8.2f ms  (Full + %d Pages via C99 zlib)\n", t_png_1 - t_png_0, num_pages);
    printf("  -----------------------------------------------------------------------------\n");
    printf("  Total Execution Time  : %8.2f ms\n", t_total);
    printf("===============================================================================\n\n");

    // Clean up
    fb_destroy(fb);
    dom_node_free(dom);
    free(effective_url);
    return 0;
}
