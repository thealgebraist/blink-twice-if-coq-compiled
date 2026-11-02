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
#include "blink_html_css_formal.h"
#include "blink_layout_paint_formal.h"
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
/* Formal HTML5/CSS4 + Multi-Span Inline + Positioned Layout & Paint         */
/* Provided by blink_html_css_formal.{h,c} and blink_layout_paint_formal.{h,c}*/
/* (Verified in BlinkHTML5TreeBuilderAndCSSCascadeEngine.v &                 */
/*  BlinkCSS4InlineAndPositionedLayoutEngine.v)                              */
/* ------------------------------------------------------------------------- */
#define COLOR_WHITE 0xFFFFFFFFu

static void extract_parent_dir(const char* path_or_url, char* out_dir, size_t cap) {
    if (!out_dir || cap == 0) return;
    strncpy(out_dir, ".", cap - 1);
    out_dir[cap - 1] = '\0';
    if (!path_or_url || strncmp(path_or_url, "http://", 7) == 0 || strncmp(path_or_url, "https://", 8) == 0) {
        return;
    }
    const char* p = (strncmp(path_or_url, "file://", 7) == 0) ? (path_or_url + 7) : path_or_url;
    const char* slash = strrchr(p, '/');
    if (slash && slash > p) {
        size_t dlen = (size_t)(slash - p);
        if (dlen >= cap) dlen = cap - 1;
        memcpy(out_dir, p, dlen);
        out_dir[dlen] = '\0';
    } else if (slash == p) {
        strncpy(out_dir, "/", cap - 1);
        out_dir[cap - 1] = '\0';
    }
}

static char* url2png_stylesheet_loader(const char* raw_href, void* user_data, char* out_dir, size_t out_dir_cap) {
    if (!raw_href || !raw_href[0]) return NULL;

    /* Decode HTML entities in stylesheet URL (e.g. &amp; -> &) */
    char* href = blink_unescape_html(raw_href);
    if (!href) href = strdup(raw_href);

    const char* base_url = (const char*)user_data;
    char target_url[2048];

    if (strncmp(href, "http://", 7) == 0 || strncmp(href, "https://", 8) == 0) {
        snprintf(target_url, sizeof(target_url), "%s", href);
    } else if (strncmp(href, "//", 2) == 0) {
        snprintf(target_url, sizeof(target_url), "https:%s", href);
    } else if (base_url && (strncmp(base_url, "http://", 7) == 0 || strncmp(base_url, "https://", 8) == 0)) {
        if (href[0] == '/') {
            char origin[1024];
            const char* p = strstr(base_url, "://");
            if (p) {
                const char* slash = strchr(p + 3, '/');
                size_t olen = slash ? (size_t)(slash - base_url) : strlen(base_url);
                if (olen >= sizeof(origin)) olen = sizeof(origin) - 1;
                memcpy(origin, base_url, olen);
                origin[olen] = '\0';
                snprintf(target_url, sizeof(target_url), "%s%s", origin, href);
            } else {
                snprintf(target_url, sizeof(target_url), "%s", href);
            }
        } else {
            char pdir[1024];
            extract_parent_dir(base_url, pdir, sizeof(pdir));
            snprintf(target_url, sizeof(target_url), "%s/%s", pdir, href);
        }
    } else {
        free(href);
        return NULL; /* Fallback to local file loader */
    }
    free(href);

    size_t sz = 0;
    char* eff = NULL;
    char* css_data = fetch_url_data(target_url, &sz, &eff);
    if (eff) {
        if (out_dir && out_dir_cap > 0) {
            extract_parent_dir(eff, out_dir, out_dir_cap);
        }
        free(eff);
    }
    return css_data;
}

/* ------------------------------------------------------------------------- */
/* Image Caching and Fetching Pipeline                                       */
/* ------------------------------------------------------------------------- */
typedef struct {
    char*          url;
    blink_image_t* image;
} image_cache_entry_t;

typedef struct {
    image_cache_entry_t* entries;
    int                  count;
    int                  capacity;
} image_cache_t;

static blink_image_t* image_cache_get(image_cache_t* cache, const char* url) {
    if (!cache || !url) return NULL;
    for (int i = 0; i < cache->count; i++) {
        if (strcmp(cache->entries[i].url, url) == 0) {
            return cache->entries[i].image;
        }
    }
    return NULL;
}

static void image_cache_put(image_cache_t* cache, const char* url, blink_image_t* img) {
    if (!cache || !url) return;
    if (cache->count >= cache->capacity) {
        cache->capacity = (cache->capacity == 0) ? 64 : cache->capacity * 2;
        cache->entries = (image_cache_entry_t*)realloc(cache->entries, sizeof(image_cache_entry_t) * cache->capacity);
    }
    cache->entries[cache->count].url = strdup(url);
    cache->entries[cache->count].image = img;
    cache->count++;
}

static void image_cache_destroy(image_cache_t* cache) {
    if (!cache) return;
    for (int i = 0; i < cache->count; i++) {
        free(cache->entries[i].url);
        if (cache->entries[i].image) {
            blink_image_free(cache->entries[i].image);
        }
    }
    free(cache->entries);
    cache->entries = NULL;
    cache->count = 0;
    cache->capacity = 0;
}

static void url_hash_hex(const char* str, char* out_hex) {
    uint64_t h1 = 14695981039346656037ULL;
    uint64_t h2 = 1099511628211ULL;
    const unsigned char* p = (const unsigned char*)str;
    while (*p) {
        h1 = (h1 ^ *p) * 1099511628211ULL;
        h2 = (h2 * 14695981039346656037ULL) ^ *p;
        p++;
    }
    snprintf(out_hex, 33, "%016llx%016llx", (unsigned long long)h1, (unsigned long long)h2);
}

static blink_image_t* load_or_fetch_image(const char* raw_src, const char* base_url, image_cache_t* cache) {
    if (!raw_src || !raw_src[0]) return NULL;

    blink_image_t* cached = image_cache_get(cache, raw_src);
    if (cached) return cached;

    /* Decode HTML entities in image src (e.g. &amp; -> &) */
    char* clean_src = blink_unescape_html(raw_src);
    const char* src_to_use = clean_src ? clean_src : raw_src;

    /* Trim leading and trailing whitespace */
    while (*src_to_use && isspace((unsigned char)*src_to_use)) src_to_use++;
    char trimmed_src[1024];
    strncpy(trimmed_src, src_to_use, sizeof(trimmed_src) - 1);
    trimmed_src[sizeof(trimmed_src) - 1] = '\0';
    char* end_p = trimmed_src + strlen(trimmed_src) - 1;
    while (end_p >= trimmed_src && isspace((unsigned char)*end_p)) {
        *end_p = '\0';
        end_p--;
    }

    /* Resolve relative URL against base_url */
    char full_url[2048];
    if (strncmp(trimmed_src, "//", 2) == 0) {
        snprintf(full_url, sizeof(full_url), "https:%s", trimmed_src);
    } else if (strncmp(trimmed_src, "http://", 7) == 0 || strncmp(trimmed_src, "https://", 8) == 0 ||
               strncmp(trimmed_src, "file://", 7) == 0) {
        snprintf(full_url, sizeof(full_url), "%s", trimmed_src);
    } else if (trimmed_src[0] == '/' && base_url && (strncmp(base_url, "http://", 7) == 0 || strncmp(base_url, "https://", 8) == 0)) {
        char origin[1024];
        const char* p = strstr(base_url, "://");
        if (p) {
            const char* slash = strchr(p + 3, '/');
            size_t olen = slash ? (size_t)(slash - base_url) : strlen(base_url);
            if (olen >= sizeof(origin)) olen = sizeof(origin) - 1;
            memcpy(origin, base_url, olen);
            origin[olen] = '\0';
            snprintf(full_url, sizeof(full_url), "%s%s", origin, trimmed_src);
        } else {
            snprintf(full_url, sizeof(full_url), "%s", trimmed_src);
        }
    } else if (base_url && (strncmp(base_url, "http://", 7) == 0 || strncmp(base_url, "https://", 8) == 0)) {
        char pdir[1024];
        extract_parent_dir(base_url, pdir, sizeof(pdir));
        snprintf(full_url, sizeof(full_url), "%s/%s", pdir, trimmed_src);
    } else if (base_url && base_url[0]) {
        snprintf(full_url, sizeof(full_url), "%s/%s", base_url, trimmed_src);
    } else {
        snprintf(full_url, sizeof(full_url), "%s", trimmed_src);
    }
    if (clean_src) free(clean_src);

    /* 1. Check disk cache if available in /tmp/blink_img_cache */
    blink_image_t* img = NULL;
    char disk_cache_path[512];
    char hash_str[33];
    url_hash_hex(full_url, hash_str);
    snprintf(disk_cache_path, sizeof(disk_cache_path), "/tmp/blink_img_cache/%s", hash_str);

    FILE* fp = fopen(disk_cache_path, "rb");
    if (!fp) {
        /* Check if local file exists by raw path or file:// */
        const char* local_path = full_url;
        if (strncmp(full_url, "file://", 7) == 0) local_path = full_url + 7;
        fp = fopen(local_path, "rb");
    }

    if (fp) {
        fseek(fp, 0, SEEK_END);
        long sz = ftell(fp);
        fseek(fp, 0, SEEK_SET);
        if (sz > 0 && sz < 64 * 1024 * 1024) {
            uint8_t* buf = (uint8_t*)malloc(sz);
            if (buf) {
                size_t rd = fread(buf, 1, sz, fp);
                if (rd == (size_t)sz) {
                    img = blink_image_load_memory(buf, sz);
                }
                free(buf);
            }
        }
        fclose(fp);
    }

    /* 2. If not on disk, fetch via libcurl */
    if (!img) {
        size_t sz = 0;
        char* eff = NULL;
        char* net_data = fetch_url_data(full_url, &sz, &eff);
        free(eff);
        if (net_data && sz > 0) {
            img = blink_image_load_memory((const uint8_t*)net_data, sz);
            /* Save to disk cache for subsequent lightning-fast runs */
            FILE* wfp = fopen(disk_cache_path, "wb");
            if (wfp) {
                fwrite(net_data, 1, sz, wfp);
                fclose(wfp);
            }
            free(net_data);
        }
    }

    if (img) {
        image_cache_put(cache, raw_src, img);
    }
    return img;
}

static void bind_images_to_dom(dom_node_t* node, const char* base_url, image_cache_t* cache, int* out_count) {
    if (!node) return;
    if (strcmp(node->tag, "img") == 0 && node->src) {
        blink_image_t* img = load_or_fetch_image(node->src, base_url, cache);
        if (img) {
            node->image_data = img;
            if (out_count) (*out_count)++;
        }
    }
    for (int i = 0; i < node->num_children; i++) {
        bind_images_to_dom(node->children[i], base_url, cache, out_count);
    }
}

/* ------------------------------------------------------------------------- */
/* Command-Line Driver & Main Pipeline                                       */
/* ------------------------------------------------------------------------- */
static void dump_subtree(dom_node_t* n, int depth) {
    if (!n || depth > 15) return;
    for (int i = 0; i < depth; i++) printf("  ");
    printf("<%s id='%s' class='%.25s'> pos=(%d,%d) size=(%d,%d) pad=(%d,%d) mar=(%d,%d) disp=%d\n",
           n->tag, n->id ? n->id : "", n->class_name ? n->class_name : "",
           n->x, n->y, n->w, n->h,
           n->style.padding_top, n->style.padding_bottom,
           n->style.margin_top, n->style.margin_bottom, n->style.display);
    for (int i = 0; i < n->num_children; i++) {
        dump_subtree(n->children[i], depth + 1);
    }
}

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

    // 2. Initialize font system, parse HTML5 DOM + <style>/<link>/@import rules, and run CSS Cascade Level 5/6
    double t_parse_0 = get_time_ms();
    blink_skia_font_init();
    blink_css_set_custom_loader(url2png_stylesheet_loader, effective_url ? effective_url : (char*)target_url);
    blink_css_stylesheet_t* stylesheet = (blink_css_stylesheet_t*)malloc(sizeof(blink_css_stylesheet_t));
    if (!stylesheet) {
        free(html_data);
        free(effective_url);
        return 1;
    }
    char base_dir[512];
    extract_parent_dir(effective_url ? effective_url : target_url, base_dir, sizeof(base_dir));
    dom_node_t* dom = blink_parse_html5_document_ex(html_data, base_dir, stylesheet);
    free(html_data);
    if (!dom) {
        fprintf(stderr, "[FATAL] Failed to parse HTML5 DOM\n");
        free(stylesheet);
        free(effective_url);
        return 1;
    }
    blink_css_resolve_document_styles(dom, stylesheet, viewport_w, page_h, layout_mode);
    blink_normalize_dom_for_layout(dom);
    double t_parse_1 = get_time_ms();
    printf("[2/5] HTML5 TreeBuilder + CSS Cascade Complete: %d DOM children, %d CSS rules in %.2f ms\n",
           dom->num_children, stylesheet->num_rules, t_parse_1 - t_parse_0);
    free(stylesheet);

    // 2b. Fetch and bind raster images to <img> DOM elements
    image_cache_t image_cache = {0};
    int images_bound = 0;
    bind_images_to_dom(dom, effective_url ? effective_url : target_url, &image_cache, &images_bound);
    if (images_bound > 0) {
        printf("      Image Pipeline: %d raster images loaded and bound to DOM (cached: %d)\n",
               images_bound, image_cache.count);
    }

    // 3. Formal Layout Execution (Multi-Span Inline + Floats + Positioned + Flex/Grid/2D-Table + Dual-Mode Z)
    double t_layout_0 = get_time_ms();
    int max_y = 0;
    blink_layout_dom_tree(dom, 0, 0, viewport_w, page_h, layout_mode, &max_y);
    double t_layout_1 = get_time_ms();

    if (verbose) {
        printf("--- VERBOSE LAYOUT: %d DOM ROOT CHILDREN ---\n", dom->num_children);
        for (int c = 0; c < dom->num_children; c++) {
            printf("[Root Child %d] tag='%s' id='%s' class='%.30s' pos=(%d,%d) size=(%d,%d) bg=0x%08X has_bg=%d\n",
                   c, dom->children[c]->tag, dom->children[c]->id ? dom->children[c]->id : "",
                   dom->children[c]->class_name ? dom->children[c]->class_name : "",
                   dom->children[c]->x, dom->children[c]->y, dom->children[c]->w, dom->children[c]->h,
                   dom->children[c]->style.bg_color, dom->children[c]->style.has_bg);
            dump_subtree(dom->children[c], 1);
        }
    }

    int total_canvas_h = max_y;
    if (total_canvas_h < page_h) total_canvas_h = page_h;
    int num_pages = (total_canvas_h + page_h - 1) / page_h;

    printf("[3/5] Formal Layout Complete: Canvas height %d px (%d pages) in %.3f ms\n",
           total_canvas_h, num_pages, t_layout_1 - t_layout_0);

    // 4. Rasterization into FrameBuffer (CSS 2.2 Appendix E 7-Phase Stacking Context Order)
    double t_raster_0 = get_time_ms();
    uint32_t clear_bg = (dom->style.has_bg && (dom->style.bg_color >> 24) > 0) ? dom->style.bg_color : COLOR_WHITE;
    blink_framebuffer_t* fb = blink_fb_create(viewport_w, total_canvas_h, clear_bg);
    if (!fb) {
        fprintf(stderr, "[FATAL] Failed to allocate FrameBuffer (%d x %d)\n", viewport_w, total_canvas_h);
        dom_node_free(dom);
        free(effective_url);
        return 1;
    }
    blink_paint_dom_stacking_context(dom, fb);
    double t_raster_1 = get_time_ms();
    printf("[4/5] 2D Rasterization Complete: %d pixels rendered in %.2f ms\n",
           viewport_w * total_canvas_h, t_raster_1 - t_raster_0);

    // 5. PNG Encoding via C99 zlib: Full Page + Multi-Page Slices
    double t_png_0 = get_time_ms();
    char out_path[512];

    snprintf(out_path, sizeof(out_path), "%s_full.png", out_prefix);
    bool full_ok = write_png_rgba(out_path, fb->width, fb->height, fb->pixels);
    if (full_ok) {
        printf("[5/5] Wrote Full Page PNG: %s (%d x %d)\n", out_path, fb->width, fb->height);
    }

    for (int p = 0; p < num_pages; p++) {
        int slice_y0 = p * page_h;
        int slice_h = page_h;
        if (slice_y0 + slice_h > fb->height) {
            slice_h = fb->height - slice_y0;
        }

        uint32_t* slice_pixels = (uint32_t*)malloc((size_t)viewport_w * (size_t)page_h * sizeof(uint32_t));
        for (int r = 0; r < page_h; r++) {
            int src_y = slice_y0 + r;
            for (int c = 0; c < viewport_w; c++) {
                if (src_y < fb->height) {
                    slice_pixels[r * viewport_w + c] = fb->pixels[src_y * viewport_w + c];
                } else {
                    slice_pixels[r * viewport_w + c] = clear_bg;
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

    printf("\n===============================================================================\n");
    printf("Execution Performance Summary:\n");
    printf("  Network Fetch Latency : %8.2f ms\n", t_fetch_1 - t_fetch_0);
    printf("  HTML5/CSS3 Cascade    : %8.2f ms  (Coq TreeBuilder + Cascade Level 5)\n", t_parse_1 - t_parse_0);
    printf("  Formal Layout Engine  : %8.3f ms  (Block/Flex/Table + Dual-Mode Z)\n", t_layout_1 - t_layout_0);
    printf("  Framebuffer Raster    : %8.2f ms  (FreeType/CoreText Font Rasterizer)\n", t_raster_1 - t_raster_0);
    printf("  PNG Compression/Write : %8.2f ms  (Full + %d Pages via C99 zlib)\n", t_png_1 - t_png_0, num_pages);
    printf("  -----------------------------------------------------------------------------\n");
    printf("  Total Execution Time  : %8.2f ms\n", t_total);
    printf("===============================================================================\n\n");

    blink_fb_destroy(fb);
    image_cache_destroy(&image_cache);
    dom_node_free(dom);
    free(effective_url);
    return 0;
}
