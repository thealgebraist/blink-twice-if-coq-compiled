### 1. Core Data Structures in Chromium Blink

In Chromium's LayoutNG (Blink), scrollbar gutter reservation is computed during box fragment generation and constraint space construction. The relevant C++ types (located primarily in `third_party/blink/renderer/core/layout/` and `third_party/blink/renderer/core/style/`) are:

1. **`NGBoxStrut` (now `BoxStrut` in modern Blink)**:
   Represents logical directional offsets (`inline_start`, `inline_end`, `block_start`, `block_end`) in `LayoutUnit` (fixed-point representation, typically $1/64\text{th}$ of a pixel, modeled here in $\mathbb{N}$ or $\mathbb{Z}_{\ge 0}$).
   ```cpp
   struct BoxStrut {
     LayoutUnit inline_start;
     LayoutUnit inline_end;
     LayoutUnit block_start;
     LayoutUnit block_end;
     LayoutUnit InlineSum() const { return inline_start + inline_end; }
   };
   ```

2. **`EScrollbarWidth` (CSS `scrollbar-width`)**:
   Defined in `computed_style_constants.h` per CSS Scrollbars Styling Module Level 1:
   - `kAuto`: Platform default scrollbar thickness (e.g., `16px`).
   - `kThin`: Thin variant scrollbar thickness (e.g., `8px`).
   - `kNone`: Suppresses scrollbar display entirely (`0px`).

3. **`ScrollbarGutter` (CSS `scrollbar-gutter`)**:
   Defined in CSS Overflow Module Level 3 (interoperating with CSS Scrollbars Level 1):
   - `kAuto`: Space is reserved only when the classic scrollbar is actually present (`overflow: scroll`, or `overflow: auto` when content overflows).
   - `kStable`: Space is deterministically reserved if `overflow` allows scrolling (`auto`, `scroll`, `hidden`), regardless of whether content currently overflows.
   - `kBothEdges`: A modifier bit/flag coupled with `kStable` indicating that the inline-start edge must mirror the inline-end reservation.

---

### 2. Reserved Gutter Width Computation

Blink calculates the single-scrollbar thickness $T$ via `ScrollableArea::HypotheticalScrollbarThickness` and `LayoutBox::ComputeLogicalScrollbars`:

$$T(\text{width\_mode}) = \begin{cases} 0 & \text{if } \text{width\_mode} = \text{None} \\ T_{\text{thin}} & \text{if } \text{width\_mode} = \text{Thin} \\ T_{\text{default}} & \text{if } \text{width\_mode} = \text{Auto} \end{cases}$$

*(Note: For overlay scrollbars, OS settings may force $T = 0$, except when overridden by specific non-overlay testing flags. Here we audit classic/non-overlay layout gutters).*

Let $\text{has\_v\_scrollbar} \in \{\text{true}, \text{false}\}$ denote whether the vertical scrollbar is actively triggered by overflow/style. The inline gutter strut $(G_{\text{start}}, G_{\text{end}})$ is computed as:

1. **Case `scrollbar-gutter: auto`**:
   $$G_{\text{start}} = 0, \quad G_{\text{end}} = \begin{cases} T(\text{width\_mode}) & \text{if } \text{has\_v\_scrollbar} \\ 0 & \text{otherwise} \end{cases}$$

2. **Case `scrollbar-gutter: stable`**:
   $$G_{\text{start}} = 0, \quad G_{\text{end}} = T(\text{width\_mode})$$

3. **Case `scrollbar-gutter: stable both-edges`**:
   $$G_{\text{start}} = T(\text{width\_mode}), \quad G_{\text{end}} = T(\text{width\_mode})$$

*(Assuming standard LTR `horizontal-tb` directionality where vertical scrollbars are placed on `inline_end` unless `direction: rtl` or specific scrollbar placement rules apply).*

---

### 3. Impact on Available Content Inline Size

During `ComputeContentSize` / `FragmentGeometry` evaluation in Blink, the border-box inline size $W_{\text{box}}$ is reduced by the `BorderPadding` inline sum and the `Scrollbars` (gutter) inline sum, clamped at $0$:

$$G_{\text{total}} = G_{\text{start}} + G_{\text{end}}$$
$$W_{\text{content}} = \max\Big(0, \, W_{\text{box}} - \big(\text{padding}_{\text{inline}} + \text{border}_{\text{inline}} + G_{\text{total}}\big)\Big)$$

In `nat` (natural number arithmetic in Rocq/Coq), truncated subtraction (`-`) naturally implements $\max(0, A - B)$.

---

### 4. Mathematical Invariants

1. **Non-negativity of Reserved Gutters**:
   $$\forall \text{cfg}, \quad G_{\text{start}} \ge 0 \land G_{\text{end}} \ge 0 \land G_{\text{total}} \ge 0$$
2. **Content Box Contraction Bound**:
   $$\forall W_{\text{box}}, \quad W_{\text{content}} \le W_{\text{box}}$$
3. **Determinism of Layout Geometry**:
   Given identical style inputs (`ScrollbarWidth`, `ScrollbarGutter`), platform metrics, and box constraints, the resulting `NGBoxStrut` and $W_{\text{content}}$ are unique.
4. **Suppression Invariant (`scrollbar-width: none`)**:
   $$\text{width\_mode} = \text{None} \implies G_{\text{start}} = 0 \land G_{\text{end}} = 0$$
   (Wait: Per CSS Scrollbars Level 1 § 2.1 and CSS Overflow Level 3, `scrollbar-width: none` forces the scrollbar thickness to zero, which collapses `scrollbar-gutter: stable` to `0px`).

---

### 5. Rocq / Coq Formalization (`BlinkScrollbarGutterSemantics.v`)

Below is a complete, self-contained, and verified Coq/Rocq development encoding these semantics and proving the core audit invariants.

```coq
(** * BlinkScrollbarGutterSemantics.v
    Formalization of Chromium Blink Scrollbar Gutter Reservation vs CSS Scrollbars Level 1.
    Agent 59 Audit Artifact. *)

From Coq Require Import Arith.PeanoNat.
From Coq Require Import Lia.

Module BlinkScrollbarGutterSemantics.

  (** ** 1. Core Data Structures *)

  (** CSS Scrollbars Level 1: [scrollbar-width] *)
  Inductive ScrollbarWidth : Type :=
  | SW_Auto : ScrollbarWidth
  | SW_Thin : ScrollbarWidth
  | SW_None : ScrollbarWidth.

  (** CSS Overflow Level 3: [scrollbar-gutter] *)
  Inductive ScrollbarGutter : Type :=
  | SG_Auto            : ScrollbarGutter
  | SG_Stable          : ScrollbarGutter
  | SG_StableBothEdges : ScrollbarGutter.

  (** Platform theme constants for classic (non-overlay) scrollbars *)
  Record PlatformScrollbarTheme : Type := mkTheme {
    default_width : nat; (* e.g., 16px *)
    thin_width    : nat; (* e.g., 8px  *)
    theme_thin_le_default : thin_width <= default_width
  }.

  (** Blink's [NGBoxStrut] (logical directional offsets in LayoutUnits/px) *)
  Record NGBoxStrut : Type := mkBoxStrut {
    inline_start : nat;
    inline_end   : nat;
    block_start  : nat;
    block_end    : nat
  }.

  Definition InlineSum (s : NGBoxStrut) : nat :=
    s.(inline_start) + s.(inline_end).

  (** ** 2. Reserved Gutter Width Computation *)

  (** Resolves single scrollbar thickness from [scrollbar-width] and theme *)
  Definition compute_scrollbar_thickness
    (theme : PlatformScrollbarTheme) (sw : ScrollbarWidth) : nat :=
    match sw with
    | SW_None => 0
    | SW_Thin => theme.(thin_width)
    | SW_Auto => theme.(default_width)
    end.

  (** Computes the logical scrollbar gutter strut (Blink's [ComputeLogicalScrollbars]) *)
  Definition compute_scrollbar_gutter_strut
    (theme : PlatformScrollbarTheme)
    (sw : ScrollbarWidth)
    (sg : ScrollbarGutter)
    (has_active_vertical_scrollbar : bool) : NGBoxStrut :=
    let thickness := compute_scrollbar_thickness theme sw in
    match sg with
    | SG_Auto =>
        if has_active_vertical_scrollbar then
          mkBoxStrut 0 thickness 0 0
        else
          mkBoxStrut 0 0 0 0
    | SG_Stable =>
        mkBoxStrut 0 thickness 0 0
    | SG_StableBothEdges =>
        mkBoxStrut thickness thickness 0 0
    end.

  (** ** 3. Impact on Available Content Inline Size *)

  (** Note: In [nat], subtraction [a - b] is truncated at 0, which is definitionally
      equivalent to [max(0, a - b)] over integers. *)
  Definition compute_available_content_inline_size
    (w_box : nat)
    (padding_inline border_inline : nat)
    (gutter_strut : NGBoxStrut) : nat :=
    w_box - (padding_inline + border_inline + InlineSum gutter_strut).

  (** ** 4. Mathematical Invariants and Audit Theorems *)

  (** Invariant 1: Reserved gutter inline sum is always non-negative. *)
  Theorem reserved_gutter_non_negative :
    forall theme sw sg active,
      0 <= InlineSum (compute_scrollbar_gutter_strut theme sw sg active).
  Proof.
    intros. lia.
  Qed.

  (** Invariant 2: Available content inline size never exceeds border-box inline size. *)
  Theorem content_size_le_box_size :
    forall w_box padding border theme sw sg active,
      let strut := compute_scrollbar_gutter_strut theme sw sg active in
      compute_available_content_inline_size w_box padding border strut <= w_box.
  Proof.
    intros. unfold compute_available_content_inline_size. lia.
  Qed.

  (** Invariant 3: Determinism of gutter computation and content inline size. *)
  Theorem gutter_computation_deterministic :
    forall theme sw sg active s1 s2,
      s1 = compute_scrollbar_gutter_strut theme sw sg active ->
      s2 = compute_scrollbar_gutter_strut theme sw sg active ->
      s1 = s2.
  Proof.
    intros. subst. reflexivity.
  Qed.

  (** Invariant 4: CSS Scrollbars L1 compliance - [scrollbar-width: none] forces
      zero gutter reservation even when [scrollbar-gutter] is [stable] or [both-edges]. *)
  Theorem scrollbar_width_none_zeroes_gutter :
    forall theme sg active,
      InlineSum (compute_scrollbar_gutter_strut theme SW_None sg active) = 0.
  Proof.
    intros theme sg active.
    unfold compute_scrollbar_gutter_strut, compute_scrollbar_thickness, InlineSum.
    destruct sg; simpl.
    - destruct active; simpl; reflexivity.
    - reflexivity.
    - reflexivity.
  Qed.

  (** Invariant 5: [stable both-edges] reserves exactly twice the inline space of [stable]. *)
  Theorem both_edges_doubles_stable_reservation :
    forall theme sw active,
      InlineSum (compute_scrollbar_gutter_strut theme sw SG_StableBothEdges active) =
      2 * InlineSum (compute_scrollbar_gutter_strut theme sw SG_Stable active).
  Proof.
    intros theme sw active.
    unfold compute_scrollbar_gutter_strut, InlineSum. simpl. lia.
  Qed.

  (** Invariant 6: Monotonicity of content size with respect to scrollbar width.
      A [thin] scrollbar always yields greater or equal content inline size than [auto]. *)
  Theorem thin_scrollbar_preserves_more_content_space_than_auto :
    forall w_box padding border theme sg active,
      let strut_thin := compute_scrollbar_gutter_strut theme SW_Thin sg active in
      let strut_auto := compute_scrollbar_gutter_strut theme SW_Auto sg active in
      compute_available_content_inline_size w_box padding border strut_auto <=
      compute_available_content_inline_size w_box padding border strut_thin.
  Proof.
    intros w_box padding border theme sg active strut_thin strut_auto.
    unfold strut_thin, strut_auto, compute_available_content_inline_size,
           compute_scrollbar_gutter_strut, compute_scrollbar_thickness, InlineSum.
    pose proof (theme_thin_le_default theme) as Hle.
    destruct sg; simpl.
    - destruct active; simpl; lia.
    - lia.
    - lia.
  Qed.

End BlinkScrollbarGutterSemantics.
```