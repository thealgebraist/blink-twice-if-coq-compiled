Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink MathML Scriptlevel Font Scaling Semantics *)
(** MathML Core §2.4: size attenuation bounded below *)

Definition scale_font_size_scriptlevel (base_size : Z) (scriptlevel : nat) : Z :=
  match scriptlevel with
  | O => Z.max 1 base_size
  | S O => Z.max 1 (base_size * 71 / 100)
  | S (S _) => Z.max 1 (base_size * 50 / 100)
  end.

Theorem scaled_size_strictly_positive : forall base_size level,
  0 < scale_font_size_scriptlevel base_size level.
Proof.
  intros base_size level.
  unfold scale_font_size_scriptlevel.
  destruct level as [| [| n]]; lia.
Qed.
