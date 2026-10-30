### 1. Text Decoration Line Geometry

In Chromium Blink (`ng_text_decoration_offset.cc`, `text_decoration_info.cc`), text decoration geometry is resolved relative to the font metrics of the decorating box and the inline layout's alphabetic baseline ($B = 0$ in local baseline-relative coordinates, where $+y$ points downward in screen space, or $+y$ points upward in standard Cartesian font space; below we adopt standard Cartesian font space where $+y$ is upward, $B = 0$, Ascent $A > 0$, Descent $D < 0$).

*   **Thickness ($T$):** 
    Resolved from `text-decoration-thickness` (auto, from-font, length, or percentage). Blink enforces a device-pixel minimum floor:
    $$T = \max(1, \text{round}(\text{resolved\_thickness}))$$
    Hence $T \ge 1$ (in layout/device units).
*   **Vertical Offset ($Y$):**
    The vertical coordinate $Y$ represents the bottom edge (or top edge depending on coordinate convention; here, the lower bound $[Y, Y+T]$) of the decoration stroke relative to the alphabetic baseline $B = 0$.

---

### 2. Positioning Rules (CSS Text Decoration 3 §2 vs. Blink)

Let the font metrics be characterized by Ascent $A > 0$, Descent $D < 0$, Cap-Height $C \in (0, A]$, and font-defined underline position $U_{\text{font}} \le 0$ and gap $G \ge 1$.

1.  **Underline (Below Baseline):**
    Positioned below the alphabetic baseline ($Y + T \le 0$). In Blink, for `text-underline-position: auto`, the offset is computed as:
    $$Y_{\text{under}} = \min(-G, U_{\text{font}}) - T$$
    guaranteeing the entire stroke $[Y_{\text{under}}, Y_{\text{under}} + T]$ lies strictly below or at the baseline ($Y_{\text{under}} + T \le -G < 0$).
2.  **Overline (Above Ascent):**
    Positioned above the typographic ascent ($Y \ge A$). Blink aligns the overline at or above the ascent boundary:
    $$Y_{\text{over}} = A + G_{\text{over}} \quad (G_{\text{over}} \ge 0)$$
    such that the lower edge of the overline satisfies $Y_{\text{over}} \ge A$.
3.  **Line-Through (Across Mid-Cap / Strikethrough):**
    Positioned to intersect the midpoint of the cap-height (or x-height). Letting $M = \frac{C}{2}$ be the mid-cap height, the stroke straddles $M$:
    $$Y_{\text{strike}} = \left\lfloor M - \frac{T}{2} \right\rfloor$$
    satisfying $Y_{\text{strike}} \le M \le Y_{\text{strike}} + T$.

---

### 3. Geometric Invariants

1.  **Line Thickness Non-Negativity (Strict Positivity):**
    $$\forall d \in \text{Decorations}, \quad T(d) \ge 1 > 0$$
2.  **Vertical Ordering Invariant:**
    $$Y_{\text{under}} + T \le 0 < Y_{\text{strike}} \le M \le Y_{\text{strike}} + T \le A \le Y_{\text{over}}$$
    (assuming standard typographic proportions $T \le C \le A$).
3.  **Line Box Vertical Containment:**
    Let the enclosing line box vertical extent be $[L_{\min}, L_{\max}]$. When layout expands or bounds the ink/scrollable overflow or line box bounds to accommodate decorations:
    $$L_{\min} \le Y_{\text{under}} \quad \text{and} \quad Y_{\text{over}} + T \le L_{\max}$$
    Every decoration interval $[Y_d, Y_d + T_d]$ is a sub-interval of $[L_{\min}, L_{\max}]$.

---

### 4. Concrete Rocq / Coq Formalization (`BlinkTextDecorationSemantics.v`)

```coq
(** * BlinkTextDecorationSemantics.v
    Formal audit of Chromium Blink Text Decoration geometry against
    CSS Text Decoration Module Level 3 §2. *)

From Coq Require Import ZArith.
From Coq Require Import Lia.
Open Scope Z_scope.

(** ** 1. Font Metrics & Line Box Context *)

Record FontMetrics := mkFontMetrics {
  ascent     : Z;  (* A > 0 *)
  descent    : Z;  (* D < 0 *)
  cap_height : Z;  (* 0 < C <= A *)
  ul_offset  : Z;  (* Font underline offset <= -1 *)
  wf_ascent  : 0 < ascent;
  wf_descent : descent < 0;
  wf_cap     : 0 < cap_height /\ cap_height <= ascent;
  wf_ul      : ul_offset <= -1
}.

Record LineBox := mkLineBox {
  lb_min : Z;
  lb_max : Z;
  wf_lb  : lb_min <= lb_max
}.

Inductive DecorationLineType :=
  | Underline
  | Overline
  | LineThrough.

Record DecorationGeometry := mkDecorationGeometry {
  line_type : DecorationLineType;
  y_offset  : Z; (* Bottom edge relative to baseline B = 0 *)
  thickness : Z  (* Stroke thickness T *)
}.

(** ** 2. Blink Geometry Resolution Functions *)

(** Blink enforces a minimum thickness of 1 unit. *)
Definition resolve_thickness (raw_t : Z) : Z :=
  Z.max 1 raw_t.

(** Compute vertical offset Y relative to alphabetic baseline (0). *)
Definition resolve_y_offset (fm : FontMetrics) (dt : DecorationLineType) (t : Z) : Z :=
  match dt with
  | Underline   => fm.(ul_offset) - t
  | Overline    => fm.(ascent)
  | LineThrough => (fm.(cap_height) / 2) - (t / 2)
  end.

Definition compute_decoration (fm : FontMetrics) (dt : DecorationLineType) (raw_t : Z)
  : DecorationGeometry :=
  let t := resolve_thickness raw_t in
  mkDecorationGeometry dt (resolve_y_offset fm dt t) t.

(** Construct the bounding LineBox enclosing font metrics and active decorations. *)
Definition enclosing_line_box (fm : FontMetrics) (raw_t : Z) : LineBox.
Proof.
  refine (let t := resolve_thickness raw_t in
          mkLineBox (Z.min fm.(descent) (fm.(ul_offset) - t))
                    (fm.(ascent) + t)
                    _).
  pose proof (wf_ascent fm).
  pose proof (wf_descent fm).
  pose proof (wf_ul fm).
  unfold resolve_thickness in *.
  lia.
Defined.

(** ** 3. CSS Text Decoration 3 §2 Specification Predicates *)

Definition thickness_valid (dg : DecorationGeometry) : Prop :=
  1 <= dg.(thickness).

Definition underline_below_baseline (dg : DecorationGeometry) : Prop :=
  dg.(line_type) = Underline ->
  dg.(y_offset) + dg.(thickness) <= 0.

Definition overline_above_ascent (fm : FontMetrics) (dg : DecorationGeometry) : Prop :=
  dg.(line_type) = Overline ->
  fm.(ascent) <= dg.(y_offset).

Definition linethrough_across_midcap (fm : FontMetrics) (dg : DecorationGeometry) : Prop :=
  dg.(line_type) = LineThrough ->
  let mid := fm.(cap_height) / 2 in
  dg.(y_offset) <= mid /\ mid <= dg.(y_offset) + dg.(thickness).

Definition contained_in_line_box (lb : LineBox) (dg : DecorationGeometry) : Prop :=
  lb.(lb_min) <= dg.(y_offset) /\
  dg.(y_offset) + dg.(thickness) <= lb.(lb_max).

(** ** 4. Verification Theorems *)

Theorem blink_thickness_non_negative :
  forall (fm : FontMetrics) (dt : DecorationLineType) (raw_t : Z),
    thickness_valid (compute_decoration fm dt raw_t).
Proof.
  intros fm dt raw_t.
  unfold thickness_valid, compute_decoration, resolve_thickness.
  simpl. lia.
Qed.

Theorem blink_underline_spec :
  forall (fm : FontMetrics) (raw_t : Z),
    underline_below_baseline (compute_decoration fm Underline raw_t).
Proof.
  intros fm raw_t _.
  unfold compute_decoration, resolve_y_offset, resolve_thickness.
  simpl.
  pose proof (wf_ul fm).
  lia.
Qed.

Theorem blink_overline_spec :
  forall (fm : FontMetrics) (raw_t : Z),
    overline_above_ascent fm (compute_decoration fm Overline raw_t).
Proof.
  intros fm raw_t _.
  unfold compute_decoration, resolve_y_offset.
  simpl. lia.
Qed.

Theorem blink_linethrough_spec :
  forall (fm : FontMetrics) (raw_t : Z),
    linethrough_across_midcap fm (compute_decoration fm LineThrough raw_t).
Proof.
  intros fm raw_t _.
  unfold compute_decoration, resolve_y_offset, resolve_thickness.
  simpl.
  set (t := Z.max 1 raw_t).
  assert (Ht : 1 <= t) by (unfold t; lia).
  assert (Hdiv : 0 <= t / 2 /\ t / 2 <= t).
  { split.
    - apply Z.div_pos; lia.
    - apply Z.div_le_upper_bound; lia. }
  lia.
Qed.

Theorem blink_decoration_within_line_box :
  forall (fm : FontMetrics) (dt : DecorationLineType) (raw_t : Z),
    contained_in_line_box (enclosing_line_box fm raw_t) (compute_decoration fm dt raw_t).
Proof.
  intros fm dt raw_t.
  unfold contained_in_line_box, enclosing_line_box, compute_decoration,
         resolve_y_offset, resolve_thickness.
  simpl.
  set (t := Z.max 1 raw_t).
  assert (Ht : 1 <= t) by (unfold t; lia).
  pose proof (wf_ascent fm) as HA.
  pose proof (wf_descent fm) as HD.
  pose proof (wf_cap fm) as [HC1 HC2].
  pose proof (wf_ul fm) as HUL.
  destruct dt; split; try lia.
  - (* LineThrough lower bound *)
    assert (0 <= fm.(cap_height) / 2) by (apply Z.div_pos; lia).
    assert (t / 2 <= t) by (apply Z.div_le_upper_bound; lia).
    lia.
  - (* LineThrough upper bound *)
    assert (fm.(cap_height) / 2 <= fm.(cap_height)) by (apply Z.div_le_upper_bound; lia).
    assert (0 <= t / 2) by (apply Z.div_pos; lia).
    lia.
Qed.
```