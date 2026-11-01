/* ========================================================================= */
/* Comprehensive Verification Suite for Pillars 1 & 5:                       */
/*   - Pillar 1: WHATWG HTML5 Numeric/Named CharRefs, Table Recovery,        */
/*               Foster Parenting, Noah's Ark & Adoption Agency Algorithm    */
/*   - Pillar 5: Skia SkRRect SDF Rounded Corners, Outer Drop Shadows,       */
/*               CSS Linear Gradients, Atomic Group Opacity,                 */
/*               Overflow Hidden Rounded Clipping & 2D CSS Transforms        */
/* ========================================================================= */

#define _POSIX_C_SOURCE 200809L
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

#include "blink_html_css_formal.h"
#include "blink_layout_paint_formal.h"

static int g_passed = 0;
static int g_failed = 0;
static blink_css_stylesheet_t g_sheet;

#define ASSERT_TRUE(cond, msg) do { \
    if (cond) { \
        g_passed++; \
        printf("  [PASS] %s\n", msg); \
    } else { \
        g_failed++; \
        printf("  [FAIL] %s (line %d)\n", msg, __LINE__); \
    } \
} while (0)

static dom_node_t* find_by_id(dom_node_t* n, const char* id) {
    if (!n || !id) return NULL;
    if (n->id && strcmp(n->id, id) == 0) return n;
    for (int i = 0; i < n->num_children; i++) {
        dom_node_t* f = find_by_id(n->children[i], id);
        if (f) return f;
    }
    return NULL;
}

static dom_node_t* find_first_tag(dom_node_t* n, const char* tag) {
    if (!n || !tag) return NULL;
    if (strcmp(n->tag, tag) == 0) return n;
    for (int i = 0; i < n->num_children; i++) {
        dom_node_t* f = find_first_tag(n->children[i], tag);
        if (f) return f;
    }
    return NULL;
}

static int max_tag_nesting_depth(const dom_node_t* n, const char* tag) {
    if (!n) return 0;
    int self = (strcmp(n->tag, tag) == 0) ? 1 : 0;
    int best_child = 0;
    for (int i = 0; i < n->num_children; i++) {
        int d = max_tag_nesting_depth(n->children[i], tag);
        if (d > best_child) best_child = d;
    }
    return self + best_child;
}

/* ------------------------------------------------------------------------- */
/* 1. Pillar 1 Tests: CharRefs, Table Recovery, Foster Parenting & AAA       */
/* ------------------------------------------------------------------------- */

static void test_char_refs(void) {
    printf("\n--- 1. WHATWG Numeric & Extended Named Character References ---\n");
    ASSERT_TRUE(blink_html_sanitize_char_ref(0) == 0xFFFD,
                "Null numeric reference &#0; sanitizes to U+FFFD");
    ASSERT_TRUE(blink_html_sanitize_char_ref(0xD800) == 0xFFFD &&
                blink_html_sanitize_char_ref(0xDFFF) == 0xFFFD,
                "UTF-16 surrogate codepoints [0xD800..0xDFFF] sanitize to U+FFFD");
    ASSERT_TRUE(blink_html_sanitize_char_ref(0x110000) == 0xFFFD,
                "Out-of-range scalar > U+10FFFF sanitizes to U+FFFD");
    ASSERT_TRUE(blink_html_sanitize_char_ref(0x00A9) == 0x00A9 &&
                blink_html_sanitize_char_ref(0x2192) == 0x2192,
                "Valid Unicode scalars pass through unchanged");

    char* u = blink_unescape_html("&#169; &#x00A7; &#x2192; &plusmn; &le; &ge; &ne; &#0; &#xD800;");
    ASSERT_TRUE(u != NULL, "blink_unescape_html allocates decoded UTF-8 buffer");
    if (u) {
        ASSERT_TRUE(strstr(u, "\xC2\xA9") != NULL && strstr(u, "\xC2\xA7") != NULL,
                    "Decimal &#169; (©) and Hex &#x00A7; (§) decode to exact UTF-8");
        ASSERT_TRUE(strstr(u, "\xE2\x86\x92") != NULL &&
                    strstr(u, "\xC2\xB1") != NULL &&
                    strstr(u, "\xE2\x89\xA4") != NULL &&
                    strstr(u, "\xE2\x89\xA5") != NULL &&
                    strstr(u, "\xE2\x89\xA0") != NULL,
                    "Extended named/hex math & arrow entities (→ ± ≤ ≥ ≠) decode cleanly");
        ASSERT_TRUE(strstr(u, "\xEF\xBF\xBD") != NULL,
                    "Invalid numeric char refs &#0; and &#xD800; emit UTF-8 U+FFFD");
        free(u);
    }
}

static void test_table_recovery_and_foster_parenting(void) {
    printf("\n--- 2. WHATWG Table Structural Recovery & Foster Parenting ---\n");

    /* Implicit <tbody> and <tr> synthesis */
    dom_node_t* doc1 = blink_parse_html5_document("<table><td>Alpha</td><td>Beta</td></table>", &g_sheet);
    dom_node_t* tbl1 = find_first_tag(doc1, "table");
    ASSERT_TRUE(tbl1 != NULL && tbl1->num_children == 1 &&
                strcmp(tbl1->children[0]->tag, "tbody") == 0,
                "<table><td>... synthesizes implicit <tbody>");
    if (tbl1 && tbl1->num_children == 1) {
        dom_node_t* tb = tbl1->children[0];
        ASSERT_TRUE(tb->num_children == 1 && strcmp(tb->children[0]->tag, "tr") == 0 &&
                    tb->children[0]->num_children == 2,
                    "Implicit <tr> wraps both sibling <td> cells inside synthesized <tbody>");
    }
    dom_node_free(doc1);

    /* Foster parenting of misnested <div> and stray text before <table> */
    dom_node_t* doc2 = blink_parse_html5_document(
        "<table><div id=\"foster\">Banner</div>Stray<tr><td id=\"cell\"><div id=\"inside\">OK</div></td></tr></table>",
        &g_sheet);
    int idx_foster = -1, idx_stray = -1, idx_table = -1;
    for (int i = 0; i < doc2->num_children; i++) {
        dom_node_t* ch = doc2->children[i];
        if (ch->id && strcmp(ch->id, "foster") == 0) idx_foster = i;
        else if (strcmp(ch->tag, "#text") == 0 && ch->text && strstr(ch->text, "Stray")) idx_stray = i;
        else if (strcmp(ch->tag, "table") == 0) idx_table = i;
    }
    ASSERT_TRUE(idx_foster >= 0 && idx_table > idx_foster,
                "Misnested <div id='foster'> inside <table> is foster-parented BEFORE <table>");
    ASSERT_TRUE(idx_stray >= 0 && idx_table > idx_stray,
                "Stray non-whitespace text inside <table> is foster-parented BEFORE <table>");
    dom_node_t* cell = find_by_id(doc2, "cell");
    dom_node_t* inside = find_by_id(doc2, "inside");
    ASSERT_TRUE(cell != NULL && inside != NULL && inside->parent == cell,
                "Subsequent <tr><td> still parses inside <table> and <td> scopes non-fostered children");
    dom_node_free(doc2);
}

static void test_noahs_ark_and_adoption_agency(void) {
    printf("\n--- 3. Active Formatting Elements, Noah's Ark & Adoption Agency ---\n");

    /* Noah's Ark Clause: <= 3 identical active formatting signatures */
    dom_node_t* ark = blink_parse_html5_document(
        "<p id=\"p1\"><b class=\"dup\"><b class=\"dup\"><b class=\"dup\"><b class=\"dup\">One</p>"
        "<p id=\"p2\">Two</p>",
        &g_sheet);
    dom_node_t* p2 = find_by_id(ark, "p2");
    int reconstructed_b_depth = max_tag_nesting_depth(p2, "b");
    ASSERT_TRUE(p2 != NULL && reconstructed_b_depth == 3,
                "Noah's Ark caps reconstructed identical <b class='dup'> tags in <p id='p2'> to exactly 3");
    dom_node_free(ark);

    /* Adoption Agency Case A: <p id="ca"><b>Bold <i>Both</b> ItalicOnly</i></p> */
    dom_node_t* doc_a = blink_parse_html5_document(
        "<p id=\"ca\"><b>Bold <i>Both</b> ItalicOnly</i></p>", &g_sheet);
    dom_node_t* ca = find_by_id(doc_a, "ca");
    ASSERT_TRUE(ca != NULL && ca->num_children == 2 &&
                strcmp(ca->children[0]->tag, "b") == 0 &&
                strcmp(ca->children[1]->tag, "i") == 0,
                "AAA Case A splits <b>Bold <i>Both</b> ItalicOnly</i> into sibling <b> and reconstructed <i>");
    dom_node_free(doc_a);

    /* Adoption Agency Case B: <div id="wrap"><b>1<p id="fb">2</b>3</p></div> */
    dom_node_t* doc_b = blink_parse_html5_document(
        "<div id=\"wrap\"><b>1<p id=\"fb\">2</b>3</p></div>", &g_sheet);
    dom_node_t* wrap = find_by_id(doc_b, "wrap");
    dom_node_t* fb_p = find_by_id(doc_b, "fb");
    ASSERT_TRUE(wrap != NULL && fb_p != NULL && fb_p->parent == wrap &&
                wrap->num_children == 2 && strcmp(wrap->children[0]->tag, "b") == 0,
                "AAA Case B reparents furthest block <p id='fb'> to common ancestor <div id='wrap'>");
    ASSERT_TRUE(fb_p != NULL && fb_p->num_children == 2 &&
                strcmp(fb_p->children[0]->tag, "b") == 0 &&
                strcmp(fb_p->children[1]->tag, "#text") == 0,
                "AAA Case B wraps '2' in cloned <b> inside <p id='fb'> while '3' follows outside <b>");
    dom_node_free(doc_b);
}

/* ------------------------------------------------------------------------- */
/* 2. Pillar 5 Tests: SkRRect SDF, Shadow, Gradient, Opacity, Clip, Transform*/
/* ------------------------------------------------------------------------- */

static void test_rrect_and_sdf_primitives(void) {
    printf("\n--- 4. Skia SkRRect Radius Clamping & Subpixel SDF Anti-Aliasing ---\n");
    ASSERT_TRUE(blink_clamp_corner_radius(100, 40, 50) == 20 &&
                blink_clamp_corner_radius(100, 40, -10) == 0,
                "blink_clamp_corner_radius clamps r into [0, min(w, h)/2]");
    ASSERT_TRUE(blink_sdf_alpha_255(-200) == 255 &&
                blink_sdf_alpha_255(200) == 0 &&
                blink_sdf_alpha_255(0) == 127,
                "blink_sdf_alpha_255 matches Gallina Q8 signed-distance coverage ramp");

    blink_framebuffer_t* fb = blink_fb_create(160, 100, 0xFFFFFFFFu);
    blink_fb_fill_rrect(fb, 20, 20, 100, 60, 24, 0xFFFF0000u);
    uint32_t px_corner = fb->pixels[20 * fb->width + 20];
    uint32_t px_center = fb->pixels[50 * fb->width + 70];
    /* Arc boundary of top-left circle (cx=44, cy=44, r=24): at (26, 27), hypot(17.5, 16.5) = 24.05 -> sd = +0.052 (AA!) */
    uint32_t px_arc = fb->pixels[27 * fb->width + 26];
    uint32_t arc_g = (px_arc >> 8) & 0xFFu;
    ASSERT_TRUE(px_corner == 0xFFFFFFFFu && px_center == 0xFFFF0000u,
                "SkRRect fill leaves outer corner (20,20) white and interior center pure red");
    ASSERT_TRUE(arc_g > 0u && arc_g < 255u,
                "SkRRect circular arc boundary produces smooth subpixel anti-aliased coverage");
    blink_fb_destroy(fb);
}

static void test_box_shadow_and_linear_gradient(void) {
    printf("\n--- 5. Outer Drop Shadows & Multi-Stop CSS Linear Gradients ---\n");
    const char* html =
        "<style>"
        "body { padding: 20px; }"
        "#card { width: 160px; height: 60px; border-radius: 14px; overflow: hidden;"
        "        background: #ffffff; box-shadow: 0px 10px 14px 0px rgba(0, 0, 0, 0.55); }"
        "#grad { margin-top: 36px; width: 200px; height: 40px; border-radius: 8px;"
        "        background: linear-gradient(to right, #ff0000, #00ff00 50%, #0000ff); }"
        "</style>"
        "<div id=\"card\"></div>"
        "<div id=\"grad\"></div>";

    dom_node_t* root = blink_parse_html5_document(html, &g_sheet);
    blink_css_resolve_document_styles(root, &g_sheet, 320, 260, BLINK_MODE_SPEC);
    blink_normalize_dom_for_layout(root);
    int max_y = 0;
    blink_layout_dom_tree(root, 0, 0, 320, 260, BLINK_MODE_SPEC, &max_y);

    blink_framebuffer_t* fb = blink_fb_create(320, 260, 0xFFFFFFFFu);
    blink_paint_dom_stacking_context(root, fb);

    dom_node_t* card = find_by_id(root, "card");
    dom_node_t* grad = find_by_id(root, "grad");
    ASSERT_TRUE(card != NULL && grad != NULL, "Located #card and #grad in laid-out DOM");
    if (card && grad) {
        int sx = card->x + card->w / 2;
        uint32_t sh_near = fb->pixels[(card->y + card->h + 5) * fb->width + sx];
        uint32_t sh_far  = fb->pixels[(card->y + card->h + 15) * fb->width + sx];
        uint32_t near_r = (sh_near >> 16) & 0xFFu;
        uint32_t far_r  = (sh_far >> 16) & 0xFFu;
        ASSERT_TRUE(near_r < 220u && far_r > near_r && far_r < 255u,
                    "Outer box-shadow renders smooth falloff outside overflow:hidden card");

        int gy = grad->y + grad->h / 2;
        uint32_t gl = fb->pixels[gy * fb->width + (grad->x + 6)];
        uint32_t gm = fb->pixels[gy * fb->width + (grad->x + grad->w / 2)];
        uint32_t gr = fb->pixels[gy * fb->width + (grad->x + grad->w - 7)];
        ASSERT_TRUE(((gl >> 16) & 0xFFu) > 220u && (gl & 0xFFu) < 30u &&
                    ((gm >> 8) & 0xFFu) > 220u && ((gm >> 16) & 0xFFu) < 30u &&
                    (gr & 0xFFu) > 220u && ((gr >> 16) & 0xFFu) < 30u,
                    "3-stop linear-gradient(to right, #f00, #0f0 50%, #00f) interpolates R -> G -> B");
    }

    blink_fb_destroy(fb);
    dom_node_free(root);
}

static void test_atomic_opacity_overflow_clip_and_transforms(void) {
    printf("\n--- 6. Atomic Group Opacity, Overflow Scissor/RRect Clip & 2D Transforms ---\n");
    const char* html =
        "<style>"
        "body { padding: 20px; }"
        "#grp { position: relative; width: 120px; height: 60px; opacity: 0.5; }"
        "#red_under { position: absolute; left: 0; top: 0; width: 100px; height: 50px; background: #ff0000; }"
        "#blue_over { position: absolute; left: 0; top: 0; width: 100px; height: 50px; background: #0000ff; }"
        "#clip_box { margin-top: 12px; width: 120px; height: 48px; overflow: hidden;"
        "            border-radius: 16px; background: #e2e8f0; }"
        "#wide_bar { width: 420px; height: 48px; background: #ef4444; }"
        "#stage { position: relative; margin-top: 12px; width: 200px; height: 100px; background: #f8fafc; }"
        "#centered { position: absolute; left: 100px; top: 50px; width: 80px; height: 30px;"
        "            transform: translate(-50%, -50%); background: #10b981; }"
        "#xform_cb { margin-top: 10px; width: 140px; height: 40px; transform: translate(30px, 20px); background: #dbeafe; }"
        "#abs_in_xform { position: absolute; left: 10px; top: 6px; width: 24px; height: 16px; background: #1d4ed8; }"
        "#sibling_after { height: 20px; background: #cbd5e1; }"
        "</style>"
        "<div id=\"grp\"><div id=\"red_under\"></div><div id=\"blue_over\"></div></div>"
        "<div id=\"clip_box\"><div id=\"wide_bar\"></div></div>"
        "<div id=\"stage\"><div id=\"centered\"></div></div>"
        "<div id=\"xform_cb\"><div id=\"abs_in_xform\"></div></div>"
        "<div id=\"sibling_after\"></div>";

    dom_node_t* root = blink_parse_html5_document(html, &g_sheet);
    blink_css_resolve_document_styles(root, &g_sheet, 400, 420, BLINK_MODE_SPEC);
    blink_normalize_dom_for_layout(root);
    int max_y = 0;
    blink_layout_dom_tree(root, 0, 0, 400, 420, BLINK_MODE_SPEC, &max_y);

    blink_framebuffer_t* fb = blink_fb_create(400, 420, 0xFFFFFFFFu);
    blink_paint_dom_stacking_context(root, fb);

    /* 1. Atomic opacity: 50% Blue over White => (127..128, 127..128, 255), ZERO Red bleed! */
    dom_node_t* grp = find_by_id(root, "grp");
    ASSERT_TRUE(grp != NULL, "Located #grp opacity stacking context");
    if (grp) {
        uint32_t p = fb->pixels[(grp->y + 25) * fb->width + (grp->x + 50)];
        int pr = (int)((p >> 16) & 0xFFu);
        int pg = (int)((p >> 8) & 0xFFu);
        int pb = (int)(p & 0xFFu);
        ASSERT_TRUE(abs(pr - 128) <= 2 && abs(pg - 128) <= 2 && pb >= 253,
                    "Atomic group opacity=0.5 composites overlapping children with ZERO red bleed-through");
    }

    /* 2. Overflow hidden scissor + rounded corner clip */
    dom_node_t* clip_box = find_by_id(root, "clip_box");
    if (clip_box) {
        uint32_t inside_px  = fb->pixels[(clip_box->y + 24) * fb->width + (clip_box->x + 60)];
        uint32_t outside_rx = fb->pixels[(clip_box->y + 24) * fb->width + (clip_box->x + 150)];
        uint32_t corner_tl  = fb->pixels[(clip_box->y + 1)  * fb->width + (clip_box->x + 1)];
        ASSERT_TRUE(inside_px == 0xFFEF4444u && outside_rx == 0xFFFFFFFFu,
                    "overflow:hidden clips 420px wide child strictly at 120px container right edge");
        ASSERT_TRUE(corner_tl == 0xFFFFFFFFu,
                    "overflow:hidden + border-radius:16px clips overflowing child at rounded corner");
    }

    /* 3. 2D CSS transform: translate(-50%, -50%) & OOF containing block + sibling flow preservation */
    dom_node_t* stage = find_by_id(root, "stage");
    dom_node_t* centered = find_by_id(root, "centered");
    dom_node_t* xform_cb = find_by_id(root, "xform_cb");
    dom_node_t* abs_in_xform = find_by_id(root, "abs_in_xform");
    dom_node_t* sibling_after = find_by_id(root, "sibling_after");
    ASSERT_TRUE(stage != NULL && centered != NULL &&
                centered->x == stage->x + 60 && centered->y == stage->y + 35,
                "transform: translate(-50%, -50%) centers 80x30 absolute box at (100-40, 50-15)");
    ASSERT_TRUE(xform_cb != NULL && abs_in_xform != NULL &&
                abs_in_xform->x == xform_cb->x + 10 && abs_in_xform->y == xform_cb->y + 6,
                "Transformed block establishes OOF containing block and shifts child together");
    ASSERT_TRUE(stage != NULL && xform_cb != NULL && sibling_after != NULL &&
                sibling_after->y == (stage->y + stage->h + 10 + xform_cb->h),
                "transform: translate(30px, 20px) preserves normal-flow y position of following sibling");

    blink_fb_destroy(fb);
    dom_node_free(root);
}

int main(void) {
    printf("=================================================================\n");
    printf("Blink Formal Engine — Pillars 1 & 5 End-to-End Verification Suite\n");
    printf("=================================================================\n");

    test_char_refs();
    test_table_recovery_and_foster_parenting();
    test_noahs_ark_and_adoption_agency();
    test_rrect_and_sdf_primitives();
    test_box_shadow_and_linear_gradient();
    test_atomic_opacity_overflow_clip_and_transforms();

    printf("\n=================================================================\n");
    printf("SUMMARY: %d passed, %d failed\n", g_passed, g_failed);
    printf("=================================================================\n");
    return (g_failed == 0) ? 0 : 1;
}
