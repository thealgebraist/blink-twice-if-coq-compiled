#!/usr/bin/env python3
"""
HM Hybrid Pillars 1 & 5 Synthesis Engine (Classes 45..54)
=========================================================
Extends `hm_hybrid_formalizer.py` (01..16), `hm_hybrid_html_css_synthesizer.py`
(17..32), and `hm_hybrid_pillars_2_3_4_synthesizer.py` (33..44) with 10 authentic
Chromium Blink classes covering:

  Pillar 1 (WHATWG HTML5 Tokenizer, Table Recovery, Foster Parenting & AAA):
    45. HTMLNumericCharRef     — Numeric `&#NNN;` / `&#xHHH;` zero/surrogate/range sanitizer
    46. HTMLFosterParentSlot   — Table foster-parent `insert_before` child count & index
    47. HTMLNoahsArkAFE        — Active Formatting Elements Noah's Ark `<= 3` signature cap
    48. HTMLAdoptionAgencyStep — Adoption Agency Algorithm bounded outer/inner fuel step

  Pillar 5 (Skia `SkRRect` SDF, `box-shadow`, `linear-gradient`, `opacity`, `overflow` & `transform`):
    49. SkiaRRectCornerClamp   — CSS Backgrounds 3 §5.3 `min(r, min(w/2, h/2))` radius clamp
    50. SkiaSDFCoverageAlpha   — Subpixel SDF edge coverage distance -> `[0..255]` alpha
    51. BoxShadowBlurFalloff   — Outer `box-shadow` spread & linear blur falloff `[0..base_a]`
    52. LinearGradientStopLerp — Multi-stop `linear-gradient` channel interpolation `[0..255]`
    53. PaintLayerGroupOpacity — Atomic offscreen group `opacity` Porter-Duff alpha scaling
    54. OverflowClipScissor    — Hierarchical `overflow: hidden` scissor box intersection
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


def get_pillars_1_5_specs() -> List[Tuple[BlinkClassSpec, Callable[[], bool]]]:
    specs_and_smt: List[Tuple[BlinkClassSpec, Callable[[], bool]]] = []

    # 45. HTMLNumericCharRef (core/html/parser/html_entity_parser.cc)
    def z3_45() -> bool:
        cp = z3.Int("cp")
        invalid = z3.Or(
            cp <= 0,
            cp > 1114111,
            z3.And(55296 <= cp, cp <= 57343),
        )
        out = z3.If(invalid, 65533, cp)
        s = z3.Solver()
        s.add(z3.Or(
            out <= 0,
            out > 1114111,
            z3.And(55296 <= out, out <= 57343),
        ))
        return s.check() == z3.unsat

    specs_and_smt.append((
        BlinkClassSpec(
            45, "HTMLNumericCharRef",
            [("raw_codepoint", "int32_t")],
            [{
                "name": "sanitize_char_ref",
                "args": [("cp", "int32_t")],
                "ret": "int32_t",
                "body": "if (cp <=? 0) || (1114111 <? cp) || ((55296 <=? cp) && (cp <=? 57343)) then 65533 else cp",
                "theorem_name": "sanitize_char_ref_always_valid_scalar",
                "theorem_stmt": "forall (cp : Z), 1 <= sanitize_char_ref cp <= 1114111 /\\ ~ (55296 <= sanitize_char_ref cp <= 57343)",
                "proof": """intros cp. unfold sanitize_char_ref.
  destruct (cp <=? 0) eqn:E0; simpl.
  - lia.
  - destruct (1114111 <? cp) eqn:Emax; simpl.
    + lia.
    + destruct ((55296 <=? cp) && (cp <=? 57343)) eqn:Esur; simpl.
      * lia.
      * apply Z.leb_gt in E0. apply Z.ltb_ge in Emax.
        apply andb_false_iff in Esur.
        destruct Esur as [Es1 | Es2]; [apply Z.leb_gt in Es1 | apply Z.leb_gt in Es2]; lia."""
            }],
            []
        ),
        z3_45,
    ))

    # 46. HTMLFosterParentSlot (core/html/parser/html_construction_site.cc)
    def z3_46() -> bool:
        parent_cnt, table_idx = z3.Ints("parent_cnt table_idx")
        slot = z3.If(
            table_idx < 0,
            parent_cnt,
            z3.If(table_idx > parent_cnt, parent_cnt, table_idx),
        )
        s = z3.Solver()
        s.add(parent_cnt >= 0)
        s.add(z3.Not(z3.And(0 <= slot, slot <= parent_cnt)))
        return s.check() == z3.unsat

    specs_and_smt.append((
        BlinkClassSpec(
            46, "HTMLFosterParentSlot",
            [("parent_child_count", "int32_t"), ("table_child_index", "int32_t")],
            [{
                "name": "foster_insert_index",
                "args": [("parent_cnt", "int32_t"), ("table_idx", "int32_t")],
                "ret": "int32_t",
                "body": "if table_idx <? 0 then parent_cnt else Z.min parent_cnt table_idx",
                "theorem_name": "foster_insert_index_valid_slot",
                "theorem_stmt": "forall (parent_cnt table_idx : Z), 0 <= parent_cnt -> 0 <= foster_insert_index parent_cnt table_idx <= parent_cnt",
                "proof": """intros parent_cnt table_idx Hcnt. unfold foster_insert_index.
  destruct (table_idx <? 0) eqn:Elt.
  - lia.
  - apply Z.ltb_ge in Elt. lia."""
            }],
            ["parent_child_count >= 0"]
        ),
        z3_46,
    ))

    # 47. HTMLNoahsArkAFE (core/html/parser/html_formatting_element_list.cc)
    def z3_47() -> bool:
        dup_cnt = z3.Int("dup_cnt")
        after_evict = z3.If(dup_cnt >= 3, 2, dup_cnt)
        after_push = after_evict + 1
        s = z3.Solver()
        s.add(0 <= dup_cnt, dup_cnt <= 3)
        s.add(z3.Not(z3.And(1 <= after_push, after_push <= 3)))
        return s.check() == z3.unsat

    specs_and_smt.append((
        BlinkClassSpec(
            47, "HTMLNoahsArkAFE",
            [("matching_sig_count", "int32_t")],
            [{
                "name": "noahs_ark_next_count",
                "args": [("dup_cnt", "int32_t")],
                "ret": "int32_t",
                "body": "(if 3 <=? dup_cnt then 2 else dup_cnt) + 1",
                "theorem_name": "noahs_ark_next_count_capped_at_3",
                "theorem_stmt": "forall (dup_cnt : Z), 0 <= dup_cnt <= 3 -> 1 <= noahs_ark_next_count dup_cnt <= 3",
                "proof": """intros dup_cnt H. unfold noahs_ark_next_count.
  destruct (3 <=? dup_cnt) eqn:E3.
  - lia.
  - apply Z.leb_gt in E3. lia."""
            }],
            ["0 <= matching_sig_count", "matching_sig_count <= 3"]
        ),
        z3_47,
    ))

    # 48. HTMLAdoptionAgencyStep (core/html/parser/html_tree_builder.cc)
    def z3_48() -> bool:
        outer_rem, inner_rem = z3.Ints("outer_rem inner_rem")
        # Lexicographic rank 4 * outer_rem + inner_rem strictly decreases on step
        rank_before = 4 * outer_rem + inner_rem
        rank_inner_step = 4 * outer_rem + (inner_rem - 1)
        rank_outer_step = 4 * (outer_rem - 1) + 3
        s = z3.Solver()
        s.add(1 <= outer_rem, outer_rem <= 8, 0 <= inner_rem, inner_rem <= 3)
        s.add(z3.Or(
            z3.And(inner_rem >= 1, z3.Not(0 <= rank_inner_step), z3.Not(rank_inner_step < rank_before)),
            z3.And(inner_rem >= 1, rank_inner_step >= rank_before),
            z3.And(inner_rem == 0, rank_outer_step >= rank_before),
        ))
        return s.check() == z3.unsat

    specs_and_smt.append((
        BlinkClassSpec(
            48, "HTMLAdoptionAgencyStep",
            [("outer_fuel", "int32_t"), ("inner_fuel", "int32_t")],
            [{
                "name": "aaa_lex_measure",
                "args": [("outer_rem", "int32_t"), ("inner_rem", "int32_t")],
                "ret": "int32_t",
                "body": "4 * outer_rem + inner_rem",
                "theorem_name": "aaa_lex_measure_strictly_decreases",
                "theorem_stmt": "forall (outer_rem inner_rem : Z), 1 <= outer_rem <= 8 -> 0 <= inner_rem <= 3 -> (1 <= inner_rem -> aaa_lex_measure outer_rem (inner_rem - 1) < aaa_lex_measure outer_rem inner_rem) /\\ (aaa_lex_measure (outer_rem - 1) 3 < aaa_lex_measure outer_rem 0)",
                "proof": "intros outer_rem inner_rem Ho Hi. unfold aaa_lex_measure. lia."
            }],
            ["0 <= outer_fuel", "outer_fuel <= 8", "0 <= inner_fuel", "inner_fuel <= 3"]
        ),
        z3_48,
    ))

    # 49. SkiaRRectCornerClamp (platform/graphics/rounded_rect.cc)
    def z3_49() -> bool:
        w, h, r = z3.Ints("w h r")
        r_pos = z3.If(r < 0, 0, r)
        half_w = w / 2
        half_h = h / 2
        min_half = z3.If(half_w < half_h, half_w, half_h)
        r_eff = z3.If(r_pos < min_half, r_pos, min_half)
        s = z3.Solver()
        s.add(w >= 0, h >= 0)
        s.add(z3.Not(z3.And(0 <= r_eff, 2 * r_eff <= w, 2 * r_eff <= h)))
        return s.check() == z3.unsat

    specs_and_smt.append((
        BlinkClassSpec(
            49, "SkiaRRectCornerClamp",
            [("box_w", "int32_t"), ("box_h", "int32_t"), ("raw_radius", "int32_t")],
            [{
                "name": "clamp_rrect_radius",
                "args": [("w", "int32_t"), ("h", "int32_t"), ("r", "int32_t")],
                "ret": "int32_t",
                "body": "Z.min (Z.max 0 r) (Z.min (w / 2) (h / 2))",
                "theorem_name": "clamp_rrect_radius_non_overlapping",
                "theorem_stmt": "forall (w h r : Z), 0 <= w -> 0 <= h -> 0 <= clamp_rrect_radius w h r /\\ 2 * clamp_rrect_radius w h r <= w /\\ 2 * clamp_rrect_radius w h r <= h",
                "proof": """intros w h r Hw Hh. unfold clamp_rrect_radius.
  assert (Hdw : 0 <= w / 2 /\\ 2 * (w / 2) <= w) by (split; [apply Z.div_pos; lia | apply Z.mul_div_le; lia]).
  assert (Hdh : 0 <= h / 2 /\\ 2 * (h / 2) <= h) by (split; [apply Z.div_pos; lia | apply Z.mul_div_le; lia]).
  lia."""
            }],
            ["box_w >= 0", "box_h >= 0"]
        ),
        z3_49,
    ))

    # 50. SkiaSDFCoverageAlpha (platform/graphics/paint/paint_canvas.cc)
    def z3_50() -> bool:
        sd_q8 = z3.Int("sd_q8")
        raw = 128 - sd_q8
        cov = z3.If(raw < 0, 0, z3.If(raw > 255, 255, raw))
        s = z3.Solver()
        s.add(z3.Not(z3.And(0 <= cov, cov <= 255)))
        return s.check() == z3.unsat

    specs_and_smt.append((
        BlinkClassSpec(
            50, "SkiaSDFCoverageAlpha",
            [("signed_dist_q8", "int32_t")],
            [{
                "name": "sdf_coverage_u8",
                "args": [("sd_q8", "int32_t")],
                "ret": "int32_t",
                "body": "Z.max 0 (Z.min 255 (128 - sd_q8))",
                "theorem_name": "sdf_coverage_u8_bounded",
                "theorem_stmt": "forall (sd_q8 : Z), 0 <= sdf_coverage_u8 sd_q8 <= 255",
                "proof": "intros sd_q8. unfold sdf_coverage_u8. lia."
            }],
            []
        ),
        z3_50,
    ))

    # 51. BoxShadowBlurFalloff (core/paint/box_painter_base.cc)
    def z3_51() -> bool:
        base_a, dist, blur = z3.Ints("base_a dist blur")
        alpha = z3.If(
            blur <= 0,
            z3.If(dist <= 0, base_a, 0),
            z3.If(dist <= 0, base_a, z3.If(blur <= dist, 0, (base_a * (blur - dist)) / blur)),
        )
        s = z3.Solver()
        s.add(0 <= base_a, base_a <= 255)
        s.add(z3.Not(z3.And(0 <= alpha, alpha <= base_a)))
        return s.check() == z3.unsat

    specs_and_smt.append((
        BlinkClassSpec(
            51, "BoxShadowBlurFalloff",
            [("base_alpha", "int32_t"), ("edge_dist", "int32_t"), ("blur_radius", "int32_t")],
            [{
                "name": "shadow_blur_alpha",
                "args": [("base_a", "int32_t"), ("dist", "int32_t"), ("blur", "int32_t")],
                "ret": "int32_t",
                "body": "if blur <=? 0 then (if dist <=? 0 then base_a else 0) else if dist <=? 0 then base_a else if blur <=? dist then 0 else (base_a * (blur - dist)) / blur",
                "theorem_name": "shadow_blur_alpha_within_base",
                "theorem_stmt": "forall (base_a dist blur : Z), 0 <= base_a <= 255 -> 0 <= shadow_blur_alpha base_a dist blur <= base_a",
                "proof": """intros base_a dist blur Ha. unfold shadow_blur_alpha.
  destruct (blur <=? 0) eqn:Eb.
  - destruct (dist <=? 0); lia.
  - apply Z.leb_gt in Eb.
    destruct (dist <=? 0) eqn:Ed.
    + lia.
    + apply Z.leb_gt in Ed.
      destruct (blur <=? dist) eqn:Ebd.
      * lia.
      * apply Z.leb_gt in Ebd. split.
        -- apply Z.div_pos; [nia | lia].
        -- apply Z.div_le_upper_bound; [lia | nia]."""
            }],
            ["0 <= base_alpha", "base_alpha <= 255"]
        ),
        z3_51,
    ))

    # 52. LinearGradientStopLerp (platform/graphics/gradient.cc)
    def z3_52() -> bool:
        c0, c1, t_q8 = z3.Ints("c0 c1 t_q8")
        t_clamped = z3.If(t_q8 < 0, 0, z3.If(t_q8 > 256, 256, t_q8))
        out = (c0 * (256 - t_clamped) + c1 * t_clamped) / 256
        s = z3.Solver()
        s.add(0 <= c0, c0 <= 255, 0 <= c1, c1 <= 255)
        s.add(z3.Not(z3.And(0 <= out, out <= 255)))
        return s.check() == z3.unsat

    specs_and_smt.append((
        BlinkClassSpec(
            52, "LinearGradientStopLerp",
            [("stop0_chan", "int32_t"), ("stop1_chan", "int32_t"), ("t_q8", "int32_t")],
            [{
                "name": "gradient_lerp_u8",
                "args": [("c0", "int32_t"), ("c1", "int32_t"), ("t_q8", "int32_t")],
                "ret": "int32_t",
                "body": "let t := Z.max 0 (Z.min 256 t_q8) in (c0 * (256 - t) + c1 * t) / 256",
                "theorem_name": "gradient_lerp_u8_in_byte_range",
                "theorem_stmt": "forall (c0 c1 t_q8 : Z), 0 <= c0 <= 255 -> 0 <= c1 <= 255 -> 0 <= gradient_lerp_u8 c0 c1 t_q8 <= 255",
                "proof": """intros c0 c1 t_q8 H0 H1. unfold gradient_lerp_u8.
  set (t := Z.max 0 (Z.min 256 t_q8)).
  assert (Ht : 0 <= t <= 256) by (unfold t; lia).
  split.
  - apply Z.div_pos; [nia | lia].
  - apply Z.div_le_upper_bound; [lia | nia]."""
            }],
            ["0 <= stop0_chan", "stop0_chan <= 255", "0 <= stop1_chan", "stop1_chan <= 255"]
        ),
        z3_52,
    ))

    # 53. PaintLayerGroupOpacity (core/paint/paint_layer_painter.cc)
    def z3_53() -> bool:
        src_a, grp_op = z3.Ints("src_a grp_op")
        eff_a = (src_a * grp_op) / 255
        s = z3.Solver()
        s.add(0 <= src_a, src_a <= 255, 0 <= grp_op, grp_op <= 255)
        s.add(z3.Not(z3.And(0 <= eff_a, eff_a <= src_a, eff_a <= grp_op)))
        return s.check() == z3.unsat

    specs_and_smt.append((
        BlinkClassSpec(
            53, "PaintLayerGroupOpacity",
            [("pixel_alpha", "int32_t"), ("group_opacity", "int32_t")],
            [{
                "name": "scale_group_alpha",
                "args": [("src_a", "int32_t"), ("grp_op", "int32_t")],
                "ret": "int32_t",
                "body": "(src_a * grp_op) / 255",
                "theorem_name": "scale_group_alpha_attenuates_both",
                "theorem_stmt": "forall (src_a grp_op : Z), 0 <= src_a <= 255 -> 0 <= grp_op <= 255 -> 0 <= scale_group_alpha src_a grp_op /\\ scale_group_alpha src_a grp_op <= src_a /\\ scale_group_alpha src_a grp_op <= grp_op",
                "proof": """intros src_a grp_op Hs Hg. unfold scale_group_alpha. split; [| split].
  - apply Z.div_pos; [nia | lia].
  - apply Z.div_le_upper_bound; [lia | nia].
  - apply Z.div_le_upper_bound; [lia | nia]."""
            }],
            ["0 <= pixel_alpha", "pixel_alpha <= 255", "0 <= group_opacity", "group_opacity <= 255"]
        ),
        z3_53,
    ))

    # 54. OverflowClipScissor (core/paint/clip_rect.cc)
    def z3_54() -> bool:
        px0, px1, cx0, cx1 = z3.Ints("px0 px1 cx0 cx1")
        ix0 = z3.If(px0 < cx0, cx0, px0)
        ix1 = z3.If(px1 < cx1, px1, cx1)
        w = z3.If(ix1 - ix0 < 0, 0, ix1 - ix0)
        s = z3.Solver()
        s.add(px0 <= px1)
        s.add(z3.Not(z3.And(0 <= w, w <= px1 - px0)))
        return s.check() == z3.unsat

    specs_and_smt.append((
        BlinkClassSpec(
            54, "OverflowClipScissor",
            [("parent_x0", "int32_t"), ("parent_x1", "int32_t"), ("child_x0", "int32_t"), ("child_x1", "int32_t")],
            [{
                "name": "scissor_intersect_span",
                "args": [("px0", "int32_t"), ("px1", "int32_t"), ("cx0", "int32_t"), ("cx1", "int32_t")],
                "ret": "int32_t",
                "body": "Z.max 0 (Z.min px1 cx1 - Z.max px0 cx0)",
                "theorem_name": "scissor_intersect_span_within_parent",
                "theorem_stmt": "forall (px0 px1 cx0 cx1 : Z), px0 <= px1 -> 0 <= scissor_intersect_span px0 px1 cx0 cx1 <= px1 - px0",
                "proof": "intros px0 px1 cx0 cx1 Hp. unfold scissor_intersect_span. lia."
            }],
            ["parent_x0 <= parent_x1"]
        ),
        z3_54,
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
    print("HM Hybrid Pillars 1 & 5 Synthesis (Classes 45..54 | 8 Parallel Agents)")
    print("Robinson MGU Row Typing + Z3 BGS-Spec UNSAT Gate + Rocq/Coq 9.3.0 Verification")
    print("=" * 84)

    items = get_pillars_1_5_specs()
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
    print(f"Generated Gallina Lines        : {total_loc} lines across 10 theories")
    print(f"Wall-Clock Synthesis Time      : {t_elapsed:.3f}s")
    print("=" * 84)

    return 0 if (passed == len(results) and admits == 0) else 1


if __name__ == "__main__":
    sys.exit(main())

