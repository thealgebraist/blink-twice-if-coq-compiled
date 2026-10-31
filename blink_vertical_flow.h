#ifndef BLINK_VERTICAL_FLOW_H
#define BLINK_VERTICAL_FLOW_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    int content_h;
    int m_top;
    int m_bottom;
    int p_top;
    int p_bottom;
    int b_top;
    int b_bottom;
} blink_box_metrics_t;

typedef struct {
    int y;
    int h;
    int collapsed_margin;
} blink_layout_fragment_t;

/**
 * Computes inductive vertical flow layout per W3C CSS 2.2 §8.3.1, §9.4.1
 * and Blink's NGBlockLayoutAlgorithm (MarginStrut).
 * 
 * Verified sound in Rocq/Coq (BlinkVerticalFlowLayoutSemantics.v).
 */
void blink_compute_vertical_flow(int initial_y,
                                 const blink_box_metrics_t* boxes,
                                 size_t count,
                                 blink_layout_fragment_t* out_fragments);

#ifdef __cplusplus
}
#endif

#endif // BLINK_VERTICAL_FLOW_H

