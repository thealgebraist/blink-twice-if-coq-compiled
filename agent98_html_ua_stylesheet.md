### 1. Core UA Rules Audit: Blink `html.css` vs. HTML Living Standard §15

An audit of Chromium’s `third_party/blink/renderer/core/html/resources/html.css` against WHATWG HTML Living Standard §15 (Rendering) confirms exact conformance for core block and tabular elements:

| Element | Blink `html.css` Rule | HTML Standard §15 Requirement | Audit Status |
| :--- | :--- | :--- | :--- |
| **`body`** | `display: block; margin: 8px;` | §15.3.1: `display: block; margin: 8px;` | **Conformant** |
| **`h1`** | `display: block; font-size: 2em; margin-block-start: 0.67em; margin-block-end: 0.67em; font-weight: bold;` | §15.3.6: `display: block; font-size: 2.00em; margin-block: 0.67em; font-weight: bold;` | **Conformant** |
| **`h2`** | `display: block; font-size: 1.5em; margin-block-start: 0.83em; margin-block-end: 0.83em; font-weight: bold;` | §15.3.6: `display: block; font-size: 1.50em; margin-block: 0.83em; font-weight: bold;` | **Conformant** |
| **`table`** | `display: table; border-collapse: separate; border-spacing: 2px; border-color: gray;` | §15.3.9: `display: table; border-collapse: separate; border-spacing: 2px;` | **Conformant** |
| **`tr`** | `display: table-row; vertical-align: inherit;` | §15.3.9: `display: table-row; vertical-align: inherit;` | **Conformant** |
| **`td`** | `display: table-cell; vertical-align: inherit; padding: 1px;` | §15.3.9: `display: table-cell; vertical-align: inherit; padding: 1px;` | **Conformant** |
| **`th`** | `display: table-cell; vertical-align: inherit; font-weight: bold; text-align: -internal-center; padding: 1px;` | §15.3.9: `display: table-cell; vertical-align: inherit; font-weight: bold; text-align: center; padding: 1px;` | **Conformant** (via internal center token) |

*Note: Floating-point values ($0.67\text{em}, 0.83\text{em}, 1.5\text{em}$) are represented in our formalization as scaled hundredths (`nat`) to maintain decidable integer arithmetic.*

---

### 2. Element Tag to UA Style Mapping

Let $\mathcal{T}$ be the set of HTML Tag Identifiers and $\mathcal{S}$ be the space of UA Style structs. We define a total valuation function:
$$\llbracket \cdot \rrbracket_{\text{UA}} : \mathcal{T} \to \mathcal{S}$$
Any tag not explicitly matched by structural rules defaults to CSS initial values (`display: inline`, `font-size: 1.00em`, `font-weight: normal`, `margin: 0`, `padding: 0`).

---

### 3. Mathematical Invariants

1. **Completeness (Totality):** $\forall t \in \mathcal{T}, \exists s \in \mathcal{S} \text{ s.t. } \llbracket t \rrbracket_{\text{UA}} = s$.
2. **Determinism:** $\forall t \in \mathcal{T}, \forall s_1, s_2 \in \mathcal{S}, (\llbracket t \rrbracket_{\text{UA}} = s_1 \land \llbracket t \rrbracket_{\text{UA}} = s_2) \implies s_1 = s_2$.
3. **Non-Negativity of Box Metrics:** For all $t \in \mathcal{T}$, all margin, padding, and border-spacing quantities in $\llbracket t \rrbracket_{\text{UA}}$ are strictly $\ge 0$.
4. **Strict Font-Size Positivity:** For all $t \in \mathcal{T}$, $\text{font\_size}(\llbracket t \rrbracket_{\text{UA}}) > 0$.

---

### 4. Formalization in Rocq/Coq (`BlinkHTMLUASheetSemantics.v`)

```coq
(** * BlinkHTMLUASheetSemantics.v
    Formalization of Chromium Blink html.css User-Agent Stylesheet Rules
    against WHATWG HTML Living Standard Section 15. *)

Require Import Coq.Arith.Arith.
Require Import Coq.Lists.List.
Require Import Coq.Bool.Bool.
Require Import Coq.micromega.Lia.
Import ListNotations.

(** ** 1. Core HTML Element Tags *)
Inductive HTMLTag : Type :=
  | Tag_Body
  | Tag_H1
  | Tag_H2
  | Tag_Table
  | Tag_Tr
  | Tag_Td
  | Tag_Th
  | Tag_Unknown (id : nat).

(** ** 2. CSS Property Value Domains *)
Inductive CSSDisplay : Type :=
  | Disp_Inline
  | Disp_Block
  | Disp_Table
  | Disp_TableRow
  | Disp_TableCell.

Inductive CSSFontWeight : Type :=
  | FW_Normal
  | FW_Bold.

Inductive CSSBorderCollapse : Type :=
  | BC_Separate
  | BC_Collapse.

Inductive CSSVerticalAlign : Type :=
  | VA_Baseline
  | VA_Inherit.

Inductive CSSTextAlign : Type :=
  | TA_Start
  | TA_Center.

(** Lengths scaled by 100 to avoid floats (e.g. 0.67em -> 67, 2px -> 200) *)
Inductive CSSLength : Type :=
  | Len_Zero
  | Len_Px (hundredths_px : nat)
  | Len_Em (hundredths_em : nat).

Definition length_val (l : CSSLength) : nat :=
  match l with
  | Len_Zero => 0
  | Len_Px n => n
  | Len_Em n => n
  end.

(** ** 3. UA Style Struct *)
Record UAStyle : Type := mkUAStyle {
  ua_display         : CSSDisplay;
  ua_margin_top      : CSSLength;
  ua_margin_bottom   : CSSLength;
  ua_margin_left     : CSSLength;
  ua_margin_right    : CSSLength;
  ua_padding_top     : CSSLength;
  ua_padding_bottom  : CSSLength;
  ua_padding_left    : CSSLength;
  ua_padding_right   : CSSLength;
  ua_font_size_em    : nat; (* Scaled by 100: 100 = 1em, 200 = 2em, 150 = 1.5em *)
  ua_font_weight     : CSSFontWeight;
  ua_border_collapse : CSSBorderCollapse;
  ua_border_spacing  : CSSLength;
  ua_vertical_align  : CSSVerticalAlign;
  ua_text_align      : CSSTextAlign
}.

(** Initial CSS specification fallback values *)
Definition initial_ua_style : UAStyle := {|
  ua_display         := Disp_Inline;
  ua_margin_top      := Len_Zero;
  ua_margin_bottom   := Len_Zero;
  ua_margin_left     := Len_Zero;
  ua_margin_right    := Len_Zero;
  ua_padding_top     := Len_Zero;
  ua_padding_bottom  := Len_Zero;
  ua_padding_left    := Len_Zero;
  ua_padding_right   := Len_Zero;
  ua_font_size_em    := 100;
  ua_font_weight     := FW_Normal;
  ua_border_collapse := BC_Separate;
  ua_border_spacing  := Len_Zero;
  ua_vertical_align  := VA_Baseline;
  ua_text_align      := TA_Start
|}.

(** ** 4. Blink html.css Mapping Function *)
Definition blink_ua_style_for_tag (t : HTMLTag) : UAStyle :=
  match t with
  | Tag_Body => {|
      ua_display         := Disp_Block;
      ua_margin_top      := Len_Px 800; (* 8px *)
      ua_margin_bottom   := Len_Px 800;
      ua_margin_left     := Len_Px 800;
      ua_margin_right    := Len_Px 800;
      ua_padding_top     := Len_Zero;
      ua_padding_bottom  := Len_Zero;
      ua_padding_left    := Len_Zero;
      ua_padding_right   := Len_Zero;
      ua_font_size_em    := 100;
      ua_font_weight     := FW_Normal;
      ua_border_collapse := BC_Separate;
      ua_border_spacing  := Len_Zero;
      ua_vertical_align  := VA_Baseline;
      ua_text_align      := TA_Start
    |}
  | Tag_H1 => {|
      ua_display         := Disp_Block;
      ua_margin_top      := Len_Em 67;  (* 0.67em *)
      ua_margin_bottom   := Len_Em 67;
      ua_margin_left     := Len_Zero;
      ua_margin_right    := Len_Zero;
      ua_padding_top     := Len_Zero;
      ua_padding_bottom  := Len_Zero;
      ua_padding_left    := Len_Zero;
      ua_padding_right   := Len_Zero;
      ua_font_size_em    := 200;        (* 2.00em *)
      ua_font_weight     := FW_Bold;
      ua_border_collapse := BC_Separate;
      ua_border_spacing  := Len_Zero;
      ua_vertical_align  := VA_Baseline;
      ua_text_align      := TA_Start
    |}
  | Tag_H2 => {|
      ua_display         := Disp_Block;
      ua_margin_top      := Len_Em 83;  (* 0.83em *)
      ua_margin_bottom   := Len_Em 83;
      ua_margin_left     := Len_Zero;
      ua_margin_right    := Len_Zero;
      ua_padding_top     := Len_Zero;
      ua_padding_bottom  := Len_Zero;
      ua_padding_left    := Len_Zero;
      ua_padding_right   := Len_Zero;
      ua_font_size_em    := 150;        (* 1.50em *)
      ua_font_weight     := FW_Bold;
      ua_border_collapse := BC_Separate;
      ua_border_spacing  := Len_Zero;
      ua_vertical_align  := VA_Baseline;
      ua_text_align      := TA_Start
    |}
  | Tag_Table => {|
      ua_display         := Disp_Table;
      ua_margin_top      := Len_Zero;
      ua_margin_bottom   := Len_Zero;
      ua_margin_left     := Len_Zero;
      ua_margin_right    := Len_Zero;
      ua_padding_top     := Len_Zero;
      ua_padding_bottom  := Len_Zero;
      ua_padding_left    := Len_Zero;
      ua_padding_right   := Len_Zero;
      ua_font_size_em    := 100;
      ua_font_weight     := FW_Normal;
      ua_border_collapse := BC_Separate;
      ua_border_spacing  := Len_Px 200; (* 2px *)
      ua_vertical_align  := VA_Baseline;
      ua_text_align      := TA_Start
    |}
  | Tag_Tr => {|
      ua_display         := Disp_TableRow;
      ua_margin_top      := Len_Zero;
      ua_margin_bottom   := Len_Zero;
      ua_margin_left     := Len_Zero;
      ua_margin_right    := Len_Zero;
      ua_padding_top     := Len_Zero;
      ua_padding_bottom  := Len_Zero;
      ua_padding_left    := Len_Zero;
      ua_padding_right   := Len_Zero;
      ua_font_size_em    := 100;
      ua_font_weight     := FW_Normal;
      ua_border_collapse := BC_Separate;
      ua_border_spacing  := Len_Zero;
      ua_vertical_align  := VA_Inherit;
      ua_text_align      := TA_Start
    |}
  | Tag_Td => {|
      ua_display         := Disp_TableCell;
      ua_margin_top      := Len_Zero;
      ua_margin_bottom   := Len_Zero;
      ua_margin_left     := Len_Zero;
      ua_margin_right    := Len_Zero;
      ua_padding_top     := Len_Px 100; (* 1px *)
      ua_padding_bottom  := Len_Px 100;
      ua_padding_left    := Len_Px 100;
      ua_padding_right   := Len_Px 100;
      ua_font_size_em    := 100;
      ua_font_weight     := FW_Normal;
      ua_border_collapse := BC_Separate;
      ua_border_spacing  := Len_Zero;
      ua_vertical_align  := VA_Inherit;
      ua_text_align      := TA_Start
    |}
  | Tag_Th => {|
      ua_display         := Disp_TableCell;
      ua_margin_top      := Len_Zero;
      ua_margin_bottom   := Len_Zero;
      ua_margin_left     := Len_Zero;
      ua_margin_right    := Len_Zero;
      ua_padding_top     := Len_Px 100; (* 1px *)
      ua_padding_bottom  := Len_Px 100;
      ua_padding_left    := Len_Px 100;
      ua_padding_right   := Len_Px 100;
      ua_font_size_em    := 100;
      ua_font_weight     := FW_Bold;
      ua_border_collapse :=