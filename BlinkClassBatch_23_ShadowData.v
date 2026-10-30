(* Blink2Coq Synthesis for ShadowData *)
(* Source: third_party/blink/renderer/core/style/shadow_data.cc *)

Require Import ZArith.
Theorem shadow_outsets_comm : forall a b : Z,
  Z.max a b = Z.max b a.
Proof. intros. apply Z.max_comm. Qed.
