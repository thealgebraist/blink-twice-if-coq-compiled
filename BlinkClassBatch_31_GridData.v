(* Blink2Coq Synthesis for GridData *)
(* Source: third_party/blink/renderer/core/layout/grid/grid_data.cc *)

Require Import ZArith Lia. Open Scope Z_scope.
Definition expand_implicit_tracks (old_count req_idx : Z) : Z :=
  Z.max old_count (req_idx + 1).
Theorem implicit_tracks_monotonic : forall old_c req_idx,
  old_c <= expand_implicit_tracks old_c req_idx.
Proof. intros. unfold expand_implicit_tracks. apply Z.le_max_l. Qed.
