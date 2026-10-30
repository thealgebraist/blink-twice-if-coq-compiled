# Formal Verification Report: File System Access API Name Validation and Path Separator Safety

**Agent Identifier:** Agent 658 (Web Platform File System, Streams, Shape Detection, and Platform Totality)  
**Target Component:** `third_party/blink/renderer/modules/file_system_access/file_system_handle.cc`  
**Formal Theory Target:** `BlinkFileSystemNameValidationSemantics.v`  
**Specification Reference:** WICG File System Access API §4, WHATWG File System Standard §2.1 (Entry Names)

---

## 1. Normative W3C / WHATWG Specification Requirements

The File System Access API (and its foundational core in the WHATWG File System Standard) enforces strict lexical constraints on entry names (file and directory names) to prevent path traversal vulnerabilities, directory escape attacks, and platform-specific path ambiguities when resolving handles via methods such as `FileSystemDirectoryHandle.getFileHandle(name, options)`, `FileSystemDirectoryHandle.getDirectoryHandle(name, options)`, `FileSystemDirectoryHandle.removeEntry(name, options)`, and `FileSystemHandle.move(destination, new_name)`.

According to **File System Standard §2.1 (Entry Names)** and **File System Access API §4 (FileSystemHandle / FileSystemDirectoryHandle)**:

A **valid file name** is a string (scalar value string / sequence of UTF-16 code units in DOMString) that satisfies all of the following normative conditions:

1. **Non-Emptiness:** It is not the empty string (`""`).
2. **Current Directory Exclusion:** It is not `"."` (a single U+002E FULL STOP).
3. **Parent Directory Exclusion:** It is not `".."` (two U+002E FULL STOP characters).
4. **Path Separator Exclusion:** It does not contain any character used as a path separator across any underlying operating system supported by the user agent. Specifically, in web platform implementations (and normatively specified for cross-platform interoperability):
   - It must not contain `/` (U+002F SOLIDUS).
   - It must not contain `\` (U+005C REVERSE SOLIDUS).

When any algorithm accepting an entry name receives a string that is not a valid file name, the user agent **must** immediately reject the returned Promise with a `TypeError` exception before queuing any parallel file system operations or IPC messages to the browser process.

### Mathematical Formulation of the Specification Property

Let $\Sigma$ be the alphabet of UTF-16 code units ($\mathbb{Z}_{2^{16}}$). Let $s \in \Sigma^*$ be a string of code units. The specification validity predicate $\text{IsValidFileName}(s)$ is defined as:

$$\text{IsValidFileName}(s) \iff (s \neq \epsilon) \land (s \neq [\text{'.'}]) \land (s \neq [\text{'.'}, \text{'.'}]) \land (\text{'/'} \notin s) \land (\text{'\textbackslash'} \notin s)$$

---

## 2. Chromium Blink Implementation Details and Invariants

In Chromium Blink, renderer-side entry name validation is implemented within the File System Access module (`third_party/blink/renderer/modules/file_system_access/`) and exposed across `FileSystemHandle` and `FileSystemDirectoryHandle` operations before dispatching Mojo IPC calls (`mojom::blink::FileSystemAccessDirectoryHandle` / `mojom::blink::FileSystemAccessTransferToken`).

### Implementation Architecture in `file_system_handle.cc` / `file_system_directory_handle.cc`

While Mojo IPC validation also occurs in the browser process (`content/browser/file_system_access/file_system_access_directory_handle_impl.cc` via `net::IsSafePortablePathComponent`), Blink enforces the exact web-exposed JavaScript `TypeError` invariants synchronously in the renderer to satisfy WebIDL and specification ordering rules:

```cpp
// Conceptual and structural representation of Blink's renderer-side validation
// in third_party/blink/renderer/modules/file_system_access/
bool IsValidFileName(const String& name) {
  if (name.empty())
    return false;
  if (name == "." || name == "..")
    return false;
  if (name.Contains('/') || name.Contains('\\'))
    return false;
  return true;
}
```

### Critical Renderer Invariants

1. **Totality and Exception Determinism:** `IsValidFileName` is a total, pure boolean function over `WTF::String` (normalizing `IsNull()` and `empty()` to `false`). Whenever `IsValidFileName(name)` returns `false`, `ScriptPromiseResolver::Reject(V8ThrowException::CreateTypeError(...))` is invoked synchronously, guaranteeing no unvalidated string crosses the Blink-Mojo boundary.
2. **Path Concatenation Safety:** If a parent path $P \in \Sigma^*$ is combined with a validated child entry name $N \in \Sigma^*$ via $P \mathbin{\Vert} [\text{'/'}] \mathbin{\Vert} N$, the number of path segments increases by exactly $1$, and the final segment of the resulting path is guaranteed to be $N$ without escaping $P$.
3. **Sub-Component Disjointness:** No prefix, suffix, or contiguous substring of a valid file name can introduce a directory separator.
4. **Equivalence of Decision Procedure and Declarative Specification:** The imperative short-circuiting C++ checks (`empty()`, `== "."`, `== ".."`, `Contains('/')`, `Contains('\\')`) are logically equivalent to the conjunction of the five mathematical specification properties.

---

## 3. Formal Specification in Rocq / Coq

Below is the complete, self-contained formalization of `BlinkFileSystemNameValidationSemantics.v`. We represent characters as integer code units (`Z`) and strings as `list Z`, matching UTF-16 / Latin-1 code unit sequences in `WTF::String`.

```coq
(** * BlinkFileSystemNameValidationSemantics.v
    Formal verification of File System Access API §4 entry name validation
    and path separator safety in Chromium Blink. *)

From Coq Require Import ZArith.
From Coq Require Import List.
From Coq Require Import Bool.
From Coq Require Import Lia.
Import ListNotations.

Open Scope Z_scope.

(** ** 1. Character Code Constants (ASCII / UTF-16 Code Units) *)

Definition char_dot : Z := 46.        (* '.' U+002E FULL STOP *)
Definition char_slash : Z := 47.      (* '/' U+002F SOLIDUS *)
Definition char_backslash : Z := 92.  (* '\' U+005C REVERSE SOLIDUS *)

(** A WTF::String in Blink is modeled as a sequence of UTF-16 code units. *)
Definition BlinkString := list Z.

Definition dot_str : BlinkString := [char_dot].
Definition dot_dot_str : BlinkString := [char_dot; char_dot].

(** ** 2. Boolean Decision Procedures (Modeling Blink C++ Implementation) *)

(** Checks if a code unit is present in the string (WTF::String::Contains). *)
Fixpoint contains_char (c : Z) (s : BlinkString) : bool :=
  match s with
  | [] => false
  | x :: xs => if Z.eqb x c then true else contains_char c xs
  end.

(** Exact string equality (WTF::operator==). *)
Fixpoint string_eqb (s1 s2 : BlinkString) : bool :=
  match s1, s2 with
  | [], [] => true
  | x :: xs, y :: ys => andb (Z.eqb x y) (string_eqb xs ys)
  | _, _ => false
  end.

(** Boolean predicates corresponding to the mathematical specification. *)
Definition non_empty_b (s : BlinkString) : bool :=
  match s with
  | [] => false
  | _ :: _ => true
  end.

Definition no_slash_b (s : BlinkString) : bool :=
  negb (contains_char char_slash s).

Definition no_backslash_b (s : BlinkString) : bool :=
  negb (contains_char char_backslash s).

Definition not_dot_dot_b (s : BlinkString) : bool :=
  negb (string_eqb s dot_dot_str).

Definition not_dot_b (s : BlinkString) : bool :=
  negb (string_eqb s dot_str).

(** Mathematical Property Target:
    is_valid_file_name(name) =
      non_empty && no_slash && no_backslash && name != '..' && name != '.' *)
Definition is_valid_file_name (name : BlinkString) : bool :=
  non_empty_b name &&
  no_slash_b name &&
  no_backslash_b name &&
  not_dot_dot_b name &&
  not_dot_b name.

(** Imperative C++ control-flow model of Blink's validation routine:
    if (name.empty()) return false;
    if (name == "." || name == "..") return false;
    if (name.Contains('/') || name.Contains('\\')) return false;
    return true; *)
Definition blink_cpp_is_valid_name (name : BlinkString) : bool :=
  if negb (non_empty_b name) then false
  else if orb (string_eqb name dot_str) (string_eqb name dot_dot_str) then false
  else if orb (contains_char char_slash name) (contains_char char_backslash name) then false
  else true.

(** ** 3. Propositional Specification Definitions (W3C / WHATWG Normative Spec) *)

Definition Spec_NonEmpty (s : BlinkString) : Prop :=
  s <> [].

Definition Spec_NoSlash (s : BlinkString) : Prop :=
  ~ In char_slash s.

Definition Spec_NoBackslash (s : BlinkString) : Prop :=
  ~ In char_backslash s.

Definition Spec_NotDotDot (s : BlinkString) : Prop :=
  s <> dot_dot_str.

Definition Spec_NotDot (s : BlinkString) : Prop :=
  s <> dot_str.

Definition Spec_ValidFileName (s : BlinkString) : Prop :=
  Spec_NonEmpty s /\
  Spec_NoSlash s /\
  Spec_NoBackslash s /\
  Spec_NotDotDot s /\
  Spec_NotDot s.

(** ** 4. Path Separator and Traversal Safety Model *)

Definition is_path_separator (c : Z) : bool :=
  orb (Z.eqb c char_slash) (Z.eqb c char_backslash).

(** Counts the number of path separators in a path string. *)
Fixpoint count_separators (s : BlinkString) : nat :=
  match s with
  | [] => 0%nat
  | x :: xs =>
      if is_path_separator x
      then S (count_separators xs)
      else count_separators xs
  end.

(** Joins a parent path and a child entry name using a forward slash. *)
Definition join_path (parent child : BlinkString) : BlinkString :=
  parent ++ [char_slash] ++ child.

(** Models a single step of canonical path resolution over path segments. *)
Definition resolve_segment (stack : list BlinkString) (seg : BlinkString) : list BlinkString :=
  if string_eqb seg [] then stack
  else if string_eqb seg dot_str then stack
  else if string_eqb seg dot_dot_str thenremovelast stack
  else stack ++ [seg].
```

---

## 4. Concrete Theorems and Complete Proofs

We now prove the soundness, completeness, equivalence of the imperative Blink implementation, path separator freedom, and directory traversal prevention without any axioms or admitted lemmas.

```coq
(** ** 5. Foundational Lemmas for String and Character Reflection *)

Lemma contains_char_iff_In : forall (c : Z) (s : BlinkString),
  contains_char c s = true <-> In c s.
Proof.
  intros c s.
  induction s as [| x xs IH].
  - simpl. split; intros H; inversion H.
  - simpl. destruct (Z.eqb_spec x c) as [Heq | Hneq].
    + subst x. split; intros _; [left; reflexivity | reflexivity].
    + split; intros H.
      * right. apply IH. exact H.
      * destruct H as [Heq | Hin].
        -- symmetry in Heq. contradiction.
        -- apply IH. exact Hin.
Qed.

Lemma contains_char_false_iff_not_In : forall (c : Z) (s : BlinkString),
  contains_char c s = false <-> ~ In c s.
Proof.
  intros c s.
  rewrite <- contains_char_iff_In.
  destruct (contains_char c s); split; intros H; try reflexivity; try congruence.
  exfalso. apply H. reflexivity.
Qed.

Lemma string_eqb_refl : forall (s : BlinkString),
  string_eqb s s = true.
Proof.
  induction s as [| x xs IH].
  - reflexivity.
  - simpl. rewrite Z.eqb_refl. simpl. exact IH.
Qed.

Lemma string_eqb_iff_eq : forall (s1 s2 : BlinkString),
  string_eqb s1 s2 = true <-> s1 = s2.
Proof.
  induction s1 as [| x xs IH]; intros [| y ys].
  - simpl. split; reflexivity.
  - simpl. split; intros H; discriminate H.
  - simpl. split; intros H; discriminate H.
  - simpl. rewrite andb_true_iff.
    rewrite Z.eqb_eq. rewrite IH.
    split.
    + intros [Hxy Hxsys]. subst. reflexivity.
    + intros Heq. inversion Heq. split; reflexivity.
Qed.

Lemma string_eqb_false_iff_neq : forall (s1 s2 : BlinkString),
  string_eqb s1 s2 = false <-> s1 <> s2.
Proof.
  intros s1 s2.
  rewrite <- string_eqb_iff_eq.
  destruct (string_eqb s1 s2); split; intros H; try reflexivity; try congruence.
  exfalso. apply H. reflexivity.
Qed.

Lemma non_empty_b_iff : forall (s : BlinkString),
  non_empty_b s = true <-> Spec_NonEmpty s.
Proof.
  intros [| x xs]; unfold Spec_NonEmpty; simpl.
  - split; intros H; [discriminate H | exfalso; apply H; reflexivity].
  - split; intros _; [discriminate | reflexivity].
Qed.

(** ** 6. Main Verification Theorems *)

(** *** Theorem 1: Equivalence of Imperative Blink C++ Code and Mathematical Property *)
Theorem blink_cpp_matches_mathematical_property : forall (name : BlinkString),
  blink_cpp_is_valid_name name = is_valid_file_name name.
Proof.
  intros name.
  unfold blink_cpp_is_valid_name, is_valid_file_name.
  unfold no_