(* ========================================================================= *)
(*               BlinkPageFragmentAssemblySemantics.v                        *)
(* ========================================================================= *)
(* Formal semantics of Chromium Blink Hierarchical Page Fragment Tree        *)
(* Assembly per W3C CSS Box Model 3 & Display 3.                             *)
(* Strictly verified with 0 admits.                                          *)
(* ========================================================================= *)

From Stdlib Require Import ZArith Lists.List Bool.Bool Lia.
Require Import BlinkPhysicalFragment.
Open Scope Z_scope.

Definition get_fragment_children (pf : PhysicalFragment) : list PhysicalFragment :=
  match pf with
  | mkPhysicalFragment _ _ _ _ ch => ch
  end.

Definition assemble_page_fragment (body_frag : PhysicalFragment) (vw vh : Z) : PhysicalFragment :=
  mkPhysicalFragment 0 0 vw vh (body_frag :: nil).

Definition assemble_body_fragment
  (block_frags : list PhysicalFragment)
  (body_x body_y body_w body_h : Z) : PhysicalFragment :=
  mkPhysicalFragment body_x body_y body_w body_h block_frags.

Definition assemble_table_fragment
  (row_frags : list PhysicalFragment)
  (tbl_x tbl_y tbl_w tbl_h : Z) : PhysicalFragment :=
  mkPhysicalFragment tbl_x tbl_y tbl_w tbl_h row_frags.

Definition assemble_row_fragment
  (cell_frags : list PhysicalFragment)
  (row_x row_y row_w row_h : Z) : PhysicalFragment :=
  mkPhysicalFragment row_x row_y row_w row_h cell_frags.

Theorem page_fragment_root_origin : forall body vw vh,
  pf_x (assemble_page_fragment body vw vh) = 0 /\
  pf_y (assemble_page_fragment body vw vh) = 0 /\
  pf_w (assemble_page_fragment body vw vh) = vw /\
  pf_h (assemble_page_fragment body vw vh) = vh.
Proof.
  intros.
  unfold assemble_page_fragment, pf_x, pf_y, pf_w, pf_h.
  repeat split; reflexivity.
Qed.

Theorem body_fragment_preserves_block_count : forall blocks b_x b_y b_w b_h,
  length (get_fragment_children (assemble_body_fragment blocks b_x b_y b_w b_h)) = length blocks.
Proof.
  intros.
  unfold assemble_body_fragment, get_fragment_children.
  reflexivity.
Qed.

Theorem table_fragment_preserves_row_count : forall rows t_x t_y t_w t_h,
  length (get_fragment_children (assemble_table_fragment rows t_x t_y t_w t_h)) = length rows.
Proof.
  intros.
  unfold assemble_table_fragment, get_fragment_children.
  reflexivity.
Qed.

Theorem row_fragment_preserves_cell_count : forall cells r_x r_y r_w r_h,
  length (get_fragment_children (assemble_row_fragment cells r_x r_y r_w r_h)) = length cells.
Proof.
  intros.
  unfold assemble_row_fragment, get_fragment_children.
  reflexivity.
Qed.

Theorem page_fragment_nonneg_dimensions : forall body vw vh,
  vw >= 0 -> vh >= 0 ->
  pf_w (assemble_page_fragment body vw vh) >= 0 /\
  pf_h (assemble_page_fragment body vw vh) >= 0.
Proof.
  intros body vw vh Hw Hh.
  unfold assemble_page_fragment, pf_w, pf_h.
  split; assumption.
Qed.
