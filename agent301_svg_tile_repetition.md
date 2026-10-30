### Audit Report: Chromium Blink `feTile` Pattern Repetition

**Agent ID:** 301  
**Target Component:** Chromium Blink (`third_party/blink/renderer/core/svg/graphics/filters/svg_fe_tile.cc` & Skia `SkTileImageFilter` / `SkTileMode::kRepeat`)  
**Audit Scope:** Formal verification of discrete coordinate repetition logic for SVG `<feTile>` filter primitives.

---

### 1. Seamless Tiling Modulo Semantics
In Chromium Blink, the `<feTile>` filter primitive fills a target rectangle with a repeated, tiled pattern of an input image (`in`). When mapping an arbitrary pixel coordinate $p \in \mathbb{Z}$ from the destination filter region back to the source tile subregion of positive dimension $w \in \mathbb{Z}^+$, the coordinate transformation must rely on Euclidean division (mathematical modulo) rather than C++ truncated division (`%`). 

For any coordinate $p$ (which may be negative if the target filter region extends to the left/top of the tile origin) and tile span $w > 0$:
$$\text{tile\_coord}(p, w) = p \bmod w$$

In standard Euclidean mathematics (and Coq's `Z.modulo`), the remainder of division by a positive integer $w$always carries the sign of the divisor, guaranteeing seamless wrap-around across negative and positive coordinate spaces without reflection artifacts at the origin.

---

### 2. Core Invariants
1. **Strict Spatial Bounding (`tile_coord_bounded`):**  
   For any coordinate $p \in \mathbb{Z}$ and tile dimension $w > 0$, the mapped coordinate is strictly valid within the 0-indexed tile memory buffer:
   $$0 \le \text{tile\_coord}(p, w) \le w - 1$$

2. **Seamless Periodicity (`tile_coord_periodic`):**  
   Shifting the destination coordinate by exactly one tile span $w$ yields the exact same source sample coordinate, ensuring translational invariance without seams:
   $$\text{tile\_coord}(p + w, w) = \text{tile\_coord}(p, w)$$

3. **Generalized Multi-Tile Periodicity (`tile_coord_periodic_k`):**  
   Shifting by $k \in \mathbb{Z}$ tile spans preserves the sample coordinate:
   $$\text{tile\_coord}(p + k \cdot w, w) = \text{tile\_coord}(p, w)$$

---

### 3. Formal Verification (`BlinkSVGTileRepetitionSemantics.v`)

The following file compiles cleanly in Coq/Rocq (8.16+) with **0 admits**.

```coq
(** * BlinkSVGTileRepetitionSemantics.v
    Formal verification of Chromium Blink SVG <feTile> pattern repetition
    coordinate mapping and invariants.
    Agent 301 Audit Artifact.
*)

From Coq Require Import ZArith.
From Coq Require Import Lia.

Open Scope Z_scope.

Section FeTileSemantics.

  (** ** 1. Definitions *)

  (** [tile_coord p w] computes the local tile coordinate for a global
      filter coordinate [p] given a tile span (width or height) [w].
      In Coq, [Z.modulo] implements Euclidean modulo where the result
      has the sign of the divisor [w]. *)
  Definition tile_coord (p w : Z) : Z :=
    Z.modulo p w.

  (** Offset-aware variant: maps global coordinate [p] into a tile of
      span [w] starting at origin offset [o], returning local index in [0, w-1]. *)
  Definition tile_coord_offset (p o w : Z) : Z :=
    tile_coord (p - o) w.


  (** ** 2. Core Invariants *)

  (** Invariant 1a: Half-open bound [0 <= tile_coord p w < w]. *)
  Theorem tile_coord_lt_bound : forall (p w : Z),
    w > 0 ->
    0 <= tile_coord p w < w.
  Proof.
    intros p w Hw.
    unfold tile_coord.
    apply Z.mod_pos_bound.
    lia.
  Qed.

  (** Invariant 1b: Closed interval bound [0 <= tile_coord p w <= w - 1]
      matching discrete pixel array indices. *)
  Theorem tile_coord_bounded : forall (p w : Z),
    w > 0 ->
    0 <= tile_coord p w <= w - 1.
  Proof.
    intros p w Hw.
    pose proof (tile_coord_lt_bound p w Hw) as Hbound.
    lia.
  Qed.

  (** Invariant 2: Fundamental Periodicity.
      Advancing the coordinate by one tile span [w] produces the exact
      same tile sample coordinate. *)
  Theorem tile_coord_periodic : forall (p w : Z),
    w > 0 ->
    tile_coord (p + w) w = tile_coord p w.
  Proof.
    intros p w Hw.
    unfold tile_coord.
    replace (p + w) with (p + 1 * w) by lia.
    rewrite Z.mod_add by lia.
    reflexivity.
  Qed.


  (** ** 3. Extended Audit Properties *)

  (** Generalized Periodicity: Shifting by any integer multiple [k] of [w]
      is invariant. *)
  Theorem tile_coord_periodic_k : forall (p w k : Z),
    w > 0 ->
    tile_coord (p + k * w) w = tile_coord p w.
  Proof.
    intros p w k Hw.
    unfold tile_coord.
    rewrite Z.mod_add by lia.
    reflexivity.
  Qed.

  (** Identity within fundamental domain: Coordinates already inside
      the [0, w - 1] base tile map to themselves. *)
  Theorem tile_coord_idempotent_in_base : forall (p w : Z),
    w > 0 ->
    0 <= p <= w - 1 ->
    tile_coord p w = p.
  Proof.
    intros p w Hw Hp.
    unfold tile_coord.
    apply Z.mod_small.
    lia.
  Qed.

  (** Idempotence of the projection operator. *)
  Theorem tile_coord_idempotent : forall (p w : Z),
    w > 0 ->
    tile_coord (tile_coord p w) w = tile_coord p w.
  Proof.
    intros p w Hw.
    unfold tile_coord.
    apply Z.mod_mod.
    lia.
  Qed.

  (** Seamless boundary transition: Stepping from the last pixel of a tile
      (where tile_coord is w - 1) to the next pixel wraps cleanly to 0. *)
  Theorem tile_coord_seamless_wrap : forall (p w : Z),
    w > 0 ->
    tile_coord p w = w - 1 ->
    tile_coord (p + 1) w = 0.
  Proof.
    intros p w Hw Hlast.
    unfold tile_coord in *.
    rewrite <- Z.add_mod_idemp_l by lia.
    rewrite Hlast.
    replace (w - 1 + 1) with w by lia.
    apply Z.mod_same.
    lia.
  Qed.

  (** Offset variant inherits strict bounds. *)
  Theorem tile_coord_offset_bounded : forall (p o w : Z),
    w > 0 ->
    0 <= tile_coord_offset p o w <= w - 1.
  Proof.
    intros p o w Hw.
    unfold tile_coord_offset.
    apply tile_coord_bounded.
     exact Hw.
  Qed.

  (** Offset variant inherits periodicity. *)
  Theorem tile_coord_offset_periodic : forall (p o w : Z),
    w > 0 ->
    tile_coord_offset (p + w) o w = tile_coord_offset p o w.
  Proof.
    intros p o w Hw.
    unfold tile_coord_offset.
    replace (p + w - o) with ((p - o) + w) by lia.
    apply tile_coord_periodic.
    exact Hw.
  Qed.

End FeTileSemantics.
```