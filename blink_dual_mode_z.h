#ifndef BLINK_DUAL_MODE_Z_H
#define BLINK_DUAL_MODE_Z_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ========================================================================= */
/* Dual-Mode Coordinate Semantics (Formally proven in BlinkDualModeZSemantics.v) */
/* ========================================================================= */
typedef enum {
    BLINK_MODE_SPEC = 0,     /* W3C CSS Spec standard: pure Z coordinates (scale = 1) */
    BLINK_MODE_CHROMIUM = 1  /* Chromium Blink engine: 26.6 LayoutUnits (scale = 64) */
} blink_layout_mode_t;

static inline int64_t blink_z_scale(blink_layout_mode_t mode) {
    return (mode == BLINK_MODE_CHROMIUM) ? 64 : 1;
}

static inline int64_t blink_z_from_pixel(int64_t px, blink_layout_mode_t mode) {
    return px * blink_z_scale(mode);
}

static inline int64_t blink_z_to_device_pixel(int64_t val, blink_layout_mode_t mode) {
    if (mode == BLINK_MODE_CHROMIUM) {
        return (val + 32) / 64; /* Blink LayoutUnit::Round() */
    }
    return val;
}

static inline int64_t blink_z_floor_device_pixel(int64_t val, blink_layout_mode_t mode) {
    if (mode == BLINK_MODE_CHROMIUM) {
        return val / 64; /* Blink LayoutUnit::Floor() */
    }
    return val;
}

static inline int64_t blink_z_ceil_device_pixel(int64_t val, blink_layout_mode_t mode) {
    if (mode == BLINK_MODE_CHROMIUM) {
        return (val + 63) / 64; /* Blink LayoutUnit::Ceil() */
    }
    return val;
}

static inline int64_t blink_z_mul_pct(int64_t avail, int64_t pct, blink_layout_mode_t mode) {
    (void)mode;
    return (avail * pct) / 100;
}

static inline int64_t blink_z_partition_boundary(int64_t total_w, int64_t total_cols, int64_t col_idx, blink_layout_mode_t mode) {
    if (mode == BLINK_MODE_CHROMIUM) {
        int64_t raw_total = total_w * 64;
        int64_t raw_col = (raw_total * col_idx) / total_cols;
        return (raw_col + 32) / 64;
    }
    return (total_w * col_idx) / total_cols;
}

#ifdef __cplusplus
}
#endif

#endif /* BLINK_DUAL_MODE_Z_H */

