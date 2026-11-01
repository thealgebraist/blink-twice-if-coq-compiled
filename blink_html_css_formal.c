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

/* WHATWG HTML5 §13.2.5.73 Numeric Character Reference Sanitizer
   Mirrors `resolve_numeric_char_ref` in `BlinkHTML5AdoptionAgencyAndSkiaPaintEngine.v` */
int32_t blink_html_sanitize_char_ref(int32_t cp) {
    if (cp <= 0 || cp > 0x10FFFF || (cp >= 0xD800 && cp <= 0xDFFF)) {
        return 0xFFFD;
    }
    return cp;
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
    st->border_style = BDR_STYLE_NONE;
    st->border_collapse = false;
    st->font_size = 14.0f;
    st->font_weight = 400;
    st->font_style = 0;
    strcpy(st->font_family, "sans-serif");
    st->width = -1;
    st->height = -1;
    st->min_width = 0;
    st->max_width = -1;
    st->gap = 0;
    st->row_gap = 0;
    st->flex_grow = 0;
    st->flex_shrink = 1;
    st->flex_direction = FLEX_DIR_ROW;
    st->flex_wrap = false;
    st->grid_col_span = 1;
    st->line_height = 1.4f;
    st->text_align = ALIGN_LEFT;
    st->vertical_align = VALIGN_BASELINE;
    st->white_space = WS_NORMAL;
    st->position = POS_STATIC;
    st->css_float = FLOAT_NONE;
    st->css_clear = CLEAR_NONE;
    st->opacity_u8 = 255;
    st->overflow_hidden = false;
    st->has_box_shadow = false;
    st->has_gradient = false;
    st->has_transform = false;
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
        n->style.border_style = BDR_STYLE_SOLID;
    } else if (strcmp(n->tag, "h2") == 0) {
        n->style.font_size = 22.0f;
        n->style.font_weight = 700;
        n->style.margin_top = 16;
        n->style.margin_bottom = 10;
        n->style.border_bottom_width = 1;
        n->style.border_style = BDR_STYLE_SOLID;
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
        n->style.border_style = BDR_STYLE_SOLID;
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
        n->style.border_style = BDR_STYLE_SOLID;
        n->style.border_color = 0xFFA2A9B1u;
        n->style.height = 140;
        n->style.width = 220;
    } else if (strcmp(n->tag, "a") == 0) {
        n->style.display = DISPLAY_INLINE;
        n->style.color = BLINK_COLOR_LINK_BLUE;
        n->style.text_underline = true;
    } else if (strcmp(n->tag, "br") == 0) {
        n->style.display = DISPLAY_INLINE;
    } else if (strcmp(n->tag, "span") == 0 || strcmp(n->tag, "b") == 0 || strcmp(n->tag, "strong") == 0 ||
               strcmp(n->tag, "i") == 0 || strcmp(n->tag, "em") == 0 || strcmp(n->tag, "small") == 0 ||
               strcmp(n->tag, "abbr") == 0 || strcmp(n->tag, "cite") == 0 || strcmp(n->tag, "sub") == 0 ||
               strcmp(n->tag, "sup") == 0 || strcmp(n->tag, "q") == 0 || strcmp(n->tag, "mark") == 0 ||
               strcmp(n->tag, "time") == 0 || strcmp(n->tag, "dfn") == 0 || strcmp(n->tag, "u") == 0 ||
               strcmp(n->tag, "ins") == 0 || strcmp(n->tag, "s") == 0 || strcmp(n->tag, "del") == 0 ||
               strcmp(n->tag, "strike") == 0 || strcmp(n->tag, "kbd") == 0 || strcmp(n->tag, "samp") == 0 ||
               strcmp(n->tag, "#text") == 0) {
        n->style.display = DISPLAY_INLINE;
        if (strcmp(n->tag, "b") == 0 || strcmp(n->tag, "strong") == 0) n->style.font_weight = 700;
        if (strcmp(n->tag, "i") == 0 || strcmp(n->tag, "em") == 0 || strcmp(n->tag, "cite") == 0 || strcmp(n->tag, "dfn") == 0) n->style.font_style = 1;
        if (strcmp(n->tag, "small") == 0) n->style.font_size = 12.0f;
        if (strcmp(n->tag, "sub") == 0) { n->style.font_size = 11.0f; n->style.vertical_align = VALIGN_SUB; }
        if (strcmp(n->tag, "sup") == 0) { n->style.font_size = 11.0f; n->style.vertical_align = VALIGN_SUPER; }
        if (strcmp(n->tag, "u") == 0 || strcmp(n->tag, "ins") == 0) n->style.text_underline = true;
        if (strcmp(n->tag, "s") == 0 || strcmp(n->tag, "del") == 0 || strcmp(n->tag, "strike") == 0) n->style.text_line_through = true;
        if (strcmp(n->tag, "kbd") == 0 || strcmp(n->tag, "samp") == 0) strcpy(n->style.font_family, "monospace");
        if (strcmp(n->tag, "mark") == 0) {
            n->style.bg_color = 0xFFFFF3CDu;
            n->style.has_bg = true;
            n->style.padding_left = 3;
            n->style.padding_right = 3;
        }
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
        n->style.border_style = BDR_STYLE_SOLID;
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
        n->style.border_style = BDR_STYLE_SOLID;
    } else if (strcmp(n->tag, "td") == 0) {
        n->style.display = DISPLAY_TABLE_CELL;
        n->style.box_sizing = BOX_SIZING_BORDER_BOX;
        n->style.padding_top = 6;
        n->style.padding_bottom = 6;
        n->style.padding_left = 10;
        n->style.padding_right = 10;
        n->style.border_width = 1;
        n->style.border_style = BDR_STYLE_SOLID;
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
            n->style.white_space = WS_PRE;
            n->style.padding_top = 10;
            n->style.padding_bottom = 10;
            n->style.padding_left = 12;
            n->style.padding_right = 12;
            n->style.margin_top = 10;
            n->style.margin_bottom = 10;
            n->style.border_radius = 4;
        } else {
            n->style.display = DISPLAY_INLINE;
            n->style.padding_left = 5;
            n->style.padding_right = 5;
            n->style.padding_top = 1;
            n->style.padding_bottom = 1;
            n->style.border_radius = 3;
        }
    } else if (strcmp(n->tag, "blockquote") == 0) {
        n->style.margin_top = 10;
        n->style.margin_bottom = 10;
        n->style.padding_left = 16;
        n->style.border_left_width = 3;
        n->style.border_style = BDR_STYLE_SOLID;
        n->style.border_color = BLINK_COLOR_LINK_BLUE;
        n->style.border_left_color = BLINK_COLOR_LINK_BLUE;
        n->style.color = 0xFF5F6368u;
    } else if (strcmp(n->tag, "hr") == 0) {
        n->style.margin_top = 14;
        n->style.margin_bottom = 14;
        n->style.border_width = 1;
        n->style.border_style = BDR_STYLE_SOLID;
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

void dom_node_insert_child_first(dom_node_t* parent, dom_node_t* child) {
    if (!parent || !child) return;
    if (parent->num_children + 1 > parent->cap_children) {
        int new_cap = (parent->cap_children == 0) ? 4 : parent->cap_children * 2;
        parent->children = (dom_node_t**)realloc(parent->children, (size_t)new_cap * sizeof(dom_node_t*));
        parent->cap_children = new_cap;
    }
    for (int i = parent->num_children; i > 0; i--) {
        parent->children[i] = parent->children[i - 1];
    }
    parent->children[0] = child;
    parent->num_children++;
    child->parent = parent;
}

/* WHATWG Foster Parenting & Adoption Agency `insert_before_target` */
void dom_node_insert_before(dom_node_t* parent, dom_node_t* ref_child, dom_node_t* new_child) {
    if (!parent || !new_child) return;
    int idx = -1;
    if (ref_child) {
        for (int i = 0; i < parent->num_children; i++) {
            if (parent->children[i] == ref_child) {
                idx = i;
                break;
            }
        }
    }
    if (idx < 0) {
        dom_node_add_child(parent, new_child);
        return;
    }
    if (parent->num_children + 1 > parent->cap_children) {
        int new_cap = (parent->cap_children == 0) ? 4 : parent->cap_children * 2;
        parent->children = (dom_node_t**)realloc(parent->children, (size_t)new_cap * sizeof(dom_node_t*));
        parent->cap_children = new_cap;
    }
    for (int i = parent->num_children; i > idx; i--) {
        parent->children[i] = parent->children[i - 1];
    }
    parent->children[idx] = new_child;
    parent->num_children++;
    new_child->parent = parent;
}

static void dom_node_detach_from_parent(dom_node_t* child) {
    if (!child || !child->parent) return;
    dom_node_t* p = child->parent;
    int w = 0;
    for (int i = 0; i < p->num_children; i++) {
        if (p->children[i] != child) {
            p->children[w++] = p->children[i];
        }
    }
    p->num_children = w;
    child->parent = NULL;
}

void dom_node_free(dom_node_t* n) {
    if (!n) return;
    free(n->text);
    free(n->id);
    free(n->class_name);
    free(n->src);
    free(n->href);
    free(n->inline_style_raw);
    free(n->inline_frags);
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

blink_specificity_t blink_specificity_max(blink_specificity_t a, blink_specificity_t b) {
    return blink_specificity_lt(a, b) ? b : a;
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

/* Forward declaration for recursive max-branch specificity & selector matching */
bool blink_css_parse_selector(const char* sel_text, blink_complex_sel_t* out_sel);
static bool match_selector_internal(const dom_node_t* el,
                                    const blink_complex_sel_t* sel,
                                    const dom_node_t* scope_root,
                                    bool ignore_pseudo_elem);

static blink_specificity_t compute_selector_list_max_specificity(const char* list_text, bool is_relative) {
    blink_specificity_t max_sp = {0, 0, 0};
    if (!list_text) return max_sp;
    const char* p = list_text;
    while (*p) {
        while (*p && isspace((unsigned char)*p)) p++;
        if (!*p) break;
        const char* start = p;
        int paren = 0;
        while (*p && !(paren == 0 && *p == ',')) {
            if (*p == '(') paren++;
            else if (*p == ')' && paren > 0) paren--;
            p++;
        }
        char item[160];
        size_t len = (size_t)(p - start);
        if (len >= sizeof(item)) len = sizeof(item) - 1;
        memcpy(item, start, len);
        item[len] = '\0';
        trim_inplace(item);

        const char* body = item;
        if (is_relative && (*body == '>' || *body == '+' || *body == '~')) {
            body++;
            while (*body && isspace((unsigned char)*body)) body++;
        }
        blink_complex_sel_t sub;
        if (body[0] && blink_css_parse_selector(body, &sub)) {
            max_sp = blink_specificity_max(max_sp, sub.specificity);
        }
        if (*p == ',') p++;
    }
    return max_sp;
}

static const char* read_paren_arg(const char* p, char* out_buf, size_t out_cap) {
    if (*p == '(') p++;
    const char* start = p;
    int depth = 1;
    while (*p && depth > 0) {
        if (*p == '(') depth++;
        else if (*p == ')') depth--;
        if (depth > 0) p++;
    }
    size_t len = (size_t)(p - start);
    if (len >= out_cap) len = out_cap - 1;
    memcpy(out_buf, start, len);
    out_buf[len] = '\0';
    trim_inplace(out_buf);
    if (*p == ')') p++;
    return p;
}

static const char* parse_compound_segment(const char* p,
                                          blink_compound_sel_t* comp,
                                          blink_specificity_t* io_spec,
                                          blink_pseudo_elem_t* out_pseudo_elem,
                                          bool suppress_specificity) {
    memset(comp, 0, sizeof(*comp));
    comp->zero_specificity = suppress_specificity;

    bool parsed_any = false;
    while (*p) {
        if (isspace((unsigned char)*p) || *p == '>' || *p == '+' || *p == '~' ||
            *p == ',' || *p == '{' || *p == ')') {
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
            while (*p && *p != '=' && *p != '~' && *p != '|' && *p != '^' &&
                   *p != '$' && *p != '*' && *p != ']' && !isspace((unsigned char)*p)) {
                p++;
            }
            copy_lower_bounded(comp->attr_name, sizeof(comp->attr_name), ks, (size_t)(p - ks));
            comp->has_attr = true;
            comp->attr_op = ATTR_OP_EXISTS;
            while (*p && isspace((unsigned char)*p)) p++;

            bool saw_op = false;
            if ((*p == '~' || *p == '|' || *p == '^' || *p == '$' || *p == '*') && p[1] == '=') {
                if (*p == '~') comp->attr_op = ATTR_OP_SPACE_LIST;
                else if (*p == '|') comp->attr_op = ATTR_OP_DASH_PREFIX;
                else if (*p == '^') comp->attr_op = ATTR_OP_PREFIX;
                else if (*p == '$') comp->attr_op = ATTR_OP_SUFFIX;
                else if (*p == '*') comp->attr_op = ATTR_OP_SUBSTR;
                p += 2;
                saw_op = true;
            } else if (*p == '=') {
                comp->attr_op = ATTR_OP_EXACT;
                p++;
                saw_op = true;
            }

            if (saw_op) {
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
            bool double_colon = false;
            if (*p == ':') {
                double_colon = true;
                p++;
            }
            const char* ps = p;
            while (*p && is_ident_char(*p)) p++;
            char pname[32];
            copy_lower_bounded(pname, sizeof(pname), ps, (size_t)(p - ps));

            if (strcmp(pname, "before") == 0) {
                if (out_pseudo_elem) *out_pseudo_elem = PSEUDO_ELEM_BEFORE;
                if (!suppress_specificity) io_spec->tag_cnt++;
                parsed_any = true;
            } else if (strcmp(pname, "after") == 0) {
                if (out_pseudo_elem) *out_pseudo_elem = PSEUDO_ELEM_AFTER;
                if (!suppress_specificity) io_spec->tag_cnt++;
                parsed_any = true;
            } else if (double_colon) {
                /* Other pseudo-elements (::placeholder, ::selection) fail match cleanly */
                strcpy(comp->tag, "__unsupported_pseudo_element__");
                return p;
            } else if (strcmp(pname, "root") == 0) {
                strcpy(comp->tag, "body");
                if (!suppress_specificity) io_spec->class_cnt++;
                parsed_any = true;
            } else if (strcmp(pname, "scope") == 0) {
                comp->pseudo = PSEUDO_SCOPE;
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
            } else if (strcmp(pname, "first-of-type") == 0) {
                comp->pseudo = PSEUDO_FIRST_OF_TYPE;
                if (!suppress_specificity) io_spec->class_cnt++;
                parsed_any = true;
            } else if (strcmp(pname, "last-of-type") == 0) {
                comp->pseudo = PSEUDO_LAST_OF_TYPE;
                if (!suppress_specificity) io_spec->class_cnt++;
                parsed_any = true;
            } else if ((strcmp(pname, "nth-child") == 0 || strcmp(pname, "nth-of-type") == 0) && *p == '(') {
                char expr[64];
                p = read_paren_arg(p, expr, sizeof(expr));
                comp->pseudo = (strcmp(pname, "nth-of-type") == 0) ? PSEUDO_NTH_OF_TYPE : PSEUDO_NTH_CHILD;
                parse_nth_expr(expr, &comp->nth_a, &comp->nth_b);
                if (!suppress_specificity) io_spec->class_cnt++;
                parsed_any = true;
            } else if (strcmp(pname, "where") == 0 && *p == '(') {
                /* `:where(...)` contributes ZERO specificity per `where_pseudo_zero_specificity`! */
                p = read_paren_arg(p, comp->where_args, sizeof(comp->where_args));
                comp->has_where = true;
                parsed_any = true;
            } else if (strcmp(pname, "is") == 0 && *p == '(') {
                /* `:is(...)` takes MAX specificity of its selector list (`is_pseudo_max_spec`)! */
                p = read_paren_arg(p, comp->is_args, sizeof(comp->is_args));
                comp->has_is = true;
                if (!suppress_specificity) {
                    blink_specificity_t ms = compute_selector_list_max_specificity(comp->is_args, false);
                    *io_spec = blink_specificity_add(*io_spec, ms);
                }
                parsed_any = true;
            } else if (strcmp(pname, "not") == 0 && *p == '(') {
                /* `:not(...)` negates selector list & takes MAX specificity of its branches! */
                p = read_paren_arg(p, comp->not_args, sizeof(comp->not_args));
                comp->has_not = true;
                if (!suppress_specificity) {
                    blink_specificity_t ms = compute_selector_list_max_specificity(comp->not_args, false);
                    *io_spec = blink_specificity_add(*io_spec, ms);
                }
                parsed_any = true;
            } else if (strcmp(pname, "has") == 0 && *p == '(') {
                /* `:has(...)` relational lookahead + MAX specificity of relative selector list! */
                p = read_paren_arg(p, comp->has_args, sizeof(comp->has_args));
                comp->has_has = true;
                if (!suppress_specificity) {
                    blink_specificity_t ms = compute_selector_list_max_specificity(comp->has_args, true);
                    *io_spec = blink_specificity_add(*io_spec, ms);
                }
                parsed_any = true;
            } else if (strcmp(pname, "focus") == 0 || strcmp(pname, "active") == 0 ||
                       strcmp(pname, "hover") == 0 || strcmp(pname, "visited") == 0 ||
                       strcmp(pname, "focus-visible") == 0 || strcmp(pname, "focus-within") == 0) {
                /* Dynamic user-action / interaction pseudo-classes are FALSE on static document render */
                strcpy(comp->tag, "__dynamic_pseudo_class__");
                if (!suppress_specificity) io_spec->class_cnt++;
                parsed_any = true;
            } else {
                /* Unsupported pseudo-class should not falsely match static document */
                if (*p == '(') {
                    char dummy[64];
                    p = read_paren_arg(p, dummy, sizeof(dummy));
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
        blink_pseudo_elem_t pe = PSEUDO_ELEM_NONE;
        const char* before = p;
        p = parse_compound_segment(p, &comp, &out_sel->specificity, &pe, false);
        if (p == before) break;

        if (pe != PSEUDO_ELEM_NONE) {
            out_sel->pseudo_elem = pe;
        }
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
        } else if (*p == '~') {
            pending_comb = COMB_SUBSEQUENT_SIBLING;
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

static bool is_real_dom_element(const dom_node_t* ch) {
    return ch && strcmp(ch->tag, "#text") != 0 && !ch->is_generated_pseudo;
}

static void element_sibling_metrics(const dom_node_t* el,
                                    int* out_idx_1based,
                                    int* out_total_el_siblings,
                                    int* out_type_idx_1based,
                                    int* out_type_total,
                                    const dom_node_t** out_prev_el) {
    *out_idx_1based = 1;
    *out_total_el_siblings = 1;
    *out_type_idx_1based = 1;
    *out_type_total = 1;
    *out_prev_el = NULL;
    if (!el || !el->parent) return;

    int count = 0;
    int type_count = 0;
    const dom_node_t* prev = NULL;
    for (int i = 0; i < el->parent->num_children; i++) {
        const dom_node_t* ch = el->parent->children[i];
        if (!is_real_dom_element(ch)) continue;
        count++;
        if (strcmp(ch->tag, el->tag) == 0) {
            type_count++;
            if (ch == el) *out_type_idx_1based = type_count;
        }
        if (ch == el) {
            *out_idx_1based = count;
            *out_prev_el = prev;
        }
        prev = ch;
    }
    *out_total_el_siblings = count;
    *out_type_total = type_count;
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

static bool match_attr_operator(blink_attr_op_t op, const char* actual, const char* pat) {
    if (!actual) return false;
    if (op == ATTR_OP_EXISTS) return true;
    if (!pat) return false;
    size_t alen = strlen(actual);
    size_t plen = strlen(pat);
    switch (op) {
        case ATTR_OP_EXISTS:
            return true;
        case ATTR_OP_EXACT:
            return strcmp(actual, pat) == 0;
        case ATTR_OP_SPACE_LIST:
            return plen > 0 && token_list_contains(actual, pat);
        case ATTR_OP_DASH_PREFIX:
            return strcmp(actual, pat) == 0 ||
                   (alen > plen && strncmp(actual, pat, plen) == 0 && actual[plen] == '-');
        case ATTR_OP_PREFIX:
            return plen > 0 && alen >= plen && strncmp(actual, pat, plen) == 0;
        case ATTR_OP_SUFFIX:
            return plen > 0 && alen >= plen && strcmp(actual + (alen - plen), pat) == 0;
        case ATTR_OP_SUBSTR:
            return plen > 0 && strstr(actual, pat) != NULL;
    }
    return false;
}

static bool match_selector_list_any(const dom_node_t* el, const char* list_text, const dom_node_t* scope_root) {
    if (!el || !list_text) return false;
    const char* p = list_text;
    while (*p) {
        while (*p && isspace((unsigned char)*p)) p++;
        if (!*p) break;
        const char* start = p;
        int paren = 0;
        while (*p && !(paren == 0 && *p == ',')) {
            if (*p == '(') paren++;
            else if (*p == ')' && paren > 0) paren--;
            p++;
        }
        char item[160];
        size_t len = (size_t)(p - start);
        if (len >= sizeof(item)) len = sizeof(item) - 1;
        memcpy(item, start, len);
        item[len] = '\0';
        trim_inplace(item);

        blink_complex_sel_t sub;
        if (item[0] && blink_css_parse_selector(item, &sub)) {
            if (match_selector_internal(el, &sub, scope_root, false)) return true;
        }
        if (*p == ',') p++;
    }
    return false;
}

/* Match `sub` on `cand` while requiring the leftmost compound of `sub` to match `root_cand`
   or a descendant of `anchor`! */
static bool match_complex_anchored_rtl(const dom_node_t* el,
                                       const blink_complex_sel_t* sel,
                                       int comp_idx,
                                       const dom_node_t* anchor,
                                       bool leftmost_must_be_child_of_anchor,
                                       const dom_node_t* scope_root);

static bool subtree_has_match(const dom_node_t* node,
                              const blink_complex_sel_t* sub,
                              const dom_node_t* anchor,
                              bool direct_child_leftmost,
                              const dom_node_t* scope_root) {
    if (!node) return false;
    for (int i = 0; i < node->num_children; i++) {
        const dom_node_t* ch = node->children[i];
        if (!is_real_dom_element(ch)) continue;
        if (match_complex_anchored_rtl(ch, sub, sub->num_compounds - 1, anchor, direct_child_leftmost, scope_root)) {
            return true;
        }
        if (subtree_has_match(ch, sub, anchor, direct_child_leftmost, scope_root)) {
            return true;
        }
    }
    return false;
}

static bool match_has_relative_list(const dom_node_t* anchor, const char* list_text, const dom_node_t* scope_root) {
    if (!anchor || !list_text) return false;
    const char* p = list_text;
    while (*p) {
        while (*p && isspace((unsigned char)*p)) p++;
        if (!*p) break;
        const char* start = p;
        int paren = 0;
        while (*p && !(paren == 0 && *p == ',')) {
            if (*p == '(') paren++;
            else if (*p == ')' && paren > 0) paren--;
            p++;
        }
        char item[160];
        size_t len = (size_t)(p - start);
        if (len >= sizeof(item)) len = sizeof(item) - 1;
        memcpy(item, start, len);
        item[len] = '\0';
        trim_inplace(item);

        char rel_comb = ' ';
        const char* body = item;
        if (*body == '>' || *body == '+' || *body == '~') {
            rel_comb = *body++;
            while (*body && isspace((unsigned char)*body)) body++;
        }

        blink_complex_sel_t sub;
        if (body[0] && blink_css_parse_selector(body, &sub)) {
            if (rel_comb == '>') {
                if (sub.num_compounds == 1) {
                    for (int i = 0; i < anchor->num_children; i++) {
                        const dom_node_t* ch = anchor->children[i];
                        if (is_real_dom_element(ch) && match_selector_internal(ch, &sub, scope_root, false)) {
                            return true;
                        }
                    }
                } else if (subtree_has_match(anchor, &sub, anchor, true, scope_root)) {
                    return true;
                }
            } else if (rel_comb == '+' || rel_comb == '~') {
                if (anchor->parent) {
                    bool seen_anchor = false;
                    for (int i = 0; i < anchor->parent->num_children; i++) {
                        const dom_node_t* sib = anchor->parent->children[i];
                        if (!is_real_dom_element(sib)) continue;
                        if (sib == anchor) { seen_anchor = true; continue; }
                        if (!seen_anchor) continue;
                        if (sub.num_compounds == 1) {
                            if (match_selector_internal(sib, &sub, scope_root, false)) return true;
                        } else {
                            if (subtree_has_match(sib, &sub, sib, false, scope_root)) return true;
                        }
                        if (rel_comb == '+') break; /* Next element sibling only! */
                    }
                }
            } else {
                if (subtree_has_match(anchor, &sub, anchor, false, scope_root)) return true;
            }
        }
        if (*p == ',') p++;
    }
    return false;
}

static bool match_compound_on_element(const dom_node_t* el,
                                      const blink_compound_sel_t* comp,
                                      const dom_node_t* scope_root) {
    if (!is_real_dom_element(el)) return false;
    if (comp->tag[0] != '\0' && strcmp(el->tag, comp->tag) != 0) return false;
    if (comp->id[0] != '\0') {
        if (!el->id || strcasecmp(el->id, comp->id) != 0) return false;
    }
    for (int i = 0; i < comp->num_classes; i++) {
        if (!token_list_contains(el->class_name, comp->classes[i])) return false;
    }
    if (comp->has_attr) {
        const char* av = get_element_attr(el, comp->attr_name);
        if (!match_attr_operator(comp->attr_op, av, comp->has_attr_val ? comp->attr_val : NULL)) {
            return false;
        }
    }
    if (comp->pseudo != PSEUDO_NONE) {
        if (comp->pseudo == PSEUDO_SCOPE) {
            const dom_node_t* target = scope_root;
            if (!target) {
                target = el;
                while (target->parent) target = target->parent;
            }
            if (el != target) return false;
        } else {
            int idx1 = 1, total = 1, tidx1 = 1, ttotal = 1;
            const dom_node_t* prev = NULL;
            element_sibling_metrics(el, &idx1, &total, &tidx1, &ttotal, &prev);
            if (comp->pseudo == PSEUDO_FIRST_CHILD && idx1 != 1) return false;
            if (comp->pseudo == PSEUDO_LAST_CHILD && idx1 != total) return false;
            if (comp->pseudo == PSEUDO_NTH_CHILD && !blink_css_match_nth_child(idx1, comp->nth_a, comp->nth_b)) return false;
            if (comp->pseudo == PSEUDO_FIRST_OF_TYPE && tidx1 != 1) return false;
            if (comp->pseudo == PSEUDO_LAST_OF_TYPE && tidx1 != ttotal) return false;
            if (comp->pseudo == PSEUDO_NTH_OF_TYPE && !blink_css_match_nth_child(tidx1, comp->nth_a, comp->nth_b)) return false;
        }
    }
    if (comp->has_is && !match_selector_list_any(el, comp->is_args, scope_root)) return false;
    if (comp->has_where && !match_selector_list_any(el, comp->where_args, scope_root)) return false;
    if (comp->has_not && match_selector_list_any(el, comp->not_args, scope_root)) return false;
    if (comp->has_has && !match_has_relative_list(el, comp->has_args, scope_root)) return false;
    return true;
}

static bool is_descendant_of(const dom_node_t* el, const dom_node_t* anc) {
    for (const dom_node_t* p = el ? el->parent : NULL; p != NULL; p = p->parent) {
        if (p == anc) return true;
    }
    return false;
}

static bool match_complex_anchored_rtl(const dom_node_t* el,
                                       const blink_complex_sel_t* sel,
                                       int comp_idx,
                                       const dom_node_t* anchor,
                                       bool leftmost_must_be_child_of_anchor,
                                       const dom_node_t* scope_root) {
    if (!el || comp_idx < 0) return false;
    if (!match_compound_on_element(el, &sel->compounds[comp_idx], scope_root)) return false;
    if (comp_idx == 0) {
        if (!anchor) return true;
        if (leftmost_must_be_child_of_anchor) return el->parent == anchor;
        return is_descendant_of(el, anchor);
    }

    blink_combinator_t comb = sel->combinators[comp_idx];
    if (comb == COMB_CHILD) {
        return el->parent && match_complex_anchored_rtl(el->parent, sel, comp_idx - 1, anchor, leftmost_must_be_child_of_anchor, scope_root);
    } else if (comb == COMB_DESCENDANT) {
        for (const dom_node_t* anc = el->parent; anc != NULL; anc = anc->parent) {
            if (anchor && anc == anchor) break;
            if (match_complex_anchored_rtl(anc, sel, comp_idx - 1, anchor, leftmost_must_be_child_of_anchor, scope_root)) return true;
        }
        return false;
    } else if (comb == COMB_NEXT_SIBLING) {
        int idx1 = 1, total = 1, tidx1 = 1, ttotal = 1;
        const dom_node_t* prev = NULL;
        element_sibling_metrics(el, &idx1, &total, &tidx1, &ttotal, &prev);
        return prev && match_complex_anchored_rtl(prev, sel, comp_idx - 1, anchor, leftmost_must_be_child_of_anchor, scope_root);
    } else if (comb == COMB_SUBSEQUENT_SIBLING) {
        if (!el->parent) return false;
        for (int i = 0; i < el->parent->num_children; i++) {
            const dom_node_t* sib = el->parent->children[i];
            if (sib == el) break;
            if (!is_real_dom_element(sib)) continue;
            if (match_complex_anchored_rtl(sib, sel, comp_idx - 1, anchor, leftmost_must_be_child_of_anchor, scope_root)) {
                return true;
            }
        }
        return false;
    }
    return false;
}

static bool match_selector_internal(const dom_node_t* el,
                                    const blink_complex_sel_t* sel,
                                    const dom_node_t* scope_root,
                                    bool ignore_pseudo_elem) {
    if (!el || !sel || sel->num_compounds <= 0) return false;
    if (!ignore_pseudo_elem && sel->pseudo_elem != PSEUDO_ELEM_NONE) return false;
    return match_complex_anchored_rtl(el, sel, sel->num_compounds - 1, NULL, false, scope_root);
}

bool blink_css_match_selector(const dom_node_t* el, const blink_complex_sel_t* sel) {
    return match_selector_internal(el, sel, NULL, false);
}

bool blink_css_in_donut_scope(const dom_node_t* el,
                              const blink_complex_sel_t* root_sel,
                              const blink_complex_sel_t* limit_sel_or_null,
                              const dom_node_t** out_scope_root) {
    if (out_scope_root) *out_scope_root = NULL;
    if (!el || !root_sel) return false;
    for (const dom_node_t* anc = el; anc != NULL; anc = anc->parent) {
        if (limit_sel_or_null && blink_css_match_selector(anc, limit_sel_or_null)) {
            /* Hit donut scope limit boundary strictly before scope root! */
            return false;
        }
        if (blink_css_match_selector(anc, root_sel)) {
            if (out_scope_root) *out_scope_root = anc;
            return true;
        }
    }
    return false;
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

static int64_t eval_math_expr_in_mode_z(const char* expr,
                                        int32_t parent_px,
                                        int32_t em_px,
                                        int32_t rem_px,
                                        int32_t vw_px,
                                        int32_t vh_px,
                                        blink_layout_mode_t mode) {
    if (!expr) return 0;
    while (*expr && isspace((unsigned char)*expr)) expr++;

    /* Nonlinear CSS Math Functions: min(...), max(...), clamp(lo, val, hi) */
    bool is_min = (strncasecmp(expr, "min(", 4) == 0);
    bool is_max = (strncasecmp(expr, "max(", 4) == 0);
    bool is_clamp = (strncasecmp(expr, "clamp(", 6) == 0);
    if (is_min || is_max || is_clamp) {
        size_t head_len = is_clamp ? 6 : 4;
        const char* p = expr + head_len;
        const char* end = strrchr(p, ')');
        size_t len = end ? (size_t)(end - p) : strlen(p);
        char inner[192];
        if (len >= sizeof(inner)) len = sizeof(inner) - 1;
        memcpy(inner, p, len);
        inner[len] = '\0';

        int64_t args[8];
        int n_args = 0;
        const char* cur = inner;
        while (*cur && n_args < 8) {
            const char* as = cur;
            int paren = 0;
            while (*cur && !(paren == 0 && *cur == ',')) {
                if (*cur == '(') paren++;
                else if (*cur == ')' && paren > 0) paren--;
                cur++;
            }
            char abuf[96];
            size_t alen = (size_t)(cur - as);
            if (alen >= sizeof(abuf)) alen = sizeof(abuf) - 1;
            memcpy(abuf, as, alen);
            abuf[alen] = '\0';
            trim_inplace(abuf);
            args[n_args++] = eval_math_expr_in_mode_z(abuf, parent_px, em_px, rem_px, vw_px, vh_px, mode);
            if (*cur == ',') cur++;
        }

        if (n_args == 0) return 0;
        if (is_min) {
            int64_t best = args[0];
            for (int i = 1; i < n_args; i++) if (args[i] < best) best = args[i];
            return best;
        }
        if (is_max) {
            int64_t best = args[0];
            for (int i = 1; i < n_args; i++) if (args[i] > best) best = args[i];
            return best;
        }
        if (n_args >= 3) {
            /* `clamp(lo, val, hi) = max(lo, min(val, hi))` (`css_clamp_min_wins_on_inversion`) */
            int64_t lo = args[0], val = args[1], hi = args[2];
            int64_t mid = (val < hi) ? val : hi;
            return (lo > mid) ? lo : mid;
        }
        return args[0];
    }

    if (strncasecmp(expr, "calc(", 5) == 0) {
        const char* p = expr + 5;
        const char* end = strrchr(p, ')');
        size_t len = end ? (size_t)(end - p) : strlen(p);
        char inner[192];
        if (len >= sizeof(inner)) len = sizeof(inner) - 1;
        memcpy(inner, p, len);
        inner[len] = '\0';

        /* Parse linear sum/difference of length/math terms: `T0 (+|-) T1 ...` respecting parens */
        int64_t acc_z = 0;
        int sign = 1;
        const char* cur = inner;
        while (*cur) {
            while (*cur && isspace((unsigned char)*cur)) cur++;
            if (!*cur) break;
            if (*cur == '+') { sign = 1; cur++; continue; }
            if (*cur == '-' && isspace((unsigned char)cur[1])) { sign = -1; cur++; continue; }

            const char* ts = cur;
            int paren = 0;
            while (*cur) {
                if (*cur == '(') paren++;
                else if (*cur == ')' && paren > 0) paren--;
                else if (paren == 0 && (*cur == '+' || *cur == '-') && cur > ts && isspace((unsigned char)cur[-1])) {
                    break;
                }
                cur++;
            }
            char term_buf[96];
            size_t tlen = (size_t)(cur - ts);
            if (tlen >= sizeof(term_buf)) tlen = sizeof(term_buf) - 1;
            memcpy(term_buf, ts, tlen);
            term_buf[tlen] = '\0';
            trim_inplace(term_buf);

            int64_t term_z = 0;
            if (strncasecmp(term_buf, "min(", 4) == 0 || strncasecmp(term_buf, "max(", 4) == 0 ||
                strncasecmp(term_buf, "clamp(", 6) == 0 || strncasecmp(term_buf, "calc(", 5) == 0) {
                term_z = eval_math_expr_in_mode_z(term_buf, parent_px, em_px, rem_px, vw_px, vh_px, mode);
            } else {
                char* star = strchr(term_buf, '*');
                if (star) {
                    *star = '\0';
                    double mult = strtod(term_buf, NULL);
                    int64_t rhs_z = eval_math_expr_in_mode_z(star + 1, parent_px, em_px, rem_px, vw_px, vh_px, mode);
                    term_z = (int64_t)llround(mult * (double)rhs_z);
                } else {
                    term_z = eval_single_length_in_mode_z(term_buf, parent_px, em_px, rem_px, vw_px, vh_px, mode);
                }
            }
            acc_z += (int64_t)sign * term_z;
            sign = 1;
        }
        return acc_z;
    }

    return eval_single_length_in_mode_z(expr, parent_px, em_px, rem_px, vw_px, vh_px, mode);
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
    if ((strncasecmp(expr, "auto", 4) == 0 && (!expr[4] || isspace((unsigned char)expr[4]))) ||
        (strncasecmp(expr, "none", 4) == 0 && (!expr[4] || isspace((unsigned char)expr[4])))) {
        if (out_is_auto) *out_is_auto = true;
        return -1;
    }

    int64_t raw_z = eval_math_expr_in_mode_z(expr, parent_px, em_px, rem_px, vw_px, vh_px, mode);
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

static float hue_to_rgb_chan(float p, float q, float t) {
    if (t < 0.0f) t += 1.0f;
    if (t > 1.0f) t -= 1.0f;
    if (t < 1.0f / 6.0f) return p + (q - p) * 6.0f * t;
    if (t < 1.0f / 2.0f) return q;
    if (t < 2.0f / 3.0f) return p + (q - p) * (2.0f / 3.0f - t) * 6.0f;
    return p;
}

uint32_t blink_parse_css_color_with_current(const char* s, uint32_t current_color, bool* out_ok) {
    if (out_ok) *out_ok = false;
    if (!s) return BLINK_COLOR_TEXT_DEFAULT;
    while (*s && isspace((unsigned char)*s)) s++;
    if (!*s) return BLINK_COLOR_TEXT_DEFAULT;

    if (strncasecmp(s, "transparent", 11) == 0 && (!s[11] || isspace((unsigned char)s[11]))) {
        if (out_ok) *out_ok = true;
        return 0x00000000u;
    }
    if (strncasecmp(s, "currentcolor", 12) == 0 && (!s[12] || isspace((unsigned char)s[12]))) {
        if (out_ok) *out_ok = true;
        return current_color;
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
        } else if (hexlen == 4) {
            unsigned int r, g, b, a;
            if (sscanf(s, "%1x%1x%1x%1x", &r, &g, &b, &a) == 4) {
                if (out_ok) *out_ok = true;
                return ((a * 17u) << 24) | ((r * 17u) << 16) | ((g * 17u) << 8) | (b * 17u);
            }
        } else if (hexlen == 8) {
            unsigned int r, g, b, a;
            if (sscanf(s, "%2x%2x%2x%2x", &r, &g, &b, &a) == 4) {
                if (out_ok) *out_ok = true;
                return (a << 24) | (r << 16) | (g << 8) | b;
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
            if (matched < 3) matched = sscanf(p + 1, "%d %d %d / %f", &r, &g, &b, &af);
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

    if (strncasecmp(s, "hsla(", 5) == 0 || strncasecmp(s, "hsl(", 4) == 0) {
        const char* p = strchr(s, '(');
        if (p) {
            char buf[128];
            read_paren_arg(p, buf, sizeof(buf));
            for (size_t i = 0; buf[i]; i++) {
                if (buf[i] == ',' || buf[i] == '/' || buf[i] == '%') buf[i] = ' ';
            }
            float h_deg = 0.0f, s_pct = 0.0f, l_pct = 0.0f, af = 1.0f;
            int matched = sscanf(buf, "%f %f %f %f", &h_deg, &s_pct, &l_pct, &af);
            if (matched >= 3) {
                float h = fmodf(h_deg, 360.0f);
                if (h < 0.0f) h += 360.0f;
                h /= 360.0f;
                float sat = fminf(1.0f, fmaxf(0.0f, s_pct / 100.0f));
                float lig = fminf(1.0f, fmaxf(0.0f, l_pct / 100.0f));
                float rf, gf, bf;
                if (sat == 0.0f) {
                    rf = gf = bf = lig;
                } else {
                    float q = (lig < 0.5f) ? (lig * (1.0f + sat)) : (lig + sat - lig * sat);
                    float pv = 2.0f * lig - q;
                    rf = hue_to_rgb_chan(pv, q, h + 1.0f / 3.0f);
                    gf = hue_to_rgb_chan(pv, q, h);
                    bf = hue_to_rgb_chan(pv, q, h - 1.0f / 3.0f);
                }
                int r = (int)lroundf(rf * 255.0f);
                int g = (int)lroundf(gf * 255.0f);
                int b = (int)lroundf(bf * 255.0f);
                int a = (int)lroundf(fminf(1.0f, fmaxf(0.0f, af)) * 255.0f);
                if (out_ok) *out_ok = true;
                return ((uint32_t)a << 24) | ((uint32_t)r << 16) | ((uint32_t)g << 8) | (uint32_t)b;
            }
        }
        return BLINK_COLOR_TEXT_DEFAULT;
    }

    /* CSS Color 5: `color-mix(in srgb, <c1> [<p1>%], <c2> [<p2>%])` */
    if (strncasecmp(s, "color-mix(", 10) == 0) {
        const char* p = s + 9;
        char inner[192];
        read_paren_arg(p, inner, sizeof(inner));

        char parts[3][128];
        int n_parts = 0;
        const char* cur = inner;
        while (*cur && n_parts < 3) {
            const char* ps = cur;
            int paren = 0;
            while (*cur && !(paren == 0 && *cur == ',')) {
                if (*cur == '(') paren++;
                else if (*cur == ')') paren--;
                cur++;
            }
            size_t plen = (size_t)(cur - ps);
            if (plen >= 128) plen = 127;
            memcpy(parts[n_parts], ps, plen);
            parts[n_parts][plen] = '\0';
            trim_inplace(parts[n_parts]);
            n_parts++;
            if (*cur == ',') cur++;
        }

        if (n_parts == 3) {
            /* Extract optional trailing `<num>%` weight from parts[1] and parts[2] */
            double w1 = -1.0, w2 = -1.0;
            for (int k = 1; k <= 2; k++) {
                size_t l = strlen(parts[k]);
                if (l > 1 && parts[k][l - 1] == '%') {
                    size_t i = l - 1;
                    while (i > 0 && (isdigit((unsigned char)parts[k][i - 1]) || parts[k][i - 1] == '.')) i--;
                    if (i > 0 && isspace((unsigned char)parts[k][i - 1])) {
                        double pct = strtod(parts[k] + i, NULL);
                        parts[k][i] = '\0';
                        trim_inplace(parts[k]);
                        if (k == 1) w1 = pct; else w2 = pct;
                    }
                }
            }
            if (w1 < 0.0 && w2 < 0.0) { w1 = 50.0; w2 = 50.0; }
            else if (w1 < 0.0) { w1 = 100.0 - w2; }
            else if (w2 < 0.0) { w2 = 100.0 - w1; }
            if (w1 < 0.0) w1 = 0.0;
            if (w2 < 0.0) w2 = 0.0;
            double wsum = w1 + w2;
            if (wsum <= 0.0) { w1 = 50.0; w2 = 50.0; wsum = 100.0; }

            bool ok1 = false, ok2 = false;
            uint32_t c1 = blink_parse_css_color_with_current(parts[1], current_color, &ok1);
            uint32_t c2 = blink_parse_css_color_with_current(parts[2], current_color, &ok2);
            if (ok1 && ok2) {
                uint32_t a1 = (c1 >> 24) & 0xFFu, r1 = (c1 >> 16) & 0xFFu, g1 = (c1 >> 8) & 0xFFu, b1 = c1 & 0xFFu;
                uint32_t a2 = (c2 >> 24) & 0xFFu, r2 = (c2 >> 16) & 0xFFu, g2 = (c2 >> 8) & 0xFFu, b2 = c2 & 0xFFu;
                uint32_t am = (uint32_t)llround(((double)a1 * w1 + (double)a2 * w2) / wsum);
                uint32_t rm = (uint32_t)llround(((double)r1 * w1 + (double)r2 * w2) / wsum);
                uint32_t gm = (uint32_t)llround(((double)g1 * w1 + (double)g2 * w2) / wsum);
                uint32_t bm = (uint32_t)llround(((double)b1 * w1 + (double)b2 * w2) / wsum);
                if (am > 255u) am = 255u;
                if (rm > 255u) rm = 255u;
                if (gm > 255u) gm = 255u;
                if (bm > 255u) bm = 255u;
                if (out_ok) *out_ok = true;
                return (am << 24) | (rm << 16) | (gm << 8) | bm;
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
        {"lightgray", 0xFFDADCE0u}, {"lightgrey", 0xFFDADCE0u}, {"whitesmoke", 0xFFF5F5F5u},
        {"cyan", 0xFF00BCD4u}, {"magenta", 0xFFE91E63u}, {"coral", 0xFFFF7043u}
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

uint32_t blink_parse_css_color(const char* s, bool* out_ok) {
    return blink_parse_css_color_with_current(s, BLINK_COLOR_TEXT_DEFAULT, out_ok);
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

static blink_stylesheet_loader_fn g_custom_stylesheet_loader = NULL;
static void*                       g_custom_stylesheet_loader_data = NULL;

void blink_css_set_custom_loader(blink_stylesheet_loader_fn loader, void* user_data) {
    g_custom_stylesheet_loader = loader;
    g_custom_stylesheet_loader_data = user_data;
}

static char* load_local_stylesheet_file(const char* base_dir, const char* href, char* out_dir, size_t out_dir_cap) {
    if (!href || !href[0]) return NULL;

    if (g_custom_stylesheet_loader) {
        char* custom_res = g_custom_stylesheet_loader(href, g_custom_stylesheet_loader_data, out_dir, out_dir_cap);
        if (custom_res) return custom_res;
    }

    if (strncasecmp(href, "http://", 7) == 0 || strncasecmp(href, "https://", 8) == 0 ||
        strncasecmp(href, "//", 2) == 0 || strncasecmp(href, "data:", 5) == 0) {
        return NULL;
    }
    const char* rel = href;
    if (strncasecmp(rel, "file://", 7) == 0) rel += 7;

    char full_path[1024];
    if (rel[0] == '/' || !base_dir || !base_dir[0] || strcmp(base_dir, ".") == 0) {
        snprintf(full_path, sizeof(full_path), "%s", rel);
    } else {
        snprintf(full_path, sizeof(full_path), "%s/%s", base_dir, rel);
    }

    /* Strip query string or fragment from local path */
    char* q = strpbrk(full_path, "?#");
    if (q) *q = '\0';

    if (out_dir && out_dir_cap > 0) {
        const char* slash = strrchr(full_path, '/');
        if (slash) {
            size_t dlen = (size_t)(slash - full_path);
            if (dlen >= out_dir_cap) dlen = out_dir_cap - 1;
            memcpy(out_dir, full_path, dlen);
            out_dir[dlen] = '\0';
        } else {
            strncpy(out_dir, ".", out_dir_cap - 1);
            out_dir[out_dir_cap - 1] = '\0';
        }
    }

    FILE* fp = fopen(full_path, "rb");
    if (!fp) return NULL;
    fseek(fp, 0, SEEK_END);
    long sz = ftell(fp);
    fseek(fp, 0, SEEK_SET);
    if (sz <= 0 || sz > 2 * 1024 * 1024) {
        fclose(fp);
        return NULL;
    }
    char* buf = (char*)malloc((size_t)sz + 1);
    if (!buf) {
        fclose(fp);
        return NULL;
    }
    size_t rd = fread(buf, 1, (size_t)sz, fp);
    buf[rd] = '\0';
    fclose(fp);
    return buf;
}

typedef struct {
    int32_t             active_layer;
    int32_t             media_min_w;
    int32_t             media_max_w;
    int32_t             container_min_w;
    int32_t             container_max_w;
    bool                has_scope;
    blink_complex_sel_t scope_root;
    bool                has_scope_limit;
    blink_complex_sel_t scope_limit;
    const char*         base_dir;
    int                 import_depth;
} css_parse_ctx_t;

static void parse_css_rules_in_ctx(blink_css_stylesheet_t* sheet,
                                   const char* css,
                                   const css_parse_ctx_t* ctx);

static void expand_nested_selector(const char* parent_sel, const char* child_sel, char* out, size_t out_cap) {
    if (!parent_sel || !parent_sel[0]) {
        snprintf(out, out_cap, "%s", child_sel ? child_sel : "");
        return;
    }
    if (strchr(child_sel, '&') != NULL) {
        size_t j = 0;
        for (size_t i = 0; child_sel[i] && j + 1 < out_cap; i++) {
            if (child_sel[i] == '&') {
                size_t plen = strlen(parent_sel);
                if (j + plen + 1 < out_cap) {
                    memcpy(out + j, parent_sel, plen);
                    j += plen;
                }
            } else {
                out[j++] = child_sel[i];
            }
        }
        out[j] = '\0';
    } else {
        snprintf(out, out_cap, "%s %s", parent_sel, child_sel);
    }
    trim_inplace(out);
}

static int parse_declarations_list(const char* block, blink_css_decl_t* out_decls, int max_decls) {
    if (!block || !out_decls || max_decls <= 0) return 0;
    int count = 0;
    const char* p = block;

    while (*p && count < max_decls) {
        while (*p && (isspace((unsigned char)*p) || *p == ';')) p++;
        if (!*p) break;

        /* Scan statement up to ';' or '{' at paren/quote depth 0 */
        const char* stmt_start = p;
        int paren = 0;
        char quote = 0;
        const char* first_colon = NULL;
        while (*p) {
            if (quote) {
                if (*p == quote) quote = 0;
            } else {
                if (*p == '"' || *p == '\'') quote = *p;
                else if (*p == '(') paren++;
                else if (*p == ')' && paren > 0) paren--;
                else if (paren == 0) {
                    if (*p == ':' && !first_colon) first_colon = p;
                    else if (*p == ';' || *p == '{') break;
                }
            }
            p++;
        }

        if (*p == '{') {
            /* Nested rule block inside declarations — skip over balanced '{...}';
               nested blocks are processed by `parse_css_rules_in_ctx`! */
            int depth = 1;
            p++;
            while (*p && depth > 0) {
                if (*p == '{') depth++;
                else if (*p == '}') depth--;
                p++;
            }
            continue;
        }

        if (!first_colon) {
            if (*p == ';') p++;
            continue;
        }

        char key[48];
        size_t klen = (size_t)(first_colon - stmt_start);
        if (klen >= sizeof(key)) klen = sizeof(key) - 1;
        memcpy(key, stmt_start, klen);
        key[klen] = '\0';
        trim_inplace(key);
        if (!(key[0] == '-' && key[1] == '-')) {
            for (size_t i = 0; key[i]; i++) key[i] = (char)tolower((unsigned char)key[i]);
        }

        const char* vs = first_colon + 1;
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

/* Extract and parse any nested `{ ... }` rules inside a qualified rule's body (CSS Nesting `&`) */
static void parse_nested_rules_in_block(blink_css_stylesheet_t* sheet,
                                        const char* parent_sel_group,
                                        const char* decl_block,
                                        const css_parse_ctx_t* ctx) {
    const char* p = decl_block;
    while (*p) {
        while (*p && (isspace((unsigned char)*p) || *p == ';')) p++;
        if (!*p) break;

        const char* stmt_start = p;
        int paren = 0;
        char quote = 0;
        while (*p) {
            if (quote) {
                if (*p == quote) quote = 0;
            } else {
                if (*p == '"' || *p == '\'') quote = *p;
                else if (*p == '(') paren++;
                else if (*p == ')' && paren > 0) paren--;
                else if (paren == 0 && (*p == ';' || *p == '{')) break;
            }
            p++;
        }

        if (*p == ';') {
            p++;
            continue;
        }
        if (*p != '{') break;

        char child_sel_group[192];
        size_t clen = (size_t)(p - stmt_start);
        if (clen >= sizeof(child_sel_group)) clen = sizeof(child_sel_group) - 1;
        memcpy(child_sel_group, stmt_start, clen);
        child_sel_group[clen] = '\0';
        trim_inplace(child_sel_group);

        p++; /* skip '{' */
        const char* inner_start = p;
        int depth = 1;
        while (*p && depth > 0) {
            if (*p == '{') depth++;
            else if (*p == '}') depth--;
            if (depth > 0) p++;
        }
        size_t inner_len = (size_t)(p - inner_start);
        if (*p == '}') p++;

        if (child_sel_group[0] == '@') {
            /* Nested @media / @container / @layer inside selector! Wrap parent selector inside it */
            size_t wrap_cap = clen + inner_len + strlen(parent_sel_group) + 16;
            char* wrapped = (char*)malloc(wrap_cap);
            if (wrapped) {
                snprintf(wrapped, wrap_cap, "%s { %s { %.*s } }", child_sel_group, parent_sel_group, (int)inner_len, inner_start);
                parse_css_rules_in_ctx(sheet, wrapped, ctx);
                free(wrapped);
            }
            continue;
        }

        /* Expand cartesian product of parent_sel_group x child_sel_group */
        const char* pp = parent_sel_group;
        while (*pp) {
            const char* p_item = pp;
            int pparen = 0;
            while (*pp && !(pparen == 0 && *pp == ',')) {
                if (*pp == '(') pparen++;
                else if (*pp == ')' && pparen > 0) pparen--;
                pp++;
            }
            char psel[160];
            size_t plen = (size_t)(pp - p_item);
            if (plen >= sizeof(psel)) plen = sizeof(psel) - 1;
            memcpy(psel, p_item, plen);
            psel[plen] = '\0';
            trim_inplace(psel);
            if (*pp == ',') pp++;

            const char* cp = child_sel_group;
            while (*cp) {
                const char* c_item = cp;
                int cparen = 0;
                while (*cp && !(cparen == 0 && *cp == ',')) {
                    if (*cp == '(') cparen++;
                    else if (*cp == ')' && cparen > 0) cparen--;
                    cp++;
                }
                char csel[160];
                size_t cslen = (size_t)(cp - c_item);
                if (cslen >= sizeof(csel)) cslen = sizeof(csel) - 1;
                memcpy(csel, c_item, cslen);
                csel[cslen] = '\0';
                trim_inplace(csel);
                if (*cp == ',') cp++;

                char combined[256];
                expand_nested_selector(psel, csel, combined, sizeof(combined));
                size_t syn_cap = strlen(combined) + inner_len + 8;
                char* syn_rule = (char*)malloc(syn_cap);
                if (syn_rule) {
                    snprintf(syn_rule, syn_cap, "%s { %.*s }", combined, (int)inner_len, inner_start);
                    parse_css_rules_in_ctx(sheet, syn_rule, ctx);
                    free(syn_rule);
                }
            }
        }
    }
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

static void parse_min_max_width_query(const char* qbuf, int32_t* io_min_w, int32_t* io_max_w) {
    const char* mn = strcasestr_portable(qbuf, "min-width");
    if (mn) {
        const char* col = strchr(mn, ':');
        if (col) *io_min_w = atoi(col + 1);
    }
    const char* mx = strcasestr_portable(qbuf, "max-width");
    if (mx) {
        const char* col = strchr(mx, ':');
        if (col) *io_max_w = atoi(col + 1);
    }
}

static void parse_css_rules_in_ctx(blink_css_stylesheet_t* sheet,
                                   const char* css,
                                   const css_parse_ctx_t* ctx) {
    const char* p = css;
    while (*p) {
        while (*p && isspace((unsigned char)*p)) p++;
        if (!*p) break;

        if (*p == '@') {
            if (strncasecmp(p, "@import", 7) == 0 && (isspace((unsigned char)p[7]) || p[7] == '"' || p[7] == '\'')) {
                p += 7;
                const char* istart = p;
                while (*p && *p != ';') p++;
                char stmt[256];
                size_t slen = (size_t)(p - istart);
                if (slen >= sizeof(stmt)) slen = sizeof(stmt) - 1;
                memcpy(stmt, istart, slen);
                stmt[slen] = '\0';
                if (*p == ';') p++;

                if (ctx->import_depth < 8) {
                    /* Extract URL from `@import "foo.css"` or `@import url("foo.css") layer(theme)` */
                    char url_buf[192] = "";
                    const char* up = stmt;
                    while (*up && isspace((unsigned char)*up)) up++;
                    if (strncasecmp(up, "url(", 4) == 0) {
                        up = read_paren_arg(up + 3, url_buf, sizeof(url_buf));
                        if ((url_buf[0] == '"' || url_buf[0] == '\'')) {
                            size_t ul = strlen(url_buf);
                            if (ul >= 2) {
                                memmove(url_buf, url_buf + 1, ul - 2);
                                url_buf[ul - 2] = '\0';
                            }
                        }
                    } else if (*up == '"' || *up == '\'') {
                        char q = *up++;
                        const char* us = up;
                        while (*up && *up != q) up++;
                        size_t ul = (size_t)(up - us);
                        if (ul >= sizeof(url_buf)) ul = sizeof(url_buf) - 1;
                        memcpy(url_buf, us, ul);
                        url_buf[ul] = '\0';
                        if (*up == q) up++;
                    }

                    int32_t imp_layer = ctx->active_layer;
                    const char* lp = strcasestr_portable(up, "layer(");
                    if (lp) {
                        char lname[48];
                        read_paren_arg(lp + 5, lname, sizeof(lname));
                        imp_layer = get_or_register_layer(sheet, lname);
                    }

                    char sub_dir[512];
                    char* imp_css = load_local_stylesheet_file(ctx->base_dir, url_buf, sub_dir, sizeof(sub_dir));
                    if (imp_css) {
                        char* clean_imp = strip_css_comments(imp_css);
                        free(imp_css);
                        if (clean_imp) {
                            css_parse_ctx_t sub_ctx = *ctx;
                            sub_ctx.active_layer = imp_layer;
                            sub_ctx.base_dir = sub_dir;
                            sub_ctx.import_depth = ctx->import_depth + 1;
                            parse_css_rules_in_ctx(sheet, clean_imp, &sub_ctx);
                            free(clean_imp);
                        }
                    }
                }
                continue;
            } else if (strncasecmp(p, "@layer", 6) == 0 && (isspace((unsigned char)p[6]) || p[6] == '{')) {
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
                        css_parse_ctx_t sub_ctx = *ctx;
                        sub_ctx.active_layer = layer_id;
                        parse_css_rules_in_ctx(sheet, sub, &sub_ctx);
                        free(sub);
                    }
                    if (*p == '}') p++;
                    continue;
                }
            } else if (strncasecmp(p, "@media", 6) == 0 || strncasecmp(p, "@container", 10) == 0) {
                bool is_container = (strncasecmp(p, "@container", 10) == 0);
                p += is_container ? 10 : 6;
                const char* qstart = p;
                while (*p && *p != '{') p++;
                char qbuf[192];
                size_t qlen = (size_t)(p - qstart);
                if (qlen >= sizeof(qbuf)) qlen = sizeof(qbuf) - 1;
                memcpy(qbuf, qstart, qlen);
                qbuf[qlen] = '\0';

                css_parse_ctx_t sub_ctx = *ctx;
                if (is_container) {
                    parse_min_max_width_query(qbuf, &sub_ctx.container_min_w, &sub_ctx.container_max_w);
                } else {
                    parse_min_max_width_query(qbuf, &sub_ctx.media_min_w, &sub_ctx.media_max_w);
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
                        parse_css_rules_in_ctx(sheet, sub, &sub_ctx);
                        free(sub);
                    }
                    if (*p == '}') p++;
                    continue;
                }
            } else if (strncasecmp(p, "@scope", 6) == 0) {
                /* CSS Cascade Level 6: `@scope (<root>) [to (<limit>)] { ... }` */
                p += 6;
                const char* sstart = p;
                while (*p && *p != '{') p++;
                char sbuf[192];
                size_t slen = (size_t)(p - sstart);
                if (slen >= sizeof(sbuf)) slen = sizeof(sbuf) - 1;
                memcpy(sbuf, sstart, slen);
                sbuf[slen] = '\0';

                css_parse_ctx_t sub_ctx = *ctx;
                const char* lp1 = strchr(sbuf, '(');
                if (lp1) {
                    char root_str[96];
                    const char* after_root = read_paren_arg(lp1, root_str, sizeof(root_str));
                    if (blink_css_parse_selector(root_str, &sub_ctx.scope_root)) {
                        sub_ctx.has_scope = true;
                    }
                    const char* to_kw = strcasestr_portable(after_root, "to");
                    if (to_kw) {
                        const char* lp2 = strchr(to_kw, '(');
                        if (lp2) {
                            char lim_str[96];
                            read_paren_arg(lp2, lim_str, sizeof(lim_str));
                            if (blink_css_parse_selector(lim_str, &sub_ctx.scope_limit)) {
                                sub_ctx.has_scope_limit = true;
                            }
                        }
                    }
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
                        parse_css_rules_in_ctx(sheet, sub, &sub_ctx);
                        free(sub);
                    }
                    if (*p == '}') p++;
                    continue;
                }
            } else {
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

        /* Standard qualified rule: `selector_list { declarations + optional nested rules }` */
        const char* sel_start = p;
        while (*p && *p != '{') p++;
        if (*p != '{') break;

        size_t sel_len = (size_t)(p - sel_start);
        char* sel_group = (char*)malloc(sel_len + 1);
        if (!sel_group) break;
        memcpy(sel_group, sel_start, sel_len);
        sel_group[sel_len] = '\0';
        trim_inplace(sel_group);

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
                    memset(rule, 0, sizeof(*rule));
                    rule->selector = csel;
                    rule->num_decls = num_decls;
                    for (int d = 0; d < num_decls; d++) rule->decls[d] = parsed_decls[d];
                    rule->layer_order = ctx->active_layer;
                    rule->source_order = sheet->next_source_order;
                    sheet->next_source_order += 64;
                    rule->media_min_w = ctx->media_min_w;
                    rule->media_max_w = ctx->media_max_w;
                    rule->container_min_w = ctx->container_min_w;
                    rule->container_max_w = ctx->container_max_w;
                    rule->has_scope = ctx->has_scope;
                    rule->scope_root = ctx->scope_root;
                    rule->has_scope_limit = ctx->has_scope_limit;
                    rule->scope_limit = ctx->scope_limit;
                }
                if (*sp == ',') sp++;
            }
        }

        /* Process any nested `{ ... }` rules inside `decl_block` */
        if (strchr(decl_block, '{') != NULL) {
            parse_nested_rules_in_block(sheet, sel_group, decl_block, ctx);
        }

        free(decl_block);
        free(sel_group);
    }
}

void blink_css_parse_stylesheet_ex(blink_css_stylesheet_t* sheet, const char* css_text, const char* base_dir) {
    if (!sheet || !css_text) return;
    char* clean = strip_css_comments(css_text);
    if (!clean) return;
    css_parse_ctx_t ctx;
    memset(&ctx, 0, sizeof(ctx));
    ctx.active_layer = BLINK_UNLAYERED_ORDER;
    ctx.media_min_w = -1;
    ctx.media_max_w = -1;
    ctx.container_min_w = -1;
    ctx.container_max_w = -1;
    ctx.base_dir = base_dir ? base_dir : ".";
    ctx.import_depth = 0;
    parse_css_rules_in_ctx(sheet, clean, &ctx);
    free(clean);
}

void blink_css_parse_stylesheet(blink_css_stylesheet_t* sheet, const char* css_text) {
    blink_css_parse_stylesheet_ex(sheet, css_text, ".");
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
           strcmp(prop, "text-align") == 0 ||
           strcmp(prop, "white-space") == 0 ||
           strcmp(prop, "border-collapse") == 0;
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
        if (strcmp(prop, "background") == 0) {
            st->has_gradient = src->has_gradient;
            st->grad_angle_deg = src->grad_angle_deg;
            st->num_grad_stops = src->num_grad_stops;
            for (int k = 0; k < 4; k++) {
                st->grad_colors[k] = src->grad_colors[k];
                st->grad_pos_pct[k] = src->grad_pos_pct[k];
            }
        }
    } else if (strcmp(prop, "background-image") == 0) {
        st->has_gradient = src->has_gradient;
        st->grad_angle_deg = src->grad_angle_deg;
        st->num_grad_stops = src->num_grad_stops;
        for (int k = 0; k < 4; k++) {
            st->grad_colors[k] = src->grad_colors[k];
            st->grad_pos_pct[k] = src->grad_pos_pct[k];
        }
    } else if (strcmp(prop, "font-size") == 0) st->font_size = src->font_size;
    else if (strcmp(prop, "font-weight") == 0) st->font_weight = src->font_weight;
    else if (strcmp(prop, "font-style") == 0) st->font_style = src->font_style;
    else if (strcmp(prop, "font-family") == 0) strcpy(st->font_family, src->font_family);
    else if (strcmp(prop, "line-height") == 0) st->line_height = src->line_height;
    else if (strcmp(prop, "text-align") == 0) st->text_align = src->text_align;
    else if (strcmp(prop, "text-decoration") == 0) {
        st->text_underline = src->text_underline;
        st->text_line_through = src->text_line_through;
    } else if (strcmp(prop, "vertical-align") == 0) st->vertical_align = src->vertical_align;
    else if (strcmp(prop, "white-space") == 0) st->white_space = src->white_space;
    else if (strcmp(prop, "margin") == 0) {
        st->margin_top = src->margin_top; st->margin_right = src->margin_right;
        st->margin_bottom = src->margin_bottom; st->margin_left = src->margin_left;
    } else if (strcmp(prop, "margin-top") == 0) st->margin_top = src->margin_top;
    else if (strcmp(prop, "margin-right") == 0) st->margin_right = src->margin_right;
    else if (strcmp(prop, "margin-bottom") == 0) st->margin_bottom = src->margin_bottom;
    else if (strcmp(prop, "margin-left") == 0) st->margin_left = src->margin_left;
    else if (strcmp(prop, "padding") == 0) {
        st->padding_top = src->padding_top; st->padding_right = src->padding_right;
        st->padding_bottom = src->padding_bottom; st->padding_left = src->padding_left;
    } else if (strcmp(prop, "padding-top") == 0) st->padding_top = src->padding_top;
    else if (strcmp(prop, "padding-right") == 0) st->padding_right = src->padding_right;
    else if (strcmp(prop, "padding-bottom") == 0) st->padding_bottom = src->padding_bottom;
    else if (strcmp(prop, "padding-left") == 0) st->padding_left = src->padding_left;
    else if (strcmp(prop, "border") == 0 || strcmp(prop, "border-width") == 0) {
        st->border_width = src->border_width;
        st->border_left_width = src->border_left_width;
        st->border_bottom_width = src->border_bottom_width;
        st->border_style = src->border_style;
        st->border_color = src->border_color;
    } else if (strcmp(prop, "border-color") == 0) st->border_color = src->border_color;
    else if (strcmp(prop, "border-style") == 0) st->border_style = src->border_style;
    else if (strcmp(prop, "border-collapse") == 0) st->border_collapse = src->border_collapse;
    else if (strcmp(prop, "width") == 0) st->width = src->width;
    else if (strcmp(prop, "height") == 0) st->height = src->height;
    else if (strcmp(prop, "min-width") == 0) st->min_width = src->min_width;
    else if (strcmp(prop, "max-width") == 0) st->max_width = src->max_width;
    else if (strcmp(prop, "display") == 0) st->display = src->display;
    else if (strcmp(prop, "box-sizing") == 0) st->box_sizing = src->box_sizing;
    else if (strcmp(prop, "position") == 0) st->position = src->position;
    else if (strcmp(prop, "z-index") == 0) { st->z_index = src->z_index; st->has_z_index = src->has_z_index; }
    else if (strcmp(prop, "float") == 0) st->css_float = src->css_float;
    else if (strcmp(prop, "clear") == 0) st->css_clear = src->css_clear;
    else if (strcmp(prop, "border-radius") == 0) st->border_radius = src->border_radius;
    else if (strcmp(prop, "opacity") == 0) st->opacity_u8 = src->opacity_u8;
    else if (strcmp(prop, "overflow") == 0 || strcmp(prop, "overflow-x") == 0 || strcmp(prop, "overflow-y") == 0) {
        st->overflow_hidden = src->overflow_hidden;
    } else if (strcmp(prop, "box-shadow") == 0) {
        st->has_box_shadow = src->has_box_shadow;
        st->shadow_dx = src->shadow_dx;
        st->shadow_dy = src->shadow_dy;
        st->shadow_blur = src->shadow_blur;
        st->shadow_spread = src->shadow_spread;
        st->shadow_color = src->shadow_color;
    } else if (strcmp(prop, "transform") == 0) {
        st->has_transform = src->has_transform;
        st->translate_x_px = src->translate_x_px;
        st->translate_x_pct = src->translate_x_pct;
        st->translate_y_px = src->translate_y_px;
        st->translate_y_pct = src->translate_y_pct;
    }
}

static bool parse_border_style_kw(const char* tok, css_border_style_t* out_style) {
    if (!tok || !out_style) return false;
    if (strcasecmp(tok, "none") == 0)   { *out_style = BDR_STYLE_NONE; return true; }
    if (strcasecmp(tok, "hidden") == 0) { *out_style = BDR_STYLE_HIDDEN; return true; }
    if (strcasecmp(tok, "inset") == 0)  { *out_style = BDR_STYLE_INSET; return true; }
    if (strcasecmp(tok, "groove") == 0) { *out_style = BDR_STYLE_GROOVE; return true; }
    if (strcasecmp(tok, "outset") == 0) { *out_style = BDR_STYLE_OUTSET; return true; }
    if (strcasecmp(tok, "ridge") == 0)  { *out_style = BDR_STYLE_RIDGE; return true; }
    if (strcasecmp(tok, "dotted") == 0) { *out_style = BDR_STYLE_DOTTED; return true; }
    if (strcasecmp(tok, "dashed") == 0) { *out_style = BDR_STYLE_DASHED; return true; }
    if (strcasecmp(tok, "solid") == 0)  { *out_style = BDR_STYLE_SOLID; return true; }
    if (strcasecmp(tok, "double") == 0) { *out_style = BDR_STYLE_DOUBLE; return true; }
    return false;
}

static void parse_border_shorthand(const char* val,
                                   uint32_t current_color,
                                   int32_t em_px, int32_t rem_px, int32_t vw_px, int32_t vh_px,
                                   blink_layout_mode_t mode,
                                   int* out_w,
                                   css_border_style_t* io_style,
                                   uint32_t* io_color) {
    *out_w = 0;
    if (!val || strcmp(val, "0") == 0) {
        if (io_style) *io_style = BDR_STYLE_NONE;
        return;
    }
    if (strcasecmp(val, "none") == 0) {
        if (io_style) *io_style = BDR_STYLE_NONE;
        return;
    }
    if (strcasecmp(val, "hidden") == 0) {
        if (io_style) *io_style = BDR_STYLE_HIDDEN;
        return;
    }

    /* Tokenize respecting parentheses (e.g. `2px solid color-mix(...)` or `1px solid rgb(...)`) */
    bool saw_style = false;
    bool saw_width = false;
    css_border_style_t parsed_st = BDR_STYLE_SOLID;
    const char* p = val;
    while (*p) {
        while (*p && isspace((unsigned char)*p)) p++;
        if (!*p) break;
        const char* ts = p;
        int paren = 0;
        while (*p && (paren > 0 || !isspace((unsigned char)*p))) {
            if (*p == '(') paren++;
            else if (*p == ')' && paren > 0) paren--;
            p++;
        }
        char tok[128];
        size_t tlen = (size_t)(p - ts);
        if (tlen >= sizeof(tok)) tlen = sizeof(tok) - 1;
        memcpy(tok, ts, tlen);
        tok[tlen] = '\0';

        css_border_style_t bst;
        if (parse_border_style_kw(tok, &bst)) {
            parsed_st = bst;
            saw_style = (bst != BDR_STYLE_NONE && bst != BDR_STYLE_HIDDEN);
            if (io_style) *io_style = bst;
        } else if (isdigit((unsigned char)tok[0]) || strncasecmp(tok, "calc(", 5) == 0 ||
                   strncasecmp(tok, "min(", 4) == 0 || strncasecmp(tok, "max(", 4) == 0 ||
                   strncasecmp(tok, "clamp(", 6) == 0) {
            bool is_auto = false;
            *out_w = blink_css_eval_length_or_calc(tok, 0, em_px, rem_px, vw_px, vh_px, mode, &is_auto);
            saw_width = true;
        } else {
            bool cok = false;
            uint32_t c = blink_parse_css_color_with_current(tok, current_color, &cok);
            if (cok) *io_color = c;
        }
    }
    if (parsed_st == BDR_STYLE_NONE || parsed_st == BDR_STYLE_HIDDEN) {
        *out_w = 0;
    } else if (!saw_width && saw_style) {
        *out_w = 1;
    }
}

static void parse_grid_track_spec(const char* track_str,
                                  int32_t parent_avail_w, int32_t em_px, int32_t root_font_px,
                                  int32_t vw_px, int32_t vh_px, blink_layout_mode_t mode,
                                  int* out_min_px, int* out_max_spec) {
    *out_min_px = 0;
    *out_max_spec = -1;
    if (!track_str) return;
    while (*track_str && isspace((unsigned char)*track_str)) track_str++;

    if (strncasecmp(track_str, "minmax(", 7) == 0) {
        char inner[128];
        read_paren_arg(track_str + 6, inner, sizeof(inner));
        char* comma = strchr(inner, ',');
        if (comma) {
            *comma = '\0';
            char* min_s = inner;
            char* max_s = comma + 1;
            trim_inplace(min_s);
            trim_inplace(max_s);
            *out_min_px = blink_css_eval_length_or_calc(min_s, parent_avail_w, em_px, root_font_px, vw_px, vh_px, mode, NULL);
            if (*out_min_px < 0) *out_min_px = 0;
            if (strcasestr_portable(max_s, "fr")) {
                int fr = atoi(max_s);
                *out_max_spec = (fr > 0) ? -fr : -1;
            } else {
                int32_t mx = blink_css_eval_length_or_calc(max_s, parent_avail_w, em_px, root_font_px, vw_px, vh_px, mode, NULL);
                *out_max_spec = (mx > 0) ? mx : -1;
            }
            return;
        }
    }

    if (strcasestr_portable(track_str, "fr")) {
        int fr = atoi(track_str);
        *out_max_spec = (fr > 0) ? -fr : -1;
    } else {
        int32_t w = blink_css_eval_length_or_calc(track_str, parent_avail_w, em_px, root_font_px, vw_px, vh_px, mode, NULL);
        *out_max_spec = (w > 0) ? w : -1;
    }
}

static bool parse_linear_gradient_decl(dom_style_t* st, const char* val) {
    if (!st || !val) return false;
    const char* lg = strcasestr_portable(val, "linear-gradient(");
    if (!lg) return false;

    char inner[256];
    read_paren_arg(lg + 15, inner, sizeof(inner));

    char args[8][128];
    int n_args = 0;
    const char* cur = inner;
    while (*cur && n_args < 8) {
        const char* s0 = cur;
        int paren = 0;
        while (*cur && !(paren == 0 && *cur == ',')) {
            if (*cur == '(') paren++;
            else if (*cur == ')' && paren > 0) paren--;
            cur++;
        }
        size_t alen = (size_t)(cur - s0);
        if (alen >= 128) alen = 127;
        memcpy(args[n_args], s0, alen);
        args[n_args][alen] = '\0';
        trim_inplace(args[n_args]);
        if (args[n_args][0]) n_args++;
        if (*cur == ',') cur++;
    }
    if (n_args < 2) return false;

    float angle = 180.0f;
    int first_stop = 0;
    const char* a0 = args[0];
    if (strncasecmp(a0, "to ", 3) == 0) {
        first_stop = 1;
        bool has_top = (strcasestr_portable(a0, "top") != NULL);
        bool has_bot = (strcasestr_portable(a0, "bottom") != NULL);
        bool has_left = (strcasestr_portable(a0, "left") != NULL);
        bool has_right = (strcasestr_portable(a0, "right") != NULL);
        if (has_top && has_right) angle = 45.0f;
        else if (has_bot && has_right) angle = 135.0f;
        else if (has_bot && has_left) angle = 225.0f;
        else if (has_top && has_left) angle = 315.0f;
        else if (has_right) angle = 90.0f;
        else if (has_left) angle = 270.0f;
        else if (has_top) angle = 0.0f;
        else angle = 180.0f;
    } else if (strcasestr_portable(a0, "deg") != NULL) {
        first_stop = 1;
        angle = strtof(a0, NULL);
    } else if (strcasestr_portable(a0, "turn") != NULL) {
        first_stop = 1;
        angle = strtof(a0, NULL) * 360.0f;
    }

    int stop_cnt = 0;
    uint32_t cols[4];
    int pos[4];
    for (int i = first_stop; i < n_args && stop_cnt < 4; i++) {
        char buf[128];
        strcpy(buf, args[i]);
        int pct = -1;
        size_t l = strlen(buf);
        if (l > 1 && buf[l - 1] == '%') {
            size_t k = l - 1;
            while (k > 0 && (isdigit((unsigned char)buf[k - 1]) || buf[k - 1] == '.')) k--;
            if (k > 0 && isspace((unsigned char)buf[k - 1])) {
                pct = (int)lround(strtod(buf + k, NULL));
                if (pct < 0) pct = 0;
                if (pct > 100) pct = 100;
                buf[k] = '\0';
                trim_inplace(buf);
            }
        }
        bool cok = false;
        uint32_t c = blink_parse_css_color_with_current(buf, st->color, &cok);
        if (cok) {
            cols[stop_cnt] = c;
            pos[stop_cnt] = pct;
            stop_cnt++;
        }
    }

    if (stop_cnt < 2) return false;
    if (pos[0] < 0) pos[0] = 0;
    if (pos[stop_cnt - 1] < 0) pos[stop_cnt - 1] = 100;
    for (int i = 1; i < stop_cnt - 1; i++) {
        if (pos[i] < 0) {
            int next_known = i + 1;
            while (next_known < stop_cnt - 1 && pos[next_known] < 0) next_known++;
            int span_idx = next_known - (i - 1);
            pos[i] = pos[i - 1] + (pos[next_known] - pos[i - 1]) / span_idx;
        }
        if (pos[i] < pos[i - 1]) pos[i] = pos[i - 1];
    }

    st->has_gradient = true;
    st->grad_angle_deg = angle;
    st->num_grad_stops = stop_cnt;
    for (int i = 0; i < stop_cnt; i++) {
        st->grad_colors[i] = cols[i];
        st->grad_pos_pct[i] = pos[i];
    }
    st->bg_color = cols[0];
    st->has_bg = true;
    return true;
}

static void parse_box_shadow_decl(dom_style_t* st,
                                  const char* val,
                                  int32_t em_px, int32_t root_font_px, int32_t vw_px, int32_t vh_px,
                                  blink_layout_mode_t mode) {
    if (!st || !val) return;
    if (strcasecmp(val, "none") == 0) {
        st->has_box_shadow = false;
        return;
    }

    /* Take first outer shadow in comma-separated list */
    char first_sh[192];
    const char* p = val;
    int paren = 0;
    size_t flen = 0;
    while (*p && !(paren == 0 && *p == ',') && flen + 1 < sizeof(first_sh)) {
        if (*p == '(') paren++;
        else if (*p == ')' && paren > 0) paren--;
        first_sh[flen++] = *p++;
    }
    first_sh[flen] = '\0';
    trim_inplace(first_sh);

    int32_t lens[4] = {0, 0, 0, 0};
    int n_lens = 0;
    uint32_t sh_col = st->color;
    bool saw_col = false;
    bool is_inset = false;

    const char* cur = first_sh;
    while (*cur) {
        while (*cur && isspace((unsigned char)*cur)) cur++;
        if (!*cur) break;
        const char* ts = cur;
        int tparen = 0;
        while (*cur && (tparen > 0 || !isspace((unsigned char)*cur))) {
            if (*cur == '(') tparen++;
            else if (*cur == ')' && tparen > 0) tparen--;
            cur++;
        }
        char tok[128];
        size_t tlen = (size_t)(cur - ts);
        if (tlen >= sizeof(tok)) tlen = sizeof(tok) - 1;
        memcpy(tok, ts, tlen);
        tok[tlen] = '\0';

        if (strcasecmp(tok, "inset") == 0) {
            is_inset = true;
            continue;
        }
        bool looks_len = (isdigit((unsigned char)tok[0]) ||
                          ((tok[0] == '-' || tok[0] == '+') && isdigit((unsigned char)tok[1])) ||
                          strncasecmp(tok, "calc(", 5) == 0 ||
                          strncasecmp(tok, "min(", 4) == 0 ||
                          strncasecmp(tok, "max(", 4) == 0 ||
                          strncasecmp(tok, "clamp(", 6) == 0);
        if (looks_len && n_lens < 4) {
            lens[n_lens++] = blink_css_eval_length_or_calc(tok, 0, em_px, root_font_px, vw_px, vh_px, mode, NULL);
        } else {
            bool cok = false;
            uint32_t c = blink_parse_css_color_with_current(tok, st->color, &cok);
            if (cok) {
                sh_col = c;
                saw_col = true;
            }
        }
    }

    if (!is_inset && n_lens >= 2) {
        st->has_box_shadow = true;
        st->shadow_dx = lens[0];
        st->shadow_dy = lens[1];
        st->shadow_blur = (n_lens >= 3 && lens[2] > 0) ? lens[2] : 0;
        st->shadow_spread = (n_lens >= 4) ? lens[3] : 0;
        st->shadow_color = saw_col ? sh_col : st->color;
    } else if (is_inset) {
        st->has_box_shadow = false;
    }
}

static void parse_translate_component(const char* raw_tok,
                                      int32_t em_px, int32_t root_font_px, int32_t vw_px, int32_t vh_px,
                                      blink_layout_mode_t mode,
                                      int* io_px,
                                      float* io_pct) {
    char tok[96];
    strncpy(tok, raw_tok ? raw_tok : "", sizeof(tok) - 1);
    tok[sizeof(tok) - 1] = '\0';
    trim_inplace(tok);
    if (!tok[0]) return;
    size_t l = strlen(tok);
    if (l > 1 && tok[l - 1] == '%' && strncasecmp(tok, "calc(", 5) != 0) {
        *io_pct += strtof(tok, NULL);
    } else {
        *io_px += blink_css_eval_length_or_calc(tok, 0, em_px, root_font_px, vw_px, vh_px, mode, NULL);
    }
}

static void parse_transform_decl(dom_style_t* st,
                                 const char* val,
                                 int32_t em_px, int32_t root_font_px, int32_t vw_px, int32_t vh_px,
                                 blink_layout_mode_t mode) {
    if (!st || !val) return;
    if (strcasecmp(val, "none") == 0) {
        st->has_transform = false;
        st->translate_x_px = st->translate_y_px = 0;
        st->translate_x_pct = st->translate_y_pct = 0.0f;
        return;
    }

    int tx_px = 0, ty_px = 0;
    float tx_pct = 0.0f, ty_pct = 0.0f;
    bool any_fn = false;

    const char* p = val;
    while (*p) {
        while (*p && isspace((unsigned char)*p)) p++;
        if (!*p) break;
        const char* fn_s = p;
        while (*p && *p != '(' && !isspace((unsigned char)*p)) p++;
        char fn_name[40];
        copy_lower_bounded(fn_name, sizeof(fn_name), fn_s, (size_t)(p - fn_s));
        while (*p && isspace((unsigned char)*p)) p++;
        if (*p != '(') {
            if (*p) p++;
            continue;
        }
        char inner[128];
        p = read_paren_arg(p, inner, sizeof(inner));
        any_fn = true;

        if (strcmp(fn_name, "translatex") == 0) {
            parse_translate_component(inner, em_px, root_font_px, vw_px, vh_px, mode, &tx_px, &tx_pct);
        } else if (strcmp(fn_name, "translatey") == 0) {
            parse_translate_component(inner, em_px, root_font_px, vw_px, vh_px, mode, &ty_px, &ty_pct);
        } else if (strcmp(fn_name, "translate") == 0 || strcmp(fn_name, "translate3d") == 0) {
            /* Split first two comma-separated args */
            char a1[96] = "", a2[96] = "";
            const char* c = inner;
            int paren = 0;
            const char* comma1 = NULL;
            const char* comma2 = NULL;
            while (*c) {
                if (*c == '(') paren++;
                else if (*c == ')' && paren > 0) paren--;
                else if (paren == 0 && *c == ',') {
                    if (!comma1) comma1 = c;
                    else if (!comma2) { comma2 = c; break; }
                }
                c++;
            }
            if (comma1) {
                size_t l1 = (size_t)(comma1 - inner);
                if (l1 >= sizeof(a1)) l1 = sizeof(a1) - 1;
                memcpy(a1, inner, l1); a1[l1] = '\0';
                const char* s2 = comma1 + 1;
                size_t l2 = comma2 ? (size_t)(comma2 - s2) : strlen(s2);
                if (l2 >= sizeof(a2)) l2 = sizeof(a2) - 1;
                memcpy(a2, s2, l2); a2[l2] = '\0';
            } else {
                strncpy(a1, inner, sizeof(a1) - 1);
            }
            parse_translate_component(a1, em_px, root_font_px, vw_px, vh_px, mode, &tx_px, &tx_pct);
            if (a2[0]) {
                parse_translate_component(a2, em_px, root_font_px, vw_px, vh_px, mode, &ty_px, &ty_pct);
            }
        }
    }

    if (any_fn) {
        st->has_transform = true;
        st->translate_x_px = tx_px;
        st->translate_x_pct = tx_pct;
        st->translate_y_px = ty_px;
        st->translate_y_pct = ty_pct;
    }
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
        uint32_t inh_c = parent_st ? parent_st->color : initial_st->color;
        uint32_t c = blink_parse_css_color_with_current(val, inh_c, &ok);
        if (ok) st->color = c;
    } else if (strcmp(prop, "background-image") == 0) {
        if (strcasecmp(val, "none") == 0) {
            st->has_gradient = false;
        } else {
            parse_linear_gradient_decl(st, val);
        }
    } else if (strcmp(prop, "background-color") == 0 || strcmp(prop, "background") == 0) {
        if (strcasecmp(val, "none") == 0 || strcasecmp(val, "transparent") == 0) {
            st->bg_color = 0;
            st->has_bg = false;
            if (strcmp(prop, "background") == 0) st->has_gradient = false;
        } else if (strcmp(prop, "background") == 0 && parse_linear_gradient_decl(st, val)) {
            /* Parsed multi-stop linear-gradient(...) */
        } else {
            bool ok = false;
            uint32_t c = blink_parse_css_color_with_current(val, st->color, &ok);
            if (ok) {
                st->bg_color = c;
                st->has_bg = ((c >> 24) > 0);
                if (strcmp(prop, "background") == 0) st->has_gradient = false;
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
    } else if (strcmp(prop, "text-decoration") == 0 || strcmp(prop, "text-decoration-line") == 0) {
        if (strcasestr_portable(val, "none")) {
            st->text_underline = false;
            st->text_line_through = false;
        } else {
            if (strcasestr_portable(val, "underline")) st->text_underline = true;
            if (strcasestr_portable(val, "line-through")) st->text_line_through = true;
        }
    } else if (strcmp(prop, "vertical-align") == 0) {
        if (strcasestr_portable(val, "sub")) st->vertical_align = VALIGN_SUB;
        else if (strcasestr_portable(val, "super")) st->vertical_align = VALIGN_SUPER;
        else if (strcasestr_portable(val, "middle")) st->vertical_align = VALIGN_MIDDLE;
        else st->vertical_align = VALIGN_BASELINE;
    } else if (strcmp(prop, "white-space") == 0) {
        if (strcasestr_portable(val, "pre")) st->white_space = WS_PRE;
        else if (strcasestr_portable(val, "nowrap")) st->white_space = WS_NOWRAP;
        else st->white_space = WS_NORMAL;
    } else if (strcmp(prop, "container-type") == 0 || strcmp(prop, "container") == 0) {
        st->is_inline_size_container = (strcasestr_portable(val, "inline-size") != NULL ||
                                        strcasestr_portable(val, "size") != NULL);
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
    } else if (strcmp(prop, "min-width") == 0) {
        bool is_auto = false;
        int32_t mw = blink_css_eval_length_or_calc(val, parent_avail_w, em_px, root_font_px, vw_px, vh_px, mode, &is_auto);
        st->min_width = (is_auto || mw < 0) ? 0 : mw;
    } else if (strcmp(prop, "max-width") == 0) {
        bool is_auto = false;
        int32_t mw = blink_css_eval_length_or_calc(val, parent_avail_w, em_px, root_font_px, vw_px, vh_px, mode, &is_auto);
        st->max_width = is_auto ? -1 : mw;
    } else if (strcmp(prop, "height") == 0) {
        bool is_auto = false;
        int32_t h = blink_css_eval_length_or_calc(val, vh_px, em_px, root_font_px, vw_px, vh_px, mode, &is_auto);
        st->height = is_auto ? -1 : h;
    } else if (strcmp(prop, "border") == 0) {
        int bw = 0;
        parse_border_shorthand(val, st->color, em_px, root_font_px, vw_px, vh_px, mode, &bw, &st->border_style, &st->border_color);
        st->border_width = bw;
    } else if (strcmp(prop, "border-width") == 0) {
        st->border_width = blink_css_eval_length_or_calc(val, 0, em_px, root_font_px, vw_px, vh_px, mode, NULL);
        if (st->border_width > 0 && st->border_style == BDR_STYLE_NONE) st->border_style = BDR_STYLE_SOLID;
    } else if (strcmp(prop, "border-style") == 0) {
        css_border_style_t bst;
        if (parse_border_style_kw(val, &bst)) {
            st->border_style = bst;
            if (bst == BDR_STYLE_NONE || bst == BDR_STYLE_HIDDEN) st->border_width = 0;
        }
    } else if (strcmp(prop, "border-collapse") == 0) {
        st->border_collapse = (strcasestr_portable(val, "collapse") != NULL);
    } else if (strcmp(prop, "border-left") == 0) {
        int bw = 0;
        uint32_t lc = st->border_color;
        css_border_style_t dummy = st->border_style;
        parse_border_shorthand(val, st->color, em_px, root_font_px, vw_px, vh_px, mode, &bw, &dummy, &lc);
        st->border_left_width = bw;
        st->border_left_color = lc;
    } else if (strcmp(prop, "border-bottom") == 0) {
        int bw = 0;
        css_border_style_t dummy = st->border_style;
        parse_border_shorthand(val, st->color, em_px, root_font_px, vw_px, vh_px, mode, &bw, &dummy, &st->border_color);
        st->border_bottom_width = bw;
    } else if (strcmp(prop, "border-color") == 0) {
        bool ok = false;
        uint32_t c = blink_parse_css_color_with_current(val, st->color, &ok);
        if (ok) st->border_color = c;
    } else if (strcmp(prop, "border-radius") == 0) {
        st->border_radius = blink_css_eval_length_or_calc(val, parent_avail_w, em_px, root_font_px, vw_px, vh_px, mode, NULL);
    } else if (strcmp(prop, "box-sizing") == 0) {
        if (strcasestr_portable(val, "border-box")) st->box_sizing = BOX_SIZING_BORDER_BOX;
        else st->box_sizing = BOX_SIZING_CONTENT_BOX;
    } else if (strcmp(prop, "position") == 0) {
        if (strcasestr_portable(val, "absolute")) st->position = POS_ABSOLUTE;
        else if (strcasestr_portable(val, "fixed")) st->position = POS_FIXED;
        else if (strcasestr_portable(val, "sticky")) st->position = POS_STICKY;
        else if (strcasestr_portable(val, "relative")) st->position = POS_RELATIVE;
        else st->position = POS_STATIC;
    } else if (strcmp(prop, "top") == 0) {
        bool is_auto = false;
        int32_t v = blink_css_eval_length_or_calc(val, vh_px, em_px, root_font_px, vw_px, vh_px, mode, &is_auto);
        size_t vl_ = strlen(val);
        st->top_is_pct = (!is_auto && vl_ > 1 && val[vl_ - 1] == '%' && strchr(val, '(') == NULL);
        st->top_pct = st->top_is_pct ? strtof(val, NULL) : 0.0f;
        st->has_top = !is_auto;
        st->top = is_auto ? 0 : v;
    } else if (strcmp(prop, "bottom") == 0) {
        bool is_auto = false;
        int32_t v = blink_css_eval_length_or_calc(val, vh_px, em_px, root_font_px, vw_px, vh_px, mode, &is_auto);
        size_t vl_ = strlen(val);
        st->bottom_is_pct = (!is_auto && vl_ > 1 && val[vl_ - 1] == '%' && strchr(val, '(') == NULL);
        st->bottom_pct = st->bottom_is_pct ? strtof(val, NULL) : 0.0f;
        st->has_bottom = !is_auto;
        st->bottom = is_auto ? 0 : v;
    } else if (strcmp(prop, "left") == 0) {
        bool is_auto = false;
        int32_t v = blink_css_eval_length_or_calc(val, parent_avail_w, em_px, root_font_px, vw_px, vh_px, mode, &is_auto);
        st->has_left = !is_auto;
        st->left = is_auto ? 0 : v;
    } else if (strcmp(prop, "right") == 0) {
        bool is_auto = false;
        int32_t v = blink_css_eval_length_or_calc(val, parent_avail_w, em_px, root_font_px, vw_px, vh_px, mode, &is_auto);
        st->has_right = !is_auto;
        st->right = is_auto ? 0 : v;
    } else if (strcmp(prop, "inset") == 0) {
        if (strcasecmp(val, "auto") == 0) {
            st->has_top = st->has_right = st->has_bottom = st->has_left = false;
        } else {
            blink_box_edges_t e;
            blink_css_parse_box_shorthand(val, parent_avail_w, em_px, root_font_px, vw_px, vh_px, mode, &e);
            st->top = e.top; st->right = e.right; st->bottom = e.bottom; st->left = e.left;
            st->has_top = st->has_right = st->has_bottom = st->has_left = true;
        }
    } else if (strcmp(prop, "z-index") == 0) {
        if (strcasecmp(val, "auto") == 0) {
            st->has_z_index = false;
            st->z_index = 0;
        } else {
            st->has_z_index = true;
            st->z_index = atoi(val);
        }
    } else if (strcmp(prop, "float") == 0) {
        if (strcasestr_portable(val, "left")) st->css_float = FLOAT_LEFT;
        else if (strcasestr_portable(val, "right")) st->css_float = FLOAT_RIGHT;
        else st->css_float = FLOAT_NONE;
    } else if (strcmp(prop, "clear") == 0) {
        if (strcasestr_portable(val, "both")) st->css_clear = CLEAR_BOTH;
        else if (strcasestr_portable(val, "left")) st->css_clear = CLEAR_LEFT;
        else if (strcasestr_portable(val, "right")) st->css_clear = CLEAR_RIGHT;
        else st->css_clear = CLEAR_NONE;
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
        const char* p = val;
        while (*p && st->num_grid_cols < 16) {
            while (*p && isspace((unsigned char)*p)) p++;
            if (!*p) break;
            const char* ts = p;
            int paren = 0;
            while (*p && (paren > 0 || !isspace((unsigned char)*p))) {
                if (*p == '(') paren++;
                else if (*p == ')' && paren > 0) paren--;
                p++;
            }
            char tok[128];
            size_t tlen = (size_t)(p - ts);
            if (tlen >= sizeof(tok)) tlen = sizeof(tok) - 1;
            memcpy(tok, ts, tlen);
            tok[tlen] = '\0';

            if (strncasecmp(tok, "repeat(", 7) == 0) {
                char rinner[128];
                read_paren_arg(tok + 6, rinner, sizeof(rinner));
                int reps = atoi(rinner);
                char* comma = strchr(rinner, ',');
                if (reps > 0 && reps <= 16 && comma) {
                    int min_px = 0, max_spec = -1;
                    parse_grid_track_spec(comma + 1, parent_avail_w, em_px, root_font_px, vw_px, vh_px, mode, &min_px, &max_spec);
                    for (int r = 0; r < reps && st->num_grid_cols < 16; r++) {
                        st->grid_col_min[st->num_grid_cols] = min_px;
                        st->grid_col_widths[st->num_grid_cols] = max_spec;
                        st->num_grid_cols++;
                    }
                }
            } else {
                int min_px = 0, max_spec = -1;
                parse_grid_track_spec(tok, parent_avail_w, em_px, root_font_px, vw_px, vh_px, mode, &min_px, &max_spec);
                st->grid_col_min[st->num_grid_cols] = min_px;
                st->grid_col_widths[st->num_grid_cols] = max_spec;
                st->num_grid_cols++;
            }
        }
    } else if (strcmp(prop, "grid-column") == 0) {
        const char* sp_kw = strcasestr_portable(val, "span");
        if (sp_kw) {
            int sp = atoi(sp_kw + 4);
            st->grid_col_span = (sp > 1) ? sp : 1;
        } else {
            const char* slash = strchr(val, '/');
            if (slash) {
                int start_line = atoi(val);
                int end_line = atoi(slash + 1);
                if (start_line > 0 && end_line > start_line) {
                    st->grid_col_span = end_line - start_line;
                }
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
    } else if (strcmp(prop, "flex-direction") == 0) {
        st->flex_direction = strcasestr_portable(val, "column") ? FLEX_DIR_COLUMN : FLEX_DIR_ROW;
    } else if (strcmp(prop, "flex-wrap") == 0) {
        st->flex_wrap = (strcasestr_portable(val, "wrap") != NULL && strcasestr_portable(val, "nowrap") == NULL);
    } else if (strcmp(prop, "flex-grow") == 0) {
        int fg = atoi(val);
        if (fg >= 0) st->flex_grow = fg;
    } else if (strcmp(prop, "flex-shrink") == 0) {
        int fs = atoi(val);
        if (fs >= 0) st->flex_shrink = fs;
    } else if (strcmp(prop, "flex") == 0) {
        if (strcasecmp(val, "none") == 0) {
            st->flex_grow = 0;
            st->flex_shrink = 0;
        } else if (strcasecmp(val, "auto") == 0) {
            st->flex_grow = 1;
            st->flex_shrink = 1;
        } else {
            char copy[128];
            strncpy(copy, val, sizeof(copy) - 1);
            copy[sizeof(copy) - 1] = '\0';
            char* save = NULL;
            char* t1 = strtok_r(copy, " \t", &save);
            char* t2 = t1 ? strtok_r(NULL, " \t", &save) : NULL;
            char* t3 = t2 ? strtok_r(NULL, " \t", &save) : NULL;
            if (t1 && isdigit((unsigned char)t1[0])) st->flex_grow = atoi(t1);
            if (t2 && isdigit((unsigned char)t2[0])) st->flex_shrink = atoi(t2);
            if (t3) {
                bool is_auto = false;
                int32_t bw = blink_css_eval_length_or_calc(t3, parent_avail_w, em_px, root_font_px, vw_px, vh_px, mode, &is_auto);
                if (!is_auto && bw >= 0) st->width = bw;
            }
        }
    } else if (strcmp(prop, "text-align") == 0) {
        if (strcasestr_portable(val, "center")) st->text_align = ALIGN_CENTER;
        else if (strcasestr_portable(val, "right") || strcasestr_portable(val, "end")) st->text_align = ALIGN_RIGHT;
        else st->text_align = ALIGN_LEFT;
    } else if (strcmp(prop, "opacity") == 0) {
        size_t vl = strlen(val);
        float opf = strtof(val, NULL);
        if (vl > 1 && val[vl - 1] == '%') opf /= 100.0f;
        if (opf < 0.0f) opf = 0.0f;
        if (opf > 1.0f) opf = 1.0f;
        st->opacity_u8 = (int)lroundf(opf * 255.0f);
    } else if (strcmp(prop, "overflow") == 0 || strcmp(prop, "overflow-x") == 0 || strcmp(prop, "overflow-y") == 0) {
        if (strcasestr_portable(val, "hidden") || strcasestr_portable(val, "clip")) {
            st->overflow_hidden = true;
        } else if (strcasestr_portable(val, "visible")) {
            st->overflow_hidden = false;
        }
    } else if (strcmp(prop, "box-shadow") == 0) {
        parse_box_shadow_decl(st, val, em_px, root_font_px, vw_px, vh_px, mode);
    } else if (strcmp(prop, "transform") == 0) {
        parse_transform_decl(st, val, em_px, root_font_px, vw_px, vh_px, mode);
    }
}

static bool rule_matches_environment(const blink_css_rule_t* rule,
                                     const dom_node_t* node,
                                     int32_t vw_px,
                                     int32_t nearest_container_w,
                                     const dom_node_t** out_scope_root) {
    if (out_scope_root) *out_scope_root = NULL;
    if (rule->media_min_w >= 0 && vw_px < rule->media_min_w) return false;
    if (rule->media_max_w >= 0 && vw_px > rule->media_max_w) return false;
    if (rule->container_min_w >= 0 || rule->container_max_w >= 0) {
        if (nearest_container_w < 0) return false;
        if (rule->container_min_w >= 0 && nearest_container_w < rule->container_min_w) return false;
        if (rule->container_max_w >= 0 && nearest_container_w > rule->container_max_w) return false;
    }
    if (rule->has_scope) {
        const blink_complex_sel_t* lim = rule->has_scope_limit ? &rule->scope_limit : NULL;
        if (!blink_css_in_donut_scope(node, &rule->scope_root, lim, out_scope_root)) {
            return false;
        }
    }
    return true;
}

static bool is_strictly_earlier_layer_candidate(const candidate_decl_t* cur, const candidate_decl_t* prev) {
    if (cur->meta.origin == CSS_ORIGIN_INLINE) {
        return prev->meta.origin == CSS_ORIGIN_AUTHOR;
    }
    if (cur->meta.origin == CSS_ORIGIN_AUTHOR && prev->meta.origin == CSS_ORIGIN_AUTHOR) {
        return prev->meta.layer_order != cur->meta.layer_order;
    }
    return false;
}

static void unquote_css_content(const char* raw, char* out, size_t out_cap) {
    out[0] = '\0';
    if (!raw) return;
    while (*raw && isspace((unsigned char)*raw)) raw++;
    if (strcasecmp(raw, "none") == 0 || strcasecmp(raw, "normal") == 0) return;

    size_t j = 0;
    const char* p = raw;
    while (*p && j + 1 < out_cap) {
        while (*p && isspace((unsigned char)*p)) p++;
        if (*p == '"' || *p == '\'') {
            char q = *p++;
            while (*p && *p != q && j + 1 < out_cap) {
                if (*p == '\\' && p[1]) {
                    p++;
                    out[j++] = *p++;
                } else if ((unsigned char)p[0] == 0xC2 && (unsigned char)p[1] == 0xA0) {
                    out[j++] = ' ';
                    p += 2;
                } else {
                    out[j++] = *p++;
                }
            }
            if (*p == q) p++;
        } else {
            break;
        }
    }
    out[j] = '\0';
}

static void materialize_pseudo_element(dom_node_t* host,
                                       blink_pseudo_elem_t which,
                                       const blink_css_stylesheet_t* sheet,
                                       const dom_style_t* initial_st,
                                       int32_t host_content_w,
                                       int32_t nearest_container_w,
                                       int32_t root_font_px,
                                       int32_t vw_px,
                                       int32_t vh_px,
                                       blink_layout_mode_t mode) {
    if (!host || !sheet || blink_html_is_void_tag(host->tag)) return;

    candidate_decl_t pcands[128];
    int n_pcands = 0;

    for (int r = 0; r < sheet->num_rules; r++) {
        const blink_css_rule_t* rule = &sheet->rules[r];
        if (rule->selector.pseudo_elem != which) continue;
        const dom_node_t* scope_root = NULL;
        if (!rule_matches_environment(rule, host, vw_px, nearest_container_w, &scope_root)) continue;
        if (!match_selector_internal(host, &rule->selector, scope_root, true)) continue;

        for (int d = 0; d < rule->num_decls && n_pcands < 128; d++) {
            pcands[n_pcands].decl = rule->decls[d];
            pcands[n_pcands].meta.origin = CSS_ORIGIN_AUTHOR;
            pcands[n_pcands].meta.important = rule->decls[d].important;
            pcands[n_pcands].meta.layer_order = rule->layer_order;
            pcands[n_pcands].meta.specificity = rule->selector.specificity;
            pcands[n_pcands].meta.source_order = rule->source_order + d;
            n_pcands++;
        }
    }

    if (n_pcands == 0) return;
    if (n_pcands > 1) {
        qsort(pcands, (size_t)n_pcands, sizeof(candidate_decl_t), cmp_candidate_decl);
    }

    dom_style_t pst;
    init_initial_style(&pst);
    pst.display = DISPLAY_INLINE;
    pst.color = host->style.color;
    pst.font_size = host->style.font_size;
    pst.font_weight = host->style.font_weight;
    pst.font_style = host->style.font_style;
    strcpy(pst.font_family, host->style.font_family);
    pst.line_height = host->style.line_height;
    pst.text_align = host->style.text_align;
    pst.white_space = host->style.white_space;
    pst.num_custom_props = host->style.num_custom_props;
    for (int i = 0; i < host->style.num_custom_props; i++) {
        pst.custom_props[i] = host->style.custom_props[i];
    }

    bool saw_content = false;
    char content_text[160] = "";

    for (int i = 0; i < n_pcands; i++) {
        const char* prop = pcands[i].decl.prop;
        if (prop[0] == '-' && prop[1] == '-') {
            set_custom_prop(&pst, prop, pcands[i].decl.value);
            continue;
        }
        char resolved_val[192];
        if (!blink_css_resolve_var_value(pst.custom_props, pst.num_custom_props,
                                         pcands[i].decl.value, resolved_val, sizeof(resolved_val))) {
            continue;
        }
        if (strcmp(prop, "content") == 0) {
            saw_content = true;
            unquote_css_content(resolved_val, content_text, sizeof(content_text));
        } else {
            apply_resolved_css_decl(&pst, &host->style, initial_st, prop, resolved_val,
                                    host_content_w, root_font_px, vw_px, vh_px, mode);
        }
    }

    if (!saw_content || pst.display == DISPLAY_NONE || !content_text[0]) return;

    dom_node_t* syn = dom_node_create("span");
    syn->is_generated_pseudo = true;
    syn->style = pst;
    dom_node_t* tn = dom_node_create("#text");
    tn->is_generated_pseudo = true;
    tn->text = strdup(content_text);
    tn->style = pst;
    tn->style.display = DISPLAY_INLINE;
    tn->style.has_bg = false;
    tn->style.border_width = 0;
    tn->style.padding_left = tn->style.padding_right = tn->style.padding_top = tn->style.padding_bottom = 0;
    dom_node_add_child(syn, tn);

    if (which == PSEUDO_ELEM_BEFORE) {
        dom_node_insert_child_first(host, syn);
    } else {
        dom_node_add_child(host, syn);
    }
}

static void remove_existing_generated_pseudos(dom_node_t* node) {
    if (!node) return;
    int write_idx = 0;
    for (int i = 0; i < node->num_children; i++) {
        if (node->children[i] && node->children[i]->is_generated_pseudo) {
            dom_node_free(node->children[i]);
        } else {
            node->children[write_idx++] = node->children[i];
        }
    }
    node->num_children = write_idx;
}

static void resolve_node_recursive(dom_node_t* node,
                                   const blink_css_stylesheet_t* sheet,
                                   const dom_style_t* initial_st,
                                   int32_t parent_avail_w,
                                   int32_t nearest_container_w,
                                   int32_t root_font_px,
                                   int32_t vw_px,
                                   int32_t vh_px,
                                   blink_layout_mode_t mode) {
    if (!node || node->is_generated_pseudo) return;

    remove_existing_generated_pseudos(node);

    const dom_style_t* parent_st = node->parent ? &node->parent->style : NULL;

    /* Text nodes purely inherit parent's computed typographic, decoration & color properties */
    if (strcmp(node->tag, "#text") == 0) {
        if (parent_st) {
            node->style.color = parent_st->color;
            node->style.font_size = parent_st->font_size;
            node->style.font_weight = parent_st->font_weight;
            node->style.font_style = parent_st->font_style;
            strcpy(node->style.font_family, parent_st->font_family);
            node->style.line_height = parent_st->line_height;
            node->style.text_align = parent_st->text_align;
            node->style.text_underline = parent_st->text_underline;
            node->style.text_line_through = parent_st->text_line_through;
            node->style.vertical_align = parent_st->vertical_align;
            node->style.white_space = parent_st->white_space;
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
        if (strcmp(node->tag, "pre") != 0) node->style.white_space = parent_st->white_space;
        if (strcmp(node->tag, "table") != 0) node->style.border_collapse = parent_st->border_collapse;
        if (parent_st->text_underline) node->style.text_underline = true;
        if (parent_st->text_line_through) node->style.text_line_through = true;
        if (parent_st->vertical_align != VALIGN_BASELINE && node->ua_style.vertical_align == VALIGN_BASELINE) {
            node->style.vertical_align = parent_st->vertical_align;
        }

        node->style.num_custom_props = parent_st->num_custom_props;
        for (int i = 0; i < parent_st->num_custom_props; i++) {
            node->style.custom_props[i] = parent_st->custom_props[i];
        }
    }

    /* Snapshot exact UA + Inherited style for CSS Cascade `revert` & `revert-layer`! */
    dom_style_t base_ua_inherited = node->style;

    /* 2. Gather matching Author & Inline declarations */
    candidate_decl_t cands[512];
    int num_cands = 0;

    if (sheet) {
        for (int r = 0; r < sheet->num_rules; r++) {
            const blink_css_rule_t* rule = &sheet->rules[r];
            if (rule->selector.pseudo_elem != PSEUDO_ELEM_NONE) continue;
            const dom_node_t* scope_root = NULL;
            if (!rule_matches_environment(rule, node, vw_px, nearest_container_w, &scope_root)) continue;
            if (!match_selector_internal(node, &rule->selector, scope_root, false)) continue;

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

    /* 5. Pass B: Apply font-size first, then all standard properties with cycle-safe `var()`,
       `revert` (`revert_author_restores_ua`), and `revert-layer` (`revert_layer_selects_strictly_earlier_layer`)! */
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

            if (strcasecmp(resolved_val, "revert") == 0) {
                apply_keyword_reset(&node->style, &base_ua_inherited, prop);
                continue;
            }
            if (strcasecmp(resolved_val, "revert-layer") == 0) {
                apply_keyword_reset(&node->style, &base_ua_inherited, prop);
                for (int j = 0; j < i; j++) {
                    if (strcmp(cands[j].decl.prop, prop) != 0) continue;
                    if (!is_strictly_earlier_layer_candidate(&cands[i], &cands[j])) continue;
                    char prev_val[192];
                    if (blink_css_resolve_var_value(node->style.custom_props,
                                                    node->style.num_custom_props,
                                                    cands[j].decl.value,
                                                    prev_val,
                                                    sizeof(prev_val)) &&
                        strcasecmp(prev_val, "revert") != 0 &&
                        strcasecmp(prev_val, "revert-layer") != 0) {
                        apply_resolved_css_decl(&node->style, parent_st, initial_st,
                                                prop, prev_val,
                                                parent_avail_w, root_font_px, vw_px, vh_px, mode);
                    }
                }
                continue;
            }

            apply_resolved_css_decl(&node->style, parent_st, initial_st,
                                    prop, resolved_val,
                                    parent_avail_w, root_font_px, vw_px, vh_px, mode);
        }
    }

    if (!node->parent) {
        root_font_px = (int32_t)lroundf(node->style.font_size);
    }

    /* Compute available inline width passed to child `%` & `@container` resolutions */
    int32_t child_avail = parent_avail_w - node->style.margin_left - node->style.margin_right;
    if (node->style.width >= 0) {
        child_avail = blink_css_resolve_content_inline_size(
            node->style.box_sizing,
            node->style.width,
            node->style.padding_left + node->style.padding_right,
            node->style.border_width * 2);
    } else {
        child_avail -= (node->style.padding_left + node->style.padding_right + node->style.border_width * 2);
    }
    if (node->style.max_width >= 0 && child_avail > node->style.max_width) {
        child_avail = node->style.max_width;
    }
    if (child_avail < node->style.min_width) {
        child_avail = node->style.min_width;
    }
    if (child_avail < 0) child_avail = 0;

    int32_t child_container_w = node->style.is_inline_size_container ? child_avail : nearest_container_w;

    for (int i = 0; i < node->num_children; i++) {
        resolve_node_recursive(node->children[i], sheet, initial_st,
                               child_avail, child_container_w, root_font_px, vw_px, vh_px, mode);
    }

    /* Materialize synthetic `::before` and `::after` inline spans after resolving real children! */
    materialize_pseudo_element(node, PSEUDO_ELEM_BEFORE, sheet, initial_st,
                               child_avail, nearest_container_w, root_font_px, vw_px, vh_px, mode);
    materialize_pseudo_element(node, PSEUDO_ELEM_AFTER, sheet, initial_st,
                               child_avail, nearest_container_w, root_font_px, vw_px, vh_px, mode);
}

static void assign_dom_order_preorder(dom_node_t* n, int* io_ord) {
    if (!n) return;
    n->dom_order = (*io_ord)++;
    for (int i = 0; i < n->num_children; i++) {
        assign_dom_order_preorder(n->children[i], io_ord);
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
    resolve_node_recursive(root, sheet, &initial_st, viewport_w - 32, -1, root_font_px, viewport_w, viewport_h, mode);
    int ord = 0;
    assign_dom_order_preorder(root, &ord);
}

/* ------------------------------------------------------------------------- */
/* 9. HTML Entity Unescaping & Full WHATWG HTML5 Document Parser (Pillar 1)  */
/* ------------------------------------------------------------------------- */

static size_t encode_utf8_scalar(int32_t cp, char* out) {
    cp = blink_html_sanitize_char_ref(cp);
    if (cp == 0x00A0) {
        out[0] = ' ';
        return 1;
    }
    if (cp < 0x80) {
        out[0] = (char)cp;
        return 1;
    }
    if (cp < 0x800) {
        out[0] = (char)(0xC0 | ((cp >> 6) & 0x1F));
        out[1] = (char)(0x80 | (cp & 0x3F));
        return 2;
    }
    if (cp < 0x10000) {
        out[0] = (char)(0xE0 | ((cp >> 12) & 0x0F));
        out[1] = (char)(0x80 | ((cp >> 6) & 0x3F));
        out[2] = (char)(0x80 | (cp & 0x3F));
        return 3;
    }
    out[0] = (char)(0xF0 | ((cp >> 18) & 0x07));
    out[1] = (char)(0x80 | ((cp >> 12) & 0x3F));
    out[2] = (char)(0x80 | ((cp >> 6) & 0x3F));
    out[3] = (char)(0x80 | (cp & 0x3F));
    return 4;
}

char* blink_unescape_html(const char* src) {
    if (!src) return NULL;
    size_t len = strlen(src);
    /* Worst-case expansion (e.g. `&#0;` -> 3-byte UTF-8 U+FFFD) fits in 4 * len + 4 */
    char* dst = (char*)malloc(len * 4 + 4);
    if (!dst) return NULL;

    static const struct {
        const char* ent;
        size_t      elen;
        int32_t     cp;
    } named_ents[] = {
        {"&amp;",    5, 0x0026},
        {"&lt;",     4, 0x003C},
        {"&gt;",     4, 0x003E},
        {"&quot;",   6, 0x0022},
        {"&apos;",   6, 0x0027},
        {"&nbsp;",   6, 0x00A0},
        {"&sect;",   6, 0x00A7},
        {"&copy;",   6, 0x00A9},
        {"&laquo;",  7, 0x00AB},
        {"&reg;",    5, 0x00AE},
        {"&deg;",    5, 0x00B0},
        {"&plusmn;", 8, 0x00B1},
        {"&raquo;",  7, 0x00BB},
        {"&times;",  7, 0x00D7},
        {"&divide;", 8, 0x00F7},
        {"&ndash;",  7, 0x2013},
        {"&mdash;",  7, 0x2014},
        {"&bull;",   6, 0x2022},
        {"&hellip;", 8, 0x2026},
        {"&larr;",   6, 0x2190},
        {"&rarr;",   6, 0x2192},
        {"&ne;",     4, 0x2260},
        {"&le;",     4, 0x2264},
        {"&ge;",     4, 0x2265}
    };

    size_t i = 0, j = 0;
    while (i < len) {
        if (src[i] == '&') {
            /* 1. Numeric Character Reference: `&#NNN;` or `&#xHHH;` / `&#XHHH;` */
            if (src[i + 1] == '#') {
                size_t k = i + 2;
                bool is_hex = false;
                if (src[k] == 'x' || src[k] == 'X') {
                    is_hex = true;
                    k++;
                }
                size_t dig_start = k;
                int64_t acc = 0;
                if (is_hex) {
                    while (k < len && isxdigit((unsigned char)src[k])) {
                        int d = isdigit((unsigned char)src[k])
                                    ? (src[k] - '0')
                                    : (tolower((unsigned char)src[k]) - 'a' + 10);
                        if (acc <= 0x200000) acc = (acc << 4) + d;
                        k++;
                    }
                } else {
                    while (k < len && isdigit((unsigned char)src[k])) {
                        if (acc <= 0x200000) acc = acc * 10 + (src[k] - '0');
                        k++;
                    }
                }
                if (k > dig_start) {
                    if (k < len && src[k] == ';') k++;
                    int32_t sanitized = blink_html_sanitize_char_ref((int32_t)acc);
                    j += encode_utf8_scalar(sanitized, dst + j);
                    i = k;
                    continue;
                }
            }

            /* 2. Named HTML5 Character References */
            bool matched_named = false;
            for (size_t e = 0; e < sizeof(named_ents) / sizeof(named_ents[0]); e++) {
                if (strncmp(src + i, named_ents[e].ent, named_ents[e].elen) == 0) {
                    j += encode_utf8_scalar(named_ents[e].cp, dst + j);
                    i += named_ents[e].elen;
                    matched_named = true;
                    break;
                }
            }
            if (matched_named) continue;

            dst[j++] = src[i++];
        } else if ((unsigned char)src[i] == 0xC2 && (unsigned char)src[i + 1] == 0xA0) {
            dst[j++] = ' ';
            i += 2;
        } else if ((unsigned char)src[i] == 0xE2 && (unsigned char)src[i + 1] == 0x80) {
            unsigned char b2 = (unsigned char)src[i + 2];
            if (b2 == 0x98 || b2 == 0x99) { dst[j++] = '\''; i += 3; }
            else if (b2 == 0x9C || b2 == 0x9D) { dst[j++] = '"'; i += 3; }
            else {
                dst[j++] = src[i++];
                dst[j++] = src[i++];
                dst[j++] = src[i++];
            }
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

/* ------------------------------------------------------------------------- */
/* WHATWG Active Formatting Elements (AFE), Noah's Ark & Adoption Agency     */
/* ------------------------------------------------------------------------- */

static bool is_html5_formatting_tag(const char* tag) {
    if (!tag) return false;
    static const char* const fmts[] = {
        "a", "b", "big", "code", "em", "font", "i", "nobr",
        "s", "small", "strike", "strong", "tt", "u", "mark", "del", "ins", "sub", "sup"
    };
    for (size_t i = 0; i < sizeof(fmts) / sizeof(fmts[0]); i++) {
        if (strcmp(tag, fmts[i]) == 0) return true;
    }
    return false;
}

static bool is_html5_special_block_tag(const char* tag) {
    if (!tag || is_html5_formatting_tag(tag)) return false;
    if (strcmp(tag, "span") == 0 || strcmp(tag, "abbr") == 0 || strcmp(tag, "cite") == 0 ||
        strcmp(tag, "dfn") == 0 || strcmp(tag, "q") == 0 || strcmp(tag, "time") == 0 ||
        strcmp(tag, "kbd") == 0 || strcmp(tag, "samp") == 0 || strcmp(tag, "var") == 0) {
        return false;
    }
    return true;
}

static bool is_foster_table_context_tag(const char* tag) {
    if (!tag) return false;
    return (strcmp(tag, "table") == 0 || strcmp(tag, "thead") == 0 ||
            strcmp(tag, "tbody") == 0 || strcmp(tag, "tfoot") == 0 ||
            strcmp(tag, "tr") == 0);
}

static bool is_afe_marker_tag(const char* tag) {
    if (!tag) return false;
    return (strcmp(tag, "table") == 0 || strcmp(tag, "td") == 0 ||
            strcmp(tag, "th") == 0 || strcmp(tag, "caption") == 0);
}

#define BLINK_MAX_AFE_ENTRIES 128
#define BLINK_MAX_OPEN_STACK  256

typedef struct {
    bool             is_marker;
    dom_node_t*      node;
    char             tag[32];
    char             id[64];
    char             class_name[128];
    char             href[256];
    char             inline_style_raw[256];
    blink_dom_attr_t attrs[BLINK_MAX_ATTRS];
    int              num_attrs;
} afe_entry_t;

typedef struct {
    afe_entry_t entries[BLINK_MAX_AFE_ENTRIES];
    int         count;
} afe_list_t;

static void afe_snapshot_node(afe_entry_t* e, dom_node_t* n) {
    memset(e, 0, sizeof(*e));
    e->is_marker = false;
    e->node = n;
    strncpy(e->tag, n->tag, sizeof(e->tag) - 1);
    if (n->id) strncpy(e->id, n->id, sizeof(e->id) - 1);
    if (n->class_name) strncpy(e->class_name, n->class_name, sizeof(e->class_name) - 1);
    if (n->href) strncpy(e->href, n->href, sizeof(e->href) - 1);
    if (n->inline_style_raw) strncpy(e->inline_style_raw, n->inline_style_raw, sizeof(e->inline_style_raw) - 1);
    e->num_attrs = n->num_attrs;
    for (int i = 0; i < n->num_attrs && i < BLINK_MAX_ATTRS; i++) {
        e->attrs[i] = n->attrs[i];
    }
}

static dom_node_t* afe_clone_entry(const afe_entry_t* e) {
    dom_node_t* c = dom_node_create(e->tag);
    if (!c) return NULL;
    if (e->id[0]) c->id = strdup(e->id);
    if (e->class_name[0]) c->class_name = strdup(e->class_name);
    if (e->href[0]) c->href = strdup(e->href);
    if (e->inline_style_raw[0]) c->inline_style_raw = strdup(e->inline_style_raw);
    c->num_attrs = e->num_attrs;
    for (int i = 0; i < e->num_attrs && i < BLINK_MAX_ATTRS; i++) {
        c->attrs[i] = e->attrs[i];
    }
    return c;
}

static bool afe_same_signature(const afe_entry_t* a, const afe_entry_t* b) {
    if (a->is_marker || b->is_marker) return false;
    if (strcmp(a->tag, b->tag) != 0) return false;
    if (strcmp(a->class_name, b->class_name) != 0) return false;
    if (strcmp(a->inline_style_raw, b->inline_style_raw) != 0) return false;
    if (strcmp(a->href, b->href) != 0) return false;
    if (a->num_attrs != b->num_attrs) return false;
    return true;
}

static void afe_remove_at(afe_list_t* afe, int idx) {
    if (idx < 0 || idx >= afe->count) return;
    for (int i = idx; i + 1 < afe->count; i++) {
        afe->entries[i] = afe->entries[i + 1];
    }
    afe->count--;
}

static void afe_push_marker(afe_list_t* afe) {
    if (afe->count >= BLINK_MAX_AFE_ENTRIES) return;
    memset(&afe->entries[afe->count], 0, sizeof(afe_entry_t));
    afe->entries[afe->count].is_marker = true;
    afe->count++;
}

static void afe_clear_to_last_marker(afe_list_t* afe) {
    while (afe->count > 0) {
        bool was_m = afe->entries[afe->count - 1].is_marker;
        afe->count--;
        if (was_m) break;
    }
}

/* Noah's Ark Clause (`noahs_ark_preserves_cap_3`): at most 3 identical active formatting signatures */
static void afe_push_formatting(afe_list_t* afe, dom_node_t* node) {
    afe_entry_t cand;
    afe_snapshot_node(&cand, node);

    int matches = 0;
    int oldest_idx = -1;
    for (int i = afe->count - 1; i >= 0; i--) {
        if (afe->entries[i].is_marker) break;
        if (afe_same_signature(&afe->entries[i], &cand)) {
            matches++;
            oldest_idx = i;
        }
    }
    if (matches >= 3 && oldest_idx >= 0) {
        afe_remove_at(afe, oldest_idx);
    }
    if (afe->count < BLINK_MAX_AFE_ENTRIES) {
        afe->entries[afe->count++] = cand;
    }
}

static int open_stack_find_node(dom_node_t** stack, int stack_len, const dom_node_t* target) {
    for (int i = stack_len - 1; i >= 0; i--) {
        if (stack[i] == target) return i;
    }
    return -1;
}

static dom_node_t* open_stack_find_enclosing_table(dom_node_t** stack, int stack_len) {
    for (int i = stack_len - 1; i >= 0; i--) {
        if (strcmp(stack[i]->tag, "table") == 0) return stack[i];
    }
    return NULL;
}

static void open_stack_pop_to_len(dom_node_t** stack, int* io_len, int target_len, afe_list_t* afe) {
    if (target_len < 1) target_len = 1;
    while (*io_len > target_len) {
        dom_node_t* popped = stack[--(*io_len)];
        if (afe && is_afe_marker_tag(popped->tag)) {
            afe_clear_to_last_marker(afe);
        }
    }
}

static void open_stack_push(dom_node_t** stack, int* io_len, dom_node_t* n) {
    if (*io_len < BLINK_MAX_OPEN_STACK) {
        stack[(*io_len)++] = n;
    }
}

static void html5_insert_node_appropriate_place(dom_node_t** stack, int stack_len, dom_node_t* child) {
    dom_node_t* cur = stack[stack_len - 1];
    if (is_foster_table_context_tag(cur->tag)) {
        dom_node_t* tbl = open_stack_find_enclosing_table(stack, stack_len);
        if (tbl && tbl->parent) {
            dom_node_insert_before(tbl->parent, tbl, child);
            return;
        }
    }
    dom_node_add_child(cur, child);
}

static void html5_reconstruct_active_formatting(afe_list_t* afe, dom_node_t** stack, int* io_stack_len) {
    if (afe->count == 0) return;
    dom_node_t* cur_top = stack[*io_stack_len - 1];
    if (is_foster_table_context_tag(cur_top->tag)) return;

    int entry_idx = afe->count - 1;
    if (afe->entries[entry_idx].is_marker ||
        open_stack_find_node(stack, *io_stack_len, afe->entries[entry_idx].node) >= 0) {
        return;
    }

    while (entry_idx > 0) {
        int prev = entry_idx - 1;
        if (afe->entries[prev].is_marker ||
            open_stack_find_node(stack, *io_stack_len, afe->entries[prev].node) >= 0) {
            break;
        }
        entry_idx = prev;
    }

    while (entry_idx < afe->count) {
        dom_node_t* cloned = afe_clone_entry(&afe->entries[entry_idx]);
        if (!cloned) break;
        html5_insert_node_appropriate_place(stack, *io_stack_len, cloned);
        open_stack_push(stack, io_stack_len, cloned);
        afe->entries[entry_idx].node = cloned;
        entry_idx++;
    }
}

static void html5_stack_pop_until_in_scope(dom_node_t** stack,
                                           int* io_len,
                                           const char* close_tag,
                                           afe_list_t* afe) {
    if (*io_len <= 1 || !close_tag || !close_tag[0]) return;
    bool closing_table_struct =
        (strcmp(close_tag, "td") == 0 || strcmp(close_tag, "th") == 0 ||
         strcmp(close_tag, "tr") == 0 || strcmp(close_tag, "thead") == 0 ||
         strcmp(close_tag, "tbody") == 0 || strcmp(close_tag, "tfoot") == 0 ||
         strcmp(close_tag, "caption") == 0 || strcmp(close_tag, "table") == 0);

    for (int i = *io_len - 1; i >= 1; i--) {
        if (strcmp(stack[i]->tag, close_tag) == 0) {
            open_stack_pop_to_len(stack, io_len, i, afe);
            return;
        }
        if (!closing_table_struct && blink_html_is_scope_boundary(stack[i]->tag)) {
            return;
        }
        if (closing_table_struct && strcmp(close_tag, "table") != 0 && strcmp(stack[i]->tag, "table") == 0) {
            return;
        }
    }
}

/* WHATWG §13.2.6.4.7 Adoption Agency Algorithm (`outer < 8`, `inner < 3`) */
static void html5_run_adoption_agency(const char* subject_tag,
                                      dom_node_t** stack,
                                      int* io_stack_len,
                                      afe_list_t* afe) {
    dom_node_t* cur = stack[*io_stack_len - 1];
    if (strcmp(cur->tag, subject_tag) == 0) {
        bool in_afe = false;
        for (int i = afe->count - 1; i >= 0 && !afe->entries[i].is_marker; i--) {
            if (afe->entries[i].node == cur) { in_afe = true; break; }
        }
        if (!in_afe) {
            open_stack_pop_to_len(stack, io_stack_len, *io_stack_len - 1, afe);
            return;
        }
    }

    for (int outer = 0; outer < 8; outer++) {
        int afe_fe_idx = -1;
        for (int i = afe->count - 1; i >= 0; i--) {
            if (afe->entries[i].is_marker) break;
            if (strcmp(afe->entries[i].tag, subject_tag) == 0) {
                afe_fe_idx = i;
                break;
            }
        }
        if (afe_fe_idx < 0) {
            for (int i = *io_stack_len - 1; i >= 1; i--) {
                if (strcmp(stack[i]->tag, subject_tag) == 0) {
                    open_stack_pop_to_len(stack, io_stack_len, i, afe);
                    return;
                }
                if (is_html5_special_block_tag(stack[i]->tag)) return;
            }
            return;
        }

        dom_node_t* fe = afe->entries[afe_fe_idx].node;
        int stack_fe_idx = open_stack_find_node(stack, *io_stack_len, fe);
        if (stack_fe_idx < 0) {
            afe_remove_at(afe, afe_fe_idx);
            return;
        }

        for (int i = *io_stack_len - 1; i > stack_fe_idx; i--) {
            if (blink_html_is_scope_boundary(stack[i]->tag)) {
                return;
            }
        }

        int stack_fb_idx = -1;
        for (int i = stack_fe_idx + 1; i < *io_stack_len; i++) {
            if (is_html5_special_block_tag(stack[i]->tag)) {
                stack_fb_idx = i;
                break;
            }
        }

        if (stack_fb_idx < 0) {
            open_stack_pop_to_len(stack, io_stack_len, stack_fe_idx, afe);
            afe_remove_at(afe, afe_fe_idx);
            return;
        }

        dom_node_t* furthest_block = stack[stack_fb_idx];
        dom_node_t* common_ancestor = (stack_fe_idx > 0) ? stack[stack_fe_idx - 1] : stack[0];

        int inner_steps = 0;
        for (int s = stack_fb_idx - 1; s > stack_fe_idx && inner_steps < 3; s--, inner_steps++) {
            dom_node_t* mid = stack[s];
            int mid_afe = -1;
            for (int k = afe->count - 1; k >= 0 && !afe->entries[k].is_marker; k--) {
                if (afe->entries[k].node == mid) { mid_afe = k; break; }
            }
            if (mid_afe >= 0) {
                dom_node_t* mid_clone = afe_clone_entry(&afe->entries[mid_afe]);
                if (mid_clone) {
                    dom_node_detach_from_parent(furthest_block);
                    while (furthest_block->num_children > 0) {
                        dom_node_t* ch = furthest_block->children[0];
                        dom_node_detach_from_parent(ch);
                        dom_node_add_child(mid_clone, ch);
                    }
                    dom_node_add_child(furthest_block, mid_clone);
                }
            }
        }

        dom_node_detach_from_parent(furthest_block);
        dom_node_t* fe_clone = afe_clone_entry(&afe->entries[afe_fe_idx]);
        if (fe_clone) {
            while (furthest_block->num_children > 0) {
                dom_node_t* ch = furthest_block->children[0];
                dom_node_detach_from_parent(ch);
                dom_node_add_child(fe_clone, ch);
            }
            dom_node_add_child(furthest_block, fe_clone);
        }

        if (is_foster_table_context_tag(common_ancestor->tag)) {
            dom_node_t* tbl = open_stack_find_enclosing_table(stack, stack_fe_idx);
            if (tbl && tbl->parent) {
                dom_node_insert_before(tbl->parent, tbl, furthest_block);
            } else {
                dom_node_add_child(common_ancestor, furthest_block);
            }
        } else {
            dom_node_add_child(common_ancestor, furthest_block);
        }

        afe_remove_at(afe, afe_fe_idx);
        stack[stack_fe_idx] = furthest_block;
        *io_stack_len = stack_fe_idx + 1;
        return;
    }
}

static void html5_stack_close_implicit_before_start(dom_node_t** stack,
                                                    int* io_len,
                                                    const char* new_tag,
                                                    afe_list_t* afe) {
    if (*io_len <= 1 || !new_tag) return;

    if (closes_open_p_tag(new_tag)) {
        html5_stack_pop_until_in_scope(stack, io_len, "p", afe);
    }

    if (strcmp(new_tag, "li") == 0) {
        for (int i = *io_len - 1; i >= 1; i--) {
            if (strcmp(stack[i]->tag, "li") == 0) {
                open_stack_pop_to_len(stack, io_len, i, afe);
                break;
            }
            if (strcmp(stack[i]->tag, "ul") == 0 || strcmp(stack[i]->tag, "ol") == 0 ||
                strcmp(stack[i]->tag, "menu") == 0 || blink_html_is_scope_boundary(stack[i]->tag)) {
                break;
            }
        }
    } else if (strcmp(new_tag, "dt") == 0 || strcmp(new_tag, "dd") == 0) {
        for (int i = *io_len - 1; i >= 1; i--) {
            if (strcmp(stack[i]->tag, "dt") == 0 || strcmp(stack[i]->tag, "dd") == 0) {
                open_stack_pop_to_len(stack, io_len, i, afe);
                break;
            }
            if (strcmp(stack[i]->tag, "dl") == 0 || blink_html_is_scope_boundary(stack[i]->tag)) {
                break;
            }
        }
    } else if (is_heading_tag(new_tag) && *io_len > 1 && is_heading_tag(stack[*io_len - 1]->tag)) {
        open_stack_pop_to_len(stack, io_len, *io_len - 1, afe);
    } else if (strcmp(new_tag, "td") == 0 || strcmp(new_tag, "th") == 0) {
        for (int i = *io_len - 1; i >= 1; i--) {
            if (strcmp(stack[i]->tag, "td") == 0 || strcmp(stack[i]->tag, "th") == 0) {
                open_stack_pop_to_len(stack, io_len, i, afe);
                break;
            }
            if (strcmp(stack[i]->tag, "tr") == 0 || strcmp(stack[i]->tag, "table") == 0) break;
        }
    } else if (strcmp(new_tag, "tr") == 0) {
        for (int i = *io_len - 1; i >= 1; i--) {
            if (strcmp(stack[i]->tag, "td") == 0 || strcmp(stack[i]->tag, "th") == 0) {
                open_stack_pop_to_len(stack, io_len, i, afe);
                break;
            }
            if (strcmp(stack[i]->tag, "tr") == 0 || strcmp(stack[i]->tag, "table") == 0) break;
        }
        for (int i = *io_len - 1; i >= 1; i--) {
            if (strcmp(stack[i]->tag, "tr") == 0) {
                open_stack_pop_to_len(stack, io_len, i, afe);
                break;
            }
            if (strcmp(stack[i]->tag, "thead") == 0 || strcmp(stack[i]->tag, "tbody") == 0 ||
                strcmp(stack[i]->tag, "tfoot") == 0 || strcmp(stack[i]->tag, "table") == 0) {
                break;
            }
        }
    } else if (strcmp(new_tag, "thead") == 0 || strcmp(new_tag, "tbody") == 0 || strcmp(new_tag, "tfoot") == 0 ||
               strcmp(new_tag, "caption") == 0 || strcmp(new_tag, "colgroup") == 0) {
        for (int i = *io_len - 1; i >= 1; i--) {
            if (strcmp(stack[i]->tag, "td") == 0 || strcmp(stack[i]->tag, "th") == 0) {
                open_stack_pop_to_len(stack, io_len, i, afe);
                break;
            }
            if (strcmp(stack[i]->tag, "table") == 0) break;
        }
        for (int i = *io_len - 1; i >= 1; i--) {
            if (strcmp(stack[i]->tag, "tr") == 0) {
                open_stack_pop_to_len(stack, io_len, i, afe);
                break;
            }
            if (strcmp(stack[i]->tag, "table") == 0) break;
        }
        for (int i = *io_len - 1; i >= 1; i--) {
            if (strcmp(stack[i]->tag, "thead") == 0 || strcmp(stack[i]->tag, "tbody") == 0 ||
                strcmp(stack[i]->tag, "tfoot") == 0 || strcmp(stack[i]->tag, "caption") == 0 ||
                strcmp(stack[i]->tag, "colgroup") == 0) {
                open_stack_pop_to_len(stack, io_len, i, afe);
                break;
            }
            if (strcmp(stack[i]->tag, "table") == 0) break;
        }
    }
}

static void html5_recover_table_structure_before_start(dom_node_t** stack, int* io_len, const char* tag) {
    dom_node_t* cur = stack[*io_len - 1];
    if (strcmp(tag, "tr") == 0 && strcmp(cur->tag, "table") == 0) {
        dom_node_t* tbody = dom_node_create("tbody");
        dom_node_add_child(cur, tbody);
        open_stack_push(stack, io_len, tbody);
    } else if (strcmp(tag, "td") == 0 || strcmp(tag, "th") == 0) {
        if (strcmp(cur->tag, "table") == 0) {
            dom_node_t* tbody = dom_node_create("tbody");
            dom_node_add_child(cur, tbody);
            open_stack_push(stack, io_len, tbody);
            cur = tbody;
        }
        if (strcmp(cur->tag, "tbody") == 0 || strcmp(cur->tag, "thead") == 0 || strcmp(cur->tag, "tfoot") == 0) {
            dom_node_t* tr = dom_node_create("tr");
            dom_node_add_child(cur, tr);
            open_stack_push(stack, io_len, tr);
        }
    }
}

static bool is_valid_direct_table_child(const char* parent_tag, const char* child_tag) {
    if (strcmp(parent_tag, "table") == 0) {
        return (strcmp(child_tag, "caption") == 0 || strcmp(child_tag, "colgroup") == 0 ||
                strcmp(child_tag, "col") == 0 || strcmp(child_tag, "thead") == 0 ||
                strcmp(child_tag, "tbody") == 0 || strcmp(child_tag, "tfoot") == 0 ||
                strcmp(child_tag, "tr") == 0);
    }
    if (strcmp(parent_tag, "thead") == 0 || strcmp(parent_tag, "tbody") == 0 || strcmp(parent_tag, "tfoot") == 0) {
        return (strcmp(child_tag, "tr") == 0);
    }
    if (strcmp(parent_tag, "tr") == 0) {
        return (strcmp(child_tag, "td") == 0 || strcmp(child_tag, "th") == 0);
    }
    return true;
}

static bool is_inside_pre_on_stack(dom_node_t** stack, int stack_len) {
    for (int i = stack_len - 1; i >= 0; i--) {
        if (strcmp(stack[i]->tag, "pre") == 0) return true;
    }
    return false;
}

dom_node_t* blink_parse_html5_document_ex(const char* html,
                                          const char* base_dir,
                                          blink_css_stylesheet_t* out_sheet) {
    if (!html) return NULL;
    if (out_sheet) blink_css_stylesheet_init(out_sheet);
    const char* eff_base = (base_dir && base_dir[0]) ? base_dir : ".";

    (void)html5_close_implicit_before_start;

    dom_node_t* root = dom_node_create("body");
    dom_node_t* open_stack[BLINK_MAX_OPEN_STACK];
    int open_len = 0;
    open_stack[open_len++] = root;

    afe_list_t afe;
    memset(&afe, 0, sizeof(afe));

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
        dom_node_t* current = open_stack[open_len - 1];
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
                if (is_html5_formatting_tag(close_tag)) {
                    html5_run_adoption_agency(close_tag, open_stack, &open_len, &afe);
                } else {
                    html5_stack_pop_until_in_scope(open_stack, &open_len, close_tag, &afe);
                }
                continue;
            }

            /* Opening Tag: <tag attr="val" ...> */
            p++;
            if (!isalpha((unsigned char)*p)) {
                /* Stray '<' in text */
                html5_reconstruct_active_formatting(&afe, open_stack, &open_len);
                dom_node_t* tn = dom_node_create("#text");
                tn->text = strdup("<");
                html5_insert_node_appropriate_place(open_stack, open_len, tn);
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
                        blink_css_parse_stylesheet_ex(out_sheet, css_buf, eff_base);
                        free(css_buf);
                    }
                }
                p = css_end ? (css_end + 8) : (p + clen);
                continue;
            }

            /* Parse external <link rel="stylesheet" href="..."> in <head> or <body>! */
            if (strcmp(tag, "link") == 0) {
                char link_rel[128] = "";
                char link_href[512] = "";
                while (*p && *p != '>') {
                    while (*p && isspace((unsigned char)*p)) p++;
                    if (*p == '/' && p[1] == '>') { p++; break; }
                    if (*p == '>') break;
                    char attr_k[64];
                    int ki = 0;
                    while (*p && *p != '=' && *p != '>' && *p != '/' && !isspace((unsigned char)*p) && ki < 63) {
                        attr_k[ki++] = (char)tolower((unsigned char)*p++);
                    }
                    attr_k[ki] = '\0';
                    while (*p && isspace((unsigned char)*p)) p++;
                    char attr_v[512];
                    attr_v[0] = '\0';
                    if (*p == '=') {
                        p++;
                        while (*p && isspace((unsigned char)*p)) p++;
                        char quote = 0;
                        if (*p == '"' || *p == '\'') quote = *p++;
                        int vi = 0;
                        while (*p && vi < 511) {
                            if (quote && *p == quote) { p++; break; }
                            if (!quote && (*p == '>' || isspace((unsigned char)*p))) break;
                            attr_v[vi++] = *p++;
                        }
                        attr_v[vi] = '\0';
                    }
                    if (strcmp(attr_k, "rel") == 0) {
                        strncpy(link_rel, attr_v, sizeof(link_rel) - 1);
                    } else if (strcmp(attr_k, "href") == 0) {
                        strncpy(link_href, attr_v, sizeof(link_href) - 1);
                    }
                    if (!attr_k[0] && *p && *p != '>') p++;
                }
                if (*p == '>') p++;
                if (out_sheet && link_href[0] && strcasestr_portable(link_rel, "stylesheet") != NULL) {
                    char link_dir[512];
                    char* link_css = load_local_stylesheet_file(eff_base, link_href, link_dir, sizeof(link_dir));
                    if (link_css) {
                        blink_css_parse_stylesheet_ex(out_sheet, link_css, link_dir);
                        free(link_css);
                    }
                }
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
                /* Skip other head metadata tags (<meta>, <base>) */
                while (*p && *p != '>') p++;
                if (*p == '>') p++;
                continue;
            }

            /* Perform WHATWG HTML5 implicit end-tag closure, table recovery & AFE reconstruction! */
            if (!is_doc_wrapper) {
                html5_stack_close_implicit_before_start(open_stack, &open_len, tag, &afe);
                html5_recover_table_structure_before_start(open_stack, &open_len, tag);
                current = open_stack[open_len - 1];
                if (is_html5_formatting_tag(tag) || !is_html5_special_block_tag(tag)) {
                    html5_reconstruct_active_formatting(&afe, open_stack, &open_len);
                    current = open_stack[open_len - 1];
                }
            }

            dom_node_t* target_node = is_doc_wrapper ? root : dom_node_create(tag);
            if (!is_doc_wrapper) {
                if (is_foster_table_context_tag(current->tag) &&
                    !is_valid_direct_table_child(current->tag, tag)) {
                    dom_node_t* tbl = open_stack_find_enclosing_table(open_stack, open_len);
                    if (tbl && tbl->parent) {
                        dom_node_insert_before(tbl->parent, tbl, target_node);
                    } else {
                        dom_node_add_child(current, target_node);
                    }
                } else {
                    dom_node_add_child(current, target_node);
                }
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
                    char* clean_attr_v = blink_unescape_html(attr_v);
                    apply_parsed_attribute(target_node, attr_k, clean_attr_v ? clean_attr_v : attr_v);
                    free(clean_attr_v);
                }
                if (!attr_k[0] && *p && *p != '>') p++;
            }
            if (*p == '>') p++;

            /* Void elements never push onto the open-element stack (`html_void_tag_never_grows_stack`) */
            if (!is_doc_wrapper && !self_closing && !blink_html_is_void_tag(tag)) {
                open_stack_push(open_stack, &open_len, target_node);
                if (is_afe_marker_tag(tag)) {
                    afe_push_marker(&afe);
                } else if (is_html5_formatting_tag(tag)) {
                    afe_push_formatting(&afe, target_node);
                }
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

                if (is_foster_table_context_tag(current->tag)) {
                    /* WHATWG §13.2.6.4.9: non-whitespace text directly inside table context is foster-parented! */
                    if (!all_ws) {
                        dom_node_t* tn = dom_node_create("#text");
                        tn->text = clean_text;
                        html5_insert_node_appropriate_place(open_stack, open_len, tn);
                    } else {
                        free(clean_text);
                    }
                } else {
                    /* Preserve pure-whitespace runs inside `<pre>` or between inline elements */
                    bool has_pending_afe = (afe.count > 0 && !afe.entries[afe.count - 1].is_marker);
                    bool after_inline = (current->num_children > 0 &&
                                         current->children[current->num_children - 1]->ua_style.display == DISPLAY_INLINE) ||
                                        has_pending_afe;
                    bool before_own_close = (p[0] == '<' && p[1] == '/' &&
                                             strncasecmp(p + 2, current->tag, strlen(current->tag)) == 0);
                    bool keep_inline_space = (all_ws && clean_text[0] != '\0' &&
                                              (is_inside_pre_on_stack(open_stack, open_len) ||
                                               (after_inline && !before_own_close)));
                    if (!all_ws || keep_inline_space) {
                        html5_reconstruct_active_formatting(&afe, open_stack, &open_len);
                        current = open_stack[open_len - 1];
                        dom_node_t* tn = dom_node_create("#text");
                        tn->text = clean_text;
                        dom_node_add_child(current, tn);
                    } else {
                        free(clean_text);
                    }
                }
            }
        }
    }

    return root;
}

dom_node_t* blink_parse_html5_document(const char* html, blink_css_stylesheet_t* out_sheet) {
    return blink_parse_html5_document_ex(html, ".", out_sheet);
}
