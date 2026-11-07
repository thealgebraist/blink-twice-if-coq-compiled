(* Standalone HTML/CSS combinatorial page generator. No libraries beyond Stdlib. *)
module Json = struct
  type t = String of string | Int of int | Bool of bool | Array of t list | Object of (string * t) list
  let quote s =
    let b = Buffer.create (String.length s + 2) in
    Buffer.add_char b '"';
    String.iter (function
      | '"' -> Buffer.add_string b "\\\"" | '\\' -> Buffer.add_string b "\\\\"
      | '\n' -> Buffer.add_string b "\\n" | '\r' -> Buffer.add_string b "\\r"
      | '\t' -> Buffer.add_string b "\\t"
      | c when Char.code c < 32 || c = '<' -> Buffer.add_string b (Printf.sprintf "\\u%04x" (Char.code c))
      | c -> Buffer.add_char b c) s;
    Buffer.add_char b '"'; Buffer.contents b
  let rec render = function
    | String s -> quote s | Int n -> string_of_int n | Bool b -> string_of_bool b
    | Array xs -> "[" ^ String.concat "," (List.map render xs) ^ "]"
    | Object xs -> "{" ^ String.concat "," (List.map (fun (k,v) -> quote k ^ ":" ^ render v) xs) ^ "}"
end

module Css = struct
  type length_unit = Px | Em | Rem | Ch | Vw | Vh | Fr
  type css_function = Rgb | Linear_gradient | Minmax | Repeat | Translate | Rotate | Scale | Blur | Brightness | Inset | Cubic_bezier
  type value =
    | Keyword of string | Ident of string | Text of string | Color of string
    | Length of float * length_unit | Percent of float | Number of float
    | Seconds of float | Degrees of float | Function of css_function * value list
    | Sequence of value list | Comma_list of value list | Slash of value * value
  let kw s = Keyword s
  let px n = Length (float_of_int n, Px)
  let em n = Length (n, Em)
  let rem n = Length (n, Rem)
  let pc n = Percent (float_of_int n)
  let num n = Number (float_of_int n)
  let color s = Color s
  let seq xs = Sequence xs
  let comma xs = Comma_list xs
  let fn f xs = Function (f,xs)
  let safe_ident s =
    String.length s > 0 && String.for_all (function
      | 'a'..'z' | 'A'..'Z' | '0'..'9' | '-' | '_' -> true | _ -> false) s
  let quote s =
    let b = Buffer.create 32 in
    Buffer.add_char b '"';
    String.iter (function
      | '"' -> Buffer.add_string b "\\\"" | '\\' -> Buffer.add_string b "\\\\"
      | '\n' | '\r' -> Buffer.add_string b "\\a "
      | '<' -> Buffer.add_string b "\\3c "
      | c -> Buffer.add_char b c) s;
    Buffer.add_char b '"'; Buffer.contents b
  let rec value = function
    | Keyword s | Ident s -> if safe_ident s then s else invalid_arg "unsafe CSS identifier"
    | Text s -> quote s
    | Color s ->
        if List.mem (String.length s) [3;6;8] && String.for_all (function '0'..'9'|'a'..'f'|'A'..'F' -> true | _ -> false) s
        then "#" ^ s else invalid_arg "invalid CSS hex color"
    | Length (n,u) -> Printf.sprintf "%g%s" n (match u with Px->"px"|Em->"em"|Rem->"rem"|Ch->"ch"|Vw->"vw"|Vh->"vh"|Fr->"fr")
    | Percent n -> Printf.sprintf "%g%%" n | Number n -> Printf.sprintf "%g" n
    | Seconds n -> Printf.sprintf "%gs" n | Degrees n -> Printf.sprintf "%gdeg" n
    | Function (f,args) ->
        let name = match f with Rgb->"rgb"|Linear_gradient->"linear-gradient"|Minmax->"minmax"|Repeat->"repeat"
          |Translate->"translate"|Rotate->"rotate"|Scale->"scale"|Blur->"blur"|Brightness->"brightness"|Inset->"inset"|Cubic_bezier->"cubic-bezier" in
        name ^ "(" ^ String.concat ", " (List.map value args) ^ ")"
    | Sequence xs -> String.concat " " (List.map value xs)
    | Comma_list xs -> String.concat ", " (List.map value xs)
    | Slash (a,b) -> value a ^ " / " ^ value b

  type property =
    | Display | Position | BoxSizing | Width | Height | MinWidth | MaxWidth | MinHeight | MaxHeight | InlineSize | BlockSize | MinInlineSize | MaxInlineSize | MinBlockSize | MaxBlockSize | AspectRatio | Margin | MarginTop | MarginRight | MarginBottom | MarginLeft | MarginInline | MarginBlock | Padding | PaddingTop | PaddingRight | PaddingBottom | PaddingLeft | PaddingInline | PaddingBlock | Border | BorderWidth | BorderStyle | BorderColor | BorderTop | BorderRight | BorderBottom | BorderLeft | BorderRadius | BorderStartStartRadius | BoxShadow | Outline | OutlineOffset | BackgroundColor | BackgroundImage | BackgroundSize | BackgroundPosition | BackgroundRepeat | BackgroundClip | BackgroundOrigin | Color | Opacity | FontFamily | FontSize | FontWeight | FontStyle | FontVariant | FontStretch | LineHeight | LetterSpacing | WordSpacing | TextAlign | TextAlignLast | TextDecoration | TextDecorationColor | TextDecorationThickness | TextUnderlineOffset | TextTransform | TextIndent | TextShadow | TextOverflow | WhiteSpace | WordBreak | OverflowWrap | Hyphens | TabSize | VerticalAlign | Direction | UnicodeBidi | WritingMode | TextOrientation | FlexDirection | FlexWrap | FlexGrow | FlexShrink | FlexBasis | Flex | Order | JustifyContent | AlignItems | AlignContent | AlignSelf | JustifyItems | JustifySelf | PlaceItems | Gap | RowGap | ColumnGap | GridTemplateColumns | GridTemplateRows | GridTemplateAreas | GridAutoFlow | GridAutoColumns | GridAutoRows | GridColumn | GridRow | Float | Clear | Top | Right | Bottom | Left | InsetInlineStart | ZIndex | Overflow | OverflowX | OverflowY | OverscrollBehavior | ScrollbarGutter | ScrollBehavior | ScrollMargin | ScrollPadding | ScrollSnapType | ScrollSnapAlign | ColumnCount | ColumnWidth | ColumnRule | ColumnFill | ColumnSpan | BreakInside | BreakBefore | BreakAfter | Orphans | Widows | ListStyleType | ListStylePosition | BorderCollapse | BorderSpacing | TableLayout | CaptionSide | EmptyCells | ObjectFit | ObjectPosition | Transform | TransformOrigin | Perspective | BackfaceVisibility | TransitionProperty | TransitionDuration | TransitionTimingFunction | AnimationName | AnimationDuration | AnimationIterationCount | AnimationTimingFunction | AnimationDirection | Filter | BackdropFilter | ClipPath | MixBlendMode | Isolation | Contain | ContainerType | ContentVisibility | ContainIntrinsicSize | Visibility | Cursor | UserSelect | PointerEvents | Resize | AccentColor | CaretColor | Appearance | Content | CounterReset | CounterIncrement | CustomAccent
  type declaration = property * value
  let catalog : (property * string * value list) list = [
    Display,"display",[kw "block";kw "flex";kw "grid";kw "flow-root"];
    Position,"position",[kw "relative";kw "static"];
    BoxSizing,"box-sizing",[kw "border-box";kw "content-box"];
    Width,"width",[pc 100;kw "auto";Length (24.,Ch)];
    Height,"height",[kw "auto";px 160];
    MinWidth,"min-width",[px 0;px 80];
    MaxWidth,"max-width",[pc 100;px 280];
    MinHeight,"min-height",[px 40;px 90];
    MaxHeight,"max-height",[px 180;px 240];
    InlineSize,"inline-size",[kw "auto";pc 100];
    BlockSize,"block-size",[kw "auto";px 160];
    MinInlineSize,"min-inline-size",[px 0;px 60];
    MaxInlineSize,"max-inline-size",[pc 100;px 260];
    MinBlockSize,"min-block-size",[px 30;px 60];
    MaxBlockSize,"max-block-size",[px 160;px 200];
    AspectRatio,"aspect-ratio",[Slash (num 4,num 3);kw "auto"];
    Margin,"margin",[px 2;px 6;seq [px 2;kw "auto"]];
    MarginTop,"margin-top",[px 0;px 6];
    MarginRight,"margin-right",[px 2;px 8];
    MarginBottom,"margin-bottom",[px 4;px 10];
    MarginLeft,"margin-left",[px 2;px 8];
    MarginInline,"margin-inline",[px 3;kw "auto"];
    MarginBlock,"margin-block",[px 3;px 8];
    Padding,"padding",[px 4;px 10;seq [px 6;px 12]];
    PaddingTop,"padding-top",[px 4;px 8];
    PaddingRight,"padding-right",[px 4;px 8];
    PaddingBottom,"padding-bottom",[px 4;px 8];
    PaddingLeft,"padding-left",[px 4;px 8];
    PaddingInline,"padding-inline",[px 5;px 10];
    PaddingBlock,"padding-block",[px 5;px 10];
    Border,"border",[seq [px 1;kw "solid";color "397d87"];seq [px 2;kw "dashed";color "a76b3c"]];
    BorderWidth,"border-width",[px 1;px 3];
    BorderStyle,"border-style",[kw "solid";kw "dashed";kw "dotted";kw "double"];
    BorderColor,"border-color",[color "317981";color "aa643e"];
    BorderTop,"border-top",[seq [px 3;kw "solid";color "e0ad48"]];
    BorderRight,"border-right",[seq [px 2;kw "dotted";color "397d87"]];
    BorderBottom,"border-bottom",[seq [px 3;kw "double";color "397d87"]];
    BorderLeft,"border-left",[seq [px 3;kw "solid";color "ab6842"]];
    BorderRadius,"border-radius",[px 0;px 8;seq [px 3;px 14]];
    BorderStartStartRadius,"border-start-start-radius",[px 3;px 12];
    BoxShadow,"box-shadow",[seq [px 1;px 3;px 8;color "163f4326"];kw "none"];
    Outline,"outline",[seq [px 1;kw "dotted";color "7b5555"]];
    OutlineOffset,"outline-offset",[px 1;px 3];
    BackgroundColor,"background-color",[color "e5f2ed";color "fff0cd";color "e9eafb"];
    BackgroundImage,"background-image",[fn Linear_gradient [Degrees 135.;color "e3f3ef";color "f8e9cc"];kw "none"];
    BackgroundSize,"background-size",[kw "cover";seq [px 40;px 40]];
    BackgroundPosition,"background-position",[kw "center";seq [kw "left";kw "top"]];
    BackgroundRepeat,"background-repeat",[kw "repeat";kw "no-repeat"];
    BackgroundClip,"background-clip",[kw "padding-box";kw "border-box"];
    BackgroundOrigin,"background-origin",[kw "padding-box";kw "content-box"];
    Color,"color",[color "153c45";color "674332";color "343269"];
    Opacity,"opacity",[Number 0.85;Number 1.];
    FontFamily,"font-family",[comma [Text "Georgia";kw "serif"];kw "system-ui";kw "monospace"];
    FontSize,"font-size",[px 13;px 16;em 1.1];
    FontWeight,"font-weight",[num 400;num 600;num 700];
    FontStyle,"font-style",[kw "normal";kw "italic"];
    FontVariant,"font-variant",[kw "normal";kw "small-caps"];
    FontStretch,"font-stretch",[kw "normal";kw "condensed"];
    LineHeight,"line-height",[Number 1.3;Number 1.6];
    LetterSpacing,"letter-spacing",[px 0;Length (0.04,Em)];
    WordSpacing,"word-spacing",[px 1;px 4];
    TextAlign,"text-align",[kw "start";kw "center";kw "justify"];
    TextAlignLast,"text-align-last",[kw "auto";kw "start";kw "center"];
    TextDecoration,"text-decoration",[kw "none";seq [kw "underline";kw "dotted"]];
    TextDecorationColor,"text-decoration-color",[color "af613f";color "197381"];
    TextDecorationThickness,"text-decoration-thickness",[px 1;px 2];
    TextUnderlineOffset,"text-underline-offset",[px 2;px 4];
    TextTransform,"text-transform",[kw "none";kw "uppercase";kw "capitalize"];
    TextIndent,"text-indent",[px 0;em 1.];
    TextShadow,"text-shadow",[seq [px 1;px 1;px 2;color "6c9da666"];kw "none"];
    TextOverflow,"text-overflow",[kw "clip";kw "ellipsis"];
    WhiteSpace,"white-space",[kw "normal";kw "pre-wrap";kw "break-spaces"];
    WordBreak,"word-break",[kw "normal";kw "break-all";kw "keep-all"];
    OverflowWrap,"overflow-wrap",[kw "normal";kw "anywhere"];
    Hyphens,"hyphens",[kw "manual";kw "auto"];
    TabSize,"tab-size",[num 2;num 4;num 8];
    VerticalAlign,"vertical-align",[kw "baseline";kw "middle";kw "top"];
    Direction,"direction",[kw "ltr";kw "rtl"];
    UnicodeBidi,"unicode-bidi",[kw "normal";kw "isolate"];
    WritingMode,"writing-mode",[kw "horizontal-tb";kw "vertical-rl";kw "vertical-lr"];
    TextOrientation,"text-orientation",[kw "mixed";kw "upright"];
    FlexDirection,"flex-direction",[kw "row";kw "column";kw "row-reverse"];
    FlexWrap,"flex-wrap",[kw "wrap";kw "nowrap"];
    FlexGrow,"flex-grow",[num 0;num 1];
    FlexShrink,"flex-shrink",[num 0;num 1];
    FlexBasis,"flex-basis",[kw "auto";px 80];
    Flex,"flex",[seq [num 1;num 1;px 80];kw "initial"];
    Order,"order",[num 0;num 1];
    JustifyContent,"justify-content",[kw "start";kw "center";kw "space-between";kw "space-around"];
    AlignItems,"align-items",[kw "stretch";kw "center";kw "baseline"];
    AlignContent,"align-content",[kw "start";kw "center";kw "space-between"];
    AlignSelf,"align-self",[kw "auto";kw "center";kw "stretch"];
    JustifyItems,"justify-items",[kw "stretch";kw "center"];
    JustifySelf,"justify-self",[kw "auto";kw "center"];
    PlaceItems,"place-items",[kw "center";seq [kw "stretch";kw "start"]];
    Gap,"gap",[px 3;px 8;seq [px 4;px 10]];
    RowGap,"row-gap",[px 4;px 9];
    ColumnGap,"column-gap",[px 6;px 12];
    GridTemplateColumns,"grid-template-columns",[fn Repeat [num 2;fn Minmax [px 0;Length (1.,Fr)]];seq [Length (1.,Fr);Length (2.,Fr)]];
    GridTemplateRows,"grid-template-rows",[seq [kw "auto";kw "auto"];fn Repeat [num 2;px 44]];
    GridTemplateAreas,"grid-template-areas",[seq [Text "a a";Text "b c"]];
    GridAutoFlow,"grid-auto-flow",[kw "row";seq [kw "row";kw "dense"];kw "column"];
    GridAutoColumns,"grid-auto-columns",[kw "auto";px 60];
    GridAutoRows,"grid-auto-rows",[kw "auto";px 45];
    GridColumn,"grid-column",[kw "auto";seq [kw "span";num 2]];
    GridRow,"grid-row",[kw "auto";Slash (num 1,num 2)];
    Float,"float",[kw "none";kw "inline-start";kw "inline-end"];
    Clear,"clear",[kw "none";kw "both";kw "inline-start"];
    Top,"top",[px 0;px 2];
    Right,"right",[kw "auto";px 2];
    Bottom,"bottom",[kw "auto";px 1];
    Left,"left",[px 0;px 2];
    InsetInlineStart,"inset-inline-start",[kw "auto";px 2];
    ZIndex,"z-index",[kw "auto";num 1];
    Overflow,"overflow",[kw "auto";kw "hidden";kw "clip"];
    OverflowX,"overflow-x",[kw "auto";kw "hidden"];
    OverflowY,"overflow-y",[kw "auto";kw "hidden"];
    OverscrollBehavior,"overscroll-behavior",[kw "auto";kw "contain"];
    ScrollbarGutter,"scrollbar-gutter",[kw "auto";kw "stable"];
    ScrollBehavior,"scroll-behavior",[kw "auto";kw "smooth"];
    ScrollMargin,"scroll-margin",[px 4;px 12];
    ScrollPadding,"scroll-padding",[px 4;px 10];
    ScrollSnapType,"scroll-snap-type",[kw "none";seq [kw "x";kw "proximity"]];
    ScrollSnapAlign,"scroll-snap-align",[kw "none";kw "start";kw "center"];
    ColumnCount,"column-count",[kw "auto";num 2];
    ColumnWidth,"column-width",[kw "auto";px 100];
    ColumnRule,"column-rule",[seq [px 1;kw "solid";color "a5bfba"]];
    ColumnFill,"column-fill",[kw "balance";kw "auto"];
    ColumnSpan,"column-span",[kw "none";kw "all"];
    BreakInside,"break-inside",[kw "auto";kw "avoid"];
    BreakBefore,"break-before",[kw "auto";kw "avoid"];
    BreakAfter,"break-after",[kw "auto";kw "avoid"];
    Orphans,"orphans",[num 2;num 3];
    Widows,"widows",[num 2;num 3];
    ListStyleType,"list-style-type",[kw "disc";kw "square";kw "decimal";kw "lower-roman"];
    ListStylePosition,"list-style-position",[kw "inside";kw "outside"];
    BorderCollapse,"border-collapse",[kw "collapse";kw "separate"];
    BorderSpacing,"border-spacing",[px 2;seq [px 3;px 5]];
    TableLayout,"table-layout",[kw "auto";kw "fixed"];
    CaptionSide,"caption-side",[kw "top";kw "bottom"];
    EmptyCells,"empty-cells",[kw "show";kw "hide"];
    ObjectFit,"object-fit",[kw "contain";kw "cover";kw "scale-down"];
    ObjectPosition,"object-position",[kw "center";seq [kw "left";kw "top"]];
    Transform,"transform",[kw "none";fn Translate [px 2;px 1];fn Rotate [Degrees (-1.)];fn Scale [Number 0.98]];
    TransformOrigin,"transform-origin",[kw "center";seq [kw "left";kw "top"]];
    Perspective,"perspective",[kw "none";px 600];
    BackfaceVisibility,"backface-visibility",[kw "visible";kw "hidden"];
    TransitionProperty,"transition-property",[kw "none";kw "background-color"];
    TransitionDuration,"transition-duration",[Seconds 0.;Seconds 0.25];
    TransitionTimingFunction,"transition-timing-function",[kw "ease";kw "linear"];
    AnimationName,"animation-name",[kw "none";Ident "monster-breathe"];
    AnimationDuration,"animation-duration",[Seconds 3.;Seconds 5.];
    AnimationIterationCount,"animation-iteration-count",[num 1;kw "infinite"];
    AnimationTimingFunction,"animation-timing-function",[kw "ease-in-out";kw "linear"];
    AnimationDirection,"animation-direction",[kw "normal";kw "alternate"];
    Filter,"filter",[kw "none";fn Brightness [Number 1.05];fn Blur [px 0]];
    BackdropFilter,"backdrop-filter",[kw "none";fn Blur [px 1]];
    ClipPath,"clip-path",[kw "none";fn Inset [px 2]];
    MixBlendMode,"mix-blend-mode",[kw "normal";kw "multiply"];
    Isolation,"isolation",[kw "auto";kw "isolate"];
    Contain,"contain",[kw "none";kw "layout";seq [kw "layout";kw "style"]];
    ContainerType,"container-type",[kw "normal";kw "inline-size"];
    ContentVisibility,"content-visibility",[kw "visible";kw "auto"];
    ContainIntrinsicSize,"contain-intrinsic-size",[px 120;seq [kw "auto";px 120]];
    Visibility,"visibility",[kw "visible"];
    Cursor,"cursor",[kw "auto";kw "crosshair";kw "pointer"];
    UserSelect,"user-select",[kw "auto";kw "text";kw "all"];
    PointerEvents,"pointer-events",[kw "auto"];
    Resize,"resize",[kw "none";kw "horizontal";kw "both"];
    AccentColor,"accent-color",[color "16786e";color "985c28"];
    CaretColor,"caret-color",[color "16786e";kw "auto"];
    Appearance,"appearance",[kw "auto";kw "none"];
    Content,"content",[kw "normal";Text "Generated content"];
    CounterReset,"counter-reset",[seq [Ident "specimen";num 0]];
    CounterIncrement,"counter-increment",[seq [Ident "specimen";num 1]];
    CustomAccent,"--monster-accent",[color "16786e";color "a46338"];
  ]
  let property_name p = let _,name,_ = List.find (fun (q,_,_) -> p=q) catalog in name
  let declarations ds = String.concat ";" (List.map (fun (p,v) -> property_name p ^ ":" ^ value v) ds)

end

module Html = struct
  type tag =
    | Html | Head | Body | Title | Base | Link | Meta | Style | Script | Noscript | Template | Slot | Address | Article | Aside | Footer | Header | Hgroup | Main | Nav | Section | Search | H1 | H2 | H3 | H4 | H5 | H6 | Blockquote | Div | Dl | Dt | Dd | Figure | Figcaption | Hr | Li | Menu | Ol | P | Pre | Ul | A | Abbr | B | Bdi | Bdo | Br | Cite | Code | Data | Dfn | Em | I | Kbd | Mark | Q | Rp | Rt | Ruby | S | Samp | Small | Span | Strong | Sub | Sup | Time | U | Var | Wbr | Area | Audio | Img | Map | Track | Video | Embed | Iframe | Object | Picture | Source | Canvas | Caption | Col | Colgroup | Table | Tbody | Td | Tfoot | Th | Thead | Tr | Button | Datalist | Fieldset | Form | Input | Label | Legend | Meter | Optgroup | Option | Output | Progress | Select | Textarea | Details | Dialog | Summary | Del | Ins
  let all_tags = [Html;Head;Body;Title;Base;Link;Meta;Style;Script;Noscript;Template;Slot;Address;Article;Aside;Footer;Header;Hgroup;Main;Nav;Section;Search;H1;H2;H3;H4;H5;H6;Blockquote;Div;Dl;Dt;Dd;Figure;Figcaption;Hr;Li;Menu;Ol;P;Pre;Ul;A;Abbr;B;Bdi;Bdo;Br;Cite;Code;Data;Dfn;Em;I;Kbd;Mark;Q;Rp;Rt;Ruby;S;Samp;Small;Span;Strong;Sub;Sup;Time;U;Var;Wbr;Area;Audio;Img;Map;Track;Video;Embed;Iframe;Object;Picture;Source;Canvas;Caption;Col;Colgroup;Table;Tbody;Td;Tfoot;Th;Thead;Tr;Button;Datalist;Fieldset;Form;Input;Label;Legend;Meter;Optgroup;Option;Output;Progress;Select;Textarea;Details;Dialog;Summary;Del;Ins]
  let tag_name = function
    | Html -> "html"
    | Head -> "head"
    | Body -> "body"
    | Title -> "title"
    | Base -> "base"
    | Link -> "link"
    | Meta -> "meta"
    | Style -> "style"
    | Script -> "script"
    | Noscript -> "noscript"
    | Template -> "template"
    | Slot -> "slot"
    | Address -> "address"
    | Article -> "article"
    | Aside -> "aside"
    | Footer -> "footer"
    | Header -> "header"
    | Hgroup -> "hgroup"
    | Main -> "main"
    | Nav -> "nav"
    | Section -> "section"
    | Search -> "search"
    | H1 -> "h1"
    | H2 -> "h2"
    | H3 -> "h3"
    | H4 -> "h4"
    | H5 -> "h5"
    | H6 -> "h6"
    | Blockquote -> "blockquote"
    | Div -> "div"
    | Dl -> "dl"
    | Dt -> "dt"
    | Dd -> "dd"
    | Figure -> "figure"
    | Figcaption -> "figcaption"
    | Hr -> "hr"
    | Li -> "li"
    | Menu -> "menu"
    | Ol -> "ol"
    | P -> "p"
    | Pre -> "pre"
    | Ul -> "ul"
    | A -> "a"
    | Abbr -> "abbr"
    | B -> "b"
    | Bdi -> "bdi"
    | Bdo -> "bdo"
    | Br -> "br"
    | Cite -> "cite"
    | Code -> "code"
    | Data -> "data"
    | Dfn -> "dfn"
    | Em -> "em"
    | I -> "i"
    | Kbd -> "kbd"
    | Mark -> "mark"
    | Q -> "q"
    | Rp -> "rp"
    | Rt -> "rt"
    | Ruby -> "ruby"
    | S -> "s"
    | Samp -> "samp"
    | Small -> "small"
    | Span -> "span"
    | Strong -> "strong"
    | Sub -> "sub"
    | Sup -> "sup"
    | Time -> "time"
    | U -> "u"
    | Var -> "var"
    | Wbr -> "wbr"
    | Area -> "area"
    | Audio -> "audio"
    | Img -> "img"
    | Map -> "map"
    | Track -> "track"
    | Video -> "video"
    | Embed -> "embed"
    | Iframe -> "iframe"
    | Object -> "object"
    | Picture -> "picture"
    | Source -> "source"
    | Canvas -> "canvas"
    | Caption -> "caption"
    | Col -> "col"
    | Colgroup -> "colgroup"
    | Table -> "table"
    | Tbody -> "tbody"
    | Td -> "td"
    | Tfoot -> "tfoot"
    | Th -> "th"
    | Thead -> "thead"
    | Tr -> "tr"
    | Button -> "button"
    | Datalist -> "datalist"
    | Fieldset -> "fieldset"
    | Form -> "form"
    | Input -> "input"
    | Label -> "label"
    | Legend -> "legend"
    | Meter -> "meter"
    | Optgroup -> "optgroup"
    | Option -> "option"
    | Output -> "output"
    | Progress -> "progress"
    | Select -> "select"
    | Textarea -> "textarea"
    | Details -> "details"
    | Dialog -> "dialog"
    | Summary -> "summary"
    | Del -> "del"
    | Ins -> "ins"
  type attribute =
    | Id of string | Class of string list | Href of string | Src of string | Srcset of string | Alt of string
    | Title_attr of string | Lang of string | Dir of string | Name of string | Value of string
    | Type of string | Rel of string | Target of string | Charset of string | Content_attr of string
    | For of string | List_attr of string | Placeholder of string | Label of string
    | Width of int | Height of int | Rows of int | Cols of int | Colspan of int
    | Min of string | Max of string | Low of string | High of string | Optimum of string
    | Open | Controls | Muted | Loop | Disabled | Checked | Selected | Multiple | Required
    | Data of string * string | Aria_label of string | Role of string | Tabindex of int
    | Datetime of string | Cite of string | Start of int | Span_attr of int
    | Usemap of string | Map_name of string | Shape of string | Coords of string
    | Kind of string | Srclang of string | Srcdoc of string | Sandbox of string
    | Loading of string | Data_uri of string | Scope of string
  type node = Text of string | Element of tag * attribute list * node list
  let text s = Text s
  let void = function Area|Base|Br|Col|Embed|Hr|Img|Input|Link|Meta|Source|Track|Wbr -> true | _ -> false
  let el tag attrs children =
    if void tag && children <> [] then invalid_arg ("void element has children: " ^ tag_name tag);
    Element (tag,attrs,children)
  let escape s =
    let b = Buffer.create 32 in
    String.iter (function '&'->Buffer.add_string b "&amp;"|'<'->Buffer.add_string b "&lt;"
      |'>'->Buffer.add_string b "&gt;"|'"'->Buffer.add_string b "&quot;"|'\''->Buffer.add_string b "&#39;"
      |c->Buffer.add_char b c) s; Buffer.contents b
  let attribute = function
    | Id s -> "id",s | Class xs -> "class",String.concat " " xs | Href s -> "href",s
    | Src s -> "src",s | Srcset s -> "srcset",s | Alt s -> "alt",s | Title_attr s -> "title",s | Lang s -> "lang",s
    | Dir s -> "dir",s | Name s -> "name",s | Value s -> "value",s | Type s -> "type",s
    | Rel s -> "rel",s | Target s -> "target",s | Charset s -> "charset",s
    | Content_attr s -> "content",s | For s -> "for",s | List_attr s -> "list",s
    | Placeholder s -> "placeholder",s | Label s -> "label",s | Width n -> "width",string_of_int n
    | Height n -> "height",string_of_int n | Rows n -> "rows",string_of_int n | Cols n -> "cols",string_of_int n
    | Colspan n -> "colspan",string_of_int n | Min s -> "min",s | Max s -> "max",s
    | Low s -> "low",s | High s -> "high",s | Optimum s -> "optimum",s
    | Open -> "open","" | Controls -> "controls","" | Muted -> "muted","" | Loop -> "loop",""
    | Disabled -> "disabled","" | Checked -> "checked","" | Selected -> "selected",""
    | Multiple -> "multiple","" | Required -> "required","" | Data (k,v) ->
        if Css.safe_ident k then "data-" ^ k,v else invalid_arg "invalid data attribute"
    | Aria_label s -> "aria-label",s | Role s -> "role",s | Tabindex n -> "tabindex",string_of_int n
    | Datetime s -> "datetime",s | Cite s -> "cite",s | Start n -> "start",string_of_int n
    | Span_attr n -> "span",string_of_int n | Usemap s -> "usemap",s | Map_name s -> "name",s
    | Shape s -> "shape",s | Coords s -> "coords",s | Kind s -> "kind",s | Srclang s -> "srclang",s
    | Srcdoc s -> "srcdoc",s | Sandbox s -> "sandbox",s | Loading s -> "loading",s
    | Data_uri s -> "data",s | Scope s -> "scope",s
  let render root =
    let b = Buffer.create 65536 in
    let rec emit = function
      | Text s -> Buffer.add_string b (escape s)
      | Element (tag,attrs,children) ->
          let name = tag_name tag in
          Buffer.add_string b ("<" ^ name);
          List.iter (fun attr -> let k,v = attribute attr in Buffer.add_string b (" " ^ k ^ "=\"" ^ escape v ^ "\"")) attrs;
          Buffer.add_char b '>';
          if not (void tag) then begin
            (match tag,children with
              | (Style|Script),[Text s] ->
                  (* Only internally generated CSS and escaped JSON enter raw-text nodes. *)
                  let lower = String.lowercase_ascii s in
                  let close = "</" ^ name in
                  let rec contains i = i + String.length close <= String.length lower &&
                    (String.sub lower i (String.length close) = close || contains (i+1)) in
                  if contains 0 then invalid_arg "raw-text closing-tag injection";
                  Buffer.add_string b s
              | (Style|Script),_ -> invalid_arg "raw-text elements require one text child"
              | _ -> List.iter emit children);
            Buffer.add_string b ("</" ^ name ^ ">")
          end
    in emit root; Buffer.contents b
  let counts root =
    let table = Hashtbl.create 128 in
    let rec visit = function Text _ -> () | Element (tag,_,children) ->
      let key = tag_name tag in
      Hashtbl.replace table key (1 + Option.value (Hashtbl.find_opt table key) ~default:0);
      List.iter visit children in
    visit root;
    List.map (fun tag -> let name = tag_name tag in name,Option.value (Hashtbl.find_opt table name) ~default:0) all_tags
end

open Html

let shuffle rng xs =
  let a = Array.of_list xs in
  for i = Array.length a - 1 downto 1 do
    let j = Random.State.int rng (i+1) in let tmp = a.(i) in a.(i) <- a.(j); a.(j) <- tmp
  done; Array.to_list a

let rec take n = function _ when n <= 0 -> [] | [] -> [] | x::xs -> x :: take (n-1) xs
let choose rng xs = List.nth xs (Random.State.int rng (List.length xs))
let uid n suffix = Printf.sprintf "sample-%d-%s" n suffix
let svg_uri = "data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='128' height='72' viewBox='0 0 128 72'%3E%3Crect width='128' height='72' rx='8' fill='%231c6a75'/%3E%3Ccircle cx='35' cy='36' r='20' fill='%23f6c96b'/%3E%3Cpath d='M65 55L90 15l25 40z' fill='%239de0d1'/%3E%3C/svg%3E"
let svg_uri = String.concat "%20" (String.split_on_char ' ' svg_uri)

let table_sample n =
  el Table [] [el Caption [] [text "A small spanning table"];
    el Colgroup [] [el Col [Span_attr 2] []];
    el Thead [] [el Tr [] [el Th [Scope "col"] [text "Item"];el Th [Scope "col"] [text "Value"]]];
    el Tbody [] [el Tr [] [el Td [] [text "alpha"];el Td [] [text (string_of_int n)]];
                el Tr [] [el Td [Colspan 2] [text "one cell, two columns"]]];
    el Tfoot [] [el Tr [] [el Td [] [text "total"];el Td [] [text "2"]]]]

let fixture n tag =
  let t = text and e = el in
  match tag with
  | Html|Head|Body|Title|Base|Link|Meta|Style|Script -> e P [] [t ("Document element: <" ^ tag_name tag ^ ">")]
  | Table|Caption|Colgroup|Col|Thead|Tbody|Tfoot|Tr|Td|Th -> table_sample n
  | Li|Ul|Menu -> e (if tag=Menu then Menu else Ul) [] [e Li [] [t "One wrapping item"]; e Li [] [t "A second, longer item"]]
  | Ol -> e Ol [Start 3] [e Li [] [t "Third"];e Li [] [t "Fourth"]]
  | Dl|Dt|Dd -> e Dl [] [e Dt [] [t "ADT"];e Dd [] [t "Algebraic data type"];e Dt [] [t "CSS"];e Dd [] [t "Cascading style sheets"]]
  | Figure|Figcaption -> e Figure [] [e Img [Src svg_uri;Alt "Circle and triangle";Width 128;Height 72] [];e Figcaption [] [t "An embedded SVG image"]]
  | Picture|Source -> e Picture [] [e Source [Srcset svg_uri;Type "image/svg+xml"] [];e Img [Src svg_uri;Alt "Self-contained image";Width 128;Height 72] []]
  | Img -> e Img [Src svg_uri;Alt "A gold circle beside a mint triangle";Width 128;Height 72] []
  | Details|Summary -> e Details [Open] [e Summary [] [t "Expand / collapse this specimen"];e P [] [t "Native disclosure content."]]
  | Fieldset|Legend -> e Fieldset [] [e Legend [] [t "Grouped controls"];e Label [] [t "A choice ";e Input [Type "checkbox";Checked] []]]
  | Form -> e Form [Aria_label "Example form"] [e Label [For (uid n "form-input")] [t "Name "];e Input [Id (uid n "form-input");Name "name";Placeholder "Ada"] [];e Button [Type "button"] [t "Local button"]]
  | Input -> e Div [] [e Input [Type "text";Aria_label "Sample text";Placeholder "Type here"] [];e Input [Type "range";Aria_label "Sample range";Min "0";Max "10";Value "6"] [];e Input [Type "color";Aria_label "Sample color";Value "#1c6a75"] []]
  | Label -> e Label [] [t "Toggle me ";e Input [Type "checkbox"] []]
  | Select|Option|Optgroup -> e Select [Aria_label "Choose an item"] [e Optgroup [Label "Letters"] [e Option [Value "a"] [t "Alpha"];e Option [Value "b";Selected] [t "Beta"]]]
  | Datalist -> e Div [] [e Input [Aria_label "Choose a language";List_attr (uid n "languages")] [];e Datalist [Id (uid n "languages")] [e Option [Value "OCaml"] [];e Option [Value "Coq"] []]]
  | Textarea -> e Textarea [Aria_label "Multiline specimen";Rows 2;Cols 20] [t "Two lines\nof editable text"]
  | Output -> e Output [Aria_label "Example result"] [t "42"]
  | Progress -> e Progress [Max "100";Value "67";Aria_label "Example progress"] [t "67%"]
  | Meter -> e Meter [Min "0";Max "100";Low "20";High "80";Optimum "60";Value "62";Aria_label "Example meter"] [t "62/100"]
  | Button -> e Button [Type "button"] [t "A native button"]
  | A -> e A [Href "#top"] [t "Back to the page index"]
  | Abbr -> e Abbr [Title_attr "Algebraic data type"] [t "ADT"]
  | Bdo -> e Bdo [Dir "rtl"] [t "Direction override"]
  | Bdi -> e P [] [t "Isolated name: ";e Bdi [Dir "auto"] [t "مرحبا"]]
  | Blockquote -> e Blockquote [] [e P [] [t "A quotation with its own block formatting."]]
  | Q -> e Q [] [t "Inline quotation"]
  | Pre -> e Pre [] [e Code [] [t "let box =\n  [ Html; Css; Random ]"]]
  | Ruby|Rt|Rp -> e Ruby [Lang "ja"] [t "漢";e Rp [] [t "("];e Rt [] [t "かん"];e Rp [] [t ")"]]
  | Audio -> e Audio [Controls;Aria_label "Audio control specimen"] [t "Audio controls; no external media is fetched."]
  | Video|Track -> e Video [Controls;Muted;Width 180;Height 100;Aria_label "Video control specimen"] [e Track [Kind "captions";Srclang "en";Label "English";Src "data:text/vtt,WEBVTT%0A%0A"] [];t "Video fallback content"]
  | Canvas -> e Canvas [Width 160;Height 80;Aria_label "Canvas with fallback text"] [t "Canvas fallback: a script-free canvas specimen."]
  | Iframe -> e Iframe [Title_attr "Isolated embedded document";Sandbox "";Loading "lazy";Srcdoc "<!doctype html><html lang='en'><meta charset='utf-8'><title>Frame</title><body style='background:#d7eee7;color:#123'>A sandboxed local document.</body></html>"] []
  | Embed -> e Embed [Src svg_uri;Type "image/svg+xml";Width 128;Height 72;Title_attr "Embedded SVG"] []
  | Object -> e Object [Data_uri svg_uri;Type "image/svg+xml";Width 128;Height 72;Aria_label "SVG object"] [t "Object fallback"]
  | Map|Area -> let name = uid n "map" in e Div [] [e Img [Src svg_uri;Alt "Mapped shapes";Width 128;Height 72;Usemap ("#" ^ name)] [];e Map [Map_name name] [e Area [Shape "rect";Coords "0,0,64,72";Href "#top";Alt "Page index"] []]]
  | Dialog -> e Dialog [Open;Aria_label "Non-modal specimen"] [t "An open, non-modal dialog."]
  | Template -> e Div [] [t "An inert template follows (its content is intentionally hidden).";e Template [] [e P [] [t "Template content"]]]
  | Slot -> e Slot [Name "example"] [t "Slot fallback without a shadow root"]
  | Noscript -> e Div [] [t "A noscript fallback is present in this specimen.";e Noscript [] [e P [] [t "Visible when scripting is disabled."]]]
  | Br -> e P [] [t "First line";e Br [] [];t "Second line"]
  | Wbr -> e P [] [t "a-long-unbroken";e Wbr [] [];t "-word-with-an-optional-break"]
  | Hr -> e Div [] [t "Above";e Hr [] [];t "Below"]
  | Time -> e Time [Datetime "2026-11-07"] [t "7 November 2026"]
  | Data -> e Data [Value "SKU-0042"] [t "Product forty-two"]
  | Del -> e Del [Datetime "2026-11-07"] [t "Removed wording"]
  | Ins -> e Ins [Datetime "2026-11-07"] [t "Inserted wording"]
  | Hgroup -> e Hgroup [] [e H3 [] [t "Grouped heading"];e P [] [t "A subtitle for the heading"]]
  | Address -> e Address [] [t "Example author · local specimen"]
  | Search -> e Search [Aria_label "Example search"] [e Label [] [t "Search ";e Input [Type "search";Placeholder "Search this specimen"] []]]
  | Article|Aside|Section|Nav|Main|Header|Footer|Div ->
      (* main cannot be nested in the document main; it appears once as the outer wrapper. *)
      if tag=Main then e P [] [t "The document's outer main contains this specimen."]
      else e tag [] [e P [] [t ("A <" ^ tag_name tag ^ "> block with inline ");e Strong [] [t "emphasis"];t " and wrapping text."]]
  | H1|H2|H3|H4|H5|H6 -> e tag [] [t ("Heading specimen " ^ tag_name tag)]
  | P -> e P [] [t "A paragraph with ";e Em [] [t "emphasis"];t ", ";e Strong [] [t "importance"];t ", and a longer run of text to test wrapping and intrinsic sizing."]
  | _ -> e tag [] [t (match tag with
      | Code -> "List.map render boxes" | Kbd -> "Ctrl + Enter" | Samp -> "OK: 512 boxes"
      | Var -> "available_width" | Small -> "Small print and secondary information"
      | Sub -> "subscript" | Sup -> "superscript" | Mark -> "highlighted text"
      | S -> "no longer accurate" | U -> "annotated wording" | Dfn -> "semantic model"
      | Cite -> "The generated specimen" | I -> "alternate voice" | B -> "attention"
      | _ -> "Inline specimen: " ^ tag_name tag)]

module Stylesheet = struct
  type pseudo = Hover | Focus_within | Before | First_child | Nth_even
  type selector = Surface | Pseudo of pseudo | Children | Child_pseudo of pseudo
  type media = Narrow | Dark | Reduced_motion
  type rule =
    | Rule of selector * Css.declaration list
    | Media of media * rule list
    | Supports of Css.property * Css.value * rule list
  let pseudo = function Hover->":hover"|Focus_within->":focus-within"|Before->"::before"
    |First_child->":first-child"|Nth_even->":nth-child(even)"
  let selector scope = function
    | Surface -> scope | Pseudo p -> scope ^ pseudo p
    | Children -> scope ^ " > *" | Child_pseudo p -> scope ^ " > *" ^ pseudo p
  let rec render scope = function
    | Rule (s,ds) -> selector scope s ^ "{" ^ Css.declarations ds ^ "}\n"
    | Media (query,rules) ->
        let query = match query with Narrow->"(max-width: 640px)"|Dark->"(prefers-color-scheme: dark)"|Reduced_motion->"(prefers-reduced-motion: reduce)" in
        "@media " ^ query ^ "{" ^ String.concat "" (List.map (render scope) rules) ^ "}\n"
    | Supports (p,v,rules) -> "@supports (" ^ Css.property_name p ^ ":" ^ Css.value v ^ "){" ^
        String.concat "" (List.map (render scope) rules) ^ "}\n"
end

type feature = Property of Css.property * Css.value list
  | Hover_state | Focus_state | Generated_content | Child_stripes | Responsive_layout
  | Grid_support | Dark_palette | Motion_preference | Nested_flex

let feature_id = function
  | Property (p,_) -> "property:" ^ Css.property_name p
  | Hover_state -> "rule:hover" | Focus_state -> "rule:focus-within"
  | Generated_content -> "rule:before" | Child_stripes -> "rule:nth-child"
  | Responsive_layout -> "rule:media-width" | Grid_support -> "rule:supports-grid"
  | Dark_palette -> "rule:media-color-scheme" | Motion_preference -> "rule:media-reduced-motion"
  | Nested_flex -> "rule:child-flex"

let features = List.map (fun (p,_,values) -> Property (p,values)) Css.catalog @
  [Hover_state;Focus_state;Generated_content;Child_stripes;Responsive_layout;
   Grid_support;Dark_palette;Motion_preference;Nested_flex]

let extra_rule =
  let open Css in let open Stylesheet in function
  | Property _ -> invalid_arg "declaration is not a rule"
  | Hover_state -> Rule (Pseudo Hover,[BackgroundColor,color "ffefbd";Outline,seq [px 2;kw "solid";color "b9802d"]])
  | Focus_state -> Rule (Pseudo Focus_within,[Outline,seq [px 3;kw "solid";color "166b74"]])
  | Generated_content -> Rule (Pseudo Before,[Content,Css.Text "CSS ::before · ";Color,color "965a26";FontWeight,num 700])
  | Child_stripes -> Rule (Child_pseudo Nth_even,[BackgroundColor,color "dee8ed";BorderRadius,px 5])
  | Responsive_layout -> Media (Narrow,[Rule (Surface,[Display,kw "block";ColumnCount,num 1;WritingMode,kw "horizontal-tb"])])
  | Grid_support -> Supports (Display,kw "grid",[Rule (Surface,[Display,kw "grid";GridTemplateColumns,fn Repeat [num 2;fn Minmax [px 0;Length (1.,Fr)]];Gap,px 5])])
  | Dark_palette -> Media (Dark,[Rule (Surface,[Color,color "f1f0df";BackgroundColor,color "25444b"])])
  | Motion_preference -> Media (Reduced_motion,[Rule (Surface,[AnimationName,kw "none";TransitionDuration,Seconds 0.])])
  | Nested_flex -> Rule (Children,[Flex,seq [num 1;num 1;px 70];MinWidth,px 0])

let baseline = {|
:root{color-scheme:light;--ink:#173c43;--paper:#f3f0e5;--accent:#eab65c;font-family:system-ui,sans-serif;background:var(--paper);color:var(--ink)}
*{box-sizing:border-box}body{margin:0}a{color:inherit}button,input,select,textarea{font:inherit;max-width:100%}
.masthead{background:#103b43;color:#f8f2dc;padding:36px max(24px,calc((100vw - 1440px)/2));border-bottom:6px solid var(--accent)}
.eyebrow{font:700 11px ui-monospace,monospace;letter-spacing:.18em;text-transform:uppercase;color:#b8d6cd}
.masthead h1{font-size:clamp(30px,5vw,64px);letter-spacing:-.05em;line-height:1.05;margin:15px 0}
.masthead p{max-width:75ch;line-height:1.65;color:#d3e1d7}.stats{display:flex;gap:12px;flex-wrap:wrap;margin-top:22px}
.stat{border:1px solid #66817b;border-radius:6px;padding:8px 13px;font:12px ui-monospace,monospace}.stat strong{font-size:22px;color:#f4ca7b;margin-right:6px}
.jumpbar{position:sticky;top:0;z-index:10;display:flex;gap:8px;align-items:center;flex-wrap:wrap;padding:12px 24px;background:#f3f0e5f5;border-bottom:1px solid #c1cec3;backdrop-filter:blur(8px)}
.jumpbar a{font:11px ui-monospace,monospace;text-decoration:none;border:1px solid #a7bbb0;border-radius:20px;padding:5px 10px}.jumpbar a:hover{background:#eac382}
main{max-width:1488px;margin:auto;padding:24px}.intro{font-size:14px;line-height:1.7;max-width:95ch}.atlas{margin:24px 0;padding:15px;background:#e4e9df;border:1px solid #b9c8ba;border-radius:8px}.atlas>summary{font-weight:700;cursor:pointer}.atlas-grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(220px,1fr));gap:12px;margin-top:18px}.atlas-card{background:#fffdf4;border-radius:5px;padding:12px;min-width:0;overflow:auto}.atlas-card h3{font:12px ui-monospace,monospace;margin:0 0 10px;color:#6a5d41}.atlas-sample{max-height:200px;overflow:auto;position:relative}
.level{margin:44px 0;scroll-margin-top:110px}.level-heading{display:flex;gap:16px;align-items:baseline;flex-wrap:wrap;border-top:2px solid #1d5157;padding-top:15px}.level-heading h2{font-size:25px;letter-spacing:-.03em;margin:0}.level-heading p{font:12px ui-monospace,monospace;color:#5f7164}.level-grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(310px,1fr));gap:18px;margin-top:18px}
.specimen{border:1px solid #bccabd;border-radius:9px;background:#fffdf5;overflow:hidden;min-width:0;content-visibility:auto;contain-intrinsic-size:360px}.specimen-header{padding:12px 14px;display:flex;align-items:center;justify-content:space-between;gap:8px;border-bottom:1px solid #d8dfd1;background:#e8ece2;font:11px ui-monospace,monospace}.box-number{font-weight:800}.badge{background:#234e52;color:#ffefc2;border-radius:15px;padding:4px 9px}.viewport{height:230px;overflow:auto;position:relative;padding:10px;isolation:isolate;background:repeating-linear-gradient(135deg,#fffdf5,#fffdf5 12px,#f4f4e9 12px,#f4f4e9 24px)}
.surface{font-size:14px;line-height:1.45;min-width:0;max-width:100%;padding:8px;background:#e7f1e8;color:#153e43;position:relative;--monster-accent:#16786e}.surface>*{min-width:0}.surface img,.atlas img{max-width:100%;height:auto}.surface p{margin:.5em 0}.surface table,.atlas table{border-collapse:collapse}.surface td,.surface th,.atlas td,.atlas th{border:1px solid #9cb8b2;padding:3px 6px}.surface dialog,.atlas dialog{position:relative;margin:0;max-width:100%}.surface figure,.atlas figure{margin:4px}.surface iframe{max-width:100%;height:95px;border:1px solid #aac0b7}.surface video,.surface audio{max-width:100%}.surface canvas{border:1px dashed #6c8d8a}.surface fieldset{min-width:0}.surface .payload{padding:5px;border:1px dashed #8da99b;border-radius:4px}.feature-list{padding:9px 14px;font:11px/1.5 ui-monospace,monospace;max-height:90px;overflow:auto;border-top:1px solid #dde2d4;color:#4e685b}.feature-list summary{cursor:pointer}.feature-list code{overflow-wrap:anywhere}.page-footer{border-top:1px solid #b5c4b6;padding:25px;font:12px/1.7 ui-monospace,monospace;color:#58705f}
@keyframes monster-breathe{from{opacity:.93}to{opacity:1}}
@media(max-width:640px){main{padding:14px}.level-grid{grid-template-columns:minmax(0,1fr)}.masthead{padding:25px 20px}.jumpbar{position:relative}.level{scroll-margin-top:12px}}
@media(prefers-reduced-motion:reduce){.surface,.surface *{animation:none!important;transition:none!important;scroll-behavior:auto!important}}
|}

type box_record = { index:int; level:int; tag:tag; selected:feature list; declarations:Css.declaration list }

let metadata_tags = [Html;Head;Body;Title;Base;Link;Meta;Style;Script]
let body_tags = List.filter (fun t -> not (List.mem t metadata_tags) && t <> Main) all_tags

let generate ~boxes ~levels ~seed =
  let rng = Random.State.make [|seed|] in
  let levels = min levels boxes in
  let feature_count = List.length features in
  let tag_order = Array.of_list (shuffle rng body_tags) in
  let records = List.init boxes (fun i ->
    let level = if boxes=1 then 0 else (i * levels) / boxes in
    let quota = if levels=1 then feature_count else 1 + level * (feature_count-1) / (levels-1) in
    let selected = take quota (shuffle rng features) in
    let declarations = List.filter_map (function Property (p,values) -> Some (p,choose rng values) | _ -> None) selected in
    {index=i;level;tag=tag_order.(i mod Array.length tag_order);selected;declarations}) in
  let css = Buffer.create (boxes * 1500) in
  Buffer.add_string css baseline;
  List.iter (fun box ->
    let scope = Printf.sprintf "#surface-%d" box.index in
    Buffer.add_string css (Stylesheet.render scope (Stylesheet.Rule (Stylesheet.Surface,box.declarations)));
    List.iter (function Property _ -> () | f -> Buffer.add_string css (Stylesheet.render scope (extra_rule f))) box.selected) records;
  let card box =
    let count = List.length box.selected in
    el Article [Class ["specimen"];Id (Printf.sprintf "box-%d" box.index);Data ("level",string_of_int (box.level+1));Data ("feature-count",string_of_int count)] [
      el Header [Class ["specimen-header"]] [el Span [Class ["box-number"]] [text (Printf.sprintf "BOX %04d · <%s>" (box.index+1) (tag_name box.tag))];el Span [Class ["badge"]] [text (Printf.sprintf "%d / %d" count feature_count)]];
      el Div [Class ["viewport"]] [el Div [Id (Printf.sprintf "surface-%d" box.index);Class ["surface"];Tabindex 0] [fixture box.index box.tag;
        el Div [Class ["payload"]] [text "A second sibling with long-ish content, ";el Strong [] [text "strong text"];text ", and unbreakable_0123456789_abcdefghij."];
        el Div [Class ["payload"]] [el Span [] [text "Third child · "];el Code [] [text "min-content / max-content"]]]];
      el Details [Class ["feature-list"]] [el Summary [] [text "Inspect selected features"];el Code [] [text (String.concat " · " (List.map feature_id box.selected))]]
    ] in
  let level_nodes = List.init levels (fun level ->
    let members = List.filter (fun b -> b.level=level) records in
    let quota = List.length (List.hd members).selected in
    el Section [Class ["level"];Id (Printf.sprintf "level-%d" (level+1));Data ("level",string_of_int (level+1))] [
      el Div [Class ["level-heading"]] [el H2 [] [text (Printf.sprintf "Level %02d" (level+1))];el P [] [text (Printf.sprintf "%d randomly selected features per box · %d boxes" quota (List.length members))]];
      el Div [Class ["level-grid"]] (List.map card members)]) in
  let atlas = el Details [Class ["atlas"];Id "atlas"] [
    el Summary [] [text (Printf.sprintf "HTML element atlas · all %d supported tags are present in this document" (List.length all_tags))];
    el P [Class ["intro"]] [text "Document-only tags live in the head or document scaffold. Context-sensitive tags get complete surrounding structures. Templates and fallback elements remain intentionally inert or conditional."];
    el Div [Class ["atlas-grid"]] (List.mapi (fun i tag ->
      el Article [Class ["atlas-card"]] [el H3 [] [text ("<" ^ tag_name tag ^ ">")];el Div [Class ["atlas-sample"]] [fixture (boxes+i) tag]]) body_tags)] in
  let stat n label = el Div [Class ["stat"]] [el Strong [] [text (string_of_int n)];text label] in
  let title = "HTML × CSS — the combinatorial monster" in
  let root = el Html [Lang "en"] [
    el Head [] [el Meta [Charset "utf-8"] [];el Meta [Name "viewport";Content_attr "width=device-width, initial-scale=1"] [];
      el Title [] [text title];el Base [Target "_self"] [];el Link [Rel "icon";Href svg_uri] [];
      el Style [] [text (Buffer.contents css)];el Script [Type "application/json";Id "generation-config"] [text (Json.render (Json.Object ["seed",Json.Int seed;"boxes",Json.Int boxes;"levels",Json.Int levels]))]];
    el Body [] [el Header [Class ["masthead"];Id "top"] [el Div [Class ["eyebrow"]] [text "OCaml / algebraic data types / seeded combinatorics"];
      el H1 [] [text "The HTML × CSS monster."];
      el P [] [text "A progressively denser specimen field: ordinary markup at the start, increasingly crowded CSS combinations toward the end. Every box is independently randomized; every selection can be inspected."];
      el Div [Class ["stats"]] [stat boxes "stress boxes";stat (List.length all_tags) "HTML tags";stat (List.length Css.catalog) "CSS properties";stat feature_count "total feature types";stat seed "seed"]];
      el Nav [Class ["jumpbar"];Aria_label "Jump to difficulty level"] (el A [Href "#atlas"] [text "Element atlas"] :: List.init levels (fun n -> el A [Href (Printf.sprintf "#level-%d" (n+1))] [text (Printf.sprintf "%02d" (n+1))]));
      el Main [] (el P [Class ["intro"]] [text "The number of selected features grows monotonically with level; feature identities and declaration values vary by seed. The final level exercises the full catalog. Styles are scoped to specimen surfaces. There are no external dependencies or executable scripts."] :: atlas :: level_nodes);
      el Footer [Class ["page-footer"]] [text (Printf.sprintf "Generated by the OCaml ADT tool · seed %d. Reproduce with --boxes %d --levels %d --seed %d. This is a common-authoring catalog, not a measured claim of 90%% web usage or a full standards conformance suite." seed boxes levels seed)]]
  ] in
  let tag_counts = Html.counts root in
  if List.exists (fun (_,count) -> count=0) tag_counts then failwith "internal error: missing catalog tag";
  let feature_usage = List.map (fun f -> feature_id f,List.fold_left (fun n b -> n + if List.mem f b.selected then 1 else 0) 0 records) features in
  if List.exists (fun (_,count) -> count=0) feature_usage then failwith "internal error: missing catalog feature";
  let json_names xs = Json.Array (List.map (fun s -> Json.String s) xs) in
  let manifest = Json.Object [
    "format_version",Json.Int 1;"seed",Json.Int seed;"box_count",Json.Int boxes;"level_count",Json.Int levels;
    "html_tag_count",Json.Int (List.length all_tags);"css_property_count",Json.Int (List.length Css.catalog);
    "feature_count",Json.Int feature_count;
    "coverage_basis",Json.String "Explicit common-authoring catalog; no measured frequency dataset or 90-percent usage claim.";
    "html_tag_counts",Json.Object (List.map (fun (name,n)->name,Json.Int n) tag_counts);
    "css_properties",json_names (List.map (fun (_,name,_)->name) Css.catalog);
    "feature_usage",Json.Object (List.map (fun (name,n)->name,Json.Int n) feature_usage);
    "boxes",Json.Array (List.map (fun b -> Json.Object [
      "index",Json.Int b.index;"level",Json.Int (b.level+1);"sample_tag",Json.String (tag_name b.tag);
      "feature_count",Json.Int (List.length b.selected);"feature_ids",json_names (List.map feature_id b.selected);
      "declarations",Json.String (Css.declarations b.declarations)]) records)] in
  "<!doctype html>\n" ^ Html.render root ^ "\n", Json.render manifest ^ "\n"

let write_file path contents =
  let channel = open_out_bin path in
  Fun.protect ~finally:(fun () -> close_out channel) (fun () -> output_string channel contents)

let normalized_path path =
  let path = if Filename.is_relative path then Filename.concat (Sys.getcwd ()) path else path in
  let parts = List.fold_left (fun stack -> function
    | "" | "." -> stack | ".." -> (match stack with []->[]|_::rest->rest) | part -> part::stack)
      [] (String.split_on_char '/' path) in
  "/" ^ String.concat "/" (List.rev parts)

let self_test () =
  let expect_invalid f = try ignore (f ()); failwith "expected rejection" with Invalid_argument _ -> () in
  if Html.escape "<&\"'>" <> "&lt;&amp;&quot;&#39;&gt;" then failwith "HTML escaping failed";
  expect_invalid (fun () -> el Input [] [text "not permitted"]);
  expect_invalid (fun () -> Css.value (Css.Keyword "red;display:none"));
  expect_invalid (fun () -> Css.value (Css.Color "not-hex"));
  expect_invalid (fun () -> Html.render (el Style [] [text "</style><script>bad</script>"]));
  if Css.value (Css.Text "</style>") <> "\"\\3c /style>\"" then failwith "CSS escaping failed";
  if List.length all_tags <> List.length (List.sort_uniq compare all_tags) then failwith "duplicate tag";
  if List.length features <> List.length (List.sort_uniq compare (List.map feature_id features)) then failwith "duplicate feature";
  if List.exists (fun (_,_,values) -> values=[]) Css.catalog then failwith "empty sample set";
  Printf.printf "ADT catalog and escaping checks passed.\n"

let () =
  let boxes = ref 512 and levels = ref 24 and seed = ref 20261107 in
  let output = ref "monster.html" and manifest_path = ref "" in
  let tests = ref false in
  let options = [
    "--boxes",Arg.Set_int boxes,"N Number of stress boxes (default 512)";
    "--levels",Arg.Set_int levels,"N Difficulty levels (default 24; capped at box count)";
    "--seed",Arg.Set_int seed,"N Deterministic random seed";
    "--out",Arg.Set_string output,"PATH HTML output path";
    "--manifest",Arg.Set_string manifest_path,"PATH JSON output path (default OUT.json)";
    "--self-test",Arg.Set tests," Run ADT, escaping and catalog checks without writing a page"
  ] in
  try
    Arg.parse options (fun s -> raise (Arg.Bad ("unexpected argument: " ^ s))) "monster [OPTIONS]";
    if !tests then (self_test (); exit 0);
    if !boxes < 1 || !boxes > 10000 then invalid_arg "--boxes must be between 1 and 10000";
    if !levels < 1 || !levels > 256 then invalid_arg "--levels must be between 1 and 256";
    let manifest_path = if !manifest_path="" then !output ^ ".json" else !manifest_path in
    if normalized_path manifest_path = normalized_path !output then invalid_arg "HTML and manifest paths must differ";
    let html,manifest = generate ~boxes:!boxes ~levels:!levels ~seed:!seed in
    write_file !output html; write_file manifest_path manifest;
    Printf.printf "Wrote %s (%d bytes) and %s\n%d boxes; %d HTML tags; %d CSS properties; %d feature types; seed %d\n"
      !output (String.length html) manifest_path !boxes (List.length all_tags) (List.length Css.catalog) (List.length features) !seed
  with Invalid_argument message | Sys_error message | Failure message ->
    Printf.eprintf "error: %s\n" message; exit 2
