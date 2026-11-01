/* ========================================================================= */
/* Blink Formal Engine: Pillars 2, 3 & 4 End-to-End C99 Verification Suite   */
/* Source: test_blink_pillars_2_3_4.c                                        */
/*                                                                           */
/* Verifies runtime C99 correspondence with:                                 */
/*   - BlinkCSS4InlineAndPositionedLayoutEngine.v                            */
/*   - BlinkHMHybrid_33_SelectorIsMaxSpec.v .. BlinkHMHybrid_44_Table...v    */
/* ========================================================================= */

#define _POSIX_C_SOURCE 200809L
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

#include "blink_html_css_formal.h"
#include "blink_layout_paint_formal.h"
#include "blink_skia_font_engine.h"

static int g_passed = 0;
static int g_failed = 0;

#define CHECK(cond, msg)                                                       \
    do {                                                                       \
        if (cond) {                                                            \
            g_passed++;                                                        \
        } else {                                                               \
            g_failed++;                                                        \
            fprintf(stderr, "  [FAIL] Line %d: %s\n", __LINE__, (msg));        \
        }                                                                      \
    } while (0)

static dom_node_t* find_by_id(dom_node_t* n, const char* id) {
    if (!n || !id) return NULL;
    if (n->id && strcmp(n->id, id) == 0) return n;
    for (int i = 0; i < n->num_children; i++) {
        dom_node_t* r = find_by_id(n->children[i], id);
        if (r) return r;
    }
    return NULL;
}

static bool rects_disjoint(const dom_node_t* a, const dom_node_t* b) {
    return (a->x + a->w <= b->x) || (b->x + b->w <= a->x) ||
           (a->y + a->h <= b->y) || (b->y + b->h <= a->y);
}

/* ------------------------------------------------------------------------- */
/* 1. Pillar 2: Selectors L4, Cascade L5/L6 (`revert-layer`, `@container`,   */
/*    `@scope`), `<link>`/`@import`, Nesting `&`, Math & `color-mix()`       */
/* ------------------------------------------------------------------------- */
static void test_pillar2_selectors_cascade_and_values(void) {
    /* Create temporary external + imported stylesheets */
    FILE* f_imp = fopen("/tmp/blink_p2_imported.css", "wb");
    if (f_imp) {
        fputs(".ext-target { padding-left: 18px; color: #112233; }\n", f_imp);
        fclose(f_imp);
    }
    FILE* f_ext = fopen("/tmp/blink_p2_linked.css", "wb");
    if (f_ext) {
        fputs("@layer base, theme, utilities;\n"
              "@import \"blink_p2_imported.css\" layer(base);\n"
              "@layer theme { .ext-target { color: #228844; } }\n"
              "@layer utilities { .ext-target { color: #990000; color: revert-layer; } }\n",
              f_ext);
        fclose(f_ext);
    }

    const char* html =
        "<!DOCTYPE html><html><head>"
        "<link rel=\"stylesheet\" href=\"blink_p2_linked.css\">"
        "<style>"
        "  /* :is() max-specificity (1,0,0) beats .box.featured (0,2,0) */"
        "  :is(.match-cls, #phantom-id) { width: 240px; }"
        "  .box.featured { width: 120px; }"
        "  /* General sibling ~, :not(), :has(), attr ^= $= *= ~= |= */"
        "  .lead ~ .follower:not(.skip)[data-kind^=\"pri\"][data-ext$=\".rs\"][data-mid*=\"core\"][data-tags~=\"coq\"][lang|=\"en\"] {"
        "    margin-top: 22px;"
        "  }"
        "  .card:has(> .alert-badge) { border: 3px solid #d93025; }"
        "  /* :nth-of-type(2n+1) & :last-of-type */"
        "  .mixed p:nth-of-type(2n+1) { padding-top: 9px; }"
        "  .mixed p:last-of-type { padding-bottom: 15px; }"
        "  /* CSS Nesting & + ::before / ::after */"
        "  .nest-host {"
        "    background: #f1f3f4;"
        "    & .nested-hit { padding-right: 17px; }"
        "    &::before { content: \"[PRE]\"; color: #1a73e8; }"
        "    &::after { content: \"[POST]\"; color: #188038; }"
        "  }"
        "  /* revert rolls author h2 font-size back to UA 21px */"
        "  h2.rev-head { font-size: 40px; font-size: revert; }"
        "  /* @container inline-size query */"
        "  .cq-wide { container-type: inline-size; width: 420px; }"
        "  .cq-narrow { container-type: inline-size; width: 200px; }"
        "  .cq-item { padding-left: 4px; }"
        "  @container (min-width: 320px) { .cq-item { padding-left: 28px; } }"
        "  /* @scope (.scope-card) to (.donut-hole) */"
        "  @scope (.scope-card) to (.donut-hole) {"
        "    .scoped-txt { margin-left: 19px; }"
        "  }"
        "  /* min(), max(), clamp(), hsl(), currentColor, color-mix() */"
        "  #math-box {"
        "    width: clamp(180px, 50%, 300px);"
        "    padding-top: min(12px, 30px);"
        "    padding-bottom: max(8px, 16px);"
        "    color: hsl(120, 100%, 25%);"
        "    border: 2px solid currentColor;"
        "    background-color: color-mix(in srgb, #ff0000 25%, #0000ff 75%);"
        "  }"
        "</style></head><body>"
        "  <div id=\"ext\" class=\"ext-target\">External + revert-layer</div>"
        "  <div id=\"is-max\" class=\"box featured match-cls\">Max spec</div>"
        "  <div>"
        "    <span class=\"lead\">L</span><b>mid</b>"
        "    <div id=\"sib\" class=\"follower\" data-kind=\"primary\" data-ext=\"lib.rs\" data-mid=\"x_core_y\" data-tags=\"z3 coq hm\" lang=\"en-US\">Hit</div>"
        "  </div>"
        "  <div id=\"has-yes\" class=\"card\"><span class=\"alert-badge\">!</span></div>"
        "  <div id=\"has-no\" class=\"card\"><span>ok</span></div>"
        "  <div class=\"mixed\"><span>s</span><p id=\"p1\">1</p><div>d</div><p id=\"p2\">2</p><p id=\"p3\">3</p></div>"
        "  <div id=\"nest\" class=\"nest-host\"><span id=\"nhit\" class=\"nested-hit\">Core</span></div>"
        "  <h2 id=\"rev-h2\" class=\"rev-head\">Heading</h2>"
        "  <div class=\"cq-wide\"><div id=\"cqi-w\" class=\"cq-item\">W</div></div>"
        "  <div class=\"cq-narrow\"><div id=\"cqi-n\" class=\"cq-item\">N</div></div>"
        "  <div class=\"scope-card\">"
        "    <p id=\"sc-in\" class=\"scoped-txt\">In donut</p>"
        "    <div class=\"donut-hole\"><p id=\"sc-out\" class=\"scoped-txt\">Excluded</p></div>"
        "  </div>"
        "  <div id=\"math-box\">Math &amp; Color</div>"
        "</body></html>";

    blink_css_stylesheet_t* sheet = (blink_css_stylesheet_t*)malloc(sizeof(blink_css_stylesheet_t));
    dom_node_t* doc = blink_parse_html5_document_ex(html, "/tmp", sheet);
    blink_css_resolve_document_styles(doc, sheet, 800, 600, BLINK_MODE_CHROMIUM);

    remove("/tmp/blink_p2_imported.css");
    remove("/tmp/blink_p2_linked.css");

    dom_node_t* ext = find_by_id(doc, "ext");
    CHECK(ext != NULL && ext->style.padding_left == 18, "<link> + @import layer(base) applied padding-left: 18px");
    CHECK(ext != NULL && ext->style.color == 0xFF228844u, "revert-layer rolled back @layer utilities to @layer theme (#228844)");

    dom_node_t* is_max = find_by_id(doc, "is-max");
    CHECK(is_max != NULL && is_max->style.width == 240, ":is(.match-cls, #phantom-id) max-specificity (1,0,0) beat .box.featured (0,2,0)");

    dom_node_t* sib = find_by_id(doc, "sib");
    CHECK(sib != NULL && sib->style.margin_top == 22, "General sibling ~ + :not() + [attr ^= $= *= ~= |=] matched");

    dom_node_t* has_yes = find_by_id(doc, "has-yes");
    dom_node_t* has_no = find_by_id(doc, "has-no");
    CHECK(has_yes != NULL && has_yes->style.border_width == 3, ":has(> .alert-badge) matched parent with direct child");
    CHECK(has_no != NULL && has_no->style.border_width == 0, ":has(> .alert-badge) rejected parent without matching child");

    dom_node_t* p1 = find_by_id(doc, "p1");
    dom_node_t* p2 = find_by_id(doc, "p2");
    dom_node_t* p3 = find_by_id(doc, "p3");
    CHECK(p1 && p2 && p3 && p1->style.padding_top == 9 && p2->style.padding_top == 0 && p3->style.padding_top == 9,
          ":nth-of-type(2n+1) counted only <p> siblings across interleaved tags");
    CHECK(p3 && p3->style.padding_bottom == 15 && p1->style.padding_bottom == 0, ":last-of-type matched final <p>");

    dom_node_t* nest = find_by_id(doc, "nest");
    dom_node_t* nhit = find_by_id(doc, "nhit");
    CHECK(nhit != NULL && nhit->style.padding_right == 17, "CSS Nesting `& .nested-hit` desugared and matched");
    CHECK(nest != NULL && nest->num_children == 3 && nest->children[0]->is_generated_pseudo && nest->children[2]->is_generated_pseudo,
          "::before and ::after materialized synthetic first/last inline children");

    dom_node_t* rev_h2 = find_by_id(doc, "rev-h2");
    CHECK(rev_h2 != NULL && fabsf(rev_h2->style.font_size - 22.0f) < 0.5f, "CSS `revert` restored UA <h2> font-size (22px)");

    dom_node_t* cqi_w = find_by_id(doc, "cqi-w");
    dom_node_t* cqi_n = find_by_id(doc, "cqi-n");
    CHECK(cqi_w && cqi_n && cqi_w->style.padding_left == 28 && cqi_n->style.padding_left == 4,
          "@container (min-width: 320px) matched inside 420px container and rejected 200px container");

    dom_node_t* sc_in = find_by_id(doc, "sc-in");
    dom_node_t* sc_out = find_by_id(doc, "sc-out");
    CHECK(sc_in && sc_out && sc_in->style.margin_left == 19 && sc_out->style.margin_left == 0,
          "@scope (.scope-card) to (.donut-hole) matched inside root and excluded limit subtree");

    dom_node_t* mbox = find_by_id(doc, "math-box");
    /* Parent content width is 800 - 32 = 768px -> 50% = 384px -> clamp(180, 384, 300) = 300px! */
    CHECK(mbox != NULL && mbox->style.width == 300, "clamp(180px, 50%, 300px) evaluated to upper bound 300px");
    CHECK(mbox != NULL && mbox->style.padding_top == 12 && mbox->style.padding_bottom == 16,
          "min(12px, 30px) -> 12px and max(8px, 16px) -> 16px");
    CHECK(mbox != NULL && mbox->style.color == 0xFF008000u && mbox->style.border_color == 0xFF008000u,
          "hsl(120, 100%, 25%) -> #008000 and border `currentColor` resolved to element color");
    /* color-mix(in srgb, #ff0000 25%, #0000ff 75%) -> R ~ 64, G = 0, B ~ 191 */
    uint32_t bg = mbox ? mbox->style.bg_color : 0;
    int r_ch = (int)((bg >> 16) & 0xFF), g_ch = (int)((bg >> 8) & 0xFF), b_ch = (int)(bg & 0xFF);
    CHECK(abs(r_ch - 64) <= 2 && g_ch == 0 && abs(b_ch - 191) <= 2,
          "color-mix(in srgb, #ff0000 25%, #0000ff 75%) interpolated RGB channels");

    dom_node_free(doc);
    free(sheet);
}

/* ------------------------------------------------------------------------- */
/* 2. Pillar 3: Multi-Span Inline Formatting Context (`blink_inline_frag_t`) */
/* ------------------------------------------------------------------------- */
static void test_pillar3_multispan_inline_formatting(void) {
    const char* html =
        "<style>"
        "  code.pill { background: #e8f0fe; padding: 2px 6px; border: 1px solid #1a73e8; }"
        "  p#rich::before { content: \"NOTE:\"; font-weight: bold; color: #b06000; }"
        "</style>"
        "<p id=\"rich\">Plain <b>bold</b> <i>italic</i> <a href=\"#x\">link</a> "
        "<code class=\"pill\">fn(x)</code> <s>old</s> X<sup>2</sup> H<sub>2</sub>O<br>Second line</p>"
        "<pre id=\"preblk\">  let a = 1;\n    let b = 2;</pre>";

    blink_css_stylesheet_t* sheet = (blink_css_stylesheet_t*)malloc(sizeof(blink_css_stylesheet_t));
    dom_node_t* doc = blink_parse_html5_document(html, sheet);
    blink_css_resolve_document_styles(doc, sheet, 800, 600, BLINK_MODE_CHROMIUM);
    blink_normalize_dom_for_layout(doc);
    int max_y = 0;
    blink_layout_dom_tree(doc, 16, 16, 768, 600, BLINK_MODE_CHROMIUM, &max_y);

    dom_node_t* rich = find_by_id(doc, "rich");
    CHECK(rich != NULL && rich->num_inline_frags >= 9, "Multi-span <p> preserved distinct styled inline fragments");

    if (rich && rich->num_inline_frags >= 9) {
        bool saw_pseudo = false, saw_bold = false, saw_italic = false, saw_link = false;
        bool saw_pill = false, saw_strike = false, saw_sup = false, saw_sub = false, saw_line2 = false;
        float plain_bl = -1.0f, sup_bl = -1.0f, sub_bl = -1.0f;

        for (int i = 0; i < rich->num_inline_frags; i++) {
            const blink_inline_frag_t* f = &rich->inline_frags[i];
            if (strcmp(f->text, "NOTE:") == 0 && f->font_weight >= 700) saw_pseudo = true;
            if (strstr(f->text, "Plain") != NULL) plain_bl = f->baseline_y;
            if (strcmp(f->text, "bold") == 0 && f->font_weight >= 700) saw_bold = true;
            if (strcmp(f->text, "italic") == 0 && f->font_style == 1) saw_italic = true;
            if (strcmp(f->text, "link") == 0 && f->underline && f->color == BLINK_COLOR_LINK_BLUE) saw_link = true;
            if (strcmp(f->text, "fn(x)") == 0 && f->has_bg && f->pad_left == 7 && f->border_width == 1) saw_pill = true;
            if (strcmp(f->text, "old") == 0 && f->line_through) saw_strike = true;
            if (strcmp(f->text, "2") == 0 && f->vertical_align == VALIGN_SUPER) { saw_sup = true; sup_bl = f->baseline_y; }
            if (strcmp(f->text, "2") == 0 && f->vertical_align == VALIGN_SUB) { saw_sub = true; sub_bl = f->baseline_y; }
            if (strstr(f->text, "Second line") != NULL && f->line_index >= 1) saw_line2 = true;
        }
        CHECK(saw_pseudo && saw_bold && saw_italic && saw_link, "Preserved ::before, <b>, <i>, and underlined <a>");
        CHECK(saw_pill && saw_strike && saw_line2, "Preserved inline <code> pill box, <s> line-through, and <br> break");
        CHECK(saw_sup && saw_sub && sup_bl < plain_bl && sub_bl > plain_bl,
              "<sup> shifted baseline upward and <sub> shifted baseline downward");
    }

    dom_node_t* preblk = find_by_id(doc, "preblk");
    CHECK(preblk != NULL && preblk->num_inline_frags == 2 &&
          strncmp(preblk->inline_frags[0].text, "  let a", 7) == 0 &&
          strncmp(preblk->inline_frags[1].text, "    let b", 9) == 0 &&
          preblk->inline_frags[1].y > preblk->inline_frags[0].y,
          "<pre> preserved exact leading indentation and newline break");

    dom_node_free(doc);
    free(sheet);
}

/* ------------------------------------------------------------------------- */
/* 3. Pillar 4A: Floats (`float: left/right` + `clear`), Out-of-Flow         */
/*    Positioning (`relative`/`absolute`/`fixed`), and Appendix E `z-index`  */
/* ------------------------------------------------------------------------- */
static void test_pillar4_floats_positioning_and_z_index(void) {
    const char* html =
        "<style>"
        "  #fl-left { float: left; width: 140px; height: 90px; background: #e8f0fe; }"
        "  #fl-clear { clear: both; height: 24px; background: #ceead6; }"
        "  #pos-cb { position: relative; width: 400px; height: 160px; background: #ffffff; }"
        "  #abs-stretch { position: absolute; left: 20px; right: 30px; top: 15px; bottom: 25px; background: #fce8e6; }"
        "  #rel-shift { position: relative; left: 25px; top: 14px; width: 100px; height: 30px; }"
        "  #after-rel { width: 100px; height: 30px; }"
        "  #fixed-badge { position: fixed; right: 18px; bottom: 12px; width: 90px; height: 36px; background: #1a73e8; }"
        "</style>"
        "<div id=\"bfc\">"
        "  <div id=\"fl-left\">Float</div>"
        "  <p id=\"wrap-p\">Wrapped inline text next to left float box</p>"
        "  <div id=\"fl-clear\">Cleared footer</div>"
        "</div>"
        "<div id=\"pos-cb\">"
        "  <div id=\"abs-stretch\">Stretched OOF</div>"
        "  <div id=\"rel-shift\">Shifted</div>"
        "  <div id=\"after-rel\">Unmoved sibling</div>"
        "</div>"
        "<div id=\"fixed-badge\">Fixed</div>";

    blink_css_stylesheet_t* sheet = (blink_css_stylesheet_t*)malloc(sizeof(blink_css_stylesheet_t));
    dom_node_t* doc = blink_parse_html5_document(html, sheet);
    blink_css_resolve_document_styles(doc, sheet, 800, 600, BLINK_MODE_CHROMIUM);
    blink_normalize_dom_for_layout(doc);
    int max_y = 0;
    blink_layout_dom_tree(doc, 16, 16, 768, 600, BLINK_MODE_CHROMIUM, &max_y);

    dom_node_t* fl_left = find_by_id(doc, "fl-left");
    dom_node_t* wrap_p = find_by_id(doc, "wrap-p");
    dom_node_t* fl_clear = find_by_id(doc, "fl-clear");
    CHECK(fl_left && wrap_p && wrap_p->num_inline_frags > 0 &&
          wrap_p->inline_frags[0].x >= (float)(fl_left->x + fl_left->w),
          "FloatExclusionSpace shifted wrapped inline line past `float: left` right edge");
    CHECK(fl_left && fl_clear && fl_clear->y >= fl_left->y + fl_left->h,
          "`clear: both` advanced block below active float bottom");

    dom_node_t* pos_cb = find_by_id(doc, "pos-cb");
    dom_node_t* abs_st = find_by_id(doc, "abs-stretch");
    dom_node_t* rel_sh = find_by_id(doc, "rel-shift");
    dom_node_t* aft_rel = find_by_id(doc, "after-rel");
    dom_node_t* fix_b = find_by_id(doc, "fixed-badge");

    CHECK(pos_cb && abs_st && abs_st->x == pos_cb->x + 20 && abs_st->w == 400 - 20 - 30 &&
          abs_st->y == pos_cb->y + 15 && abs_st->h == 160 - 15 - 25,
          "`position: absolute` inset-stretch resolved exact (x, y, w, h) inside positioned ancestor");
    CHECK(pos_cb && rel_sh && aft_rel &&
          rel_sh->x == pos_cb->x + 25 && rel_sh->y == pos_cb->y + 14 &&
          aft_rel->y == pos_cb->y + 30,
          "`position: relative` shifted box by (+25,+14) without displacing normal-flow sibling (`oof_zero_normal_flow_impact`)");
    CHECK(fix_b && fix_b->x == 800 - 18 - 90 && fix_b->y == 600 - 12 - 36,
          "`position: fixed` anchored box to viewport (800x600) insets");

    dom_node_free(doc);
    free(sheet);

    /* Direct RGBA Pixel Test for CSS 2.2 Appendix E 7-Phase `z-index` Paint Order */
    const char* z_html =
        "<div id=\"sc\" style=\"position:relative; z-index:0; width:200px; height:200px; background:#ffffff;\">"
        "  <div style=\"position:absolute; left:20px; top:20px; width:100px; height:100px; z-index:10; background:#ff0000;\"></div>"
        "  <div style=\"position:absolute; left:20px; top:20px; width:100px; height:100px; z-index:2;  background:#00ff00;\"></div>"
        "  <div style=\"margin-left:50px; width:120px; height:120px; background:#0000ff;\"></div>"
        "  <div style=\"position:absolute; left:10px; top:10px; width:160px; height:160px; z-index:-1; background:#ffff00;\"></div>"
        "</div>";

    sheet = (blink_css_stylesheet_t*)malloc(sizeof(blink_css_stylesheet_t));
    doc = blink_parse_html5_document(z_html, sheet);
    blink_css_resolve_document_styles(doc, sheet, 300, 300, BLINK_MODE_CHROMIUM);
    blink_normalize_dom_for_layout(doc);
    max_y = 0;
    blink_layout_dom_tree(doc, 0, 0, 300, 300, BLINK_MODE_CHROMIUM, &max_y);

    blink_framebuffer_t* fb = blink_fb_create(300, 300, 0xFFEEEEEEu);
    blink_paint_dom_stacking_context(doc, fb);

    dom_node_t* sc = find_by_id(doc, "sc");
    int sx = sc ? sc->x : 0;
    int sy = sc ? sc->y : 0;

    /* At (sx + 70, sy + 70): all 4 boxes overlap -> z-index: 10 (#ff0000, first in DOM!) MUST win Phase 7! */
    uint32_t px_top = fb->pixels[(sy + 70) * fb->width + (sx + 70)];
    CHECK(px_top == 0xFFFF0000u, "Appendix E Phase 7: DOM-first `z-index: 10` (#ff0000) painted on top of all lower layers");

    /* At (sx + 130, sy + 70): only in-flow Blue [50..170] and `z-index: -1` Yellow [10..170] overlap -> Phase 3 Blue beats Phase 2 Yellow! */
    uint32_t px_inflow = fb->pixels[(sy + 70) * fb->width + (sx + 130)];
    CHECK(px_inflow == 0xFF0000FFu, "Appendix E Phase 3 vs Phase 2: in-flow block (#0000ff) painted above `z-index: -1` (#ffff00)");

    /* At (sx + 15, sy + 70): only `z-index: -1` Yellow [10..170] and stacking context root White [0..200] -> Phase 2 Yellow beats Phase 1 White! */
    uint32_t px_negz = fb->pixels[(sy + 70) * fb->width + (sx + 15)];
    CHECK(px_negz == 0xFFFFFF00u, "Appendix E Phase 2 vs Phase 1: `z-index: -1` (#ffff00) painted above stacking context root background");

    blink_fb_destroy(fb);
    dom_node_free(doc);
    free(sheet);
}

/* ------------------------------------------------------------------------- */
/* 4. Pillar 4B: Complete Flex (`column`, `wrap`, `shrink`), Grid (`minmax`, */
/*    `span`), and 2D Table (`rowspan`+`colspan` + `border-collapse`)        */
/* ------------------------------------------------------------------------- */
static void test_pillar4_flex_grid_and_2d_table(void) {
    const char* html =
        "<style>"
        "  #fwrap { display: flex; flex-wrap: wrap; width: 450px; gap: 10px; row-gap: 12px; }"
        "  .fw-it { width: 200px; height: 30px; }"
        "  #fshrink { display: flex; width: 300px; }"
        "  #fs-1 { width: 200px; flex-shrink: 1; height: 24px; }"
        "  #fs-2 { width: 200px; flex-shrink: 3; min-width: 110px; height: 24px; }"
        "  #fcol { display: flex; flex-direction: column; width: 200px; gap: 8px; }"
        "  #grid { display: grid; width: 420px; grid-template-columns: minmax(180px, 1fr) 1fr 1fr; gap: 10px; row-gap: 8px; }"
        "  #g-span2 { grid-column: span 2; height: 28px; }"
        "  #tbl { border-collapse: collapse; width: 360px; border: 2px solid #202124; }"
        "  #tbl td { border: 1px solid #80868b; height: 32px; }"
        "</style>"
        "<div id=\"fwrap\"><div id=\"fw1\" class=\"fw-it\">1</div><div id=\"fw2\" class=\"fw-it\">2</div><div id=\"fw3\" class=\"fw-it\">3</div></div>"
        "<div id=\"fshrink\"><div id=\"fs-1\">A</div><div id=\"fs-2\">B</div></div>"
        "<div id=\"fcol\"><div id=\"fc1\" style=\"height:20px\">C1</div><div id=\"fc2\" style=\"height:25px\">C2</div></div>"
        "<div id=\"grid\"><div id=\"g0\" style=\"height:24px\">0</div><div id=\"g-span2\">1-2</div><div id=\"g3\" style=\"height:24px\">3</div></div>"
        "<table id=\"tbl\">"
        "  <tr><td id=\"t-r0c0\" rowspan=\"2\">R2</td><td id=\"t-r0c1\" colspan=\"2\">C2</td></tr>"
        "  <tr><td id=\"t-r1c1\">B1</td><td id=\"t-r1c2\">B2</td></tr>"
        "</table>";

    blink_css_stylesheet_t* sheet = (blink_css_stylesheet_t*)malloc(sizeof(blink_css_stylesheet_t));
    dom_node_t* doc = blink_parse_html5_document(html, sheet);
    blink_css_resolve_document_styles(doc, sheet, 800, 600, BLINK_MODE_CHROMIUM);
    blink_normalize_dom_for_layout(doc);
    int max_y = 0;
    blink_layout_dom_tree(doc, 16, 16, 768, 600, BLINK_MODE_CHROMIUM, &max_y);

    dom_node_t* fw1 = find_by_id(doc, "fw1");
    dom_node_t* fw2 = find_by_id(doc, "fw2");
    dom_node_t* fw3 = find_by_id(doc, "fw3");
    CHECK(fw1 && fw2 && fw3 && fw1->y == fw2->y && fw3->y >= fw1->y + 30 + 12 && fw3->x == fw1->x,
          "`flex-wrap: wrap` wrapped 3rd 200px item onto second flex line at row-gap 12px");

    dom_node_t* fs1 = find_by_id(doc, "fs-1");
    dom_node_t* fs2 = find_by_id(doc, "fs-2");
    /* Deficit = 400 - 300 = 100px; shrink weights 1:3 -> raw -25 / -75 -> fs1=175, fs2=max(125, 110)=125 */
    CHECK(fs1 && fs2 && fs1->w == 175 && fs2->w == 125,
          "`flex-shrink` weighted contraction distributed 100px deficit in 1:3 ratio (175px, 125px)");

    dom_node_t* fc1 = find_by_id(doc, "fc1");
    dom_node_t* fc2 = find_by_id(doc, "fc2");
    CHECK(fc1 && fc2 && fc1->x == fc2->x && fc2->y == fc1->y + 20 + 8,
          "`flex-direction: column` stacked items vertically with 8px gap");

    dom_node_t* g0 = find_by_id(doc, "g0");
    dom_node_t* gs2 = find_by_id(doc, "g-span2");
    dom_node_t* g3 = find_by_id(doc, "g3");
    /* 420px - 20px gaps = 400px -> 400/3 = 133px, so col 0 clamps up to minmax(180px, 1fr) = 180px! */
    CHECK(g0 && gs2 && g3 && g0->w >= 180 && gs2->x == g0->x + g0->w + 10 && g3->y > g0->y,
          "CSS Grid `minmax(180px, 1fr)` enforced 180px floor and `grid-column: span 2` spanned cols 1..2");

    dom_node_t* tr0c0 = find_by_id(doc, "t-r0c0");
    dom_node_t* tr0c1 = find_by_id(doc, "t-r0c1");
    dom_node_t* tr1c1 = find_by_id(doc, "t-r1c1");
    dom_node_t* tr1c2 = find_by_id(doc, "t-r1c2");
    CHECK(tr0c0 && tr0c1 && tr1c1 && tr1c2 &&
          rects_disjoint(tr0c0, tr0c1) && rects_disjoint(tr0c0, tr1c1) &&
          rects_disjoint(tr0c1, tr1c1) && rects_disjoint(tr1c1, tr1c2) &&
          tr1c1->x >= tr0c0->x + tr0c0->w && tr0c0->h == tr0c1->h + tr1c1->h,
          "2D Table occupancy grid placed simultaneous `rowspan=2` + `colspan=2` with zero overlap");

    /* Direct check of CSS 2.2 §17.6.2.1 `blink_resolve_collapsed_border` */
    blink_collapsed_border_edge_t e_hid = { 4, BDR_STYLE_HIDDEN, 0xFF000000u };
    blink_collapsed_border_edge_t e_w4  = { 4, BDR_STYLE_SOLID,  0xFFFF0000u };
    blink_collapsed_border_edge_t e_w2d = { 2, BDR_STYLE_DOUBLE, 0xFF00FF00u };
    blink_collapsed_border_edge_t e_w2s = { 2, BDR_STYLE_DASHED, 0xFF0000FFu };
    blink_collapsed_border_edge_t r1 = blink_resolve_collapsed_border(e_w4, e_hid);
    blink_collapsed_border_edge_t r2 = blink_resolve_collapsed_border(e_w2d, e_w4);
    blink_collapsed_border_edge_t r3 = blink_resolve_collapsed_border(e_w2s, e_w2d);
    CHECK(r1.style == BDR_STYLE_HIDDEN && r1.width == 0, "Collapsed border: `hidden` suppresses 4px solid");
    CHECK(r2.width == 4 && r2.color == 0xFFFF0000u, "Collapsed border: wider 4px solid beats 2px double");
    CHECK(r3.style == BDR_STYLE_DOUBLE && r3.color == 0xFF00FF00u, "Collapsed border: 2px double beats 2px dashed");

    dom_node_free(doc);
    free(sheet);
}

int main(void) {
    blink_skia_font_init();
    printf("==========================================================================\n");
    printf("Blink Formal Pillars 2, 3 & 4 End-to-End C99 Verification Suite\n");
    printf("==========================================================================\n");

    test_pillar2_selectors_cascade_and_values();
    test_pillar3_multispan_inline_formatting();
    test_pillar4_floats_positioning_and_z_index();
    test_pillar4_flex_grid_and_2d_table();

    printf("--------------------------------------------------------------------------\n");
    printf("Assertions Passed : %d\n", g_passed);
    printf("Assertions Failed : %d\n", g_failed);
    printf("Status            : %s\n",
           (g_failed == 0) ? "ALL PILLARS 2, 3 & 4 INVARIANTS VERIFIED (100%)" : "VERIFICATION FAILED");
    printf("==========================================================================\n");
    return (g_failed == 0) ? 0 : 1;
}
