# Formal Verification Report: File System `SyncAccessHandle` Exclusive File Locking Semantics

**Agent**: Formal Verification Agent 663  
**Specialization**: Web Platform File System, Streams, Shape Detection, and Platform Totality in Chromium Blink  
**Topic**: File System `SyncAccessHandle` Exclusive File Locking Semantics  
**Chromium Source**: `third_party/blink/renderer/modules/file_system_access/file_system_sync_access_handle.cc`  
**Specification**: WHATWG File System Standard / WICG File System Access API §7 (`createSyncAccessHandle` exclusive file lock)  
**Formal Theory Target**: `BlinkSyncAccessHandleLockExclusivitySemantics.v`  
**Core Mathematical Property**: $\text{acquire\_lock}(\text{locked}) = \text{if } \text{locked} \text{ then } \text{None} \text{ else } \text{Some } \text{true}$

---

## 1. Exact Normative W3C/WHATWG Specification Requirements

Within the WHATWG File System Standard and WICG File System Access specification, high-performance synchronous file I/O in Dedicated Workers is mediated through the `FileSystemSyncAccessHandle` interface, obtained via `FileSystemFileHandle.createSyncAccessHandle()`. 

### 1.1 Lock Acquisition (`createSyncAccessHandle`)
According to the specification for `createSyncAccessHandle()` on `FileSystemFileHandle`:
1. Every file entry in the origin-private file system (OPFS) has an associated **lock** state, which is either *unlocked*, *locked exclusively* (taken by a `FileSystemSyncAccessHandle`), or *locked shared* (taken by `FileSystemWritableFileStream`). Under the default exclusive mode (`readwrite`), only one active `SyncAccessHandle` may hold the lock for a given file entry at any point in time.
2. When `createSyncAccessHandle()` is invoked:
   - Let *promise* be a new promise.
   - Run steps in parallel to locate the underlying file entry.
   - Attempt to **take a lock** with value *exclusive* on the file:
     - If the file's lock is currently held (i.e., `locked == true`), the lock acquisition fails. The algorithm rejects *promise* with a `NoModificationAllowedError` `DOMException` (or `InvalidStateError` depending on lock contention context).
     - If the file's lock is currently *unlocked* (`locked == false`), the lock state transitions atomically to *locked* (`locked' == true`), and a new `FileSystemSyncAccessHandle` object is instantiated and resolved via *promise*.

### 1.2 Synchronous I/O Invariants (`read`, `write`, `truncate`, `getSize`, `flush`)
For all synchronous operations on `FileSystemSyncAccessHandle`:
1. Each method first checks the handle's internal `[[state]]` slot (which is `"open"` or `"closed"`).
2. If `[[state]]` is `"closed"`, the method immediately throws an `InvalidStateError` `DOMException` without performing any OS-level file descriptor operations.
3. While `[[state]]` is `"open"`, the exclusive lock on the underlying file is guaranteed to be held (`locked == true`) by this specific handle.

### 1.3 Lock Release (`close`)
When `close()` is invoked on `FileSystemSyncAccessHandle`:
1. If `[[state]]` is already `"closed"`, the operation is an idempotent no-op and returns `undefined`.
2. If `[[state]]` is `"open"`:
   - Set `[[state]]` to `"closed"`.
   - Close the underlying OS file handle.
   - **Release the lock** on the associated file entry (`locked' == false`), allowing subsequent `createSyncAccessHandle()` invocations on the same file to succeed.

---

## 2. Blink Implementation Details and Invariants

In Chromium's Blink rendering engine, the renderer-side logic for `FileSystemSyncAccessHandle` resides in `third_party/blink/renderer/modules/file_system_access/file_system_sync_access_handle.cc` (paired with `file_system_file_handle.cc` and browser-process lock management in `content/browser/file_system_access/file_system_access_lock_manager.cc`).

### 2.1 Lock Acquisition & Mojo IPC Lifetime
When `FileSystemFileHandle::createSyncAccessHandle` is called in Blink:
1. It sends an asynchronous Mojo IPC call `FileSystemAccessFileHandleHost::OpenAccessHandle()` to the browser process.
2. The browser process invokes `FileSystemAccessLockManager::TakeLock()` for the file's `storage::FileSystemURL` with an exclusive lock type.
3. If an existing lock conflicts (`locked == true`), `TakeLock()` returns `nullptr`, and the Mojo callback returns `FileSystemAccessError::New(mojom::blink::FileSystemAccessStatus::kNoModificationAllowedError, ...)`. Blink rejects the script promise without constructing a `FileSystemSyncAccessHandle`.
4. If `TakeLock()` succeeds (`locked == false` $\to$ `locked' == true`), the browser retains a `scoped_refptr<FileSystemAccessLockManager::LockHandle>` bound to the `FileSystemAccessAccessHandleHost` Mojo receiver, and returns both the `base::File` (wrapped in `FileSystemAccessRegularFile` or incumbent quota file wrapper) and the `mojo::PendingRemote<mojom::blink::FileSystemAccessAccessHandleHost>` to Blink.

### 2.2 Handle State Representation in `file_system_sync_access_handle.cc`
Inside `FileSystemSyncAccessHandle`:
- **Exclusive Ownership**: Blink holds `HeapMojoRemote<mojom::blink::FileSystemAccessAccessHandleHost> access_handle_host_` and `Member<FileSystemAccessFileDelegate> file_delegate_`.
- **Closed State Tracking**: A boolean member `is_closed_` (initialized to `false` upon construction) tracks the synchronous state of the handle.
- **Synchronous Method Guards**:
  ```cpp
  uint64_t FileSystemSyncAccessHandle::read(
      MaybeShared<DOMArrayBufferView> buffer,
      FileSystemReadWriteOptions* options,
      ExceptionState& exception_state) {
    if (is_closed_ || !file_delegate_->IsValid()) {
      exception_state.ThrowDOMException(DOMExceptionCode::kInvalidStateError,
                                        "The file was already closed");
      return 0;
    }
    // ...
  }
  ```
  The exact same guard protects `write()`, `truncate()`, `getSize()`, and `flush()`.
- **Synchronous Lock Release (`close()`)**:
  ```cpp
  void FileSystemSyncAccessHandle::close() {
    if (is_closed_) {
      return;
    }
    DCHECK(file_delegate_->IsValid());
    DCHECK(access_handle_host_.is_bound());

    is_closed_ = true;
    file_delegate_->Close();
    access_handle_host_->Close();
    access_handle_host_.reset();
  }
  ```
- **Invariants Maintained by Blink**:
  1. **Exclusivity**: At most one live (`is_closed_ == false`) `FileSystemSyncAccessHandle` instance can exist per file entry across the entire browser context group.
  2. **Monotonic Handle Closure**: Once `is_closed_` transitions from `false` to `true`, it never transitions back to `false` for that handle instance.
  3. **Synchronous IPC Synchrony**: `access_handle_host_->Close()` is a `[Sync]` Mojo method in `file_system_access_access_handle_host.mojom`. This guarantees that the browser-side `LockHandle` is destroyed and the exclusive lock is released *before* `close()` returns to JavaScript, allowing an immediately subsequent `createSyncAccessHandle()` call on the next line of JS to acquire the lock deterministically.

---

## 3. Formal Specification Definitions in Rocq/Coq

Below is the complete, self-contained formalization of `BlinkSyncAccessHandleLockExclusivitySemantics.v` in Rocq/Coq. It models the direct mathematical lock acquisition primitive, the full state machine of a file and its handles in Blink, synchronous I/O guard semantics, and multi-handle trace invariants.

```coq
(** * BlinkSyncAccessHandleLockExclusivitySemantics.v
    Formal Verification of File System SyncAccessHandle Exclusive File Locking
    in Chromium Blink (file_system_sync_access_handle.cc). *)

From Coq Require Import Bool.Bool.
From Coq Require Import Arith.PeanoNat.
From Coq Require Import ZArith.ZArith.
From Coq Require Import Lists.List.
From Coq Require Import micromega.Lia.
Import ListNotations.

Open Scope bool_scope.
Open Scope nat_scope.

(* ========================================================================== *)
(* 1. Core Mathematical Lock Primitive                                        *)
(* ========================================================================== *)

(** The core mathematical property specified for exclusive lock acquisition:
    acquire_lock(locked) = if locked then None else Some true. *)
Definition acquire_lock (locked : bool) : option bool :=
  if locked then None else Some true.

(** Releasing an exclusive lock unconditionally transitions the lock state
    to false (unlocked). *)
Definition release_lock (locked : bool) : bool :=
  false.

(* ========================================================================== *)
(* 2. Blink SyncAccessHandle & File System State Machine                      *)
(* ========================================================================== *)

(** Unique identifier for a FileSystemSyncAccessHandle instance in Blink. *)
Definition HandleId := nat.

(** DOMException codes relevant to FileSystemSyncAccessHandle operations. *)
Inductive DOMException : Type :=
  | NoModificationAllowedError (* Thrown when lock acquisition fails *)
  | InvalidStateError.         (* Thrown on I/O when is_closed_ is true *)

(** Result of an operation in Blink paired with ExceptionState. *)
Inductive BlinkResult (A : Type) : Type :=
  | Ok (val : A)
  | Throw (ex : DOMException).

Arguments Ok {A} val.
Arguments Throw {A} ex.

(** Synchronous operations supported by FileSystemSyncAccessHandle. *)
Inductive SyncIOOp : Type :=
  | OpRead
  | OpWrite
  | OpTruncate
  | OpGetSize
  | OpFlush.

(** Representation of a single FileSystemSyncAccessHandle in Blink.
    Mirrors `is_closed_` and `access_handle_host_.is_bound()` in
    file_system_sync_access_handle.cc. *)
Record HandleState : Type := mkHandleState {
  handle_id : HandleId;
  is_closed : bool;
  host_bound : bool
}.

(** Global state for a single OPFS File Entry and all handles ever created
    for it.
    - [file_locked]: Browser-side LockManager state for this file URL.
    - [active_owner]: The HandleId currently holding the exclusive lock, if any.
    - [next_handle_id]: Monotonic counter for fresh handle allocations.
    - [handles]: List of all instantiated handles (both open and closed). *)
Record FileLockSystemState : Type := mkSystemState {
  file_locked : bool;
  active_owner : option HandleId;
  next_handle_id : HandleId;
  handles : list HandleState
}.

(** Initial state of an unlocked file with no handles. *)
Definition initial_system_state : FileLockSystemState := {|
  file_locked := false;
  active_owner := None;
  next_handle_id := 0;
  handles := []
|}.

(** Lookup a handle by its HandleId. *)
Fixpoint find_handle (hid : HandleId) (hs : list HandleState) : option HandleState :=
  match hs with
  | [] => None
  | h :: rest =>
      if Nat.eqb (handle_id h) hid then Some h else find_handle hid rest
  end.

(** Update a handle in the handle list to mark it closed and unbind its host. *)
Fixpoint close_handle_in_list (hid : HandleId) (hs : list HandleState) : list HandleState :=
  match hs with
  | [] => []
  | h :: rest =>
      if Nat.eqb (handle_id h) hid then
        {| handle_id := handle_id h; is_closed := true; host_bound := false |}
          :: close_handle_in_list hid rest
      else
        h :: close_handle_in_list hid rest
  end.

(** Count the number of currently open handles (`is_closed = false`). *)
Fixpoint count_open_handles (hs : list HandleState) : nat :=
  match hs with
  | [] => 0
  | h :: rest =>
      (if is_closed h then 0 else 1) + count_open_handles rest
  end.

(* ========================================================================== *)
(* 3. Blink Operations: createSyncAccessHandle, Sync I/O, and close()         *)
(* ========================================================================== *)

(** Specification of `FileSystemFileHandle::createSyncAccessHandle()`.
    Uses `acquire_lock` to check and transition the file lock state. *)
Definition blink_create_sync_access_handle (st : FileLockSystemState)
  : FileLockSystemState * BlinkResult HandleId :=
  match acquire_lock (file_locked st) with
  | None =>
      (st, Throw NoModificationAllowedError)
  | Some new_lock_state =>
      let hid := next_handle_id st in
      let new_handle := {|
        handle_id := hid;
        is_closed := false;
        host_bound := true
      |} in
      let st' := {|
        file_locked := new_lock_state;
        active_owner := Some hid;
        next_handle_id := S hid;
        handles := new_handle :: handles st
      |} in
      (st', Ok hid)
  end.

(** Specification of synchronous I/O operations (`read`, `write`, `truncate`,
    `getSize`, `flush`) in `file_system_sync_access_handle.cc`.
    Checks `if (is_closed_ || !file_delegate_->IsValid())`. *)
Definition blink_sync_io (st : FileLockSystemState) (hid : HandleId) (op : SyncIOOp)
  : BlinkResult unit :=
  match find_handle hid (handles st) with
  | None => Throw InvalidStateError
  | Some h =>
      if is_closed h || negb (host_bound h) then
        Throw InvalidStateError
      else
        Ok tt
  end.

(** Specification of `FileSystemSyncAccessHandle::close()` in
    `file_system_sync_access_handle.cc`.
    - If `is_closed_` is true, returns immediately (no-op).
    - Otherwise sets `is_closed_ = true`, unbinds `access_handle_host_`,
      and synchronously releases the browser-side lock. *)
Definition blink_close_handle (st : FileLockSystemState) (hid : HandleId)
  : FileLockSystemState :=
  match find_handle hid (handles st) with
  | None => st
  | Some h =>
      if is_closed h then
        st
      else
        {|
          file_locked := release_lock (file_