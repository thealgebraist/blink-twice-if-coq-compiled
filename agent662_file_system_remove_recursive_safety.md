# Formal Verification Report: File System Access API `removeEntry` Recursive Safety Check

**Agent Identifier:** Formal Verification Agent 662  
**Domain:** Web Platform File System, Streams, Shape Detection, and Platform Totality  
**Target Component:** Chromium Blink `FileSystemDirectoryHandle::removeEntry`  
**Chromium Source:** `third_party/blink/renderer/modules/file_system_access/file_system_directory_handle.cc`  
**Specification Target:** File System Access API (WICG / WHATWG File System Standard) §6  
**Formal Theory Target:** `BlinkFileSystemRemoveRecursiveSafetySemantics.v`  
**Core Mathematical Property:** $\text{can\_remove}(\text{is\_empty}, \text{recursive}) = \text{is\_empty} \lor \text{recursive}$

---

## 1. Normative W3C/WHATWG Specification Requirements

In the WHATWG File System Standard and WICG File System Access API Specification (§6, *The `FileSystemDirectoryHandle` interface*), the `removeEntry(name, options)` method allows a web application to request the removal of a file or directory entry identified by `name` within the context of a parent `FileSystemDirectoryHandle`.

### 1.1 WebIDL Definition

```webidl
dictionary FileSystemRemoveOptions {
  boolean recursive = false;
};

[Exposed=(Window,Worker), SecureContext, Serializable]
interface FileSystemDirectoryHandle : FileSystemHandle {
  Promise<undefined> removeEntry(USVString name, optional FileSystemRemoveOptions options = {});
};
```

### 1.2 Normative Algorithm Steps for `removeEntry(name, options)`

When `removeEntry(name, options)` is invoked, the user agent must execute the following normative steps:

1. Let `result` be a new `Promise`.
2. In parallel, run the following steps:
   a. Validate `name`: If `name` is not a valid file name (e.g., empty string, contains path separators, is `.` or `..`), reject `result` with a `TypeError` and abort these steps.
   b. Locate the entry corresponding to `this` handle in the underlying file system. If not found, reject `result` with a `"NotFoundError"` `DOMException` and abort.
   c. Verify access permissions (`readwrite`). If permission is not `"granted"`, reject `result` with a `"NotAllowedError"` `DOMException` and abort.
   d. Look up the child entry named `name` within the directory. If no such entry exists, reject `result` with a `"NotFoundError"` `DOMException` and abort.
   e. **Recursive Removal Safety Check:**
      * If the child entry is a **directory**:
        1. Let `is_empty` be true if the directory contains zero children, and false otherwise.
        2. Let `recursive` be `options["recursive"]` (which defaults to `false`).
        3. **If `is_empty` is `false` and `recursive` is `false`, reject `result` with an `"InvalidModificationError"` `DOMException` and abort these steps.**
      * If the child entry is a **file**:
        1. The entry has no child entries (vacuously empty with respect to directory containment). Removal proceeds regardless of the `recursive` boolean flag.
   f. Attempt to remove the child entry (and all its descendants if it is a non-empty directory and `recursive` is `true`).
   g. If the removal fails due to OS-level constraints, reject `result` with an `"InvalidModificationError"` or `"NoModificationAllowedError"` `DOMException`.
   h. Otherwise, resolve `result` with `undefined`.

The critical safety invariant mandated by Step 2.e is that a non-empty directory can never be destroyed unless the caller explicitly sets `options.recursive = true`.

---

## 2. Blink Implementation Details and Invariants

In Chromium, the renderer-side binding for `removeEntry` is implemented in `third_party/blink/renderer/modules/file_system_access/file_system_directory_handle.cc` and delegates the actual filesystem mutation over Mojo IPC to the browser process (`content/browser/file_system_access/file_system_access_directory_handle_impl.cc` and `storage/browser/file_system/file_system_operation_impl.cc`).

### 2.1 Renderer Implementation (`file_system_directory_handle.cc`)

```cpp
ScriptPromise<IDLUndefined> FileSystemDirectoryHandle::removeEntry(
    ScriptState* script_state,
    const String& name,
    const FileSystemRemoveOptions* options,
    ExceptionState& exception_state) {
  if (!mojo_ptr_.is_bound()) {
    exception_state.ThrowDOMException(DOMExceptionCode::kInvalidStateError, "");
    return EmptyPromise();
  }

  auto* resolver =
      MakeGarbageCollected<ScriptPromiseResolver<IDLUndefined>>(
          script_state, exception_state.GetContext());
  auto result = resolver->Promise();

  if (!FileSystemAccessDirectoryHandleImpl::IsValidPathComponent(name)) {
    resolver->RejectWithTypeError("Name is not allowed.");
    return result;
  }

  mojo_ptr_->RemoveEntry(
      name, options->recursive(),
      WTF::BindOnce(
          [](FileSystemDirectoryHandle*,
             ScriptPromiseResolver<IDLUndefined>* resolver,
             mojom::blink::FileSystemAccessErrorPtr result) {
            file_system_access_error::ResolveOrReject(resolver, *result);
          },
          WrapPersistent(this), WrapPersistent(resolver)));

  return result;
}
```

### 2.2 Browser & Storage Enforcement Invariants

When `mojo_ptr_->RemoveEntry(name, options->recursive(), ...)` crosses the Mojo boundary into `FileSystemAccessDirectoryHandleImpl::RemoveEntry`:

1. **Option Forwarding Invariant:** Blink's generated WebIDL binding for `FileSystemRemoveOptions` guarantees that `options->recursive()` is initialized to `false` if omitted by JavaScript, ensuring total boolean valuation prior to IPC serialization.
2. **Storage Operation Dispatch:** The browser process invokes `FileSystemOperationRunner::Remove(url, recursive, callback)`.
3. **Safety Check Realization:**
   * If `recursive == false`, the storage layer invokes non-recursive removal (`FileSystemOperationImpl::Remove` with `recursive = false`), which translates to `base::DeleteFile` (non-recursive) or `ObfuscatedFileUtil::DeleteDirectory`.
   * Both the sandboxed (`ObfuscatedFileUtil`) and local (`NativeFileUtil`) backends enforce the POSIX/Win32 `rmdir` semantics when `recursive == false`: if the target is a directory and its child list is non-empty, the underlying operation returns `base::File::FILE_ERROR_NOT_EMPTY`.
   * `FileSystemAccessDirectoryHandleImpl` maps `base::File::FILE_ERROR_NOT_EMPTY` to `mojom::FileSystemAccessStatus::kInvalidModificationError`, which `file_system_access_error::ResolveOrReject` in Blink translates into a `DOMException` with `DOMExceptionCode::kInvalidModificationError`.
4. **Totality Invariant:** Every execution path through `RemoveEntry` terminates in exactly one Mojo callback invocation carrying a `FileSystemAccessErrorPtr`, resolving or rejecting the `ScriptPromiseResolver<IDLUndefined>`.

---

## 3. Formal Specification Definitions in Rocq/Coq

Below is the complete, self-contained formalization in Rocq/Coq (`BlinkFileSystemRemoveRecursiveSafetySemantics.v`). It models the WebIDL options, directory tree state, recursive removal predicate, error codes, and the state transition semantics of `removeEntry`.

```coq
(** * BlinkFileSystemRemoveRecursiveSafetySemantics.v
    Formal verification of the File System Access API removeEntry recursive
    safety check in Chromium Blink.
*)

Require Import Coq.Bool.Bool.
Require Import Coq.Lists.List.
Require Import Coq.ZArith.ZArith.
Require Import Coq.micromega.Lia.
Import ListNotations.

Open Scope bool_scope.
Open Scope Z_scope.

(** ** 1. Core Mathematical Predicate *)

(** The fundamental safety predicate specified by File System Access API §6:
    An entry with emptiness status [is_empty] can be removed under flag [recursive]
    if and only if [is_empty || recursive] holds. *)
Definition can_remove (is_empty : bool) (recursive : bool) : bool :=
  is_empty || recursive.

(** ** 2. Web Platform Types and File System Model *)

(** Identifier for entry names (modeled as Z for decidable equality). *)
Definition EntryName := Z.

(** WebIDL FileSystemRemoveOptions dictionary.
    In WebIDL: dictionary FileSystemRemoveOptions { boolean recursive = false; }; *)
Record FileSystemRemoveOptions : Type := mkRemoveOptions {
  opt_recursive : bool
}.

(** Default WebIDL options when omitted by the caller. *)
Definition default_remove_options : FileSystemRemoveOptions :=
  mkRemoveOptions false.

(** File System Entry representation: either a File or a Directory containing
    a list of child entries. *)
Inductive FSEntry : Type :=
  | FSFile : EntryName -> FSEntry
  | FSDirectory : EntryName -> list FSEntry -> FSEntry.

(** Extract the name of a file system entry. *)
Definition entry_name (e : FSEntry) : EntryName :=
  match e with
  | FSFile n => n
  | FSDirectory n _ => n
  end.

(** Determine whether a list of child entries is empty. *)
Definition children_empty (children : list FSEntry) : bool :=
  match children with
  | [] => true
  | _ :: _ => false
  end.

(** Determine whether an entry is considered "empty" for removal purposes.
    - A file has no child entries, so it is vacuously empty (true).
    - A directory is empty iff its children list is empty. *)
Definition is_entry_empty (e : FSEntry) : bool :=
  match e with
  | FSFile _ => true
  | FSDirectory _ children => children_empty children
  end.

(** Count of immediate children of an entry (0 for files). *)
Definition child_count (e : FSEntry) : Z :=
  match e with
  | FSFile _ => 0
  | FSDirectory _ children => Z.of_nat (length children)
  end.

(** ** 3. DOMException and Mojo Result Model *)

Inductive DOMExceptionCode : Type :=
  | kTypeError
  | kInvalidStateError
  | kNotFoundError
  | kNotAllowedError
  | kInvalidModificationError.

(** Promise settlement outcome in Blink. *)
Inductive RemoveResult (State : Type) : Type :=
  | Resolved : State -> RemoveResult State
  | Rejected : DOMExceptionCode -> State -> RemoveResult State.

Arguments Resolved {State} _.
Arguments Rejected {State} _ _.

(** ** 4. Directory Lookup and Removal Operations *)

(** Find the first child entry with the matching name. *)
Fixpoint find_entry (name : EntryName) (children : list FSEntry) : option FSEntry :=
  match children with
  | [] => None
  | e :: rest =>
      if Z.eqb (entry_name e) name then Some e
      else find_entry name rest
  end.

(** Remove the child entry with the matching name from the child list. *)
Fixpoint filter_out_entry (name : EntryName) (children : list FSEntry) : list FSEntry :=
  match children with
  | [] => []
  | e :: rest =>
      if Z.eqb (entry_name e) name then filter_out_entry name rest
      else e :: filter_out_entry name rest
  end.

(** Model of a FileSystemDirectoryHandle state in Blink. *)
Record DirectoryHandleState : Type := mkDirState {
  mojo_bound : bool;
  valid_name_pred : EntryName -> bool;
  has_write_permission : bool;
  dir_children : list FSEntry
}.

(** Complete operational semantics of FileSystemDirectoryHandle::removeEntry. *)
Definition blink_remove_entry
    (state : DirectoryHandleState)
    (name : EntryName)
    (options : option FileSystemRemoveOptions)
    : RemoveResult DirectoryHandleState :=
  if negb (mojo_bound state) then
    Rejected kInvalidStateError state
  else if negb (valid_name_pred state name) then
    Rejected kTypeError state
  else if negb (has_write_permission state) then
    Rejected kNotAllowedError state
  else
    let recursive :=
      match options with
      | None => opt_recursive default_remove_options
      | Some opts => opt_recursive opts
      end
    in
    match find_entry name (dir_children state) with
    | None => Rejected kNotFoundError state
    | Some target =>
        let is_empty := is_entry_empty target in
        if can_remove is_empty recursive then
          let new_children := filter_out_entry name (dir_children state) in
          Resolved (mkDirState
                      (mojo_bound state)
                      (valid_name_pred state)
                      (has_write_permission state)
                      new_children)
        else
          Rejected kInvalidModificationError state
    end.
```

---

## 4. Concrete Theorems and Complete Proofs

All theorems below are proven without `admit` or `Admitted`, utilizing `Bool`, `List`, `ZArith`, and `Lia`.

```coq
(** ** 5. Formal Verification Theorems and Proofs *)

(** Theorem 1: Exact algebraic characterization of [can_remove]. *)
Theorem can_remove_characterization :
  forall (is_empty recursive : bool),
    can_remove is_empty recursive = true <->
    (is_empty = true \/ recursive = true).
Proof.
  intros is_empty recursive.
  unfold can_remove.
   apply orb_true_iff.
Qed.

(** Theorem 2: Non-empty directory with recursive = false is strictly blocked. *)
Theorem non_empty_non_recursive_blocked :
  forall (is_empty recursive : bool),
    can_remove is_empty recursive = false <->
    (is_empty = false /\ recursive = false).
Proof.
  intros is_empty recursive.
  unfold can_remove.
  apply orb_false_iff.
Qed.

(** Theorem 3: Monotonicity of [can_remove] with respect to the [recursive] flag.
    Enabling [recursive] never revokes removal permission. *)
Theorem can_remove_monotone_recursive :
  forall (is_empty : bool),
    can_remove is_empty false = true ->
    can_remove is_empty true = true.
Proof.
  intros is_empty H.
  unfold can_remove in *.
  rewrite orb_true_r.
  reflexivity.
Qed.

(** Theorem 4: Quantitative equivalence between [is_entry_empty] and [child_count = 0]. *)
Theorem is_entry_empty_iff_zero_children :
  forall (e : FSEntry),
    is_