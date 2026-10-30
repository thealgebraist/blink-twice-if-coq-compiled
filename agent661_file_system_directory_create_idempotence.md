# Formal Verification Report: File System Access API `getDirectoryHandle` Create Idempotence

**Agent ID:** 661  
**Specialization:** Web Platform File System, Streams, Shape Detection, and Platform Totality in Chromium Blink  
**Target Source:** `third_party/blink/renderer/modules/file_system_access/file_system_directory_handle.cc`  
**Specification:** File System Access API §6 (`getDirectoryHandle` with `create: true`)  
**Formal Theory Target:** `BlinkFileSystemDirectoryCreateIdempotenceSemantics.v`  
**Mathematical Property:** `create_dir(dir, name)` is idempotent on existing directory entries and fails deterministically on type mismatches without mutating the file system state.

---

## 1. Normative W3C/WHATWG Specification Requirements

In the WHATWG File System Standard and W3C File System Access API specification (Section 6: *The `FileSystemDirectoryHandle` interface*), the `getDirectoryHandle(name, options)` method allows web applications to resolve or create a subdirectory within the context of a parent directory handle.

### 1.1 Normative Algorithm (`getDirectoryHandle`)
When `directory.getDirectoryHandle(name, options)` is invoked, the user agent executes the following normative steps:

1. Let `promise` be a new Promise.
2. Run the following steps in parallel:
   a. If `name` is not a *valid file name* (e.g., empty string `""`, current directory `"."`, parent directory `".."`, or contains path separators `'/'` or `'\\'`), reject `promise` with a `TypeError` and abort.
   b. Let `entry` be the result of running the entry resolution algorithm for `directory`'s underlying locator with child `name`.
   c. If `options["create"]` is `true`:
      i. If permissions for `directory` do not satisfy `readwrite` mode, reject `promise` with a `"NotAllowedError"` `DOMException` and abort.
      ii. If `entry` is `null` (does not exist):
          1. Create a new directory entry in the underlying file system with name `name` and empty children list.
          2. If an OS/platform error occurs, reject `promise` with the corresponding `DOMException` and abort.
          3. Set `entry` to the newly created directory entry.
      iii. Else if `entry` is a *file entry*:
          1. Reject `promise` with a `"TypeMismatchError"` `DOMException` and abort.
      iv. Else (`entry` is an existing *directory entry*):
          1. **Idempotence Requirement:** Do not overwrite, truncate, or modify the children or metadata of `entry`. Retain `entry` as-is.
   d. Else (`options["create"]` is `false`):
      i. If permissions for `directory` do not satisfy `read` mode, reject `promise` with a `"NotAllowedError"` `DOMException` and abort.
      ii. If `entry` is `null`, reject `promise` with a `"NotFoundError"` `DOMException` and abort.
      iii. If `entry` is a *file entry*, reject `promise` with a `"TypeMismatchError"` `DOMException` and abort.
   e. Resolve `promise` with a new `FileSystemDirectoryHandle` associated with `entry`.

### 1.2 Formal Invariants Derived from Spec
- **Idempotence on Success:** For any valid state $\Sigma$, parent directory $d$, and valid name $n$, if $\text{getDirectoryHandle}(\Sigma, d, n, \text{true}) = \text{Success}(\Sigma', h_1)$, then immediately executing $\text{getDirectoryHandle}(\Sigma', d, n, \text{true})$ yields $\text{Success}(\Sigma', h_2)$ where the state $\Sigma'$ is strictly unchanged and $h_1 = h_2$.
- **Subtree Preservation:** If a directory named $n$ already exists under $d$ and contains existing child entries $C$, calling `getDirectoryHandle(n, {create: true})` preserves $C$ intact.
- **Error Totality & State Non-Mutation:** If $\text{getDirectoryHandle}(\Sigma, d, n, c)$ returns an error (e.g., `TypeMismatchError` because $n$ is a file, `TypeError` due to an invalid name, or `NotAllowedError`), the resulting file system state must be identical to $\Sigma$.

---

## 2. Chromium Blink Implementation Analysis

In Chromium, the renderer-side implementation resides in `third_party/blink/renderer/modules/file_system_access/file_system_directory_handle.cc` and delegates IPC execution via Mojo to `content/browser/file_system_access/file_system_access_directory_handle_impl.cc`.

### 2.1 Renderer Layer (`file_system_directory_handle.cc`)
```cpp
ScriptPromise<FileSystemDirectoryHandle>
FileSystemDirectoryHandle::getDirectoryHandle(
    ScriptState* script_state,
    const String& name,
    const FileSystemGetDirectoryOptions* options,
    ExceptionState& exception_state) {
  auto* resolver = MakeGarbageCollected<
      ScriptPromiseResolver<FileSystemDirectoryHandle>>(
      script_state, exception_state.GetContext());
  auto result = resolver->Promise();

  if (!mojo_ptr_.is_bound()) {
    resolver->RejectWithDOMException(DOMExceptionCode::kInvalidStateError, "");
    return result;
  }

  mojo_ptr_->GetDirectory(
      name, options->create(),
      WTF::BindOnce(
          [](FileSystemDirectoryHandle*,
             ScriptPromiseResolver<FileSystemDirectoryHandle>* resolver,
             const String& name, FileSystemAccessErrorPtr result,
             mojo::PendingRemote<mojom::blink::FileSystemAccessDirectoryHandle>
                 handle) {
            ExecutionContext* context = resolver->GetExecutionContext();
            if (!context)
              return;
            if (result->status != mojom::blink::FileSystemAccessStatus::kOk) {
              file_system_access_error::Reject(resolver, *result);
              return;
            }
            resolver->Resolve(MakeGarbageCollected<FileSystemDirectoryHandle>(
                context, name, std::move(handle)));
          },
          WrapPersistent(this), WrapPersistent(resolver), name));

  return result;
}
```

### 2.2 Browser & Storage Layer Semantics
When `mojo_ptr_->GetDirectory(name, create, callback)` reaches `FileSystemAccessDirectoryHandleImpl::GetDirectory`:
1. **Name Validation (`IsSafePathComponent`):** Validates that `name` is not empty, not `.` or `..`, and contains no path separators. If invalid, returns `FileSystemAccessStatus::kInvalidArgument` (mapped to `TypeError` in Blink).
2. **Permission Check:** If `create == true`, verifies `GetReadWritePermissionStatus() == PermissionStatus::GRANTED`. If `create == false`, verifies read permission.
3. **Storage Operation (`FileSystemOperationRunner::CreateDirectory` vs `DirectoryExists`):**
   - When `create == true`, Chromium invokes `operation_runner()->CreateDirectory(child_url, /*exclusive=*/false, /*recursive=*/false, callback)`.
   - Crucially, **`exclusive` is set to `false`**.
   - In the underlying `storage::FileSystemOperationImpl::CreateDirectory` and OS/sandboxed VFS backends (`base::File::Error`), when `exclusive == false`:
     - If the target path does not exist, the directory is created and `base::File::FILE_OK` is returned.
     - If the target path already exists and is a directory, `base::File::FILE_OK` is returned without modifying the directory or its contents.
     - If the target path already exists and is a regular file, `base::File::FILE_ERROR_NOT_A_DIRECTORY` or `FILE_ERROR_EXISTS` is returned, which `FileSystemAccessDirectoryHandleImpl` translates into `FileSystemAccessStatus::kInvalidModificationError` / `DOMExceptionCode::kTypeMismatchError`.

---

## 3. Formal Specification & Verification in Rocq/Coq

Below is the complete, self-contained formalization `BlinkFileSystemDirectoryCreateIdempotenceSemantics.v`. It models the file system directory state, entry kinds, permission states, name validity, the exact transition relation of `getDirectoryHandle`, and proves the core idempotence, subtree preservation, and error non-mutation theorems without any `Admitted` or `axiom` statements.

```coq
(** * BlinkFileSystemDirectoryCreateIdempotenceSemantics.v
    Formal Verification of File System Access API §6:
    FileSystemDirectoryHandle.getDirectoryHandle(name, {create: true}) Idempotence
    Target: third_party/blink/renderer/modules/file_system_access/file_system_directory_handle.cc *)

Require Import Coq.ZArith.ZArith.
Require Import Coq.Lists.List.
Require Import Coq.Bool.Bool.
Require Import Coq.Micromega.Lia.
Import ListNotations.

Open Scope Z_scope.

(** ** 1. Web Platform File System Domain Types *)

(** Node identifiers and names represented as integers (Z) for decidable equality. *)
Definition Name := Z.
Definition NodeId := Z.

(** Permission states modeled after blink::mojom::PermissionStatus *)
Inductive PermissionMode : Type :=
  | PermDenied : PermissionMode
  | PermReadOnly : PermissionMode
  | PermReadWrite : PermissionMode.

(** DOMException and JS Error codes modeled aftermojom::blink::FileSystemAccessStatus *)
Inductive FSException : Type :=
  | ErrInvalidState : FSException       (* Mojo pipe unbound *)
  | ErrTypeError : FSException          (* Invalid path component *)
  | ErrNotAllowed : FSException         (* Insufficient permission *)
  | ErrNotFound : FSException           (* Entry missing when create = false *)
  | ErrTypeMismatch : FSException.      (* Entry is a File, expected Directory *)

(** File System Entries inside a Directory *)
Inductive FSEntry : Type :=
  | FileEntry (id : NodeId) (size : Z)
  | DirEntry (id : NodeId) (children_count : Z).

(** A Directory node maps child Names to FSEntry values. *)
Definition DirMap := list (Name * FSEntry).

(** Complete state of a FileSystemDirectoryHandle context *)
Record DirectoryContext : Type := mkDirCtx {
  mojo_bound : bool;
  perm_mode : PermissionMode;
  next_node_id : NodeId;
  entries : DirMap
}.

(** Outcome of getDirectoryHandle *)
Inductive GetDirResult : Type :=
  | ResOk (new_ctx : DirectoryContext) (resolved_id : NodeId) (preserved_children : Z)
  | ResErr (unchanged_ctx : DirectoryContext) (err : FSException).

(** ** 2. Helper Functions and Decidable Predicates *)

(** Safe path component check: In our Z representation, names > 0 are valid names,
    while names <= 0 represent "", ".", "..", or strings with '/' or '\'. *)
Definition is_valid_name (n : Name) : bool :=
  0 <? n.

(** Permission check for getDirectoryHandle based on options.create *)
Definition has_required_permission (perm : PermissionMode) (create : bool) : bool :=
  match create, perm with
  | true, PermReadWrite => true
  | true, _ => false
  | false, PermReadOnly => true
  | false, PermReadWrite => true
  | false, PermDenied => false
  end.

(** Lookup an entry by Name in a DirMap *)
Fixpoint lookup_entry (n : Name) (m : DirMap) : option FSEntry :=
  match m with
  | [] => None
  | (k, v) :: rest =>
      if Z.eqb k n then Some v else lookup_entry n rest
  end.

(** Insert a new entry only if it does not exist (append/cons semantics) *)
Definition insert_new_dir (n : Name) (id : NodeId) (m : DirMap) : DirMap :=
  (n, DirEntry id 0) :: m.

(** ** 3. Operational Semantics of Blink getDirectoryHandle *)

(** Models FileSystemDirectoryHandle::getDirectoryHandle +
    FileSystemAccessDirectoryHandleImpl::GetDirectory(exclusive=false) *)
Definition getDirectoryHandle
  (ctx : DirectoryContext)
  (name : Name)
  (create : bool) : GetDirResult :=
  if negb (mojo_bound ctx) then
    ResErr ctx ErrInvalidState
  else if negb (is_valid_name name) then
    ResErr ctx ErrTypeError
  else if negb (has_required_permission (perm_mode ctx) create) then
    ResErr ctx ErrNotAllowed
  else
    match lookup_entry name (entries ctx) with
    | None =>
        if create then
          let allocated_id := next_node_id ctx in
          let updated_entries := insert_new_dir name allocated_id (entries ctx) in
          let ctx' := mkDirCtx
                        (mojo_bound ctx)
                        (perm_mode ctx)
                        (allocated_id + 1)
                        updated_entries in
          ResOk ctx' allocated_id 0
        else
          ResErr ctx ErrNotFound
    | Some (FileEntry _ _) =>
        ResErr ctx ErrTypeMismatch
    | Some (DirEntry existing_id existing_children) =>
        (* Exclusive = false: existing directory is returned unmodified *)
        ResOk ctx existing_id existing_children
    end.

(** ** 4. Fundamental Lemmas on Directory Lookup *)

Lemma lookup_insert_same : forall (n : Name) (id : NodeId) (m : DirMap),
  lookup_entry n (insert_new_dir n id m) = Some (DirEntry id 0).
Proof.
  intros n id m.
  unfold insert_new_dir.
  simpl.
  rewrite Z.eqb_refl.
  reflexivity.
Qed.

Lemma lookup_insert_other : forall (n1 n2 : Name) (id : NodeId) (m : DirMap),
  n1 <> n2 ->
  lookup_entry n1 (insert_new_dir n2 id m) = lookup_entry n1 m.
Proof.
  intros n1 n2 id m Hneq.
  unfold insert_new_dir.
  simpl.
  destruct (Z.eqb_spec n2 n1) as [Heq | Hneq'].
  - subst. contradiction.
  - reflexivity.
Qed.

(** ** 5. Main Formal Verification Theorems *)

(** *** Theorem 1: Existing Directory Idempotence & Subtree Preservation
    If a directory entry already exists in `ctx` with `existing_id` and `children`,
    calling `getDirectoryHandle(ctx, name, true)` (or `false`) returns `ctx`
    completely unmodified and preserves both the node ID and `children`. *)
Theorem getDirectoryHandle_existing_dir_idempotent :
  forall (ctx : DirectoryContext) (name : Name) (create : bool)
         (existing_id : NodeId) (children : Z),
    mojo_bound ctx = true ->
    is_valid_name