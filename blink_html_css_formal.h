#ifndef BLINK_HTML_CSS_FORMAL_H
#define BLINK_HTML_CSS_FORMAL_H

/* ========================================================================= */
/* Chromium Blink Formal HTML5 TreeBuilder & CSS Cascade Engine (C99)        */
/* Verified in Rocq/Coq 9.3.0:                                               */
/*   - BlinkHTML5TreeBuilderAndCSSCascadeEngine.v                            */
/*   - BlinkDualModeZSemantics.v                                             */
/*   - BlinkHMHybrid_17_HTMLToken.v .. BlinkHMHybrid_32_TableColumnAutoTrack */
/* ========================================================================= */

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "blink_dual_mode_z.h"

#ifdef __cplusplus
extern "C" {
#endif

/* ------------------------------------------------------------------------- */
/* 1. Computed Style & DOM Node Representation                               */
/* ------------------------------------------------------------------------- */

#define BLINK_COLOR_WHITE        0xFFFFFFFFu
#define BLINK_COLOR_BLACK        0xFF000000u
#define BLINK_COLOR_TEXT_DEFAULT 0xFF202124u
#define BLINK_COLOR_BORDER_GRAY  0xFFDADCE0u
#define BLINK_COLOR_BG_LIGHT     0xFFF8F9FAu
#define BLINK_COLOR_LINK_BLUE    0xFF1A73E8u

typedef enum {
    DISPLAY_BLOCK = 0,
    DISPLAY_INLINE,
    DISPLAY_INLINE_BLOCK,
    DISPLAY_FLEX,
    DISPLAY_GRID,
    DISPLAY_TABLE,
    DISPLAY_TABLE_ROW_GROUP,
    DISPLAY_TABLE_ROW,
    DISPLAY_TABLE_CELL,
    DISPLAY_LIST_ITEM,
    DISPLAY_NONE
} css_display_t;

typedef enum {
    ALIGN_LEFT = 0,
    ALIGN_CENTER,
    ALIGN_RIGHT
} css_align_t;

typedef enum {
    BOX_SIZING_CONTENT_BOX = 0,
    BOX_SIZING_BORDER_BOX  = 1
} css_box_sizing_t;

typedef enum {
    JUSTIFY_FLEX_START = 0,
    JUSTIFY_CENTER,
    JUSTIFY_FLEX_END,
    JUSTIFY_SPACE_BETWEEN
} css_justify_t;

#define BLINK_MAX_CUSTOM_PROPS 32
#define BLINK_MAX_ATTRS        12

typedef struct {
    char name[48];   /* e.g. "--accent" */
    char value[160]; /* raw token stream */
} blink_custom_prop_t;

typedef struct {
    char name[32];
    char value[128];
} blink_dom_attr_t;

typedef struct {
    css_display_t    display;
    css_box_sizing_t box_sizing;
    css_justify_t    justify_content;
    uint32_t         color;
    uint32_t         bg_color;
    bool             has_bg;
    uint32_t         border_color;
    uint32_t         border_left_color;
    int              border_width;
    int              border_left_width;
    int              border_bottom_width;
    int              border_radius;
    float            font_size;
    int              font_weight; /* 400 normal, 700 bold */
    int              font_style;  /* 0 normal, 1 italic */
    char             font_family[64];
    int              margin_top;
    int              margin_bottom;
    int              margin_left;
    int              margin_right;
    int              padding_top;
    int              padding_bottom;
    int              padding_left;
    int              padding_right;
    int              width;       /* -1 = auto */
    int              height;      /* -1 = auto */
    int              gap;         /* flex/grid column gap in px */
    int              row_gap;     /* grid row gap in px */
    int              flex_grow;   /* flex-grow factor >= 0 */
    bool             align_items_center;
    int              grid_col_widths[16]; /* >0 = px, <=0 = -fr weight */
    int              num_grid_cols;
    float            line_height;
    css_align_t      text_align;

    /* Active custom property environment on this element */
    blink_custom_prop_t custom_props[BLINK_MAX_CUSTOM_PROPS];
    int                 num_custom_props;
} dom_style_t;

typedef struct dom_node {
    char              tag[32];
    char*             text;
    char*             id;
    char*             class_name;
    char*             src;
    char*             href;
    char*             inline_style_raw;
    int               colspan;
    int               rowspan;
    blink_dom_attr_t  attrs[BLINK_MAX_ATTRS];
    int               num_attrs;

    dom_style_t       ua_style;  /* Initial UA style prior to author cascade */
    dom_style_t       style;     /* Computed style after Cascade + Inheritance */

    /* Formal layout box coordinates */
    int               x;
    int               y;
    int               w;
    int               h;
    int               content_h;

    struct dom_node*  parent;
    struct dom_node** children;
    int               num_children;
    int               cap_children;
} dom_node_t;

/* ------------------------------------------------------------------------- */
/* 2. CSS Selector, Specificity & Cascade Level 5 Structures                 */
/* ------------------------------------------------------------------------- */

typedef struct {
    int32_t id_cnt;
    int32_t class_cnt;
    int32_t tag_cnt;
} blink_specificity_t;

typedef enum {
    CSS_ORIGIN_UA = 0,
    CSS_ORIGIN_USER = 1,
    CSS_ORIGIN_AUTHOR = 2,
    CSS_ORIGIN_INLINE = 3
} blink_css_origin_t;

typedef struct {
    blink_css_origin_t  origin;
    bool                important;
    int32_t             layer_order; /* 0..N-1 for explicit @layer, 65535 for unlayered */
    blink_specificity_t specificity;
    int32_t             source_order;
} blink_cascade_meta_t;

#define BLINK_UNLAYERED_ORDER 65535

typedef enum {
    COMB_NONE = 0,        /* Subject compound selector */
    COMB_DESCENDANT = 1,  /* ' ' */
    COMB_CHILD = 2,       /* '>' */
    COMB_NEXT_SIBLING = 3 /* '+' */
} blink_combinator_t;

typedef enum {
    PSEUDO_NONE = 0,
    PSEUDO_FIRST_CHILD,
    PSEUDO_LAST_CHILD,
    PSEUDO_NTH_CHILD
} blink_pseudo_kind_t;

#define BLINK_MAX_CLASSES_PER_COMPOUND 4
#define BLINK_MAX_COMPOUNDS_PER_SEL    6

typedef struct {
    bool                universal;
    char                tag[32];      /* empty if none */
    char                id[64];       /* empty if none */
    char                classes[BLINK_MAX_CLASSES_PER_COMPOUND][64];
    int                 num_classes;
    char                attr_name[32];
    char                attr_val[64];
    bool                has_attr;
    bool                has_attr_val;
    blink_pseudo_kind_t pseudo;
    int                 nth_a;
    int                 nth_b;
    /* `:where(...)` zero-specificity wrapper support */
    bool                zero_specificity;
} blink_compound_sel_t;

typedef struct {
    /* Stored left-to-right: compounds[0] ... compounds[num_compounds-1] (subject).
       combinators[k] joins compounds[k-1] and compounds[k] (combinators[0] == COMB_NONE).
       Evaluated right-to-left starting from compounds[num_compounds-1] per Blink SelectorChecker! */
    blink_compound_sel_t compounds[BLINK_MAX_COMPOUNDS_PER_SEL];
    blink_combinator_t   combinators[BLINK_MAX_COMPOUNDS_PER_SEL];
    int                  num_compounds;
    blink_specificity_t  specificity;
} blink_complex_sel_t;

typedef struct {
    char prop[48];
    char value[192];
    bool important;
} blink_css_decl_t;

#define BLINK_MAX_RULE_DECLS 24
#define BLINK_MAX_STYLESHEET_RULES 512
#define BLINK_MAX_LAYERS 32

typedef struct {
    blink_complex_sel_t selector;
    blink_css_decl_t    decls[BLINK_MAX_RULE_DECLS];
    int                 num_decls;
    int32_t             layer_order;
    int32_t             source_order;
    int32_t             media_min_w; /* -1 if unconstrained */
    int32_t             media_max_w; /* -1 if unconstrained */
} blink_css_rule_t;

typedef struct {
    blink_css_rule_t rules[BLINK_MAX_STYLESHEET_RULES];
    int              num_rules;
    char             layer_names[BLINK_MAX_LAYERS][48];
    int              num_layers;
    int32_t          next_source_order;
} blink_css_stylesheet_t;

typedef struct {
    int32_t top;
    int32_t right;
    int32_t bottom;
    int32_t left;
} blink_box_edges_t;

/* ------------------------------------------------------------------------- */
/* 3. Formally Verified Pure Functions (Exact Mirrors of Gallina Definitions)*/
/* ------------------------------------------------------------------------- */

/* HTML5 TreeBuilder & Attribute Sanitization */
bool blink_html_is_void_tag(const char* tag);
bool blink_html_is_scope_boundary(const char* tag);
int32_t blink_html_sanitize_span(int32_t raw_span, int32_t max_cap);

/* Specificity & Cascade Priority Algebra */
blink_specificity_t blink_specificity_add(blink_specificity_t a, blink_specificity_t b);
bool blink_specificity_lt(blink_specificity_t a, blink_specificity_t b);
int32_t blink_origin_importance_rank(blink_css_origin_t origin, bool important);
bool blink_cascade_meta_lt(blink_cascade_meta_t a, blink_cascade_meta_t b);

/* Selector Parsing & Right-to-Left DOM Matching */
bool blink_css_parse_selector(const char* sel_text, blink_complex_sel_t* out_sel);
bool blink_css_match_selector(const dom_node_t* el, const blink_complex_sel_t* sel);
bool blink_css_match_nth_child(int index_1based, int a, int b);

/* Cycle-Safe Custom Property `var(--x, fallback)` Resolution */
bool blink_css_resolve_var_value(const blink_custom_prop_t* props,
                                 int num_props,
                                 const char* raw_val,
                                 char* out_resolved,
                                 size_t out_cap);

/* Shorthands, Units, `calc()`, `box-sizing`, Flexbox & Table Partitioning */
blink_box_edges_t blink_css_expand_shorthand_ints(const int32_t* vals, int count);
void blink_css_parse_box_shorthand(const char* raw_val,
                                   int32_t parent_px,
                                   int32_t em_px,
                                   int32_t rem_px,
                                   int32_t vw_px,
                                   int32_t vh_px,
                                   blink_layout_mode_t mode,
                                   blink_box_edges_t* out_edges);

int32_t blink_css_eval_length_or_calc(const char* expr,
                                      int32_t parent_px,
                                      int32_t em_px,
                                      int32_t rem_px,
                                      int32_t vw_px,
                                      int32_t vh_px,
                                      blink_layout_mode_t mode,
                                      bool* out_is_auto);

int32_t blink_css_resolve_content_inline_size(css_box_sizing_t sizing,
                                              int32_t specified_w,
                                              int32_t pad_h,
                                              int32_t bdr_h);

int32_t blink_flex_justify_start_offset(css_justify_t mode,
                                        int32_t container_w,
                                        int32_t used_w,
                                        int32_t item_count);

int32_t blink_flex_justify_inter_gap(css_justify_t mode,
                                     int32_t container_w,
                                     int32_t used_w,
                                     int32_t item_count,
                                     int32_t base_gap);

int32_t blink_table_col_start_formal(int32_t avail_w,
                                     int32_t total_cols,
                                     int32_t col_idx,
                                     blink_layout_mode_t mode);

int32_t blink_table_col_width_formal(int32_t avail_w,
                                     int32_t total_cols,
                                     int32_t col_idx,
                                     blink_layout_mode_t mode);

/* ------------------------------------------------------------------------- */
/* 4. End-to-End HTML5 Document Parser + CSS Stylesheet & Cascade Pipeline   */
/* ------------------------------------------------------------------------- */

dom_node_t* dom_node_create(const char* tag);
void dom_node_add_child(dom_node_t* parent, dom_node_t* child);
void dom_node_free(dom_node_t* n);
char* blink_unescape_html(const char* src);
uint32_t blink_parse_css_color(const char* s, bool* out_ok);

void blink_css_stylesheet_init(blink_css_stylesheet_t* sheet);
void blink_css_parse_stylesheet(blink_css_stylesheet_t* sheet, const char* css_text);

dom_node_t* blink_parse_html5_document(const char* html, blink_css_stylesheet_t* out_sheet);

void blink_css_resolve_document_styles(dom_node_t* root,
                                       const blink_css_stylesheet_t* sheet,
                                       int32_t viewport_w,
                                       int32_t viewport_h,
                                       blink_layout_mode_t mode);

#ifdef __cplusplus
}
#endif

#endif /* BLINK_HTML_CSS_FORMAL_H */
