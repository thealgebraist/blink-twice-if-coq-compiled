(** * BlinkFirstLineLetterSemantics.v
    Formalization of Chromium Blink ::first-line and ::first-letter
    against CSS Pseudo-Elements Module Level 4 (Section 2).
*)

From Stdlib Require Import Lists.List.
From Stdlib Require Import Arith.PeanoNat.
From Stdlib Require Import Bool.Bool.
From Stdlib Require Import micromega.Lia.
Import ListNotations.

(** ** 1. Character Classification & Text Representation *)

Inductive CharClass : Type :=
  | CC_Space       (* Whitespace / Newline *)
  | CC_Punct       (* Punctuation *)
  | CC_LetterNum   (* Valid core typographic letter/number unit *)
  | CC_Combining   (* Combining diacritical marks *)
  | CC_Other.

Record CodePoint : Type := mkCodePoint {
  cp_id    : nat;
  cp_class : CharClass
}.

Definition TextBuffer := list CodePoint.

Record LayoutTextFragment : Type := mkFragment {
  frag_source : TextBuffer;
  frag_start  : nat;
  frag_length : nat
}.

Definition eval_fragment (f : LayoutTextFragment) : TextBuffer :=
  firstn (frag_length f) (skipn (frag_start f) (frag_source f)).

(** ** 2. Blink First-Letter Splitting State Machine *)

Definition is_space (c : CodePoint) : bool :=
  match cp_class c with CC_Space => true | _ => false end.

Definition is_punct (c : CodePoint) : bool :=
  match cp_class c with CC_Punct => true | _ => false end.

Definition is_letter_or_num (c : CodePoint) : bool :=
  match cp_class c with CC_LetterNum => true | _ => false end.

Definition is_combining (c : CodePoint) : bool :=
  match cp_class c with CC_Combining => true | _ => false end.

Fixpoint scan_leading_spaces (s : TextBuffer) : nat :=
  match s with
  | [] => 0
  | c :: rest => if is_space c then S (scan_leading_spaces rest) else 0
  end.

Fixpoint scan_punct (s : TextBuffer) : nat :=
  match s with
  | [] => 0
  | c :: rest => if is_punct c then S (scan_punct rest) else 0
  end.

Fixpoint scan_combining (s : TextBuffer) : nat :=
  match s with
  | [] => 0
  | c :: rest => if is_combining c then S (scan_combining rest) else 0
  end.

Definition compute_first_letter_length (s : TextBuffer) : nat :=
  let sp := scan_leading_spaces s in
  let s1 := skipn sp s in
  let p1 := scan_punct s1 in
  let s2 := skipn p1 s1 in
  match s2 with
  | [] => 0
  | c :: rest =>
      if is_letter_or_num c then
        let cb := scan_combining rest in
        let s3 := skipn (S cb) s2 in
        let p2 := scan_punct s3 in
        sp + p1 + 1 + cb + p2
      else 0
  end.

Definition split_first_letter (s : TextBuffer) : (LayoutTextFragment * LayoutTextFragment) :=
  let len := compute_first_letter_length s in
  let bounded_len := Nat.min len (length s) in
  (mkFragment s 0 bounded_len,
   mkFragment s bounded_len (length s - bounded_len)).

(** ** 3. ::first-line Style Filtering *)

Inductive CSSProperty : Type :=
  | PropFontSize
  | PropFontWeight
  | PropColor
  | PropBackground
  | PropLineHeight
  | PropLetterSpacing
  | PropDisplay
  | PropWidth
  | PropHeight
  | PropMargin
  | PropFloat.

Definition valid_for_first_line (p : CSSProperty) : bool :=
  match p with
  | PropFontSize
  | PropFontWeight
  | PropColor
  | PropBackground
  | PropLineHeight
  | PropLetterSpacing => true
  | PropDisplay
  | PropWidth
  | PropHeight
  | PropMargin
  | PropFloat => false
  end.

Definition StyleDeclaration := (CSSProperty * nat)%type.
Definition StyleMap := list StyleDeclaration.

Definition filter_first_line (m : StyleMap) : StyleMap :=
  filter (fun decl => valid_for_first_line (fst decl)) m.

(** ** 4. Mathematical Invariants & Verification *)

(** Invariant 1: First-letter text splitting preserves exact string concatenation *)
Theorem first_letter_partition_exact : forall s,
  let '(f1, f2) := split_first_letter s in
  eval_fragment f1 ++ eval_fragment f2 = s.
Proof.
  intros s.
  unfold split_first_letter, eval_fragment.
  set (len := compute_first_letter_length s).
  set (bounded_len := Nat.min len (length s)).
  simpl frag_start. simpl frag_length. simpl frag_source.
  rewrite skipn_O.
  assert (Hle : bounded_len <= length s) by apply Nat.le_min_r.
  assert (Hlen : length s - bounded_len = length (skipn bounded_len s)).
  { rewrite length_skipn. reflexivity. }
  rewrite Hlen.
  rewrite firstn_all.
  apply firstn_skipn.
Qed.

(** Invariant 2: Total length is conserved across text fragments *)
Theorem first_letter_length_conserved : forall s,
  let '(f1, f2) := split_first_letter s in
  length (eval_fragment f1) + length (eval_fragment f2) = length s.
Proof.
  intros s.
  pose proof (first_letter_partition_exact s) as Hpart.
  destruct (split_first_letter s) as [f1 f2].
  rewrite <- (length_app (eval_fragment f1) (eval_fragment f2)).
  rewrite Hpart.
  reflexivity.
Qed.

(** Invariant 3: First-line property filter is idempotent *)
Theorem filter_first_line_idempotent : forall m,
  filter_first_line (filter_first_line m) = filter_first_line m.
Proof.
  induction m as [| [p v] rest IH].
  - reflexivity.
  - simpl.
    destruct (valid_for_first_line p) eqn:Hp.
    + simpl. rewrite Hp. rewrite IH. reflexivity.
    + exact IH.
Qed.

(** Invariant 4: Layout-affecting box properties (width, display, float) are rejected *)
Theorem filter_rejects_layout_properties : forall m p,
  valid_for_first_line p = false ->
  forall decl, In decl (filter_first_line m) -> fst decl <> p.
Proof.
  intros m p Hnot decl Hin Heq.
  unfold filter_first_line in Hin.
  apply filter_In in Hin.
  destruct Hin as [_ Hvalid].
  simpl in Hvalid.
  subst p.
  rewrite Hnot in Hvalid.
  discriminate.
Qed.
