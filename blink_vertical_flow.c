#include "blink_vertical_flow.h"

static inline int z_max(int a, int b) {
    return (a > b) ? a : b;
}

static inline int z_min(int a, int b) {
    return (a < b) ? a : b;
}

void blink_compute_vertical_flow(int initial_y,
                                 const blink_box_metrics_t* boxes,
                                 size_t count,
                                 blink_layout_fragment_t* out_fragments) {
    if (!boxes || !out_fragments) return;

    int cursor_y = initial_y;
    int margin_pos = 0;
    int margin_neg = 0;

    for (size_t i = 0; i < count; i++) {
        const blink_box_metrics_t* b = &boxes[i];

        // 1. Collapse with incoming top margin
        int top_pos = z_max(0, b->m_top);
        int top_neg = z_min(0, b->m_top);

        int eff_pos = z_max(margin_pos, top_pos);
        int eff_neg = z_min(margin_neg, top_neg);

        int collapsed_margin = eff_pos + eff_neg;

        // 2. Compute fragment positioning
        int child_y = cursor_y + collapsed_margin;
        int child_h = b->b_top + b->p_top + b->content_h + b->p_bottom + b->b_bottom;

        out_fragments[i].y = child_y;
        out_fragments[i].h = child_h;
        out_fragments[i].collapsed_margin = collapsed_margin;

        // 3. Advance cursor
        cursor_y = child_y + child_h;

        // 4. Reset margin strut to child's bottom margin
        margin_pos = z_max(0, b->m_bottom);
        margin_neg = z_min(0, b->m_bottom);
    }
}
