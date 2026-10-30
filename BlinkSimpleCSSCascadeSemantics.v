(* ========================================================================= *)
(*               BlinkSimpleCSSCascadeSemantics.v                            *)
(* ========================================================================= *)
(* Formal semantics of Chromium Blink Simple CSS Cascade & Property          *)
(* Inheritance per W3C CSS Cascading and Inheritance Module Level 4 §3 & §4. *)
(* Strictly verified with 0 admits.                                          *)
(* ========================================================================= *)

From Stdlib Require Import ZArith Lists.List Bool.Bool Lia.
Open Scope Z_scope.

Definition resolve_cascade_property (v_inline : option Z) (v_author : option Z) (v_ua : Z) : Z :=
  match v_inline with
  | Some vi => vi
  | None =>
      match v_author with
      | Some va => va
      | None => v_ua
      end
  end.

Definition resolve_inherited_property (specified_val : option Z) (parent_computed_val : Z) : Z :=
  match specified_val with
  | Some v => v
  | None => parent_computed_val
  end.

Definition resolve_non_inherited_property (specified_val : option Z) (default_initial_val : Z) : Z :=
  match specified_val with
  | Some v => v
  | None => default_initial_val
  end.

Theorem cascade_inline_overrides_all : forall vi va vua,
  resolve_cascade_property (Some vi) va vua = vi.
Proof.
  intros. reflexivity.
Qed.

Theorem cascade_author_overrides_ua : forall va vua,
  resolve_cascade_property None (Some va) vua = va.
Proof.
  intros. reflexivity.
Qed.

Theorem cascade_ua_fallback : forall vua,
  resolve_cascade_property None None vua = vua.
Proof.
  intros. reflexivity.
Qed.

Theorem inherited_child_override : forall vchild vparent,
  resolve_inherited_property (Some vchild) vparent = vchild.
Proof.
  intros. reflexivity.
Qed.

Theorem inherited_parent_fallback : forall vparent,
  resolve_inherited_property None vparent = vparent.
Proof.
  intros. reflexivity.
Qed.

Theorem non_inherited_initial_fallback : forall vinit,
  resolve_non_inherited_property None vinit = vinit.
Proof.
  intros. reflexivity.
Qed.

Theorem cascade_deterministic : forall vi va vua r1 r2,
  r1 = resolve_cascade_property vi va vua ->
  r2 = resolve_cascade_property vi va vua ->
  r1 = r2.
Proof.
  intros. subst. reflexivity.
Qed.

