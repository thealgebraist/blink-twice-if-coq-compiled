#!/usr/bin/env python3
"""
HM Hybrid Pillars 2, 3 & 4 Synthesis Engine (Classes 33..44)
============================================================
Extends `hm_hybrid_formalizer.py` (01..16) and `hm_hybrid_html_css_synthesizer.py`
(17..32) with 12 authentic Chromium Blink classes covering:

  Pillar 2 (Selectors L4, Cascade L5/L6 & Nonlinear CSS Values):
    33. SelectorIsMaxSpec     — `:is()` / `:not()` max-branch packed specificity
    34. RevertLayerCandidate  — `revert-layer` strictly-earlier `@layer` rollback
    35. ContainerInlineQuery  — `@container (min-width / max-width)` inline-size check
    36. CSSMathClamp          — `clamp(min_v, val, max_v)` min-wins-on-inversion
    37. CSSColorMixSRGB       — `color-mix(in srgb, c1 p1%, c2 p2%)` channel bounds

  Pillar 3 (Multi-Span Inline Formatting Context):
    38. InlineSpanBox         — Inline pill `<code>` total box width (`pad_l + glyph_w + pad_r + 2*border`)

  Pillar 4 (Out-of-Flow Positioning, Stacking `z-index`, Floats, Flex/Grid/Table):
    39. OutOfFlowInset        — CSS Positioned Layout 3 `left`/`right`/`width` resolution
    40. StackingZOrder        — CSS 2.2 Appendix E `(paint_phase, z_index, dom_order)` key
    41. FloatExclusionBand    — `float: left | right` inline band narrowing `[x_left, x_right]`
    42. FlexShrinkDeficit     — CSS Flexbox `flex-shrink` weighted deficit contraction
    43. GridMinMaxTrack       — CSS Grid `minmax(min_t, max_t)` track resolution
    44. TableCollapsedBorder  — CSS 2.1 §17.6.2.1 `border-collapse: collapse` edge winner
"""

import subprocess
import sys
import threading
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from typing import Any, Callable, Dict, List, Tuple

import z3

Z3_GLOBAL_CTX_LOCK = threading.Lock()

from hm_hybrid_formalizer import (
    BaseType,
    BlinkClassSpec,
    RobinsonUnification,
    RowRecordType,
    TypeTerm,
    TypeVar,
    synthesize_coq_file,
)


def get_pillars_2_3_4_specs() -> List[Tuple[BlinkClassSpec, Callable[[], bool]]]:
    specs_and_smt: List[Tuple[BlinkClassSpec, Callable[[], bool]]] = []

    # 33. SelectorIsMaxSpec (core/css/css_selector.cc)
    def z3_33() -> bool:
        s1, s2, s3 = z3.Ints("s1 s2 s3")
        m12 = z3.If(s1 < s2, s2, s1)
        m123 = z3.If(m12 < s3, s3, m12)
        s = z3.Solver()
        s.add(z3.Not(z3.And(s1 <= m123, s2 <= m123, s3 <= m123)))
        return s.check() == z3.unsat

    specs_and_smt.append((
        BlinkClassSpec(
            33, "SelectorIsMaxSpec",
            [("branch1_spec", "int32_t"), ("branch2_spec", "int32_t"), ("branch3_spec", "int32_t")],
            [{
                "name": "is_pseudo_max_spec3",
                "args": [("s1", "int32_t"), ("s2", "int32_t"), ("s3", "int32_t")],
                "ret": "int32_t",
                "body": "Z.max (Z.max s1 s2) s3",
                "theorem_name": "is_pseudo_max_spec3_dominates_branches",
                "theorem_stmt": "forall (s1 s2 s3 : Z), s1 <= is_pseudo_max_spec3 s1 s2 s3 /\\ s2 <= is_pseudo_max_spec3 s1 s2 s3 /\\ s3 <= is_pseudo_max_spec3 s1 s2 s3",
                "proof": "intros s1 s2 s3. unfold is_pseudo_max_spec3. lia."
            }],
            ["branch1_spec >= 0", "branch2_spec >= 0", "branch3_spec >= 0"]
        ),
        z3_33,
    ))

    # 34. RevertLayerCandidate (core/css/resolver/style_cascade.cc)
    def z3_34() -> bool:
        cur_origin, cur_layer, cand_origin, cand_layer = z3.Ints("cur_origin cur_layer cand_origin cand_layer")
        kept = z3.Or(cand_origin < cur_origin, z3.And(cand_origin == cur_origin, cand_layer < cur_layer))
        s = z3.Solver()
        s.add(cand_origin == cur_origin, cand_layer >= cur_layer, kept)
        return s.check() == z3.unsat

    specs_and_smt.append((
        BlinkClassSpec(
            34, "RevertLayerCandidate",
            [("cur_origin", "int32_t"), ("cur_layer", "int32_t"), ("cand_origin", "int32_t"), ("cand_layer", "int32_t")],
            [{
                "name": "revert_layer_accepts",
                "args": [("cur_origin", "int32_t"), ("cur_layer", "int32_t"), ("cand_origin", "int32_t"), ("cand_layer", "int32_t")],
                "ret": "bool",
                "body": "(cand_origin <? cur_origin) || ((cand_origin =? cur_origin) && (cand_layer <? cur_layer))",
                "theorem_name": "revert_layer_rejects_same_or_later_layer",
                "theorem_stmt": "forall (orig cur_layer cand_layer : Z), cur_layer <= cand_layer -> revert_layer_accepts orig cur_layer orig cand_layer = false",
                "proof": """intros orig cur_layer cand_layer Hle.
  unfold revert_layer_accepts.
  rewrite Z.ltb_irrefl, Z.eqb_refl. simpl.
  apply Z.ltb_ge. lia."""
            }],
            ["cur_origin >= 0", "cur_layer >= 0"]
        ),
        z3_34,
    ))

    # 35. ContainerInlineQuery (core/css/container_query_evaluator.cc)
    def z3_35() -> bool:
        avail_w, min_w, max_w = z3.Ints("avail_w min_w max_w")
        matches = z3.And(min_w <= avail_w, avail_w <= max_w)
        s = z3.Solver()
        s.add(matches, z3.Not(min_w <= max_w))
        return s.check() == z3.unsat

    specs_and_smt.append((
        BlinkClassSpec(
            35, "ContainerInlineQuery",
            [("container_inline_w", "int32_t"), ("min_w", "int32_t"), ("max_w", "int32_t")],
            [{
                "name": "eval_container_inline_range",
                "args": [("avail_w", "int32_t"), ("min_w", "int32_t"), ("max_w", "int32_t")],
                "ret": "bool",
                "body": "(min_w <=? avail_w) && (avail_w <=? max_w)",
                "theorem_name": "container_inline_range_implies_consistent_bounds",
                "theorem_stmt": "forall (avail_w min_w max_w : Z), eval_container_inline_range avail_w min_w max_w = true -> min_w <= avail_w /\\ avail_w <= max_w /\\ min_w <= max_w",
                "proof": """intros avail_w min_w max_w H.
  unfold eval_container_inline_range in H.
  apply andb_true_iff in H as [H1 H2].
  apply Z.leb_le in H1. apply Z.leb_le in H2. lia."""
            }],
            ["container_inline_w >= 0"]
        ),
        z3_35,
    ))

    # 36. CSSMathClamp (core/css/css_math_expression_node.cc)
    def z3_36() -> bool:
        lo, val, hi = z3.Ints("lo val hi")
        inner = z3.If(val < hi, val, hi)
        clamped = z3.If(lo < inner, inner, lo)
        s = z3.Solver()
        s.add(z3.Or(
            z3.And(lo <= hi, z3.Not(z3.And(lo <= clamped, clamped <= hi))),
            z3.And(hi < lo, clamped != lo)
        ))
        return s.check() == z3.unsat

    specs_and_smt.append((
        BlinkClassSpec(
            36, "CSSMathClamp",
            [("min_val", "int32_t"), ("preferred_val", "int32_t"), ("max_val", "int32_t")],
            [{
                "name": "css_clamp_val",
                "args": [("lo", "int32_t"), ("val", "int32_t"), ("hi", "int32_t")],
                "ret": "int32_t",
                "body": "Z.max lo (Z.min val hi)",
                "theorem_name": "css_clamp_bounds_and_min_wins",
                "theorem_stmt": "forall (lo val hi : Z), (lo <= hi -> lo <= css_clamp_val lo val hi <= hi) /\\ (hi < lo -> css_clamp_val lo val hi = lo)",
                "proof": "intros lo val hi. unfold css_clamp_val. lia."
            }],
            []
        ),
        z3_36,
    ))

    # 37. CSSColorMixSRGB (core/css/style_color.cc)
    def z3_37() -> bool:
        c1, c2, p = z3.Ints("c1 c2 p")
        mixed = (c1 * p + c2 * (100 - p)) / 100
        s = z3.Solver()
        s.add(0 <= c1, c1 <= 255, 0 <= c2, c2 <= 255, 0 <= p, p <= 100)
        s.add(z3.Not(z3.And(0 <= mixed, mixed <= 255)))
        return s.check() == z3.unsat

    specs_and_smt.append((
        BlinkClassSpec(
            37, "CSSColorMixSRGB",
            [("chan1", "int32_t"), ("chan2", "int32_t"), ("weight_pct", "int32_t")],
            [{
                "name": "mix_srgb_byte",
                "args": [("c1", "int32_t"), ("c2", "int32_t"), ("p", "int32_t")],
                "ret": "int32_t",
                "body": "(c1 * p + c2 * (100 - p)) / 100",
                "theorem_name": "mix_srgb_byte_in_u8_range",
                "theorem_stmt": "forall (c1 c2 p : Z), 0 <= c1 <= 255 -> 0 <= c2 <= 255 -> 0 <= p <= 100 -> 0 <= mix_srgb_byte c1 c2 p <= 255",
                "proof": """intros c1 c2 p Hc1 Hc2 Hp. unfold mix_srgb_byte. split.
  - apply Z.div_pos; [nia | lia].
  - apply Z.div_le_upper_bound; [lia | nia]."""
            }],
            ["0 <= chan1", "chan1 <= 255", "0 <= chan2", "chan2 <= 255", "0 <= weight_pct", "weight_pct <= 100"]
        ),
        z3_37,
    ))

    # 38. InlineSpanBox (core/layout/inline/inline_box_state.cc)
    def z3_38() -> bool:
        glyph_w, pad_l, pad_r, border_w = z3.Ints("glyph_w pad_l pad_r border_w")
        box_w = glyph_w + pad_l + pad_r + 2 * border_w
        s = z3.Solver()
        s.add(glyph_w >= 0, pad_l >= 0, pad_r >= 0, border_w >= 0)
        s.add(z3.Not(box_w >= glyph_w))
        return s.check() == z3.unsat

    specs_and_smt.append((
        BlinkClassSpec(
            38, "InlineSpanBox",
            [("glyph_w", "int32_t"), ("pad_l", "int32_t"), ("pad_r", "int32_t"), ("border_w", "int32_t")],
            [{
                "name": "inline_span_outer_advance",
                "args": [("glyph_w", "int32_t"), ("pad_l", "int32_t"), ("pad_r", "int32_t"), ("border_w", "int32_t")],
                "ret": "int32_t",
                "body": "glyph_w + Z.max 0 pad_l + Z.max 0 pad_r + 2 * Z.max 0 border_w",
                "theorem_name": "inline_span_outer_advance_ge_glyph_w",
                "theorem_stmt": "forall (glyph_w pad_l pad_r border_w : Z), glyph_w <= inline_span_outer_advance glyph_w pad_l pad_r border_w",
                "proof": "intros. unfold inline_span_outer_advance. lia."
            }],
            ["glyph_w >= 0", "pad_l >= 0", "pad_r >= 0", "border_w >= 0"]
        ),
        z3_38,
    ))

    # 39. OutOfFlowInset (core/layout/out_of_flow_layout_part.cc)
    def z3_39() -> bool:
        cb_size, i_start, i_end = z3.Ints("cb_size i_start i_end")
        raw = cb_size - i_start - i_end
        sz = z3.If(raw < 0, 0, raw)
        s = z3.Solver()
        s.add(cb_size >= i_start + i_end)
        s.add(i_start + sz + i_end != cb_size)
        return s.check() == z3.unsat

    specs_and_smt.append((
        BlinkClassSpec(
            39, "OutOfFlowInset",
            [("cb_size", "int32_t"), ("inset_start", "int32_t"), ("inset_end", "int32_t")],
            [{
                "name": "oof_stretch_size",
                "args": [("cb_size", "int32_t"), ("inset_start", "int32_t"), ("inset_end", "int32_t")],
                "ret": "int32_t",
                "body": "Z.max 0 (cb_size - inset_start - inset_end)",
                "theorem_name": "oof_stretch_fills_containing_block",
                "theorem_stmt": "forall (cb_size inset_start inset_end : Z), inset_start + inset_end <= cb_size -> inset_start + oof_stretch_size cb_size inset_start inset_end + inset_end = cb_size",
                "proof": "intros cb_size inset_start inset_end Hle. unfold oof_stretch_size. lia."
            }],
            ["cb_size >= 0"]
        ),
        z3_39,
    ))

    # 40. StackingZOrder (core/paint/paint_layer_stacking_node.cc)
    def z3_40() -> bool:
        z1, z2, d1, d2 = z3.Ints("z1 z2 d1 d2")
        # z_index clamped to [-32768, 32767], dom_order in [0, 65535]
        key1 = (z1 + 32768) * 65536 + d1
        key2 = (z2 + 32768) * 65536 + d2
        s = z3.Solver()
        s.add(-32768 <= z1, z1 < z2, z2 <= 32767, 0 <= d1, d1 < 65536, 0 <= d2, d2 < 65536)
        s.add(z3.Not(key1 < key2))
        return s.check() == z3.unsat

    specs_and_smt.append((
        BlinkClassSpec(
            40, "StackingZOrder",
            [("z_index", "int32_t"), ("dom_order", "int32_t")],
            [{
                "name": "pack_stacking_key",
                "args": [("z_idx", "int32_t"), ("dom_ord", "int32_t")],
                "ret": "int32_t",
                "body": "(z_idx + 32768) * 65536 + dom_ord",
                "theorem_name": "higher_z_index_strictly_dominates_dom_order",
                "theorem_stmt": "forall (z1 z2 d1 d2 : Z), -32768 <= z1 -> z1 < z2 -> z2 <= 32767 -> 0 <= d1 < 65536 -> 0 <= d2 < 65536 -> pack_stacking_key z1 d1 < pack_stacking_key z2 d2",
                "proof": "intros z1 z2 d1 d2 Hz1 Hlt Hz2 Hd1 Hd2. unfold pack_stacking_key. lia."
            }],
            ["0 <= dom_order", "dom_order < 65536"]
        ),
        z3_40,
    ))

    # 41. FloatExclusionBand (core/layout/exclusions/exclusion_space.cc)
    def z3_41() -> bool:
        cb_l, cb_r, fl_r, fr_l = z3.Ints("cb_l cb_r fl_r fr_l")
        x_l = z3.If(cb_l < fl_r, fl_r, cb_l)
        x_r = z3.If(cb_r < fr_l, cb_r, fr_l)
        avail = z3.If(x_r - x_l < 0, 0, x_r - x_l)
        s = z3.Solver()
        s.add(cb_l <= cb_r)
        s.add(z3.Not(z3.And(0 <= avail, avail <= cb_r - cb_l)))
        return s.check() == z3.unsat

    specs_and_smt.append((
        BlinkClassSpec(
            41, "FloatExclusionBand",
            [("cb_left", "int32_t"), ("cb_right", "int32_t"), ("left_float_edge", "int32_t"), ("right_float_edge", "int32_t")],
            [{
                "name": "float_band_avail_width",
                "args": [("cb_l", "int32_t"), ("cb_r", "int32_t"), ("fl_r", "int32_t"), ("fr_l", "int32_t")],
                "ret": "int32_t",
                "body": "Z.max 0 (Z.min cb_r fr_l - Z.max cb_l fl_r)",
                "theorem_name": "float_band_avail_width_within_cb",
                "theorem_stmt": "forall (cb_l cb_r fl_r fr_l : Z), cb_l <= cb_r -> 0 <= float_band_avail_width cb_l cb_r fl_r fr_l <= cb_r - cb_l",
                "proof": "intros cb_l cb_r fl_r fr_l Hcb. unfold float_band_avail_width. lia."
            }],
            ["cb_left <= cb_right"]
        ),
        z3_41,
    ))

    # 42. FlexShrinkDeficit (core/layout/flex/flexible_box_algorithm.cc)
    def z3_42() -> bool:
        base_sz, deficit, factor, total_factor, min_sz = z3.Ints("base_sz deficit factor total_factor min_sz")
        shrunk = base_sz - (deficit * factor) / total_factor
        clamped = z3.If(shrunk < min_sz, min_sz, shrunk)
        s = z3.Solver()
        s.add(min_sz >= 0, base_sz >= min_sz, deficit >= 0, factor >= 0, total_factor > 0)
        s.add(z3.Not(z3.And(min_sz <= clamped, clamped <= base_sz)))
        return s.check() == z3.unsat

    specs_and_smt.append((
        BlinkClassSpec(
            42, "FlexShrinkDeficit",
            [("base_size", "int32_t"), ("deficit", "int32_t"), ("shrink_weight", "int32_t"), ("total_weight", "int32_t"), ("min_size", "int32_t")],
            [{
                "name": "apply_flex_shrink_clamped",
                "args": [("base_sz", "int32_t"), ("deficit", "int32_t"), ("weight", "int32_t"), ("total_weight", "int32_t"), ("min_sz", "int32_t")],
                "ret": "int32_t",
                "body": "Z.max min_sz (base_sz - (deficit * weight) / total_weight)",
                "theorem_name": "flex_shrink_respects_min_and_base",
                "theorem_stmt": "forall (base_sz deficit weight total_weight min_sz : Z), min_sz <= base_sz -> 0 <= deficit -> 0 <= weight -> 0 < total_weight -> min_sz <= apply_flex_shrink_clamped base_sz deficit weight total_weight min_sz <= base_sz",
                "proof": """intros base_sz deficit weight total_weight min_sz Hmin Hdef Hw Htw.
  unfold apply_flex_shrink_clamped.
  assert (Hpos : 0 <= (deficit * weight) / total_weight) by (apply Z.div_pos; [nia | lia]).
  lia."""
            }],
            ["min_size >= 0", "base_size >= min_size", "total_weight > 0"]
        ),
        z3_42,
    ))

    # 43. GridMinMaxTrack (core/layout/grid/grid_layout_algorithm.cc)
    def z3_43() -> bool:
        min_t, max_t, avail = z3.Ints("min_t max_t avail")
        inner = z3.If(avail < max_t, avail, max_t)
        track = z3.If(min_t < inner, inner, min_t)
        s = z3.Solver()
        s.add(0 <= min_t)
        s.add(z3.Not(min_t <= track))
        return s.check() == z3.unsat

    specs_and_smt.append((
        BlinkClassSpec(
            43, "GridMinMaxTrack",
            [("min_track", "int32_t"), ("max_track", "int32_t"), ("avail_share", "int32_t")],
            [{
                "name": "resolve_grid_minmax",
                "args": [("min_t", "int32_t"), ("max_t", "int32_t"), ("avail", "int32_t")],
                "ret": "int32_t",
                "body": "Z.max min_t (Z.min avail max_t)",
                "theorem_name": "grid_minmax_never_below_min_track",
                "theorem_stmt": "forall (min_t max_t avail : Z), min_t <= resolve_grid_minmax min_t max_t avail",
                "proof": "intros min_t max_t avail. unfold resolve_grid_minmax. lia."
            }],
            ["min_track >= 0"]
        ),
        z3_43,
    ))

    # 44. TableCollapsedBorder (core/layout/table/table_borders.cc)
    def z3_44() -> bool:
        # style rank: 0=none, 1..8=visible, 9=hidden
        s1, w1, s2, w2 = z3.Ints("s1 w1 s2 w2")
        out_w = z3.If(
            z3.Or(s1 == 9, s2 == 9),
            0,
            z3.If(s1 == 0, w2, z3.If(s2 == 0, w1, z3.If(w1 < w2, w2, w1))),
        )
        s = z3.Solver()
        s.add(z3.Or(
            z3.And(s1 == 9, out_w != 0),
            z3.And(1 <= s1, s1 <= 8, 1 <= s2, s2 <= 8, 0 <= w1, 0 <= w2, out_w != z3.If(w1 < w2, w2, w1)),
        ))
        return s.check() == z3.unsat

    specs_and_smt.append((
        BlinkClassSpec(
            44, "TableCollapsedBorder",
            [("style1", "int32_t"), ("width1", "int32_t"), ("style2", "int32_t"), ("width2", "int32_t")],
            [{
                "name": "collapsed_border_width",
                "args": [("s1", "int32_t"), ("w1", "int32_t"), ("s2", "int32_t"), ("w2", "int32_t")],
                "ret": "int32_t",
                "body": "if (s1 =? 9) || (s2 =? 9) then 0 else if s1 =? 0 then w2 else if s2 =? 0 then w1 else Z.max w1 w2",
                "theorem_name": "collapsed_border_hidden_zeros_and_visible_max",
                "theorem_stmt": "forall (s1 w1 s2 w2 : Z), collapsed_border_width 9 w1 s2 w2 = 0 /\\ (1 <= s1 <= 8 -> 1 <= s2 <= 8 -> collapsed_border_width s1 w1 s2 w2 = Z.max w1 w2)",
                "proof": """intros s1 w1 s2 w2. unfold collapsed_border_width. split.
  - reflexivity.
  - intros Hs1 Hs2.
    assert (E19 : (s1 =? 9) = false) by (apply Z.eqb_neq; lia).
    assert (E29 : (s2 =? 9) = false) by (apply Z.eqb_neq; lia).
    assert (E10 : (s1 =? 0) = false) by (apply Z.eqb_neq; lia).
    assert (E20 : (s2 =? 0) = false) by (apply Z.eqb_neq; lia).
    rewrite E19, E29, E10, E20. reflexivity."""
            }],
            ["0 <= style1", "style1 <= 9", "0 <= style2", "style2 <= 9"]
        ),
        z3_44,
    ))

    return specs_and_smt


def process_pillar_class(
    item: Tuple[BlinkClassSpec, Callable[[], bool]],
    agent_id: int,
) -> Dict[str, Any]:
    spec, smt_check = item
    t0 = time.time()

    subst: Dict[TypeVar, TypeTerm] = {}
    row_fields: Dict[str, TypeTerm] = {}
    for fname, ftype in spec.fields:
        t = BaseType("bool") if ftype == "bool" else BaseType("Z")
        tv = TypeVar(f"{spec.name}_{fname}")
        res = RobinsonUnification.unify(tv, t, subst)
        if res is not None:
            subst = res
        row_fields[fname] = t

    rec_type = RowRecordType(spec.name, row_fields)
    tv_rec = TypeVar(f"rec_{spec.name}")
    res_rec = RobinsonUnification.unify(tv_rec, rec_type, subst)
    if res_rec is not None:
        subst = res_rec

    with Z3_GLOBAL_CTX_LOCK:
        z3_unsat = smt_check()

    coq_code = synthesize_coq_file(spec, subst)
    v_file = f"BlinkHMHybrid_{spec.class_id:02d}_{spec.name}.v"
    with open(v_file, "w") as vf:
        vf.write(coq_code)

    has_admit = ("admit" in coq_code) or ("Admitted" in coq_code)

    proc = subprocess.run(["coqc", "-Q", ".", "", v_file], capture_output=True, text=True)
    coqc_ok = (proc.returncode == 0) and (not has_admit) and z3_unsat
    t1 = time.time()

    return {
        "agent_id": agent_id,
        "class_id": spec.class_id,
        "class_name": spec.name,
        "file": v_file,
        "z3_unsat": z3_unsat,
        "coqc_success": coqc_ok,
        "has_admit": has_admit,
        "elapsed_sec": t1 - t0,
        "stderr": proc.stderr,
        "lines_of_coq": len(coq_code.splitlines()),
    }


def main() -> int:
    print("=" * 84)
    print("HM Hybrid Pillars 2, 3 & 4 Synthesis (Classes 33..44 | 8 Parallel Agents)")
    print("Robinson MGU Row Typing + Z3 BGS-Spec UNSAT Gate + Rocq/Coq 9.3.0 Verification")
    print("=" * 84)

    items = get_pillars_2_3_4_specs()
    tasks = [(item, (idx % 8) + 1) for idx, item in enumerate(items)]

    t_start = time.time()
    results: List[Dict[str, Any]] = []
    with ThreadPoolExecutor(max_workers=8) as pool:
        futs = {pool.submit(process_pillar_class, item, aid): (item, aid) for item, aid in tasks}
        for fut in as_completed(futs):
            r = fut.result()
            results.append(r)
            status = "PASS (Z3 UNSAT + coqc 0 Admits)" if r["coqc_success"] else f"FAIL: {r['stderr']}"
            print(
                f"  [Agent {r['agent_id']}] Class {r['class_id']:02d}: "
                f"{r['class_name']:22} -> {r['file']:42} | {status} ({r['elapsed_sec']:.3f}s)"
            )

    t_elapsed = time.time() - t_start
    results.sort(key=lambda x: x["class_id"])

    passed = sum(1 for r in results if r["coqc_success"])
    admits = sum(1 for r in results if r["has_admit"])
    total_loc = sum(r["lines_of_coq"] for r in results)

    print("-" * 84)
    print(f"Classes Synthesized & Verified : {passed}/{len(results)}")
    print(f"Z3 BGS-Spec UNSAT Checks       : {sum(1 for r in results if r['z3_unsat'])}/{len(results)}")
    print(f"Admitted Theorems              : {admits} (STRICTLY 0 REQUIRED)")
    print(f"Generated Gallina Lines        : {total_loc} lines across 12 theories")
    print(f"Wall-Clock Synthesis Time      : {t_elapsed:.3f}s")
    print("=" * 84)

    return 0 if (passed == len(results) and admits == 0) else 1


if __name__ == "__main__":
    sys.exit(main())

