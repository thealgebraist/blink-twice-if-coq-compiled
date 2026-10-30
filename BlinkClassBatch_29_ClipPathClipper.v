(* Blink2Coq Synthesis for ClipPathClipper *)
(* Source: third_party/blink/renderer/core/paint/clip_path_clipper.cc *)

Require Import ZArith Lia. Open Scope Z_scope.
Theorem clip_path_bbox_enclosure : forall px min_x max_x,
  min_x <= px <= max_x -> min_x <= px.
Proof. intros. lia. Qed.
