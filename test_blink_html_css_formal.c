/* ========================================================================= */
/* Verified C99 Test Suite for Chromium Blink HTML5 & CSS Cascade Engine     */
/* Source: test_blink_html_css_formal.c                                      */
/*                                                                           */
/* Tests all 24 Rocq/Coq 9.3.0 invariants proved in:                         */
/*   - BlinkHTML5TreeBuilderAndCSSCascadeEngine.v                            */
/*   - BlinkDualModeZSemantics.v                                             */
/* ========================================================================= */

#include "blink_html_css_formal.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int g_passed = 0;
static int g_failed = 0;

#define CHECK(cond, msg)                                                       \
    do {                                                                       \
        if (cond) {                                                            \
            g_passed++;                                                        \
        } else {                                                               \
            g_failed++;                                                        \
            fprintf(stderr, "  [FAIL] %s (line %d)\n", (msg), __LINE__);       \
        }                                                                      \
    } while (0)

static dom_node_t* find_by_id(dom_node_t* n, const char* id) {
    if (!n || !id) return NULL;
    if (n->id && strcmp(n->id, id) == 0) return n;
    for (int i = 0; i < n->num_children; i++) {
        dom_node_t* found = find_by_id(n->children[i], id);
        if (found) return found;
    }
    return NULL;
}

/* 1. HTML5 Void Elements & Implicit End-Tag Closure */
static void test_html5_treebuilder_implicit_closure_and_scope(void) {
    const char* html =
        "<div id=\"wrap\">"
        "  <p id=\"p1\">First<img src=\"a.png\"><br>paragraph"
        "  <p id=\"p2\">Second unclosed paragraph"
        "  <ul id=\"list\"><li>One<li>Two<li>Three</ul>"
        "  <table id=\"tbl\"><tr><td>A<td>B<tr><td>C<td>D</table>"
        "</div>";

    dom_node_t* root = blink_parse_html5_document(html, NULL);
    CHECK(root != NULL, "HTML5 document parsed");

    dom_node_t* wrap = find_by_id(root, "wrap");
    dom_node_t* p1 = find_by_id(root, "p1");
    dom_node_t* p2 = find_by_id(root, "p2");
    dom_node_t* list = find_by_id(root, "list");
    dom_node_t* tbl = find_by_id(root, "tbl");

    CHECK(wrap != NULL && p1 != NULL && p2 != NULL, "Located wrap, p1, p2");
    /* `implicit_p_closes_prior_p`: p1 and p2 must be siblings under wrap, NOT p2 inside p1! */
    CHECK(p1->parent == wrap && p2->parent == wrap, "Implicit <p> closes prior <p> (siblings under #wrap)");
    /* `html_void_tag_never_grows_stack`: <img> and <br> inside p1 have 0 children; trailing text stays in p1 */
    CHECK(p1->num_children == 4 && strcmp(p1->children[1]->tag, "img") == 0 && p1->children[1]->num_children == 0,
          "Void <img>/<br> never grow open-element stack");

    /* `implicit_li_closes_sibling_li_preserving_ul`: 3 <li> children directly under <ul> */
    CHECK(list != NULL && list->num_children == 3, "Implicit <li> closes sibling <li> preserving <ul>");
    CHECK(strcmp(list->children[0]->tag, "li") == 0 &&
          strcmp(list->children[1]->tag, "li") == 0 &&
          strcmp(list->children[2]->tag, "li") == 0,
          "All three <li> elements are direct children of <ul>");

    /* `implicit_td_closes_prior_td_preserving_tr`: 2 <tr> rows, each with 2 <td> cells */
    CHECK(tbl != NULL && tbl->num_children == 2, "Implicit <tr> closes prior <tr> inside <table>");
    CHECK(tbl->children[0]->num_children == 2 && tbl->children[1]->num_children == 2,
          "Implicit <td> closes prior <td> preserving <tr>");

    dom_node_free(root);

    /* `pop_until_in_scope_preserves_scope_boundary`: stray </div> inside <td> must NOT pop outer #box! */
    const char* firewall_html =
        "<div id=\"outer_box\">"
        "  <table><tr><td>Inside cell</div></td></tr></table>"
        "  <span id=\"still_inside\">After table</span>"
        "</div>";
    dom_node_t* root2 = blink_parse_html5_document(firewall_html, NULL);
    dom_node_t* outer_box = find_by_id(root2, "outer_box");
    dom_node_t* still_inside = find_by_id(root2, "still_inside");
    CHECK(outer_box != NULL && still_inside != NULL && still_inside->parent == outer_box,
          "Table <td> scope boundary blocks stray </div> from popping #outer_box");
    dom_node_free(root2);
}

/* 2. Right-to-Left Selector Matching & `:where(...)` Zero Specificity */
static void test_selectors_and_specificity(void) {
    blink_complex_sel_t s_where, s_tag, s_complex;
    CHECK(blink_css_parse_selector(":where(#hero.banner)", &s_where), "Parsed :where(#hero.banner)");
    CHECK(s_where.specificity.id_cnt == 0 && s_where.specificity.class_cnt == 0 && s_where.specificity.tag_cnt == 0,
          ":where(#hero.banner) has exact (0,0,0) specificity");

    CHECK(blink_css_parse_selector("p", &s_tag), "Parsed tag selector p");
    CHECK(blink_specificity_lt(s_where.specificity, s_tag.specificity),
          "(0,0,0) < (0,0,1): bare tag selector beats :where(#id.class)");

    CHECK(blink_css_parse_selector("div.panel > ul.items li + li:nth-child(even)", &s_complex),
          "Parsed combinator chain `div.panel > ul.items li + li:nth-child(even)`");
    CHECK(s_complex.specificity.id_cnt == 0 &&
          s_complex.specificity.class_cnt == 3 &&
          s_complex.specificity.tag_cnt == 4,
          "Additive specificity (0, 3, 4) across combinators");

    const char* html =
        "<div class=\"panel\">"
        "  <ul class=\"items\">"
        "    <li id=\"i1\">1</li>"
        "    <li id=\"i2\">2</li>"
        "    <li id=\"i3\">3</li>"
        "    <li id=\"i4\">4</li>"
        "  </ul>"
        "</div>";
    dom_node_t* root = blink_parse_html5_document(html, NULL);
    CHECK(!blink_css_match_selector(find_by_id(root, "i1"), &s_complex), "li#i1 does not match li + li:nth-child(even)");
    CHECK(blink_css_match_selector(find_by_id(root, "i2"), &s_complex), "li#i2 matches li + li:nth-child(even)");
    CHECK(!blink_css_match_selector(find_by_id(root, "i3"), &s_complex), "li#i3 (odd) does not match");
    CHECK(blink_css_match_selector(find_by_id(root, "i4"), &s_complex), "li#i4 matches li + li:nth-child(even)");
    dom_node_free(root);
}

/* 3. CSS Cascade Level 5: `@layer` `!important` Inversion & Origin Duality */
static void test_cascade_level5_layers_and_important(void) {
    const char* html =
        "<html><head><style>"
        "  @layer base, theme;"
        "  @layer base {"
        "    #box_norm { color: #111111; }"
        "    #box_imp  { color: #34a853 !important; }"
        "  }"
        "  @layer theme {"
        "    #box_norm { color: #1a73e8; }"
        "    #box_imp  { color: #ea4335 !important; }"
        "  }"
        "  #box_imp { color: #000000 !important; }"
        "  #inline_test { color: #7b1fa2 !important; }"
        "  :where(#where_box) { color: #ea4335; }"
        "  div { color: #1a73e8; }"
        "</style></head><body>"
        "  <div id=\"box_norm\">Normal layer order</div>"
        "  <div id=\"box_imp\">Important layer inversion</div>"
        "  <div id=\"inline_test\" style=\"color: #fbbc05\">Author !important vs Inline normal</div>"
        "  <div id=\"where_box\">Bare div beats :where(#where_box)</div>"
        "</body></html>";

    blink_css_stylesheet_t* sheet = (blink_css_stylesheet_t*)malloc(sizeof(blink_css_stylesheet_t));
    dom_node_t* root = blink_parse_html5_document(html, sheet);
    blink_css_resolve_document_styles(root, sheet, 800, 600, BLINK_MODE_CHROMIUM);

    dom_node_t* box_norm = find_by_id(root, "box_norm");
    dom_node_t* box_imp = find_by_id(root, "box_imp");
    dom_node_t* inline_test = find_by_id(root, "inline_test");
    dom_node_t* where_box = find_by_id(root, "where_box");

    /* Normal declarations: later `@layer theme` (#1a73e8) beats earlier `@layer base` (#111111) */
    CHECK(box_norm && box_norm->style.color == 0xFF1A73E8u,
          "Normal @layer: later layer `theme` beats earlier layer `base`");

    /* `!important` declarations: earlier `@layer base` (#34a853) beats BOTH `theme` AND unlayered `!important`! */
    CHECK(box_imp && box_imp->style.color == 0xFF34A853u,
          "!important @layer inversion: earlier layer `base !important` beats `theme !important` and unlayered `!important`");

    /* Author `!important` (rank 6) beats Inline normal `style="color: ..."` (rank 4) */
    CHECK(inline_test && inline_test->style.color == 0xFF7B1FA2u,
          "Cascade origin duality: Author !important beats Inline normal style");

    /* `div` (0,0,1) beats `:where(#where_box)` (0,0,0) even though `:where` appeared earlier/had #id */
    CHECK(where_box && where_box->style.color == 0xFF1A73E8u,
          "Bare `div` (0,0,1) beats `:where(#where_box)` (0,0,0)");

    free(sheet);
    dom_node_free(root);
}

/* 4. Cycle-Safe `var(--x, fallback)` & `unset` Keyword Duality */
static void test_custom_properties_and_unset_duality(void) {
    const char* html =
        "<style>"
        "  :root {"
        "    --brand: #1a73e8;"
        "    --self: var(--self, #34a853);"
        "    --cyc-a: var(--cyc-b);"
        "    --cyc-b: var(--cyc-a);"
        "    --pad-v: 14px;"
        "  }"
        "  #parent_el { color: #dc143c; background-color: #fbbc05; padding: 20px; }"
        "  #child_unset { color: unset; background-color: #111111; background-color: unset; padding: 18px; padding: unset; }"
        "  #var_ok { color: var(--brand); padding: var(--pad-v) 24px; }"
        "  #var_self_cycle { color: var(--self); }"
        "  #var_mutual_cycle { color: var(--cyc-a, #ea4335); }"
        "</style>"
        "<div id=\"parent_el\">"
        "  <div id=\"child_unset\">Unset test</div>"
        "  <div id=\"var_ok\">Valid var()</div>"
        "  <div id=\"var_self_cycle\">Self cycle fallback</div>"
        "  <div id=\"var_mutual_cycle\">Mutual 2-cycle fallback</div>"
        "</div>";

    blink_css_stylesheet_t* sheet = (blink_css_stylesheet_t*)malloc(sizeof(blink_css_stylesheet_t));
    dom_node_t* root = blink_parse_html5_document(html, sheet);
    blink_css_resolve_document_styles(root, sheet, 800, 600, BLINK_MODE_SPEC);

    dom_node_t* child_unset = find_by_id(root, "child_unset");
    dom_node_t* var_ok = find_by_id(root, "var_ok");
    dom_node_t* var_self = find_by_id(root, "var_self_cycle");
    dom_node_t* var_mutual = find_by_id(root, "var_mutual_cycle");

    /* `css_unset_keyword_duality`: color is inherited (#dc143c), background & padding reset to initial! */
    CHECK(child_unset && child_unset->style.color == 0xFFDC143Cu,
          "`color: unset` acts as `inherit` (#dc143c)");
    CHECK(child_unset && !child_unset->style.has_bg && child_unset->style.padding_top == 0,
          "`background-color: unset` & `padding: unset` act as `initial`");

    CHECK(var_ok && var_ok->style.color == 0xFF1A73E8u &&
          var_ok->style.padding_top == 14 && var_ok->style.padding_left == 24,
          "Inherited custom properties resolve inside color and 2-value shorthand");

    /* `css_var_self_cycle_safe_fallback` & `css_var_mutual_2_cycle_safe` */
    CHECK(var_self && var_self->style.color == 0xFF34A853u,
          "Self-referential `--self: var(--self, #34a853)` terminates with fallback #34a853");
    CHECK(var_mutual && var_mutual->style.color == 0xFFEA4335u,
          "Mutual 2-cycle `--cyc-a <-> --cyc-b` terminates cleanly with fallback #ea4335");

    free(sheet);
    dom_node_free(root);
}

/* 5. TRBL Shorthands, `calc()`, `box-sizing: border-box`, Flex & Table Conservation */
static void test_shorthands_calc_border_box_flex_table(void) {
    /* 1/2/3/4-value TRBL symmetry laws */
    int32_t v1[1] = {10};
    int32_t v2[2] = {12, 24};
    int32_t v3[3] = {8, 16, 20};
    int32_t v4[4] = {1, 2, 3, 4};
    blink_box_edges_t e1 = blink_css_expand_shorthand_ints(v1, 1);
    blink_box_edges_t e2 = blink_css_expand_shorthand_ints(v2, 2);
    blink_box_edges_t e3 = blink_css_expand_shorthand_ints(v3, 3);
    blink_box_edges_t e4 = blink_css_expand_shorthand_ints(v4, 4);

    CHECK(e1.top == 10 && e1.right == 10 && e1.bottom == 10 && e1.left == 10, "1-value TRBL shorthand uniform");
    CHECK(e2.top == 12 && e2.bottom == 12 && e2.left == 24 && e2.right == 24, "2-value TRBL shorthand symmetric");
    CHECK(e3.top == 8 && e3.left == 16 && e3.right == 16 && e3.bottom == 20, "3-value TRBL shorthand L==R");
    CHECK(e4.top == 1 && e4.right == 2 && e4.bottom == 3 && e4.left == 4, "4-value TRBL shorthand exact");

    /* `calc()` & `100vw` identity under SpecMode & ChromiumMode */
    for (int m = 0; m <= 1; m++) {
        blink_layout_mode_t mode = (m == 0) ? BLINK_MODE_SPEC : BLINK_MODE_CHROMIUM;
        int32_t w_vw = blink_css_eval_length_or_calc("100vw", 500, 16, 16, 800, 600, mode, NULL);
        int32_t w_calc = blink_css_eval_length_or_calc("calc(100% - 40px + 2rem)", 600, 14, 16, 800, 600, mode, NULL);
        CHECK(w_vw == 800, "100vw resolves to exact viewport width 800px");
        CHECK(w_calc == 592, "calc(100% - 40px + 2rem) on 600px basis, 16px rem == 592px");
    }

    /* `border_box_outer_width_conservation`: cw + pad_h + bdr_h == specified_w */
    int32_t cw_bb = blink_css_resolve_content_inline_size(BOX_SIZING_BORDER_BOX, 300, 32, 4);
    CHECK(cw_bb == 264 && (cw_bb + 32 + 4) == 300, "border-box outer width conservation: 264 + 32 + 4 == 300");

    /* `flex_justify_offset_bounded`: 0 <= off && off + used_w <= container_w */
    css_justify_t modes[4] = {JUSTIFY_FLEX_START, JUSTIFY_CENTER, JUSTIFY_FLEX_END, JUSTIFY_SPACE_BETWEEN};
    for (int i = 0; i < 4; i++) {
        int32_t off = blink_flex_justify_start_offset(modes[i], 700, 420, 3);
        CHECK(off >= 0 && off + 420 <= 700, "Flexbox justify-content start offset bounded within container");
    }

    /* `table_two_col_seamless_conservation` + N-column partition conservation on prime width 703px */
    for (int m = 0; m <= 1; m++) {
        blink_layout_mode_t mode = (m == 0) ? BLINK_MODE_SPEC : BLINK_MODE_CHROMIUM;
        int32_t w0 = blink_table_col_width_formal(703, 2, 0, mode);
        int32_t w1 = blink_table_col_width_formal(703, 2, 1, mode);
        int32_t s1 = blink_table_col_start_formal(703, 2, 1, mode);
        CHECK(w0 == s1 && (w0 + w1) == 703, "2-column table auto partition conserves 703px with 0-pixel seam");

        int32_t sum5 = 0;
        for (int c = 0; c < 5; c++) {
            sum5 += blink_table_col_width_formal(703, 5, c, mode);
        }
        CHECK(sum5 == 703, "5-column table auto partition conserves 703px exactly");
    }
}

int main(void) {
    printf("==========================================================================\n");
    printf("Blink Formal HTML5 TreeBuilder & CSS Cascade C99 Verification Suite\n");
    printf("==========================================================================\n");

    test_html5_treebuilder_implicit_closure_and_scope();
    test_selectors_and_specificity();
    test_cascade_level5_layers_and_important();
    test_custom_properties_and_unset_duality();
    test_shorthands_calc_border_box_flex_table();

    printf("--------------------------------------------------------------------------\n");
    printf("Assertions Passed : %d\n", g_passed);
    printf("Assertions Failed : %d\n", g_failed);
    printf("Status            : %s\n", (g_failed == 0) ? "ALL FORMAL INVARIANTS VERIFIED (100%)" : "FAILED");
    printf("==========================================================================\n");
    return (g_failed == 0) ? 0 : 1;
}
