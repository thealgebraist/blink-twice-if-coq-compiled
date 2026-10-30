From Stdlib Require Import ZArith Lia.
Open Scope Z_scope.

(* CSS View Transitions 1 §3 View Transition Pseudo-Element Tree *)
Inductive ViewTransitionPseudo :=
  | VTP_Root
  | VTP_Group
  | VTP_ImagePair
  | VTP_OldImage
  | VTP_NewImage.

Definition pseudo_depth (p : ViewTransitionPseudo) : Z :=
  match p with
  | VTP_Root      => 1
  | VTP_Group     => 2
  | VTP_ImagePair => 3
  | VTP_OldImage  => 4
  | VTP_NewImage  => 4
  end.

Theorem pseudo_tree_strictly_ordered :
  pseudo_depth VTP_Root < pseudo_depth VTP_Group /\
  pseudo_depth VTP_Group < pseudo_depth VTP_ImagePair /\
  pseudo_depth VTP_ImagePair < pseudo_depth VTP_OldImage.
Proof.
  unfold pseudo_depth; cbn. lia.
Qed.
