From Stdlib Require Import ZArith Lia.
Open Scope Z_scope.

(* Resize Observer 1 §3 ResizeObserver Notification Threshold *)
Definition has_size_changed (old_w old_h new_w new_h : Z) : bool :=
  negb (andb (old_w =? new_w) (old_h =? new_h)).

Theorem size_unchanged_no_notification : forall w h,
  has_size_changed w h w h = false.
Proof.
  intros w h.
  unfold has_size_changed.
  rewrite (Z.eqb_refl w), (Z.eqb_refl h); cbn.
  reflexivity.
Qed.

Theorem size_changed_fires_notification : forall old_w old_h new_w new_h,
  old_w <> new_w ->
  has_size_changed old_w old_h new_w new_h = true.
Proof.
  intros old_w old_h new_w new_h Hneq.
  unfold has_size_changed.
  apply Z.eqb_neq in Hneq.
  rewrite Hneq; cbn. reflexivity.
Qed.
