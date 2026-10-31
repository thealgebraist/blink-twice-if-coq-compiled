/* ========================================================================= */
/* Chromium Blink Formal HTML5 TreeBuilder & CSS Cascade Engine (C99)        */
/* Source: blink_html_css_formal.c                                           */
/*                                                                           */
/* Verified against Rocq/Coq 9.3.0 specifications in:                        */
/*   - BlinkHTML5TreeBuilderAndCSSCascadeEngine.v                            */
/*   - BlinkDualModeZSemantics.v                                             */
/*   - BlinkHMHybrid_17_HTMLToken.v .. BlinkHMHybrid_32_TableColumnAutoTrack */
/* ========================================================================= */

#define _POSIX_C_SOURCE 200809L
#include "blink_html_css_formal.h"

#include <ctype.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>

/* ------------------------------------------------------------------------- */
/* String & Token Helpers                                                    */
/* ------------------------------------------------------------------------- */

static void trim_inplace(char* s) {
    if (!s) return;
    char* p = s;
    while (*p && isspace((unsigned char)*p)) p++;
    if (p != s) memmove(s, p, strlen(p) + 1);
    size_t len = strlen(s);
    while (len > 0 && isspace((unsigned char)s[len - 1])) {
        s[--len] = '\0';
    }
}

static void copy_lower_bounded(char* dst, size_t cap, const char* src, size_t n) {
    if (!dst || cap == 0) return;
    size_t i = 0;
    for (; i < n && i + 1 < cap && src[i]; i++) {
        dst[i] = (char)tolower((unsigned char)src[i]);
    }
    dst[i] = '\0';
}

static const char* strcasestr_portable(const char* haystack, const char* needle) {
    if (!haystack || !needle) return NULL;
    size_t nlen = strlen(needle);
    if (nlen == 0) return haystack;
    for (const char* p = haystack; *p; p++) {
        if (strncasecmp(p, needle, nlen) == 0) return p;
    }
    return NULL;
}

static bool token_list_contains(const char* space_sep_list, const char* token) {
    if (!space_sep_list || !token || !token[0]) return false;
    size_t tlen = strlen(token);
    const char* p = space_sep_list;
    while (*p) {
        while (*p && isspace((unsigned char)*p)) p++;
        if (!*p) break;
        const char* start = p;
        while (*p && !isspace((unsigned char)*p)) p++;
        size_t len = (size_t)(p - start);
        if (len == tlen && strncmp(start, token, tlen) == 0) return true;
    }
    return false;
}

/* ------------------------------------------------------------------------- */
/* 1. HTML5 TreeBuilder Primitives (Mirrors Section 1 of Coq Formalization)  */
/* ------------------------------------------------------------------------- */

bool blink_html_is_void_tag(const char* tag) {
    if (!tag) return false;
    static const char* const voids[] = {
        "area", "base", "br", "col", "embed", "hr", "img",
        "input", "link", "meta", "param", "source", "track", "wbr"
    };
    for (size_t i = 0; i < sizeof(voids) / sizeof(voids[0]); i++) {
        if (strcmp(tag, voids[i]) == 0) return true;
    }
    return false;
}

bool blink_html_is_scope_boundary(const char* tag) {
    if (!tag) return false;
    static const char* const bounds[] = {
        "html", "body", "table", "thead", "tbody", "tfoot",
        "caption", "td", "th", "template"
    };
    for (size_t i = 0; i < sizeof(bounds) / sizeof(bounds[0]); i++) {
        if (strcmp(tag, bounds[i]) == 0) return true;
    }
    return false;
}

int32_t blink_html_sanitize_span(int32_t raw_span, int32_t max_cap) {
    if (max_cap < 1) max_cap = 1;
    if (raw_span <= 1) return 1;
    if (raw_span > max_cap) return max_cap;
    return raw_span;
}

static bool is_heading_tag(const char* tag) {
    return tag && tag[0] == 'h' && tag[1] >= '1' && tag[1] <= '6' && tag[2] == '\0';
}

static bool closes_open_p_tag(const char* start_tag) {
    if (!start_tag) return false;
    if (is_heading_tag(start_tag)) return true;
    static const char* const p_closers[] = {
        "address", "article", "aside", "blockquote", "details", "dialog",
        "dir", "div", "dl", "fieldset", "figcaption", "figure", "footer",
        "form", "header", "hgroup", "hr", "main", "menu", "nav", "ol",
        "p", "pre", "search", "section", "table", "ul"
    };
    for (size_t i = 0; i < sizeof(p_closers) / sizeof(p_closers[0]); i++) {
        if (strcmp(start_tag, p_closers[i]) == 0) return true;
    }
    return false;
}

/* Scope-bounded pop matching `pop_until_in_scope` in Coq */
static dom_node_t* html5_pop_until_in_scope(dom_node_t* current, dom_node_t* root, const char* close_tag) {
    if (!current || !root || !close_tag || !close_tag[0]) return current;
    if (current == root) return root;

    bool closing_table_struct =
        (strcmp(close_tag, "td") == 0 || strcmp(close_tag, "th") == 0 ||
         strcmp(close_tag, "tr") == 0 || strcmp(close_tag, "thead") == 0 ||
         strcmp(close_tag, "tbody") == 0 || strcmp(close_tag, "tfoot") == 0 ||
         strcmp(close_tag, "caption") == 0 || strcmp(close_tag, "table") == 0);

    for (dom_node_t* anc = current; anc && anc != root; anc = anc->parent) {
        if (strcmp(anc->tag, close_tag) == 0) {
            return anc->parent ? anc->parent : root;
        }
        if (!closing_table_struct && blink_html_is_scope_boundary(anc->tag)) {
            /* Firewall boundary preserves outer open elements! */
            return current;
        }
        if (closing_table_struct && strcmp(close_tag, "table") != 0 && strcmp(anc->tag, "table") == 0) {
            /* Never pop past enclosing <table> when closing <td>/<tr>/<tbody> */
            return current;
        }
    }
    return current;
}

/* Implicit end-tag closure matching `close_implicit_before_start` in Coq */
static dom_node_t* html5_close_implicit_before_start(dom_node_t* current, dom_node_t* root, const char* new_tag) {
    if (!current || !root || !new_tag) return current;

    /* 1. Close open <p> in button scope when block-level tag opens */
    if (closes_open_p_tag(new_tag)) {
        current = html5_pop_until_in_scope(current, root, "p");
    }

    /* 2. <li> implicitly closes sibling <li> within nearest <ul>/<ol>/<menu> */
    if (strcmp(new_tag, "li") == 0) {
        for (dom_node_t* anc = current; anc && anc != root; anc = anc->parent) {
            if (strcmp(anc->tag, "li") == 0) {
                current = anc->parent ? anc->parent : root;
                break;
            }
            if (strcmp(anc->tag, "ul") == 0 || strcmp(anc->tag, "ol") == 0 ||
                strcmp(anc->tag, "menu") == 0 || blink_html_is_scope_boundary(anc->tag)) {
                break;
            }
        }
    }
    /* 3. <dt>/<dd> implicitly closes sibling <dt>/<dd> within <dl> */
    else if (strcmp(new_tag, "dt") == 0 || strcmp(new_tag, "dd") == 0) {
        for (dom_node_t* anc = current; anc && anc != root; anc = anc->parent) {
            if (strcmp(anc->tag, "dt") == 0 || strcmp(anc->tag, "dd") == 0) {
                current = anc->parent ? anc->parent : root;
                break;
            }
            if (strcmp(anc->tag, "dl") == 0 || blink_html_is_scope_boundary(anc->tag)) {
                break;
            }
        }
    }
    /* 4. <h1>..<h6> implicitly closes immediately open heading */
    else if (is_heading_tag(new_tag) && current != root && is_heading_tag(current->tag)) {
        current = current->parent ? current->parent : root;
    }
    /* 5. <td>/<th> implicitly closes prior <td>/<th> within <tr> */
    else if (strcmp(new_tag, "td") == 0 || strcmp(new_tag, "th") == 0) {
        for (dom_node_t* anc = current; anc && anc != root; anc = anc->parent) {
            if (strcmp(anc->tag, "td") == 0 || strcmp(anc->tag, "th") == 0) {
                current = anc->parent ? anc->parent : root;
                break;
            }
            if (strcmp(anc->tag, "tr") == 0 || strcmp(anc->tag, "table") == 0) {
                break;
            }
        }
    }
    /* 6. <tr> implicitly closes open <td>/<th> and prior <tr> within table section/table */
    else if (strcmp(new_tag, "tr") == 0) {
        for (dom_node_t* anc = current; anc && anc != root; anc = anc->parent) {
            if (strcmp(anc->tag, "td") == 0 || strcmp(anc->tag, "th") == 0) {
                current = anc->parent ? anc->parent : root;
                break;
            }
            if (strcmp(anc->tag, "tr") == 0 || strcmp(anc->tag, "table") == 0) break;
        }
        for (dom_node_t* anc = current; anc && anc != root; anc = anc->parent) {
            if (strcmp(anc->tag, "tr") == 0) {
                current = anc->parent ? anc->parent : root;
                break;
            }
            if (strcmp(anc->tag, "thead") == 0 || strcmp(anc->tag, "tbody") == 0 ||
                strcmp(anc->tag, "tfoot") == 0 || strcmp(anc->tag, "table") == 0) {
                break;
            }
        }
    }
    /* 7. <thead>/<tbody>/<tfoot> implicitly closes open <td>/<th>/<tr> and prior row-group */
    else if (strcmp(new_tag, "thead") == 0 || strcmp(new_tag, "tbody") == 0 || strcmp(new_tag, "tfoot") == 0) {
        for (dom_node_t* anc = current; anc && anc != root; anc = anc->parent) {
            if (strcmp(anc->tag, "thead") == 0 || strcmp(anc->tag, "tbody") == 0 || strcmp(anc->tag, "tfoot") == 0) {
                current = anc->parent ? anc->parent : root;
                break;
            }
            if (strcmp(anc->tag, "table") == 0) break;
        }
        for (dom_node_t* anc = current; anc && anc != root; anc = anc->parent) {
            if (strcmp(anc->tag, "tr") == 0) {
                current = anc->parent ? anc->parent : root;
                break;
            }
            if (strcmp(anc->tag, "table") == 0) break;
        }
    }

    return current;
}

/* ------------------------------------------------------------------------- */
/* 2. DOM Node Creation & UA Default Stylesheet                              */
/* ------------------------------------------------------------------------- */

static bool tag_has_explicit_ua_color(const char* tag) {
    return strcmp(tag, "a") == 0 || strcmp(tag, "button") == 0 ||
           strcmp(tag, "blockquote") == 0 || strcmp(tag, "figcaption") == 0;
}

static bool tag_has_explicit_ua_font_size(const char* tag) {
    return is_heading_tag(tag) || strcmp(tag, "pre") == 0 || strcmp(tag, "code") == 0 ||
           strcmp(tag, "figcaption") == 0 || strcmp(tag, "small") == 0;
}

static bool tag_has_explicit_ua_font_weight(const char* tag) {
    return is_heading_tag(tag) || strcmp(tag, "b") == 0 || strcmp(tag, "strong") == 0 ||
           strcmp(tag, "th") == 0;
}

static bool tag_has_explicit_ua_font_style(const char* tag) {
    return strcmp(tag, "i") == 0 || strcmp(tag, "em") == 0 || strcmp(tag, "cite") == 0 ||
           strcmp(tag, "dfn") == 0;
}

static bool tag_has_explicit_ua_font_family(const char* tag) {
    return strcmp(tag, "pre") == 0 || strcmp(tag, "code") == 0 || strcmp(tag, "kbd") == 0 ||
           strcmp(tag, "samp") == 0;
}

static void init_initial_style(dom_style_t* st) {
    memset(st, 0, sizeof(*st));
    st->display = DISPLAY_BLOCK;
    st->box_sizing = BOX_SIZING_CONTENT_BOX;
    st->justify_content = JUSTIFY_FLEX_START;
    st->color = BLINK_COLOR_TEXT_DEFAULT;
    st->bg_color = 0;
    st->has_bg = false;
    st->border_color = BLINK_COLOR_BORDER_GRAY;
    st->border_left_color = BLINK_COLOR_BORDER_GRAY;
    st->border_width = 0;
    st->border_left_width = 0;
    st->border_bottom_width = 0;
    st->border_radius = 0;
    st->font_size = 14.0f;
    st->font_weight = 400;
    st->font_style = 0;
    strcpy(st->font_family, "sans-serif");
    st->width = -1;
    st->height = -1;
    st->gap = 0;
    st->flex_grow = 0;
    st->line_height = 1.4f;
    st->text_align = ALIGN_LEFT;
}

dom_node_t* dom_node_create(const char* tag) {
    dom_node_t* n = (dom_node_t*)calloc(1, sizeof(dom_node_t));
    if (!n) return NULL;
    strncpy(n->tag, tag ? tag : "", 31);
    n->tag[31] = '\0';
    n->colspan = 1;
    n->rowspan = 1;

    init_initial_style(&n->style);

    /* User-Agent Default Stylesheet Rules */
    if (strcmp(n->tag, "body") == 0) {
        n->style.padding_top = 20;
        n->style.padding_bottom = 24;
        n->style.padding_left = 32;
        n->style.padding_right = 32;
    } else if (strcmp(n->tag, "head") == 0 || strcmp(n->tag, "title") == 0 ||
               strcmp(n->tag, "style") == 0 || strcmp(n->tag, "script") == 0 ||
               strcmp(n->tag, "meta") == 0 || strcmp(n->tag, "link") == 0) {
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
        n->style.border_bottom_width = 1;
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
    } else if (strcmp(n->tag, "h5") == 0 || strcmp(n->tag, "h6") == 0) {
        n->style.font_size = 13.0f;
        n->style.font_weight = 700;
        n->style.margin_top = 8;
        n->style.margin_bottom = 4;
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
        n->style.bg_color = 0xFFF8F9FAu;
        n->style.has_bg = true;
        n->style.border_width = 1;
        n->style.border_color = 0xFFC8CCD1u;
    } else if (strcmp(n->tag, "figcaption") == 0) {
        n->style.font_size = 12.5f;
        n->style.color = 0xFF54595Du;
        n->style.margin_top = 6;
    } else if (strcmp(n->tag, "img") == 0) {
        n->style.box_sizing = BOX_SIZING_BORDER_BOX;
        n->style.bg_color = 0xFFEAECF0u;
        n->style.has_bg = true;
        n->style.border_width = 1;
        n->style.border_color = 0xFFA2A9B1u;
        n->style.height = 140;
        n->style.width = 220;
    } else if (strcmp(n->tag, "a") == 0) {
        n->style.display = DISPLAY_INLINE;
        n->style.color = BLINK_COLOR_LINK_BLUE;
    } else if (strcmp(n->tag, "span") == 0 || strcmp(n->tag, "b") == 0 || strcmp(n->tag, "strong") == 0 ||
               strcmp(n->tag, "i") == 0 || strcmp(n->tag, "em") == 0 || strcmp(n->tag, "small") == 0 ||
               strcmp(n->tag, "abbr") == 0 || strcmp(n->tag, "cite") == 0 || strcmp(n->tag, "sub") == 0 ||
               strcmp(n->tag, "sup") == 0 || strcmp(n->tag, "q") == 0 || strcmp(n->tag, "mark") == 0 ||
               strcmp(n->tag, "time") == 0 || strcmp(n->tag, "dfn") == 0 || strcmp(n->tag, "u") == 0 ||
               strcmp(n->tag, "#text") == 0) {
        n->style.display = DISPLAY_INLINE;
        if (strcmp(n->tag, "b") == 0 || strcmp(n->tag, "strong") == 0) n->style.font_weight = 700;
        if (strcmp(n->tag, "i") == 0 || strcmp(n->tag, "em") == 0 || strcmp(n->tag, "cite") == 0) n->style.font_style = 1;
        if (strcmp(n->tag, "small") == 0) n->style.font_size = 12.0f;
        if (strcmp(n->tag, "mark") == 0) { n->style.bg_color = 0xFFFFF3CDu; n->style.has_bg = true; }
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
    } else if (strcmp(n->tag, "thead") == 0 || strcmp(n->tag, "tbody") == 0 || strcmp(n->tag, "tfoot") == 0) {
        n->style.display = DISPLAY_TABLE_ROW_GROUP;
    } else if (strcmp(n->tag, "tr") == 0) {
        n->style.display = DISPLAY_TABLE_ROW;
    } else if (strcmp(n->tag, "th") == 0) {
        n->style.display = DISPLAY_TABLE_CELL;
        n->style.box_sizing = BOX_SIZING_BORDER_BOX;
        n->style.font_weight = 700;
        n->style.padding_top = 6;
        n->style.padding_bottom = 6;
        n->style.padding_left = 10;
        n->style.padding_right = 10;
        n->style.border_width = 1;
    } else if (strcmp(n->tag, "td") == 0) {
        n->style.display = DISPLAY_TABLE_CELL;
        n->style.box_sizing = BOX_SIZING_BORDER_BOX;
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
        n->style.bg_color = BLINK_COLOR_LINK_BLUE;
        n->style.has_bg = true;
        n->style.color = BLINK_COLOR_WHITE;
        n->style.border_radius = 4;
    } else if (strcmp(n->tag, "pre") == 0 || strcmp(n->tag, "code") == 0) {
        strcpy(n->style.font_family, "monospace");
        n->style.font_size = 12.5f;
        n->style.bg_color = 0xFFF1F3F4u;
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
        n->style.border_left_width = 3;
        n->style.border_color = BLINK_COLOR_LINK_BLUE;
        n->style.border_left_color = BLINK_COLOR_LINK_BLUE;
        n->style.color = 0xFF5F6368u;
    } else if (strcmp(n->tag, "hr") == 0) {
        n->style.margin_top = 14;
        n->style.margin_bottom = 14;
        n->style.border_width = 1;
        n->style.border_color = BLINK_COLOR_BORDER_GRAY;
        n->style.height = 1;
    }

    n->ua_style = n->style;
    return n;
}

void dom_node_add_child(dom_node_t* parent, dom_node_t* child) {
    if (!parent || !child) return;
    if (parent->num_children + 1 > parent->cap_children) {
        int new_cap = (parent->cap_children == 0) ? 4 : parent->cap_children * 2;
        parent->children = (dom_node_t**)realloc(parent->children, (size_t)new_cap * sizeof(dom_node_t*));
        parent->cap_children = new_cap;
    }
    parent->children[parent->num_children++] = child;
    child->parent = parent;
}

void dom_node_free(dom_node_t* n) {
    if (!n) return;
    free(n->text);
    free(n->id);
    free(n->class_name);
    free(n->src);
    free(n->href);
    free(n->inline_style_raw);
    for (int i = 0; i < n->num_children; i++) {
        dom_node_free(n->children[i]);
    }
    free(n->children);
    free(n);
}

/* ------------------------------------------------------------------------- */
/* 3. Specificity & Cascade Priority Algebra (Mirrors Sections 2 & 3)        */
/* ------------------------------------------------------------------------- */

blink_specificity_t blink_specificity_add(blink_specificity_t a, blink_specificity_t b) {
    blink_specificity_t r;
    r.id_cnt = a.id_cnt + b.id_cnt;
    r.class_cnt = a.class_cnt + b.class_cnt;
    r.tag_cnt = a.tag_cnt + b.tag_cnt;
    return r;
}

bool blink_specificity_lt(blink_specificity_t a, blink_specificity_t b) {
    if (a.id_cnt != b.id_cnt) return a.id_cnt < b.id_cnt;
    if (a.class_cnt != b.class_cnt) return a.class_cnt < b.class_cnt;
    return a.tag_cnt < b.tag_cnt;
}

int32_t blink_origin_importance_rank(blink_css_origin_t origin, bool important) {
    switch (origin) {
        case CSS_ORIGIN_UA:     return important ? 8 : 1;
        case CSS_ORIGIN_USER:   return important ? 7 : 2;
        case CSS_ORIGIN_AUTHOR: return important ? 6 : 3;
        case CSS_ORIGIN_INLINE: return important ? 5 : 4;
    }
    return 3;
}

bool blink_cascade_meta_lt(blink_cascade_meta_t a, blink_cascade_meta_t b) {
    int32_t r1 = blink_origin_importance_rank(a.origin, a.important);
    int32_t r2 = blink_origin_importance_rank(b.origin, b.important);
    if (r1 != r2) return r1 < r2;

    /* CSS Cascade Level 5 @layer order:
       - Normal: earlier layer < later layer < unlayered (BLINK_UNLAYERED_ORDER)
       - !important: unlayered < later layer < earlier layer (INVERTED!) */
    if (a.layer_order != b.layer_order) {
        if (a.important) {
            return b.layer_order < a.layer_order;
        }
        return a.layer_order < b.layer_order;
    }

    if (blink_specificity_lt(a.specificity, b.specificity)) return true;
    if (blink_specificity_lt(b.specificity, a.specificity)) return false;

    return a.source_order < b.source_order;
}

/* ------------------------------------------------------------------------- */
/* 4. CSS Selector Parser & Right-to-Left Matcher (Mirrors Section 2)        */
/* ------------------------------------------------------------------------- */

bool blink_css_match_nth_child(int index_1based, int a, int b) {
    if (index_1based < 1) return false;
    if (a == 0) return index_1based == b;
    int diff = index_1based - b;
    if (a > 0) {
        return (diff >= 0) && (diff % a == 0);
    } else {
        return (diff <= 0) && (diff % (-a) == 0);
    }
}

static bool is_ident_char(char c) {
    return isalnum((unsigned char)c) || c == '-' || c == '_';
}

static void parse_nth_expr(const char* expr, int* out_a, int* out_b) {
    char buf[64];
    size_t j = 0;
    for (size_t i = 0; expr[i] && j + 1 < sizeof(buf); i++) {
        if (!isspace((unsigned char)expr[i])) {
            buf[j++] = (char)tolower((unsigned char)expr[i]);
        }
    }
    buf[j] = '\0';

    if (strcmp(buf, "odd") == 0) { *out_a = 2; *out_b = 1; return; }
    if (strcmp(buf, "even") == 0) { *out_a = 2; *out_b = 0; return; }

    char* n_pos = strchr(buf, 'n');
    if (!n_pos) {
        *out_a = 0;
        *out_b = atoi(buf);
        return;
    }

    if (n_pos == buf) {
        *out_a = 1;
    } else if (n_pos == buf + 1 && buf[0] == '+') {
        *out_a = 1;
    } else if (n_pos == buf + 1 && buf[0] == '-') {
        *out_a = -1;
    } else {
        *n_pos = '\0';
        *out_a = atoi(buf);
    }

    const char* rest = n_pos + 1;
    *out_b = (*rest) ? atoi(rest) : 0;
}

static const char* parse_compound_segment(const char* p,
                                          blink_compound_sel_t* comp,
                                          blink_specificity_t* io_spec,
                                          bool suppress_specificity) {
    memset(comp, 0, sizeof(*comp));
    comp->zero_specificity = suppress_specificity;

    bool parsed_any = false;
    while (*p) {
        if (isspace((unsigned char)*p) || *p == '>' || *p == '+' || *p == ',' || *p == '{' || *p == ')') {
            break;
        }
        if (*p == '*') {
            comp->universal = true;
            parsed_any = true;
            p++;
        } else if (*p == '#') {
            p++;
            const char* s = p;
            while (*p && is_ident_char(*p)) p++;
            copy_lower_bounded(comp->id, sizeof(comp->id), s, (size_t)(p - s));
            if (!suppress_specificity) io_spec->id_cnt++;
            parsed_any = true;
        } else if (*p == '.') {
            p++;
            const char* s = p;
            while (*p && is_ident_char(*p)) p++;
            if (comp->num_classes < BLINK_MAX_CLASSES_PER_COMPOUND) {
                /* Class names are case-sensitive in HTML5/CSS, keep exact case */
                size_t len = (size_t)(p - s);
                if (len > 63) len = 63;
                memcpy(comp->classes[comp->num_classes], s, len);
                comp->classes[comp->num_classes][len] = '\0';
                comp->num_classes++;
            }
            if (!suppress_specificity) io_spec->class_cnt++;
            parsed_any = true;
        } else if (*p == '[') {
            p++;
            while (*p && isspace((unsigned char)*p)) p++;
            const char* ks = p;
            while (*p && *p != '=' && *p != ']' && !isspace((unsigned char)*p)) p++;
            copy_lower_bounded(comp->attr_name, sizeof(comp->attr_name), ks, (size_t)(p - ks));
            comp->has_attr = true;
            while (*p && isspace((unsigned char)*p)) p++;
            if (*p == '=') {
                p++;
                while (*p && isspace((unsigned char)*p)) p++;
                char q = (*p == '"' || *p == '\'') ? *p++ : 0;
                const char* vs = p;
                while (*p && ((q && *p != q) || (!q && *p != ']' && !isspace((unsigned char)*p)))) p++;
                size_t vlen = (size_t)(p - vs);
                if (vlen > 63) vlen = 63;
                memcpy(comp->attr_val, vs, vlen);
                comp->attr_val[vlen] = '\0';
                comp->has_attr_val = true;
                if (q && *p == q) p++;
            }
            while (*p && *p != ']') p++;
            if (*p == ']') p++;
            if (!suppress_specificity) io_spec->class_cnt++;
            parsed_any = true;
        } else if (*p == ':') {
            p++;
            if (*p == ':') {
                /* Pseudo-elements (::before, ::after) not modeled as DOM elements: fail match cleanly */
                while (*p && is_ident_char(*p)) p++;
                strcpy(comp->tag, "__unsupported_pseudo_element__");
                return p;
            }
            const char* ps = p;
            while (*p && is_ident_char(*p)) p++;
            char pname[32];
            copy_lower_bounded(pname, sizeof(pname), ps, (size_t)(p - ps));

            if (strcmp(pname, "root") == 0) {
                strcpy(comp->tag, "body");
                if (!suppress_specificity) io_spec->class_cnt++;
                parsed_any = true;
            } else if (strcmp(pname, "first-child") == 0) {
                comp->pseudo = PSEUDO_FIRST_CHILD;
                if (!suppress_specificity) io_spec->class_cnt++;
                parsed_any = true;
            } else if (strcmp(pname, "last-child") == 0) {
                comp->pseudo = PSEUDO_LAST_CHILD;
                if (!suppress_specificity) io_spec->class_cnt++;
                parsed_any = true;
            } else if (strcmp(pname, "nth-child") == 0 && *p == '(') {
                p++;
                const char* es = p;
                int depth = 1;
                while (*p && depth > 0) {
                    if (*p == '(') depth++;
                    else if (*p == ')') depth--;
                    if (depth > 0) p++;
                }
                char expr[64];
                size_t elen = (size_t)(p - es);
                if (elen > 63) elen = 63;
                memcpy(expr, es, elen);
                expr[elen] = '\0';
                if (*p == ')') p++;
                comp->pseudo = PSEUDO_NTH_CHILD;
                parse_nth_expr(expr, &comp->nth_a, &comp->nth_b);
                if (!suppress_specificity) io_spec->class_cnt++;
                parsed_any = true;
            } else if (strcmp(pname, "where") == 0 && *p == '(') {
                /* `:where(...)` contributes ZERO specificity per `where_pseudo_zero_specificity`! */
                p++;
                while (*p && isspace((unsigned char)*p)) p++;
                blink_compound_sel_t inner;
                p = parse_compound_segment(p, &inner, io_spec, true);
                if (inner.tag[0] && !comp->tag[0]) strcpy(comp->tag, inner.tag);
                if (inner.id[0] && !comp->id[0]) strcpy(comp->id, inner.id);
                for (int c = 0; c < inner.num_classes && comp->num_classes < BLINK_MAX_CLASSES_PER_COMPOUND; c++) {
                    strcpy(comp->classes[comp->num_classes++], inner.classes[c]);
                }
                if (inner.has_attr) {
                    comp->has_attr = true;
                    comp->has_attr_val = inner.has_attr_val;
                    strcpy(comp->attr_name, inner.attr_name);
                    strcpy(comp->attr_val, inner.attr_val);
                }
                if (inner.pseudo != PSEUDO_NONE) {
                    comp->pseudo = inner.pseudo;
                    comp->nth_a = inner.nth_a;
                    comp->nth_b = inner.nth_b;
                }
                while (*p && *p != ')') p++;
                if (*p == ')') p++;
                parsed_any = true;
            } else {
                /* Unsupported pseudo-class (e.g. :hover) should not falsely match static document */
                if (*p == '(') {
                    int depth = 1;
                    p++;
                    while (*p && depth > 0) {
                        if (*p == '(') depth++;
                        else if (*p == ')') depth--;
                        p++;
                    }
                }
                strcpy(comp->tag, "__unsupported_pseudo_class__");
                return p;
            }
        } else if (is_ident_char(*p)) {
            const char* s = p;
            while (*p && is_ident_char(*p)) p++;
            copy_lower_bounded(comp->tag, sizeof(comp->tag), s, (size_t)(p - s));
            if (strcmp(comp->tag, "html") == 0) {
                /* Map html tag selector onto document root ("body") */
                strcpy(comp->tag, "body");
            }
            if (!suppress_specificity) io_spec->tag_cnt++;
            parsed_any = true;
        } else {
            p++;
        }
    }

    if (!parsed_any) {
        comp->tag[0] = '\0';
    }
    return p;
}

bool blink_css_parse_selector(const char* sel_text, blink_complex_sel_t* out_sel) {
    if (!sel_text || !out_sel) return false;
    memset(out_sel, 0, sizeof(*out_sel));

    const char* p = sel_text;
    while (*p && isspace((unsigned char)*p)) p++;
    if (!*p) return false;

    blink_combinator_t pending_comb = COMB_NONE;
    while (*p && out_sel->num_compounds < BLINK_MAX_COMPOUNDS_PER_SEL) {
        blink_compound_sel_t comp;
        const char* before = p;
        p = parse_compound_segment(p, &comp, &out_sel->specificity, false);
        if (p == before) break;

        int idx = out_sel->num_compounds++;
        out_sel->compounds[idx] = comp;
        out_sel->combinators[idx] = pending_comb;

        bool saw_space = false;
        while (*p && isspace((unsigned char)*p)) { saw_space = true; p++; }
        if (!*p || *p == ',' || *p == '{') break;

        if (*p == '>') {
            pending_comb = COMB_CHILD;
            p++;
            while (*p && isspace((unsigned char)*p)) p++;
        } else if (*p == '+') {
            pending_comb = COMB_NEXT_SIBLING;
            p++;
            while (*p && isspace((unsigned char)*p)) p++;
        } else if (saw_space) {
            pending_comb = COMB_DESCENDANT;
        } else {
            break;
        }
    }

    return out_sel->num_compounds > 0;
}

static void element_sibling_metrics(const dom_node_t* el, int* out_idx_1based, int* out_total_el_siblings, const dom_node_t** out_prev_el) {
    *out_idx_1based = 1;
    *out_total_el_siblings = 1;
    *out_prev_el = NULL;
    if (!el || !el->parent) return;

    int count = 0;
    const dom_node_t* prev = NULL;
    for (int i = 0; i < el->parent->num_children; i++) {
        const dom_node_t* ch = el->parent->children[i];
        if (strcmp(ch->tag, "#text") == 0) continue;
        count++;
        if (ch == el) {
            *out_idx_1based = count;
            *out_prev_el = prev;
        }
        prev = ch;
    }
    *out_total_el_siblings = count;
}

static const char* get_element_attr(const dom_node_t* el, const char* attr_name) {
    if (!el || !attr_name) return NULL;
    if (strcmp(attr_name, "id") == 0) return el->id;
    if (strcmp(attr_name, "class") == 0) return el->class_name;
    if (strcmp(attr_name, "src") == 0) return el->src;
    if (strcmp(attr_name, "href") == 0) return el->href;
    for (int i = 0; i < el->num_attrs; i++) {
        if (strcmp(el->attrs[i].name, attr_name) == 0) return el->attrs[i].value;
    }
    return NULL;
}

static bool match_compound_on_element(const dom_node_t* el, const blink_compound_sel_t* comp) {
    if (!el || strcmp(el->tag, "#text") == 0) return false;
    if (comp->tag[0] != '\0' && strcmp(el->tag, comp->tag) != 0) return false;
    if (comp->id[0] != '\0') {
        if (!el->id || strcasecmp(el->id, comp->id) != 0) return false;
    }
    for (int i = 0; i < comp->num_classes; i++) {
        if (!token_list_contains(el->class_name, comp->classes[i])) return false;
    }
    if (comp->has_attr) {
        const char* av = get_element_attr(el, comp->attr_name);
        if (!av) return false;
        if (comp->has_attr_val && strcmp(av, comp->attr_val) != 0) return false;
    }
    if (comp->pseudo != PSEUDO_NONE) {
        int idx1 = 1, total = 1;
        const dom_node_t* prev = NULL;
        element_sibling_metrics(el, &idx1, &total, &prev);
        if (comp->pseudo == PSEUDO_FIRST_CHILD && idx1 != 1) return false;
        if (comp->pseudo == PSEUDO_LAST_CHILD && idx1 != total) return false;
        if (comp->pseudo == PSEUDO_NTH_CHILD && !blink_css_match_nth_child(idx1, comp->nth_a, comp->nth_b)) {
            return false;
        }
    }
    return true;
}

static bool match_complex_rtl_from(const dom_node_t* el, const blink_complex_sel_t* sel, int comp_idx) {
    if (!el || comp_idx < 0) return false;
    if (!match_compound_on_element(el, &sel->compounds[comp_idx])) return false;
    if (comp_idx == 0) return true;

    blink_combinator_t comb = sel->combinators[comp_idx];
    if (comb == COMB_CHILD) {
        return el->parent && match_complex_rtl_from(el->parent, sel, comp_idx - 1);
    } else if (comb == COMB_DESCENDANT) {
        for (const dom_node_t* anc = el->parent; anc != NULL; anc = anc->parent) {
            if (match_complex_rtl_from(anc, sel, comp_idx - 1)) return true;
        }
        return false;
    } else if (comb == COMB_NEXT_SIBLING) {
        int idx1 = 1, total = 1;
        const dom_node_t* prev = NULL;
        element_sibling_metrics(el, &idx1, &total, &prev);
        return prev && match_complex_rtl_from(prev, sel, comp_idx - 1);
    }
    return false;
}

bool blink_css_match_selector(const dom_node_t* el, const blink_complex_sel_t* sel) {
    if (!el || !sel || sel->num_compounds <= 0) return false;
    return match_complex_rtl_from(el, sel, sel->num_compounds - 1);
}

/* ------------------------------------------------------------------------- */
/* 5. Cycle-Safe `var(--x, fallback)` Resolution (Mirrors Section 4)         */
/* ------------------------------------------------------------------------- */

static const char* lookup_custom_prop(const blink_custom_prop_t* props, int num_props, const char* name) {
    for (int i = 0; i < num_props; i++) {
        if (strcmp(props[i].name, name) == 0) return props[i].value;
    }
    return NULL;
}

static bool resolve_var_recursive(const blink_custom_prop_t* props,
                                  int num_props,
                                  const char* raw_val,
                                  const char visited[][48],
                                  int num_visited,
                                  int fuel,
                                  char* out_buf,
                                  size_t out_cap) {
    if (fuel <= 0 || !raw_val || !out_buf || out_cap == 0) return false;

    size_t out_len = 0;
    out_buf[0] = '\0';

    const char* p = raw_val;
    while (*p) {
        if (strncasecmp(p, "var(", 4) == 0) {
            /* Find matching ')' respecting nested parentheses */
            const char* inner_start = p + 4;
            const char* scan = inner_start;
            int depth = 1;
            const char* top_comma = NULL;
            while (*scan && depth > 0) {
                if (*scan == '(') depth++;
                else if (*scan == ')') depth--;
                else if (*scan == ',' && depth == 1 && !top_comma) top_comma = scan;
                if (depth > 0) scan++;
            }
            if (depth != 0) return false; /* Malformed var( */

            char var_name[48];
            size_t nlen = (size_t)((top_comma ? top_comma : scan) - inner_start);
            if (nlen >= sizeof(var_name)) nlen = sizeof(var_name) - 1;
            memcpy(var_name, inner_start, nlen);
            var_name[nlen] = '\0';
            trim_inplace(var_name);

            bool has_cycle = false;
            for (int v = 0; v < num_visited; v++) {
                if (strcmp(visited[v], var_name) == 0) {
                    has_cycle = true;
                    break;
                }
            }

            const char* target = (!has_cycle) ? lookup_custom_prop(props, num_props, var_name) : NULL;
            char sub_resolved[192];
            bool ok = false;

            if (target && num_visited < 16) {
                char next_visited[16][48];
                for (int v = 0; v < num_visited; v++) strcpy(next_visited[v], visited[v]);
                strncpy(next_visited[num_visited], var_name, 47);
                next_visited[num_visited][47] = '\0';

                ok = resolve_var_recursive(props, num_props, target,
                                           next_visited, num_visited + 1, fuel - 1,
                                           sub_resolved, sizeof(sub_resolved));
            }

            /* Fallback path when undefined OR when target has a cycle! */
            if (!ok && top_comma) {
                char fb_raw[192];
                size_t flen = (size_t)(scan - (top_comma + 1));
                if (flen >= sizeof(fb_raw)) flen = sizeof(fb_raw) - 1;
                memcpy(fb_raw, top_comma + 1, flen);
                fb_raw[flen] = '\0';
                trim_inplace(fb_raw);
                ok = resolve_var_recursive(props, num_props, fb_raw,
                                           visited, num_visited, fuel - 1,
                                           sub_resolved, sizeof(sub_resolved));
            }

            if (!ok) return false; /* IACVT per CSS Custom Properties spec */

            size_t slen = strlen(sub_resolved);
            if (out_len + slen + 1 >= out_cap) return false;
            memcpy(out_buf + out_len, sub_resolved, slen + 1);
            out_len += slen;

            p = scan + 1;
        } else {
            if (out_len + 2 >= out_cap) return false;
            out_buf[out_len++] = *p++;
            out_buf[out_len] = '\0';
        }
    }
    trim_inplace(out_buf);
    return true;
}

bool blink_css_resolve_var_value(const blink_custom_prop_t* props,
                                 int num_props,
                                 const char* raw_val,
                                 char* out_resolved,
                                 size_t out_cap) {
    char visited[16][48];
    return resolve_var_recursive(props, num_props, raw_val, visited, 0, 16, out_resolved, out_cap);
}

/* ------------------------------------------------------------------------- */
/* 6. Shorthands, Units, `calc()`, `box-sizing`, Flex & Table (Sec 6 & 7)    */
/* ------------------------------------------------------------------------- */

blink_box_edges_t blink_css_expand_shorthand_ints(const int32_t* vals, int count) {
    blink_box_edges_t e = {0, 0, 0, 0};
    if (!vals || count <= 0) return e;
    if (count == 1) {
        e.top = e.right = e.bottom = e.left = vals[0];
    } else if (count == 2) {
        e.top = e.bottom = vals[0];
        e.right = e.left = vals[1];
    } else if (count == 3) {
        e.top = vals[0];
        e.right = e.left = vals[1];
        e.bottom = vals[2];
    } else {
        e.top = vals[0];
        e.right = vals[1];
        e.bottom = vals[2];
        e.left = vals[3];
    }
    return e;
}

static int64_t eval_single_length_in_mode_z(const char* tok,
                                            int32_t parent_px,
                                            int32_t em_px,
                                            int32_t rem_px,
                                            int32_t vw_px,
                                            int32_t vh_px,
                                            blink_layout_mode_t mode) {
    while (*tok && isspace((unsigned char)*tok)) tok++;
    char* endp = NULL;
    double val = strtod(tok, &endp);
    int64_t scale = blink_z_scale(mode);
    if (!endp || endp == tok) return 0;

    while (*endp && isspace((unsigned char)*endp)) endp++;
    if (*endp == '%') {
        return (int64_t)llround(((double)parent_px * (double)scale * val) / 100.0);
    } else if (strncasecmp(endp, "rem", 3) == 0) {
        return (int64_t)llround(val * (double)rem_px * (double)scale);
    } else if (strncasecmp(endp, "em", 2) == 0) {
        return (int64_t)llround(val * (double)em_px * (double)scale);
    } else if (strncasecmp(endp, "vw", 2) == 0) {
        return (int64_t)llround(((double)vw_px * (double)scale * val) / 100.0);
    } else if (strncasecmp(endp, "vh", 2) == 0) {
        return (int64_t)llround(((double)vh_px * (double)scale * val) / 100.0);
    } else if (strncasecmp(endp, "pt", 2) == 0) {
        return (int64_t)llround(val * (96.0 / 72.0) * (double)scale);
    }
    /* Default: px or unitless zero */
    return (int64_t)llround(val * (double)scale);
}

int32_t blink_css_eval_length_or_calc(const char* expr,
                                      int32_t parent_px,
                                      int32_t em_px,
                                      int32_t rem_px,
                                      int32_t vw_px,
                                      int32_t vh_px,
                                      blink_layout_mode_t mode,
                                      bool* out_is_auto) {
    if (out_is_auto) *out_is_auto = false;
    if (!expr) return 0;
    while (*expr && isspace((unsigned char)*expr)) expr++;
    if (strncasecmp(expr, "auto", 4) == 0 && (!expr[4] || isspace((unsigned char)expr[4]))) {
        if (out_is_auto) *out_is_auto = true;
        return -1;
    }

    if (strncasecmp(expr, "calc(", 5) == 0) {
        const char* p = expr + 5;
        const char* end = strrchr(p, ')');
        size_t len = end ? (size_t)(end - p) : strlen(p);
        char inner[192];
        if (len >= sizeof(inner)) len = sizeof(inner) - 1;
        memcpy(inner, p, len);
        inner[len] = '\0';

        /* Parse linear sum/difference of length terms: `T0 (+|-) T1 (+|-) T2 ...` */
        int64_t acc_z = 0;
        int sign = 1;
        const char* cur = inner;
        while (*cur) {
            while (*cur && isspace((unsigned char)*cur)) cur++;
            if (!*cur) break;
            if (*cur == '+') { sign = 1; cur++; continue; }
            if (*cur == '-' && isspace((unsigned char)cur[1])) { sign = -1; cur++; continue; }

            /* Read one term up to space-surrounded '+' or '-' */
            const char* ts = cur;
            while (*cur) {
                if ((*cur == '+' || *cur == '-') && cur > ts && isspace((unsigned char)cur[-1])) {
                    break;
                }
                cur++;
            }
            char term_buf[64];
            size_t tlen = (size_t)(cur - ts);
            if (tlen >= sizeof(term_buf)) tlen = sizeof(term_buf) - 1;
            memcpy(term_buf, ts, tlen);
            term_buf[tlen] = '\0';
            trim_inplace(term_buf);

            /* Also support `k * <length>` inside a term */
            char* star = strchr(term_buf, '*');
            int64_t term_z = 0;
            if (star) {
                *star = '\0';
                double mult = strtod(term_buf, NULL);
                int64_t rhs_z = eval_single_length_in_mode_z(star + 1, parent_px, em_px, rem_px, vw_px, vh_px, mode);
                term_z = (int64_t)llround(mult * (double)rhs_z);
            } else {
                term_z = eval_single_length_in_mode_z(term_buf, parent_px, em_px, rem_px, vw_px, vh_px, mode);
            }
            acc_z += (int64_t)sign * term_z;
            sign = 1;
        }
        return (int32_t)blink_z_floor_device_pixel(acc_z, mode);
    }

    int64_t raw_z = eval_single_length_in_mode_z(expr, parent_px, em_px, rem_px, vw_px, vh_px, mode);
    return (int32_t)blink_z_floor_device_pixel(raw_z, mode);
}

void blink_css_parse_box_shorthand(const char* raw_val,
                                   int32_t parent_px,
                                   int32_t em_px,
                                   int32_t rem_px,
                                   int32_t vw_px,
                                   int32_t vh_px,
                                   blink_layout_mode_t mode,
                                   blink_box_edges_t* out_edges) {
    if (!out_edges) return;
    int32_t vals[4] = {0, 0, 0, 0};
    int count = 0;
    if (raw_val) {
        const char* p = raw_val;
        while (*p && count < 4) {
            while (*p && isspace((unsigned char)*p)) p++;
            if (!*p) break;
            const char* ts = p;
            int paren = 0;
            while (*p && (paren > 0 || !isspace((unsigned char)*p))) {
                if (*p == '(') paren++;
                else if (*p == ')' && paren > 0) paren--;
                p++;
            }
            char tok[96];
            size_t tlen = (size_t)(p - ts);
            if (tlen >= sizeof(tok)) tlen = sizeof(tok) - 1;
            memcpy(tok, ts, tlen);
            tok[tlen] = '\0';
            bool is_auto = false;
            int32_t px = blink_css_eval_length_or_calc(tok, parent_px, em_px, rem_px, vw_px, vh_px, mode, &is_auto);
            vals[count++] = is_auto ? 0 : px;
        }
    }
    *out_edges = blink_css_expand_shorthand_ints(vals, count);
}

int32_t blink_css_resolve_content_inline_size(css_box_sizing_t sizing,
                                              int32_t specified_w,
                                              int32_t pad_h,
                                              int32_t bdr_h) {
    if (sizing == BOX_SIZING_BORDER_BOX) {
        int32_t cw = specified_w - pad_h - bdr_h;
        return (cw < 0) ? 0 : cw;
    }
    return (specified_w < 0) ? 0 : specified_w;
}

int32_t blink_flex_justify_start_offset(css_justify_t mode,
                                        int32_t container_w,
                                        int32_t used_w,
                                        int32_t item_count) {
    (void)item_count;
    int32_t free_sp = container_w - used_w;
    if (free_sp < 0) free_sp = 0;
    switch (mode) {
        case JUSTIFY_FLEX_START:    return 0;
        case JUSTIFY_CENTER:        return free_sp / 2;
        case JUSTIFY_FLEX_END:      return free_sp;
        case JUSTIFY_SPACE_BETWEEN: return 0;
    }
    return 0;
}

int32_t blink_flex_justify_inter_gap(css_justify_t mode,
                                     int32_t container_w,
                                     int32_t used_w,
                                     int32_t item_count,
                                     int32_t base_gap) {
    if (mode == JUSTIFY_SPACE_BETWEEN && item_count > 1) {
        int32_t free_sp = container_w - used_w;
        if (free_sp < 0) free_sp = 0;
        return base_gap + (free_sp / (item_count - 1));
    }
    return base_gap;
}

int32_t blink_table_col_start_formal(int32_t avail_w,
                                     int32_t total_cols,
                                     int32_t col_idx,
                                     blink_layout_mode_t mode) {
    if (total_cols <= 0) return 0;
    return (int32_t)blink_z_partition_boundary(avail_w, total_cols, col_idx, mode);
}

int32_t blink_table_col_width_formal(int32_t avail_w,
                                     int32_t total_cols,
                                     int32_t col_idx,
                                     blink_layout_mode_t mode) {
    if (total_cols <= 0) return 0;
    int32_t s0 = blink_table_col_start_formal(avail_w, total_cols, col_idx, mode);
    int32_t s1 = blink_table_col_start_formal(avail_w, total_cols, col_idx + 1, mode);
    return s1 - s0;
}

/* ------------------------------------------------------------------------- */
/* 7. CSS Color & Stylesheet Parser (`@layer`, `@media`, `!important`)       */
/* ------------------------------------------------------------------------- */

uint32_t blink_parse_css_color(const char* s, bool* out_ok) {
    if (out_ok) *out_ok = false;
    if (!s) return BLINK_COLOR_TEXT_DEFAULT;
    while (*s && isspace((unsigned char)*s)) s++;
    if (!*s) return BLINK_COLOR_TEXT_DEFAULT;

    if (strcasecmp(s, "transparent") == 0) {
        if (out_ok) *out_ok = true;
        return 0x00000000u;
    }

    if (*s == '#') {
        s++;
        size_t hexlen = 0;
        while (isxdigit((unsigned char)s[hexlen])) hexlen++;
        if (hexlen == 3) {
            unsigned int r, g, b;
            if (sscanf(s, "%1x%1x%1x", &r, &g, &b) == 3) {
                if (out_ok) *out_ok = true;
                return (0xFFu << 24) | ((r * 17u) << 16) | ((g * 17u) << 8) | (b * 17u);
            }
        } else if (hexlen >= 6) {
            unsigned int r, g, b;
            if (sscanf(s, "%2x%2x%2x", &r, &g, &b) == 3) {
                if (out_ok) *out_ok = true;
                return (0xFFu << 24) | (r << 16) | (g << 8) | b;
            }
        }
        return BLINK_COLOR_TEXT_DEFAULT;
    }

    if (strncasecmp(s, "rgba(", 5) == 0 || strncasecmp(s, "rgb(", 4) == 0) {
        const char* p = strchr(s, '(');
        if (p) {
            int r = 0, g = 0, b = 0;
            float af = 1.0f;
            int matched = sscanf(p + 1, "%d , %d , %d , %f", &r, &g, &b, &af);
            if (matched < 3) matched = sscanf(p + 1, "%d %d %d", &r, &g, &b);
            if (matched >= 3) {
                if (r < 0) r = 0; else if (r > 255) r = 255;
                if (g < 0) g = 0; else if (g > 255) g = 255;
                if (b < 0) b = 0; else if (b > 255) b = 255;
                int a = (int)lroundf(af * 255.0f);
                if (a < 0) a = 0; else if (a > 255) a = 255;
                if (out_ok) *out_ok = true;
                return ((uint32_t)a << 24) | ((uint32_t)r << 16) | ((uint32_t)g << 8) | (uint32_t)b;
            }
        }
        return BLINK_COLOR_TEXT_DEFAULT;
    }

    struct { const char* name; uint32_t argb; } named[] = {
        {"white", 0xFFFFFFFFu}, {"black", 0xFF000000u}, {"red", 0xFFEA4335u},
        {"crimson", 0xFFDC143Cu}, {"green", 0xFF34A853u}, {"blue", 0xFF1A73E8u},
        {"navy", 0xFF0D47A1u}, {"teal", 0xFF00796Bu}, {"orange", 0xFFFB8C00u},
        {"gold", 0xFFF9AB00u}, {"yellow", 0xFFFBBC05u}, {"purple", 0xFF7B1FA2u},
        {"indigo", 0xFF3949ABu}, {"gray", 0xFF5F6368u}, {"grey", 0xFF5F6368u},
        {"lightgray", 0xFFDADCE0u}, {"lightgrey", 0xFFDADCE0u}, {"whitesmoke", 0xFFF5F5F5u}
    };
    for (size_t i = 0; i < sizeof(named) / sizeof(named[0]); i++) {
        size_t nl = strlen(named[i].name);
        if (strncasecmp(s, named[i].name, nl) == 0 && (!s[nl] || isspace((unsigned char)s[nl]))) {
            if (out_ok) *out_ok = true;
            return named[i].argb;
        }
    }
    return BLINK_COLOR_TEXT_DEFAULT;
}

void blink_css_stylesheet_init(blink_css_stylesheet_t* sheet) {
    if (!sheet) return;
    memset(sheet, 0, sizeof(*sheet));
}

static int32_t get_or_register_layer(blink_css_stylesheet_t* sheet, const char* name) {
    char clean[48];
    strncpy(clean, name ? name : "", sizeof(clean) - 1);
    clean[sizeof(clean) - 1] = '\0';
    trim_inplace(clean);
    if (!clean[0]) return BLINK_UNLAYERED_ORDER;

    for (int i = 0; i < sheet->num_layers; i++) {
        if (strcmp(sheet->layer_names[i], clean) == 0) return i;
    }
    if (sheet->num_layers < BLINK_MAX_LAYERS) {
        int idx = sheet->num_layers++;
        strcpy(sheet->layer_names[idx], clean);
        return idx;
    }
    return sheet->num_layers - 1;
}

static int parse_declarations_list(const char* block, blink_css_decl_t* out_decls, int max_decls) {
    if (!block || !out_decls || max_decls <= 0) return 0;
    int count = 0;
    const char* p = block;

    while (*p && count < max_decls) {
        while (*p && (isspace((unsigned char)*p) || *p == ';')) p++;
        if (!*p) break;

        /* Find ':' */
        const char* ks = p;
        while (*p && *p != ':' && *p != ';') p++;
        if (*p != ':') {
            while (*p && *p != ';') p++;
            continue;
        }
        char key[48];
        size_t klen = (size_t)(p - ks);
        if (klen >= sizeof(key)) klen = sizeof(key) - 1;
        memcpy(key, ks, klen);
        key[klen] = '\0';
        trim_inplace(key);
        if (!(key[0] == '-' && key[1] == '-')) {
            for (size_t i = 0; key[i]; i++) key[i] = (char)tolower((unsigned char)key[i]);
        }

        p++; /* skip ':' */
        const char* vs = p;
        int paren = 0;
        char quote = 0;
        while (*p) {
            if (quote) {
                if (*p == quote) quote = 0;
            } else {
                if (*p == '"' || *p == '\'') quote = *p;
                else if (*p == '(') paren++;
                else if (*p == ')' && paren > 0) paren--;
                else if (*p == ';' && paren == 0) break;
            }
            p++;
        }

        char val[192];
        size_t vlen = (size_t)(p - vs);
        if (vlen >= sizeof(val)) vlen = sizeof(val) - 1;
        memcpy(val, vs, vlen);
        val[vlen] = '\0';
        trim_inplace(val);

        bool important = false;
        const char* imp = strcasestr_portable(val, "!important");
        if (imp) {
            important = true;
            val[(size_t)(imp - val)] = '\0';
            trim_inplace(val);
        }

        if (key[0] && val[0]) {
            strcpy(out_decls[count].prop, key);
            strcpy(out_decls[count].value, val);
            out_decls[count].important = important;
            count++;
        }
        if (*p == ';') p++;
    }
    return count;
}

static char* strip_css_comments(const char* src) {
    if (!src) return NULL;
    size_t len = strlen(src);
    char* dst = (char*)malloc(len + 1);
    if (!dst) return NULL;
    size_t i = 0, j = 0;
    while (i < len) {
        if (src[i] == '/' && src[i + 1] == '*') {
            i += 2;
            while (i + 1 < len && !(src[i] == '*' && src[i + 1] == '/')) i++;
            if (i + 1 < len) i += 2;
            dst[j++] = ' ';
        } else {
            dst[j++] = src[i++];
        }
    }
    dst[j] = '\0';
    return dst;
}

static void parse_css_rules_in_context(blink_css_stylesheet_t* sheet,
                                       const char* css,
                                       int32_t active_layer,
                                       int32_t media_min_w,
                                       int32_t media_max_w) {
    const char* p = css;
    while (*p) {
        while (*p && isspace((unsigned char)*p)) p++;
        if (!*p) break;

        if (*p == '@') {
            if (strncasecmp(p, "@layer", 6) == 0 && (isspace((unsigned char)p[6]) || p[6] == '{')) {
                p += 6;
                while (*p && isspace((unsigned char)*p)) p++;
                const char* head_start = p;
                while (*p && *p != '{' && *p != ';') p++;
                char head[192];
                size_t hlen = (size_t)(p - head_start);
                if (hlen >= sizeof(head)) hlen = sizeof(head) - 1;
                memcpy(head, head_start, hlen);
                head[hlen] = '\0';
                trim_inplace(head);

                if (*p == ';') {
                    /* `@layer base, theme, utilities;` statement registers layer order! */
                    char* saveptr = NULL;
                    char* tok = strtok_r(head, ",", &saveptr);
                    while (tok) {
                        get_or_register_layer(sheet, tok);
                        tok = strtok_r(NULL, ",", &saveptr);
                    }
                    p++;
                    continue;
                } else if (*p == '{') {
                    int32_t layer_id = get_or_register_layer(sheet, head);
                    p++;
                    const char* body_start = p;
                    int depth = 1;
                    while (*p && depth > 0) {
                        if (*p == '{') depth++;
                        else if (*p == '}') depth--;
                        if (depth > 0) p++;
                    }
                    size_t blen = (size_t)(p - body_start);
                    char* sub = (char*)malloc(blen + 1);
                    if (sub) {
                        memcpy(sub, body_start, blen);
                        sub[blen] = '\0';
                        parse_css_rules_in_context(sheet, sub, layer_id, media_min_w, media_max_w);
                        free(sub);
                    }
                    if (*p == '}') p++;
                    continue;
                }
            } else if (strncasecmp(p, "@media", 6) == 0) {
                p += 6;
                const char* qstart = p;
                while (*p && *p != '{') p++;
                char qbuf[192];
                size_t qlen = (size_t)(p - qstart);
                if (qlen >= sizeof(qbuf)) qlen = sizeof(qbuf) - 1;
                memcpy(qbuf, qstart, qlen);
                qbuf[qlen] = '\0';

                int32_t min_w = media_min_w;
                int32_t max_w = media_max_w;
                const char* mn = strcasestr_portable(qbuf, "min-width");
                if (mn) {
                    const char* col = strchr(mn, ':');
                    if (col) min_w = atoi(col + 1);
                }
                const char* mx = strcasestr_portable(qbuf, "max-width");
                if (mx) {
                    const char* col = strchr(mx, ':');
                    if (col) max_w = atoi(col + 1);
                }

                if (*p == '{') {
                    p++;
                    const char* body_start = p;
                    int depth = 1;
                    while (*p && depth > 0) {
                        if (*p == '{') depth++;
                        else if (*p == '}') depth--;
                        if (depth > 0) p++;
                    }
                    size_t blen = (size_t)(p - body_start);
                    char* sub = (char*)malloc(blen + 1);
                    if (sub) {
                        memcpy(sub, body_start, blen);
                        sub[blen] = '\0';
                        parse_css_rules_in_context(sheet, sub, active_layer, min_w, max_w);
                        free(sub);
                    }
                    if (*p == '}') p++;
                    continue;
                }
            } else {
                /* Skip other @-rules (@import, @keyframes, @font-face) */
                while (*p && *p != ';' && *p != '{') p++;
                if (*p == ';') {
                    p++;
                } else if (*p == '{') {
                    int depth = 1;
                    p++;
                    while (*p && depth > 0) {
                        if (*p == '{') depth++;
                        else if (*p == '}') depth--;
                        p++;
                    }
                }
                continue;
            }
        }

        /* Standard qualified rule: `selector_list { declarations }` */
        const char* sel_start = p;
        while (*p && *p != '{') p++;
        if (*p != '{') break;

        size_t sel_len = (size_t)(p - sel_start);
        char* sel_group = (char*)malloc(sel_len + 1);
        if (!sel_group) break;
        memcpy(sel_group, sel_start, sel_len);
        sel_group[sel_len] = '\0';

        p++; /* skip '{' */
        const char* decl_start = p;
        int depth = 1;
        while (*p && depth > 0) {
            if (*p == '{') depth++;
            else if (*p == '}') depth--;
            if (depth > 0) p++;
        }
        size_t decl_len = (size_t)(p - decl_start);
        if (*p == '}') p++;

        char* decl_block = (char*)malloc(decl_len + 1);
        if (!decl_block) { free(sel_group); break; }
        memcpy(decl_block, decl_start, decl_len);
        decl_block[decl_len] = '\0';

        blink_css_decl_t parsed_decls[BLINK_MAX_RULE_DECLS];
        int num_decls = parse_declarations_list(decl_block, parsed_decls, BLINK_MAX_RULE_DECLS);

        /* Split comma-separated selector list (respecting parentheses like :where(...)) */
        if (num_decls > 0) {
            const char* sp = sel_group;
            while (*sp && sheet->num_rules < BLINK_MAX_STYLESHEET_RULES) {
                const char* item_start = sp;
                int paren = 0;
                while (*sp && !(paren == 0 && *sp == ',')) {
                    if (*sp == '(') paren++;
                    else if (*sp == ')' && paren > 0) paren--;
                    sp++;
                }
                size_t ilen = (size_t)(sp - item_start);
                char single_sel[192];
                if (ilen >= sizeof(single_sel)) ilen = sizeof(single_sel) - 1;
                memcpy(single_sel, item_start, ilen);
                single_sel[ilen] = '\0';
                trim_inplace(single_sel);

                blink_complex_sel_t csel;
                if (single_sel[0] && blink_css_parse_selector(single_sel, &csel)) {
                    blink_css_rule_t* rule = &sheet->rules[sheet->num_rules++];
                    rule->selector = csel;
                    rule->num_decls = num_decls;
                    for (int d = 0; d < num_decls; d++) rule->decls[d] = parsed_decls[d];
                    rule->layer_order = active_layer;
                    rule->source_order = sheet->next_source_order;
                    sheet->next_source_order += 64;
                    rule->media_min_w = media_min_w;
                    rule->media_max_w = media_max_w;
                }
                if (*sp == ',') sp++;
            }
        }

        free(decl_block);
        free(sel_group);
    }
}

void blink_css_parse_stylesheet(blink_css_stylesheet_t* sheet, const char* css_text) {
    if (!sheet || !css_text) return;
    char* clean = strip_css_comments(css_text);
    if (!clean) return;
    parse_css_rules_in_context(sheet, clean, BLINK_UNLAYERED_ORDER, -1, -1);
    free(clean);
}

/* ------------------------------------------------------------------------- */
/* 8. Full Cascade Level 5 + Inheritance + Keyword Duality Resolver          */
/* ------------------------------------------------------------------------- */

typedef struct {
    blink_css_decl_t     decl;
    blink_cascade_meta_t meta;
} candidate_decl_t;

static int cmp_candidate_decl(const void* pa, const void* pb) {
    const candidate_decl_t* a = (const candidate_decl_t*)pa;
    const candidate_decl_t* b = (const candidate_decl_t*)pb;
    if (blink_cascade_meta_lt(a->meta, b->meta)) return -1;
    if (blink_cascade_meta_lt(b->meta, a->meta)) return 1;
    return 0;
}

static bool is_inherited_css_prop(const char* prop) {
    return strcmp(prop, "color") == 0 ||
           strcmp(prop, "font-size") == 0 ||
           strcmp(prop, "font-weight") == 0 ||
           strcmp(prop, "font-style") == 0 ||
           strcmp(prop, "font-family") == 0 ||
           strcmp(prop, "line-height") == 0 ||
           strcmp(prop, "text-align") == 0;
}

static void set_custom_prop(dom_style_t* st, const char* name, const char* val) {
    for (int i = 0; i < st->num_custom_props; i++) {
        if (strcmp(st->custom_props[i].name, name) == 0) {
            strncpy(st->custom_props[i].value, val, sizeof(st->custom_props[i].value) - 1);
            st->custom_props[i].value[sizeof(st->custom_props[i].value) - 1] = '\0';
            return;
        }
    }
    if (st->num_custom_props < BLINK_MAX_CUSTOM_PROPS) {
        int idx = st->num_custom_props++;
        strncpy(st->custom_props[idx].name, name, sizeof(st->custom_props[idx].name) - 1);
        st->custom_props[idx].name[sizeof(st->custom_props[idx].name) - 1] = '\0';
        strncpy(st->custom_props[idx].value, val, sizeof(st->custom_props[idx].value) - 1);
        st->custom_props[idx].value[sizeof(st->custom_props[idx].value) - 1] = '\0';
    }
}

static void apply_keyword_reset(dom_style_t* st, const dom_style_t* src, const char* prop) {
    if (strcmp(prop, "color") == 0) st->color = src->color;
    else if (strcmp(prop, "background") == 0 || strcmp(prop, "background-color") == 0) {
        st->bg_color = src->bg_color;
        st->has_bg = src->has_bg;
    } else if (strcmp(prop, "font-size") == 0) st->font_size = src->font_size;
    else if (strcmp(prop, "font-weight") == 0) st->font_weight = src->font_weight;
    else if (strcmp(prop, "font-style") == 0) st->font_style = src->font_style;
    else if (strcmp(prop, "font-family") == 0) strcpy(st->font_family, src->font_family);
    else if (strcmp(prop, "text-align") == 0) st->text_align = src->text_align;
    else if (strcmp(prop, "margin") == 0) {
        st->margin_top = src->margin_top; st->margin_right = src->margin_right;
        st->margin_bottom = src->margin_bottom; st->margin_left = src->margin_left;
    } else if (strcmp(prop, "padding") == 0) {
        st->padding_top = src->padding_top; st->padding_right = src->padding_right;
        st->padding_bottom = src->padding_bottom; st->padding_left = src->padding_left;
    } else if (strcmp(prop, "border") == 0 || strcmp(prop, "border-width") == 0) {
        st->border_width = src->border_width;
        st->border_left_width = src->border_left_width;
        st->border_bottom_width = src->border_bottom_width;
    } else if (strcmp(prop, "width") == 0) st->width = src->width;
    else if (strcmp(prop, "height") == 0) st->height = src->height;
    else if (strcmp(prop, "display") == 0) st->display = src->display;
    else if (strcmp(prop, "box-sizing") == 0) st->box_sizing = src->box_sizing;
}

static void parse_border_shorthand(const char* val,
                                   int32_t em_px, int32_t rem_px, int32_t vw_px, int32_t vh_px,
                                   blink_layout_mode_t mode,
                                   int* out_w, uint32_t* io_color) {
    *out_w = 0;
    if (!val || strcasecmp(val, "none") == 0 || strcmp(val, "0") == 0) return;

    char copy[192];
    strncpy(copy, val, sizeof(copy) - 1);
    copy[sizeof(copy) - 1] = '\0';

    bool saw_style = false;
    bool saw_width = false;
    char* save = NULL;
    char* tok = strtok_r(copy, " \t", &save);
    while (tok) {
        if (strcasecmp(tok, "solid") == 0 || strcasecmp(tok, "dashed") == 0 ||
            strcasecmp(tok, "dotted") == 0 || strcasecmp(tok, "double") == 0) {
            saw_style = true;
        } else if (isdigit((unsigned char)tok[0])) {
            bool is_auto = false;
            *out_w = blink_css_eval_length_or_calc(tok, 0, em_px, rem_px, vw_px, vh_px, mode, &is_auto);
            saw_width = true;
        } else {
            bool cok = false;
            uint32_t c = blink_parse_css_color(tok, &cok);
            if (cok) *io_color = c;
        }
        tok = strtok_r(NULL, " \t", &save);
    }
    if (!saw_width && saw_style) *out_w = 1;
}

static void apply_resolved_css_decl(dom_style_t* st,
                                    const dom_style_t* parent_st,
                                    const dom_style_t* initial_st,
                                    const char* prop,
                                    const char* val,
                                    int32_t parent_avail_w,
                                    int32_t root_font_px,
                                    int32_t vw_px,
                                    int32_t vh_px,
                                    blink_layout_mode_t mode) {
    /* CSS Cascade Keyword Duality (`initial` / `inherit` / `unset`) */
    if (strcasecmp(val, "initial") == 0) {
        apply_keyword_reset(st, initial_st, prop);
        return;
    }
    if (strcasecmp(val, "inherit") == 0) {
        apply_keyword_reset(st, parent_st ? parent_st : initial_st, prop);
        return;
    }
    if (strcasecmp(val, "unset") == 0) {
        const dom_style_t* target = (is_inherited_css_prop(prop) && parent_st) ? parent_st : initial_st;
        apply_keyword_reset(st, target, prop);
        return;
    }

    int32_t em_px = (int32_t)lroundf(st->font_size);
    int32_t parent_font_px = parent_st ? (int32_t)lroundf(parent_st->font_size) : root_font_px;

    if (strcmp(prop, "color") == 0) {
        bool ok = false;
        uint32_t c = blink_parse_css_color(val, &ok);
        if (ok) st->color = c;
    } else if (strcmp(prop, "background-color") == 0 || strcmp(prop, "background") == 0) {
        if (strcasecmp(val, "none") == 0 || strcasecmp(val, "transparent") == 0) {
            st->bg_color = 0;
            st->has_bg = false;
        } else {
            bool ok = false;
            uint32_t c = blink_parse_css_color(val, &ok);
            if (ok) {
                st->bg_color = c;
                st->has_bg = ((c >> 24) > 0);
            }
        }
    } else if (strcmp(prop, "font-size") == 0) {
        bool is_auto = false;
        int32_t sz = blink_css_eval_length_or_calc(val, parent_font_px, parent_font_px, root_font_px, vw_px, vh_px, mode, &is_auto);
        if (!is_auto && sz > 0) st->font_size = (float)sz;
    } else if (strcmp(prop, "font-weight") == 0) {
        if (strcasestr_portable(val, "bold") || atoi(val) >= 600) st->font_weight = 700;
        else st->font_weight = 400;
    } else if (strcmp(prop, "font-style") == 0) {
        st->font_style = (strcasestr_portable(val, "italic") || strcasestr_portable(val, "oblique")) ? 1 : 0;
    } else if (strcmp(prop, "font-family") == 0) {
        strncpy(st->font_family, val, sizeof(st->font_family) - 1);
        st->font_family[sizeof(st->font_family) - 1] = '\0';
    } else if (strcmp(prop, "line-height") == 0) {
        float lh = strtof(val, NULL);
        if (lh > 0.0f) st->line_height = (lh > 4.0f) ? (lh / st->font_size) : lh;
    } else if (strcmp(prop, "margin") == 0) {
        blink_box_edges_t e;
        blink_css_parse_box_shorthand(val, parent_avail_w, em_px, root_font_px, vw_px, vh_px, mode, &e);
        st->margin_top = e.top; st->margin_right = e.right;
        st->margin_bottom = e.bottom; st->margin_left = e.left;
    } else if (strcmp(prop, "margin-top") == 0) {
        st->margin_top = blink_css_eval_length_or_calc(val, parent_avail_w, em_px, root_font_px, vw_px, vh_px, mode, NULL);
    } else if (strcmp(prop, "margin-right") == 0) {
        st->margin_right = blink_css_eval_length_or_calc(val, parent_avail_w, em_px, root_font_px, vw_px, vh_px, mode, NULL);
    } else if (strcmp(prop, "margin-bottom") == 0) {
        st->margin_bottom = blink_css_eval_length_or_calc(val, parent_avail_w, em_px, root_font_px, vw_px, vh_px, mode, NULL);
    } else if (strcmp(prop, "margin-left") == 0) {
        st->margin_left = blink_css_eval_length_or_calc(val, parent_avail_w, em_px, root_font_px, vw_px, vh_px, mode, NULL);
    } else if (strcmp(prop, "padding") == 0) {
        blink_box_edges_t e;
        blink_css_parse_box_shorthand(val, parent_avail_w, em_px, root_font_px, vw_px, vh_px, mode, &e);
        st->padding_top = e.top; st->padding_right = e.right;
        st->padding_bottom = e.bottom; st->padding_left = e.left;
    } else if (strcmp(prop, "padding-top") == 0) {
        st->padding_top = blink_css_eval_length_or_calc(val, parent_avail_w, em_px, root_font_px, vw_px, vh_px, mode, NULL);
    } else if (strcmp(prop, "padding-right") == 0) {
        st->padding_right = blink_css_eval_length_or_calc(val, parent_avail_w, em_px, root_font_px, vw_px, vh_px, mode, NULL);
    } else if (strcmp(prop, "padding-bottom") == 0) {
        st->padding_bottom = blink_css_eval_length_or_calc(val, parent_avail_w, em_px, root_font_px, vw_px, vh_px, mode, NULL);
    } else if (strcmp(prop, "padding-left") == 0) {
        st->padding_left = blink_css_eval_length_or_calc(val, parent_avail_w, em_px, root_font_px, vw_px, vh_px, mode, NULL);
    } else if (strcmp(prop, "width") == 0) {
        bool is_auto = false;
        int32_t w = blink_css_eval_length_or_calc(val, parent_avail_w, em_px, root_font_px, vw_px, vh_px, mode, &is_auto);
        st->width = is_auto ? -1 : w;
    } else if (strcmp(prop, "height") == 0) {
        bool is_auto = false;
        int32_t h = blink_css_eval_length_or_calc(val, vh_px, em_px, root_font_px, vw_px, vh_px, mode, &is_auto);
        st->height = is_auto ? -1 : h;
    } else if (strcmp(prop, "border") == 0) {
        int bw = 0;
        parse_border_shorthand(val, em_px, root_font_px, vw_px, vh_px, mode, &bw, &st->border_color);
        st->border_width = bw;
    } else if (strcmp(prop, "border-width") == 0) {
        st->border_width = blink_css_eval_length_or_calc(val, 0, em_px, root_font_px, vw_px, vh_px, mode, NULL);
    } else if (strcmp(prop, "border-left") == 0) {
        int bw = 0;
        uint32_t lc = st->border_color;
        parse_border_shorthand(val, em_px, root_font_px, vw_px, vh_px, mode, &bw, &lc);
        st->border_left_width = bw;
        st->border_left_color = lc;
    } else if (strcmp(prop, "border-bottom") == 0) {
        int bw = 0;
        parse_border_shorthand(val, em_px, root_font_px, vw_px, vh_px, mode, &bw, &st->border_color);
        st->border_bottom_width = bw;
    } else if (strcmp(prop, "border-color") == 0) {
        bool ok = false;
        uint32_t c = blink_parse_css_color(val, &ok);
        if (ok) st->border_color = c;
    } else if (strcmp(prop, "border-radius") == 0) {
        st->border_radius = blink_css_eval_length_or_calc(val, parent_avail_w, em_px, root_font_px, vw_px, vh_px, mode, NULL);
    } else if (strcmp(prop, "box-sizing") == 0) {
        if (strcasestr_portable(val, "border-box")) st->box_sizing = BOX_SIZING_BORDER_BOX;
        else st->box_sizing = BOX_SIZING_CONTENT_BOX;
    } else if (strcmp(prop, "display") == 0) {
        if (strcasestr_portable(val, "none")) st->display = DISPLAY_NONE;
        else if (strcasestr_portable(val, "inline-block")) st->display = DISPLAY_INLINE_BLOCK;
        else if (strcasestr_portable(val, "inline")) st->display = DISPLAY_INLINE;
        else if (strcasestr_portable(val, "grid")) st->display = DISPLAY_GRID;
        else if (strcasestr_portable(val, "flex")) st->display = DISPLAY_FLEX;
        else if (strcasestr_portable(val, "table-row-group")) st->display = DISPLAY_TABLE_ROW_GROUP;
        else if (strcasestr_portable(val, "table-row")) st->display = DISPLAY_TABLE_ROW;
        else if (strcasestr_portable(val, "table-cell")) st->display = DISPLAY_TABLE_CELL;
        else if (strcasestr_portable(val, "table")) st->display = DISPLAY_TABLE;
        else if (strcasestr_portable(val, "list-item")) st->display = DISPLAY_LIST_ITEM;
        else st->display = DISPLAY_BLOCK;
    } else if (strcmp(prop, "grid-template-columns") == 0) {
        st->num_grid_cols = 0;
        if (strncasecmp(val, "repeat(", 7) == 0) {
            int reps = atoi(val + 7);
            const char* comma = strchr(val + 7, ',');
            if (reps > 0 && reps <= 16 && comma) {
                char track[64];
                strncpy(track, comma + 1, sizeof(track) - 1);
                track[sizeof(track) - 1] = '\0';
                char* rp = strrchr(track, ')');
                if (rp) *rp = '\0';
                trim_inplace(track);
                int w_spec = -1;
                if (strcasestr_portable(track, "fr")) {
                    int fr = atoi(track);
                    w_spec = (fr > 0) ? -fr : -1;
                } else {
                    w_spec = blink_css_eval_length_or_calc(track, parent_avail_w, em_px, root_font_px, vw_px, vh_px, mode, NULL);
                }
                for (int r = 0; r < reps && st->num_grid_cols < 16; r++) {
                    st->grid_col_widths[st->num_grid_cols++] = w_spec;
                }
            }
        } else {
            char copy[192];
            strncpy(copy, val, sizeof(copy) - 1);
            copy[sizeof(copy) - 1] = '\0';
            char* save = NULL;
            char* tok = strtok_r(copy, " \t", &save);
            while (tok && st->num_grid_cols < 16) {
                if (strcasestr_portable(tok, "fr")) {
                    int fr = atoi(tok);
                    st->grid_col_widths[st->num_grid_cols++] = (fr > 0) ? -fr : -1;
                } else {
                    int32_t w = blink_css_eval_length_or_calc(tok, parent_avail_w, em_px, root_font_px, vw_px, vh_px, mode, NULL);
                    st->grid_col_widths[st->num_grid_cols++] = (w > 0) ? w : -1;
                }
                tok = strtok_r(NULL, " \t", &save);
            }
        }
    } else if (strcmp(prop, "align-items") == 0) {
        st->align_items_center = (strcasestr_portable(val, "center") != NULL);
    } else if (strcmp(prop, "justify-content") == 0) {
        if (strcasestr_portable(val, "space-between")) st->justify_content = JUSTIFY_SPACE_BETWEEN;
        else if (strcasestr_portable(val, "center")) st->justify_content = JUSTIFY_CENTER;
        else if (strcasestr_portable(val, "flex-end") || strcasestr_portable(val, "end")) st->justify_content = JUSTIFY_FLEX_END;
        else st->justify_content = JUSTIFY_FLEX_START;
    } else if (strcmp(prop, "gap") == 0) {
        int32_t g = blink_css_eval_length_or_calc(val, parent_avail_w, em_px, root_font_px, vw_px, vh_px, mode, NULL);
        st->gap = g;
        st->row_gap = g;
    } else if (strcmp(prop, "column-gap") == 0) {
        st->gap = blink_css_eval_length_or_calc(val, parent_avail_w, em_px, root_font_px, vw_px, vh_px, mode, NULL);
    } else if (strcmp(prop, "row-gap") == 0) {
        st->row_gap = blink_css_eval_length_or_calc(val, parent_avail_w, em_px, root_font_px, vw_px, vh_px, mode, NULL);
    } else if (strcmp(prop, "flex-grow") == 0 || strcmp(prop, "flex") == 0) {
        int fg = atoi(val);
        if (fg >= 0) st->flex_grow = fg;
    } else if (strcmp(prop, "text-align") == 0) {
        if (strcasestr_portable(val, "center")) st->text_align = ALIGN_CENTER;
        else if (strcasestr_portable(val, "right") || strcasestr_portable(val, "end")) st->text_align = ALIGN_RIGHT;
        else st->text_align = ALIGN_LEFT;
    }
}

static void resolve_node_recursive(dom_node_t* node,
                                   const blink_css_stylesheet_t* sheet,
                                   const dom_style_t* initial_st,
                                   int32_t parent_avail_w,
                                   int32_t root_font_px,
                                   int32_t vw_px,
                                   int32_t vh_px,
                                   blink_layout_mode_t mode) {
    if (!node) return;

    const dom_style_t* parent_st = node->parent ? &node->parent->style : NULL;

    /* Text nodes purely inherit parent's computed typographic & color properties */
    if (strcmp(node->tag, "#text") == 0) {
        if (parent_st) {
            node->style.color = parent_st->color;
            node->style.font_size = parent_st->font_size;
            node->style.font_weight = parent_st->font_weight;
            node->style.font_style = parent_st->font_style;
            strcpy(node->style.font_family, parent_st->font_family);
            node->style.line_height = parent_st->line_height;
            node->style.text_align = parent_st->text_align;
        }
        return;
    }

    /* 1. Initialize from UA defaults + CSS Inheritance from parent */
    node->style = node->ua_style;
    if (parent_st) {
        if (!tag_has_explicit_ua_color(node->tag)) node->style.color = parent_st->color;
        if (!tag_has_explicit_ua_font_size(node->tag)) node->style.font_size = parent_st->font_size;
        if (!tag_has_explicit_ua_font_weight(node->tag)) node->style.font_weight = parent_st->font_weight;
        if (!tag_has_explicit_ua_font_style(node->tag)) node->style.font_style = parent_st->font_style;
        if (!tag_has_explicit_ua_font_family(node->tag)) strcpy(node->style.font_family, parent_st->font_family);
        node->style.line_height = parent_st->line_height;
        node->style.text_align = parent_st->text_align;

        node->style.num_custom_props = parent_st->num_custom_props;
        for (int i = 0; i < parent_st->num_custom_props; i++) {
            node->style.custom_props[i] = parent_st->custom_props[i];
        }
    }

    /* 2. Gather matching Author & Inline declarations */
    candidate_decl_t cands[512];
    int num_cands = 0;

    if (sheet) {
        for (int r = 0; r < sheet->num_rules; r++) {
            const blink_css_rule_t* rule = &sheet->rules[r];
            if (rule->media_min_w >= 0 && vw_px < rule->media_min_w) continue;
            if (rule->media_max_w >= 0 && vw_px > rule->media_max_w) continue;
            if (!blink_css_match_selector(node, &rule->selector)) continue;

            for (int d = 0; d < rule->num_decls && num_cands < 512; d++) {
                cands[num_cands].decl = rule->decls[d];
                cands[num_cands].meta.origin = CSS_ORIGIN_AUTHOR;
                cands[num_cands].meta.important = rule->decls[d].important;
                cands[num_cands].meta.layer_order = rule->layer_order;
                cands[num_cands].meta.specificity = rule->selector.specificity;
                cands[num_cands].meta.source_order = rule->source_order + d;
                num_cands++;
            }
        }
    }

    if (node->inline_style_raw && node->inline_style_raw[0]) {
        blink_css_decl_t idecls[BLINK_MAX_RULE_DECLS];
        int n_idecls = parse_declarations_list(node->inline_style_raw, idecls, BLINK_MAX_RULE_DECLS);
        for (int d = 0; d < n_idecls && num_cands < 512; d++) {
            cands[num_cands].decl = idecls[d];
            cands[num_cands].meta.origin = CSS_ORIGIN_INLINE;
            cands[num_cands].meta.important = idecls[d].important;
            cands[num_cands].meta.layer_order = BLINK_UNLAYERED_ORDER;
            cands[num_cands].meta.specificity = (blink_specificity_t){0, 0, 0};
            cands[num_cands].meta.source_order = 1000000 + d;
            num_cands++;
        }
    }

    /* 3. Sort declarations strictly by Cascade Level 5 Priority */
    if (num_cands > 1) {
        qsort(cands, (size_t)num_cands, sizeof(candidate_decl_t), cmp_candidate_decl);
    }

    /* 4. Pass A: Apply custom property declarations `--*` in cascade order */
    for (int i = 0; i < num_cands; i++) {
        if (cands[i].decl.prop[0] == '-' && cands[i].decl.prop[1] == '-') {
            set_custom_prop(&node->style, cands[i].decl.prop, cands[i].decl.value);
        }
    }

    /* 5. Pass B: Apply font-size first (so `em` units on same element use updated font-size!),
       then apply all standard properties with cycle-safe `var()` substitution */
    for (int pass = 0; pass < 2; pass++) {
        for (int i = 0; i < num_cands; i++) {
            const char* prop = cands[i].decl.prop;
            if (prop[0] == '-' && prop[1] == '-') continue;
            bool is_fs = (strcmp(prop, "font-size") == 0);
            if ((pass == 0 && !is_fs) || (pass == 1 && is_fs)) continue;

            char resolved_val[192];
            if (!blink_css_resolve_var_value(node->style.custom_props,
                                             node->style.num_custom_props,
                                             cands[i].decl.value,
                                             resolved_val,
                                             sizeof(resolved_val))) {
                continue; /* Cyclic or unresolved var() -> IACVT fallback */
            }

            apply_resolved_css_decl(&node->style, parent_st, initial_st,
                                    prop, resolved_val,
                                    parent_avail_w, root_font_px, vw_px, vh_px, mode);
        }
    }

    if (!node->parent) {
        root_font_px = (int32_t)lroundf(node->style.font_size);
    }

    /* Compute approximate available width passed to child `%` resolutions */
    int32_t child_avail = parent_avail_w - node->style.margin_left - node->style.margin_right;
    if (node->style.width > 0) {
        child_avail = blink_css_resolve_content_inline_size(
            node->style.box_sizing,
            node->style.width,
            node->style.padding_left + node->style.padding_right,
            node->style.border_width * 2);
    } else {
        child_avail -= (node->style.padding_left + node->style.padding_right + node->style.border_width * 2);
    }
    if (child_avail < 0) child_avail = 0;

    for (int i = 0; i < node->num_children; i++) {
        resolve_node_recursive(node->children[i], sheet, initial_st,
                               child_avail, root_font_px, vw_px, vh_px, mode);
    }
}

void blink_css_resolve_document_styles(dom_node_t* root,
                                       const blink_css_stylesheet_t* sheet,
                                       int32_t viewport_w,
                                       int32_t viewport_h,
                                       blink_layout_mode_t mode) {
    if (!root) return;
    dom_style_t initial_st;
    init_initial_style(&initial_st);
    int32_t root_font_px = 14;
    resolve_node_recursive(root, sheet, &initial_st, viewport_w - 32, root_font_px, viewport_w, viewport_h, mode);
}

/* ------------------------------------------------------------------------- */
/* 9. HTML Entity Unescaping & Full HTML5 Document Parser                    */
/* ------------------------------------------------------------------------- */

char* blink_unescape_html(const char* src) {
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
            } else if (strncmp(src + i, "&nbsp;", 6) == 0 || strncmp(src + i, "&#160;", 6) == 0) {
                dst[j++] = ' '; i += 6;
            } else if (strncmp(src + i, "&mdash;", 7) == 0 || strncmp(src + i, "&ndash;", 7) == 0) {
                dst[j++] = '-'; i += 7;
            } else if (strncmp(src + i, "&rarr;", 6) == 0) {
                dst[j++] = '-'; dst[j++] = '>'; i += 6;
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
            else if (b2 == 0xA2) dst[j++] = '*';
            i += 3;
        } else if ((unsigned char)src[i] >= 0x80) {
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

static void apply_parsed_attribute(dom_node_t* node, const char* attr_k, const char* attr_v) {
    if (!node || !attr_k) return;
    if (strcmp(attr_k, "style") == 0) {
        free(node->inline_style_raw);
        node->inline_style_raw = strdup(attr_v);
    } else if (strcmp(attr_k, "id") == 0) {
        free(node->id);
        node->id = strdup(attr_v);
    } else if (strcmp(attr_k, "class") == 0) {
        free(node->class_name);
        node->class_name = strdup(attr_v);
    } else if (strcmp(attr_k, "src") == 0) {
        free(node->src);
        node->src = strdup(attr_v);
    } else if (strcmp(attr_k, "href") == 0) {
        free(node->href);
        node->href = strdup(attr_v);
    } else if (strcmp(attr_k, "colspan") == 0) {
        node->colspan = blink_html_sanitize_span(atoi(attr_v), 1000);
    } else if (strcmp(attr_k, "rowspan") == 0) {
        node->rowspan = blink_html_sanitize_span(atoi(attr_v), 65534);
    } else if (strcmp(attr_k, "width") == 0 && strcmp(node->tag, "img") == 0) {
        int iw = atoi(attr_v);
        if (iw > 0) {
            node->ua_style.width = (iw > 360) ? 360 : iw;
            node->style.width = node->ua_style.width;
        }
    } else if (strcmp(attr_k, "height") == 0 && strcmp(node->tag, "img") == 0) {
        int ih = atoi(attr_v);
        if (ih > 0) {
            node->ua_style.height = (ih > 260) ? 260 : ih;
            node->style.height = node->ua_style.height;
        }
    } else if (node->num_attrs < BLINK_MAX_ATTRS && attr_k[0]) {
        strncpy(node->attrs[node->num_attrs].name, attr_k, 31);
        node->attrs[node->num_attrs].name[31] = '\0';
        strncpy(node->attrs[node->num_attrs].value, attr_v, 127);
        node->attrs[node->num_attrs].value[127] = '\0';
        node->num_attrs++;
    }
}

dom_node_t* blink_parse_html5_document(const char* html, blink_css_stylesheet_t* out_sheet) {
    if (!html) return NULL;
    if (out_sheet) blink_css_stylesheet_init(out_sheet);

    dom_node_t* root = dom_node_create("body");
    dom_node_t* current = root;
    bool in_head = false;

    /* Extract <title> for Parsoid documents lacking <h1> */
    const char* title_open = strcasestr_portable(html, "<title>");
    if (title_open) {
        title_open += 7;
        const char* title_close = strcasestr_portable(title_open, "</title>");
        if (title_close && title_close > title_open && (title_close - title_open) < 128 &&
            strcasestr_portable(html, "<h1") == NULL) {
            size_t tlen = (size_t)(title_close - title_open);
            char* raw_t = (char*)malloc(tlen + 1);
            memcpy(raw_t, title_open, tlen);
            raw_t[tlen] = '\0';
            dom_node_t* h1 = dom_node_create("h1");
            dom_node_t* tn = dom_node_create("#text");
            tn->text = blink_unescape_html(raw_t);
            free(raw_t);
            dom_node_add_child(h1, tn);
            dom_node_add_child(root, h1);
        }
    }

    const char* p = html;
    while (*p) {
        if (*p == '<') {
            /* HTML Comment: <!-- ... --> */
            if (strncmp(p, "<!--", 4) == 0) {
                const char* end_c = strstr(p + 4, "-->");
                p = end_c ? (end_c + 3) : (p + strlen(p));
                continue;
            }
            /* DOCTYPE or XML declaration: <!DOCTYPE ...> / <?xml ...> */
            if (p[1] == '!' || p[1] == '?') {
                while (*p && *p != '>') p++;
                if (*p == '>') p++;
                continue;
            }
            /* Closing Tag: </tag> */
            if (p[1] == '/') {
                p += 2;
                char close_tag[32];
                int ti = 0;
                while (*p && *p != '>' && !isspace((unsigned char)*p) && ti < 31) {
                    close_tag[ti++] = (char)tolower((unsigned char)*p++);
                }
                close_tag[ti] = '\0';
                while (*p && *p != '>') p++;
                if (*p == '>') p++;

                if (strcmp(close_tag, "head") == 0) {
                    in_head = false;
                    continue;
                }
                if (strcmp(close_tag, "html") == 0 || strcmp(close_tag, "body") == 0) {
                    continue;
                }
                current = html5_pop_until_in_scope(current, root, close_tag);
                continue;
            }

            /* Opening Tag: <tag attr="val" ...> */
            p++;
            if (!isalpha((unsigned char)*p)) {
                /* Stray '<' in text */
                dom_node_t* tn = dom_node_create("#text");
                tn->text = strdup("<");
                dom_node_add_child(current, tn);
                continue;
            }

            char tag[32];
            int ti = 0;
            while (*p && *p != '>' && !isspace((unsigned char)*p) && *p != '/' && ti < 31) {
                tag[ti++] = (char)tolower((unsigned char)*p++);
            }
            tag[ti] = '\0';

            bool is_doc_wrapper = (strcmp(tag, "html") == 0 || strcmp(tag, "body") == 0);
            if (strcmp(tag, "head") == 0) {
                in_head = true;
                while (*p && *p != '>') p++;
                if (*p == '>') p++;
                continue;
            }

            /* Parse <style>...</style> into stylesheet! */
            if (strcmp(tag, "style") == 0) {
                while (*p && *p != '>') p++;
                if (*p == '>') p++;
                const char* css_end = strcasestr_portable(p, "</style>");
                size_t clen = css_end ? (size_t)(css_end - p) : strlen(p);
                if (out_sheet && clen > 0) {
                    char* css_buf = (char*)malloc(clen + 1);
                    if (css_buf) {
                        memcpy(css_buf, p, clen);
                        css_buf[clen] = '\0';
                        blink_css_parse_stylesheet(out_sheet, css_buf);
                        free(css_buf);
                    }
                }
                p = css_end ? (css_end + 8) : (p + clen);
                continue;
            }

            /* Skip raw-text non-rendered blocks (<script>, <noscript>, <svg>, <title>) */
            if (strcmp(tag, "script") == 0 || strcmp(tag, "noscript") == 0 ||
                strcmp(tag, "svg") == 0 || strcmp(tag, "title") == 0) {
                while (*p && *p != '>') p++;
                if (*p == '>') p++;
                char end_pat[40];
                snprintf(end_pat, sizeof(end_pat), "</%s>", tag);
                const char* end_tag = strcasestr_portable(p, end_pat);
                p = end_tag ? (end_tag + strlen(end_pat)) : (p + strlen(p));
                continue;
            }

            if (in_head) {
                /* Skip other head metadata tags (<meta>, <link>, <base>) */
                while (*p && *p != '>') p++;
                if (*p == '>') p++;
                continue;
            }

            /* Perform WHATWG HTML5 implicit end-tag closure BEFORE inserting element! */
            if (!is_doc_wrapper) {
                current = html5_close_implicit_before_start(current, root, tag);
            }

            dom_node_t* target_node = is_doc_wrapper ? root : dom_node_create(tag);
            if (!is_doc_wrapper) {
                dom_node_add_child(current, target_node);
            }

            bool self_closing = false;
            while (*p && *p != '>') {
                while (*p && isspace((unsigned char)*p)) p++;
                if (*p == '/' && p[1] == '>') {
                    self_closing = true;
                    p++;
                    break;
                }
                if (*p == '>') break;

                char attr_k[64];
                int ki = 0;
                while (*p && *p != '=' && *p != '>' && *p != '/' && !isspace((unsigned char)*p) && ki < 63) {
                    attr_k[ki++] = (char)tolower((unsigned char)*p++);
                }
                attr_k[ki] = '\0';
                while (*p && isspace((unsigned char)*p)) p++;

                char attr_v[1024];
                attr_v[0] = '\0';
                if (*p == '=') {
                    p++;
                    while (*p && isspace((unsigned char)*p)) p++;
                    char quote = 0;
                    if (*p == '"' || *p == '\'') quote = *p++;
                    int vi = 0;
                    while (*p && vi < 1023) {
                        if (quote && *p == quote) { p++; break; }
                        if (!quote && (*p == '>' || isspace((unsigned char)*p))) break;
                        attr_v[vi++] = *p++;
                    }
                    attr_v[vi] = '\0';
                }
                if (attr_k[0]) {
                    apply_parsed_attribute(target_node, attr_k, attr_v);
                }
                if (!attr_k[0] && *p && *p != '>') p++;
            }
            if (*p == '>') p++;

            /* Void elements never push onto the open-element stack (`html_void_tag_never_grows_stack`) */
            if (!is_doc_wrapper && !self_closing && !blink_html_is_void_tag(tag)) {
                current = target_node;
            }
        } else {
            /* Character data run */
            const char* start = p;
            while (*p && *p != '<') p++;
            size_t tlen = (size_t)(p - start);
            if (!in_head && tlen > 0) {
                char* raw_text = (char*)malloc(tlen + 1);
                memcpy(raw_text, start, tlen);
                raw_text[tlen] = '\0';
                char* clean_text = blink_unescape_html(raw_text);
                free(raw_text);

                bool all_ws = true;
                for (size_t k = 0; clean_text[k]; k++) {
                    if (!isspace((unsigned char)clean_text[k])) { all_ws = false; break; }
                }
                if (!all_ws) {
                    dom_node_t* tn = dom_node_create("#text");
                    tn->text = clean_text;
                    dom_node_add_child(current, tn);
                } else {
                    free(clean_text);
                }
            }
        }
    }

    return root;
}
