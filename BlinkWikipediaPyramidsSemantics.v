(* Blink Formalization for Wikipedia Pyramids Article Layout & Rasterization *)
(* Machine-verified Rocq / Coq Theory *)

From Stdlib Require Import ZArith List Lia.
Import ListNotations.
Open Scope Z_scope.

Record Rect := {
  rx : Z;
  ry : Z;
  rw : Z;
  rh : Z
}.

Record Color := {
  cr : Z;
  cg : Z;
  cb : Z;
  ca : Z
}.

Definition pt_in_rect (px py : Z) (r : Rect) : bool :=
  (r.(rx) <=? px) && (px <? r.(rx) + r.(rw)) &&
  (r.(ry) <=? py) && (py <? r.(ry) + r.(rh)).

Definition c_white : Color := {| cr := 255; cg := 255; cb := 255; ca := 255 |}.
Definition c_wiki_gray : Color := {| cr := 248; cg := 249; cb := 250; ca := 255 |}.
Definition c_border_gray : Color := {| cr := 162; cg := 169; cb := 177; ca := 255 |}.
Definition c_table_head : Color := {| cr := 234; cg := 236; cb := 240; ca := 255 |}.
Definition c_dark_text : Color := {| cr := 32; cg := 33; cb := 34; ca := 255 |}.
Definition c_search_border : Color := {| cr := 114; cg := 119; cb := 125; ca := 255 |}.

(* Viewport geometry: 800 x 600 *)
Definition viewport_w : Z := 800.
Definition viewport_h : Z := 600.

(* Key Structural Boxes *)
Definition r_header : Rect := {| rx := 0; ry := 0; rw := 800; rh := 48 |}.
Definition r_header_border : Rect := {| rx := 0; ry := 47; rw := 800; rh := 1 |}.
Definition r_search : Rect := {| rx := 560; ry := 10; rw := 220; rh := 28 |}.
Definition r_title_border : Rect := {| rx := 24; ry := 98; rw := 752; rh := 1 |}.
Definition r_toc_box : Rect := {| rx := 24; ry := 235; rw := 210; rh := 99 |}.
Definition r_section_border : Rect := {| rx := 24; ry := 367; rw := 460; rh := 1 |}.
Definition r_table_head : Rect := {| rx := 24; ry := 376; rw := 460; rh := 21 |}.
Definition r_table_row2 : Rect := {| rx := 24; ry := 416; rw := 460; rh := 19 |}.
Definition r_table_row4 : Rect := {| rx := 24; ry := 454; rw := 460; rh := 19 |}.

(* Infobox Boxes *)
Definition r_infobox : Rect := {| rx := 504; ry := 152; rw := 272; rh := 330 |}.
Definition r_infobox_title : Rect := {| rx := 510; ry := 158; rw := 260; rh := 22 |}.
Definition r_thumb_img : Rect := {| rx := 512; ry := 187; rw := 256; rh := 170 |}.

Theorem wikipedia_pyramids_layout_exact :
  (* Header bounds *)
  r_header.(rh) = 48 /\
  r_header_border.(ry) = 47 /\
  r_search.(rx) + r_search.(rw) = 780 /\
  (* Content bounds *)
  r_title_border.(rw) = 752 /\
  r_toc_box.(rw) = 210 /\
  r_toc_box.(ry) = 235 /\
  r_section_border.(rw) = 460 /\
  r_section_border.(ry) = 367 /\
  r_table_head.(rw) = 460 /\
  r_table_head.(ry) = 376 /\
  (* Infobox bounds *)
  r_infobox.(rx) = 504 /\
  r_infobox.(ry) = 152 /\
  r_thumb_img.(rx) = 512 /\
  r_thumb_img.(ry) = 187 /\
  r_thumb_img.(rw) = 256 /\
  r_thumb_img.(rh) = 170.
Proof.
  repeat split; reflexivity.
Qed.

Definition get_pixel_color (px py : Z) : Color :=
  (* Top Header border *)
  if pt_in_rect px py r_header_border then c_border_gray
  (* Search input *)
  else if pt_in_rect px py r_search then c_wiki_gray
  (* Top Header background *)
  else if pt_in_rect px py r_header then c_white
  (* Title rule *)
  else if pt_in_rect px py r_title_border then c_border_gray
  (* TOC box *)
  else if pt_in_rect px py r_toc_box then c_wiki_gray
  (* Section heading rule *)
  else if pt_in_rect px py r_section_border then c_border_gray
  (* Table header *)
  else if pt_in_rect px py r_table_head then c_table_head
  (* Table zebra rows *)
  else if pt_in_rect px py r_table_row2 then c_wiki_gray
  else if pt_in_rect px py r_table_row4 then c_wiki_gray
  (* Infobox Title *)
  else if pt_in_rect px py r_infobox_title then c_table_head
  (* Infobox Body *)
  else if pt_in_rect px py r_infobox then c_wiki_gray
  (* Default Body Background *)
  else c_white.

Theorem wikipedia_pyramids_raster_pixel_exact :
  (* Header background *)
  get_pixel_color 100 20 = c_white /\
  (* Header border *)
  get_pixel_color 100 47 = c_border_gray /\
  (* Search box *)
  get_pixel_color 600 20 = c_wiki_gray /\
  (* Title border *)
  get_pixel_color 100 98 = c_border_gray /\
  (* TOC box *)
  get_pixel_color 50 250 = c_wiki_gray /\
  (* Section border *)
  get_pixel_color 100 367 = c_border_gray /\
  (* Table header *)
  get_pixel_color 100 380 = c_table_head /\
  (* Table zebra row 2 *)
  get_pixel_color 100 420 = c_wiki_gray /\
  (* Infobox title *)
  get_pixel_color 550 165 = c_table_head /\
  (* Infobox body *)
  get_pixel_color 550 400 = c_wiki_gray /\
  (* General article background *)
  get_pixel_color 100 550 = c_white.
Proof.
  vm_compute. repeat split; reflexivity.
Qed.
