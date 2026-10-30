# Formal Verification Research Report: File System Access API Handle Kind Enum Semantics

**Agent**: Formal Verification Agent 657 (Web Platform File System, Streams, Shape Detection, and Platform Totality)  
**Topic**: File System Access API `FileSystemHandle.kind` Enum Semantics  
**Chromium Source Target**: `third_party/blink/renderer/modules/file_system_access/file_system_handle.cc`  
**Specification Target**: WICG / WHATWG File System Standard §4 (`FileSystemHandle` Interface)  
**Formal Theory Target**: `BlinkFileSystemHandleKindSemantics.v`  
**Mathematical Property**: `kind_to_int` injectivity, distinct enum values for `file` and `directory`, and total round-trip conversion across Blink C++, V8 IDL bindings, and Mojo IPC boundaries.

---

## 1. Exact Normative W3C/WHATWG Specification Requirements

In the WHATWG File System Standard (and WICG File System Access specification), §4 defines the `FileSystemHandle` interface and its associated enumeration `FileSystemHandleKind`.

### 1.1 WebIDL Definition
```webidl
enum FileSystemHandleKind {
  "file",
  "directory"
};

[Exposed=(Window,Worker), SecureContext, Serializable]
interface FileSystemHandle {
  readonly attribute FileSystemHandleKind kind;
  readonly attribute USVString name;

  Promise<boolean> isSameEntry(FileSystemHandle other);
};
```

### 1.2 Normative Requirements
1. **Exhaustive Domain**: A `FileSystemHandle` represents an entry in a file system. Every handle has an associated `kind`, which must strictly be one of the two `FileSystemHandleKind` enumeration values: `"file"` or `"directory"`.
2. **Disjoint Subtyping**:
   - The `kind` getter on `FileSystemFileHandle` must always return `"file"` (`V8FileSystemHandleKind::Enum::kFile`).
   - The `kind` getter on `FileSystemDirectoryHandle` must always return `"directory"` (`V8FileSystemHandleKind::Enum::kDirectory`).
3. **Same-Entry Comparison (`isSameEntry`)**: Two `FileSystemHandle` objects cannot represent the same entry unless their underlying `kind` values are identical. Specifically, a file handle and a directory handle can never be the same entry, even if they share a path or name across sequential operations.
4. **Serialization Invariant**: When a `FileSystemHandle` is serialized (via `StructuredSerialize`), its `kind` discriminator is preserved intact so that `StructuredDeserialize` reconstructs the exact corresponding subclass (`FileSystemFileHandle` or `FileSystemDirectoryHandle`).

---

## 2. Blink Implementation Details and Invariants

In Chromium's Blink rendering engine, `FileSystemHandle` is implemented as an abstract C++ base class in `third_party/blink/renderer/modules/file_system_access/file_system_handle.h` and `file_system_handle.cc`.

### 2.1 C++ Class Hierarchy and Virtual Dispatch
In `file_system_handle.h`:
```cpp
class FileSystemHandle : public ScriptWrappable,
                         public ExecutionContextClient {
  DEFINE_WRAPPERTYPEINFO();
 public:
  FileSystemHandle(ExecutionContext* execution_context, const String& name);
  ~FileSystemHandle() override = default;

  virtual bool isFile() const { return false; }
  virtual bool isDirectory() const { return false; }
  const String& kind() const { return isFile() ? "file" : "directory"; }
  // Or in newer V8 binding generators:
  // V8FileSystemHandleKind kind() const;
  const String& name() const { return name_; }
  ...
};
```

And in `file_system_handle.cc`:
```cpp
// static
FileSystemHandle* FileSystemHandle::CreateFromMojoEntry(
    mojom::blink::FileSystemAccessEntryPtr e,
    ExecutionContext* execution_context) {
  if (e->entry_handle->is_file()) {
    return MakeGarbageCollected<FileSystemFileHandle>(
        execution_context, e->name, std::move(e->entry_handle->get_file()));
  }
  return MakeGarbageCollected<FileSystemDirectoryHandle>(
      execution_context, e->name, std::move(e->entry_handle->get_directory()));
}
```

### 2.2 V8 Bindings Enum Representation
The Blink IDL compiler generates `V8FileSystemHandleKind` from `file_system_handle.idl`:
```cpp
class V8FileSystemHandleKind {
 public:
  enum class Enum {
    kFile = 0,
    kDirectory = 1,
  };
  static constexpr size_t kEnumSize = 2;
  ...
};
```

### 2.3 Mojo Union Discriminator (`FileSystemAccessEntryHandle`)
Across the browser-renderer IPC boundary (`third_party/blink/public/mojom/file_system_access/file_system_access_directory_handle.mojom`), the entry handle is transmitted as a Mojo union:
```mojom
union FileSystemAccessEntryHandle {
  pending_remote<FileSystemAccessFileHandle> file;
  pending_remote<FileSystemAccessDirectoryHandle> directory;
};
```
In generated C++ (`file_system_access_directory_handle.mojom-blink.h`), the union tag is:
```cpp
enum class Tag : uint32_t {
  kFile = 0,
  kDirectory = 1,
};
```

### 2.4 Core Implementation Invariants
1. **Partition Totality**: Every concrete `FileSystemHandle` instance instantiated in Blink is either a `FileSystemFileHandle` (`isFile() == true`, `isDirectory() == false`) or a `FileSystemDirectoryHandle` (`isFile() == false`, `isDirectory() == true`). The base class `FileSystemHandle` is never instantiated directly.
2. **Discriminator Distinctness (`kind_to_int`)**: The integer mapping of `kFile` ($0$) and `kDirectory` ($1$) in both `V8FileSystemHandleKind::Enum` and `mojom::blink::FileSystemAccessEntryHandle::Tag` assigns strictly distinct integer values to file and directory kinds.
3. **Factory Exactness (`CreateFromMojoEntry`)**: The factory method `FileSystemHandle::CreateFromMojoEntry` inspects `e->entry_handle->is_file()` and deterministically constructs a `FileSystemFileHandle` if and only if the Mojo tag is `Tag::kFile`, and a `FileSystemDirectoryHandle` if and only if the Mojo tag is `Tag::kDirectory`.

---

## 3. Formal Specification Definitions in Rocq/Coq

Below is the self-contained formalization in `BlinkFileSystemHandleKindSemantics.v`. It models the WebIDL enumeration, the V8/Mojo integer encodings, the C++ runtime subclass predicates, and the `CreateFromMojoEntry` factory semantics.

```coq
(** * BlinkFileSystemHandleKindSemantics.v
    Formal Verification of File System Access API Handle Kind Enum Semantics
    in Chromium Blink (third_party/blink/renderer/modules/file_system_access/file_system_handle.cc)
*)

Require Import Coq.ZArith.ZArith.
Require Import Coq.micromega.Lia.
Require Import Coq.Bool.Bool.
Require Import Coq.Lists.List.
Import ListNotations.

Open Scope Z_scope.

(** ** 1. Specification Domain: FileSystemHandleKind (§4) *)

Inductive FileSystemHandleKind : Type :=
  | KindFile : FileSystemHandleKind
  | KindDirectory : FileSystemHandleKind.

(** Decidable equality for FileSystemHandleKind *)
Definition kind_eq_dec (k1 k2 : FileSystemHandleKind) : {k1 = k2} + {k1 <> k2}.
Proof.
  decide equality.
Defined.

(** Boolean equality for FileSystemHandleKind *)
Definition kind_eqb (k1 k2 : FileSystemHandleKind) : bool :=
  match k1, k2 with
  | KindFile, KindFile => true
  | KindDirectory, KindDirectory => true
  | _, _ => false
  end.

(** ** 2. Integer Encoding: V8FileSystemHandleKind::Enum & Mojo Tag *)

(** Maps FileSystemHandleKind to its underlying C++ enum integer value:
    V8FileSystemHandleKind::Enum::kFile = 0
    V8FileSystemHandleKind::Enum::kDirectory = 1 *)
Definition kind_to_int (k : FileSystemHandleKind) : Z :=
  match k with
  | KindFile => 0
  | KindDirectory => 1
  end.

(** Partial inverse: maps integer back to FileSystemHandleKind *)
Definition int_to_kind (n : Z) : option FileSystemHandleKind :=
  if Z.eqb n 0 then Some KindFile
  else if Z.eqb n 1 then Some KindDirectory
  else None.

(** Valid enum integer range predicate: 0 <= n < kEnumSize (2) *)
Definition valid_kind_int (n : Z) : Prop :=
  0 <= n < 2.

(** ** 3. Blink C++ Class Hierarchy and Mojo Entry Model *)

(** Represents mojom::blink::FileSystemAccessEntryHandle union *)
Inductive MojoEntryHandle : Type :=
  | MojoFileHandle (remote_id : Z)
  | MojoDirectoryHandle (remote_id : Z).

(** Represents mojom::blink::FileSystemAccessEntry struct *)
Record MojoEntry : Type := mkMojoEntry {
  mojo_name : Z; (* Abstracted string identifier *)
  mojo_entry_handle : MojoEntryHandle
}.

(** Mojo union tag inspection: e->entry_handle->is_file() *)
Definition mojo_is_file (eh : MojoEntryHandle) : bool :=
  match eh with
  | MojoFileHandle _ => true
  | MojoDirectoryHandle _ => false
  end.

(** Mojo union tag inspection: e->entry_handle->is_directory() *)
Definition mojo_is_directory (eh : MojoEntryHandle) : bool :=
  match eh with
  | MojoFileHandle _ => false
  | MojoDirectoryHandle _ => true
  end.

(** Represents the concrete Blink C++ subclasses of FileSystemHandle *)
Inductive BlinkFileSystemHandle : Type :=
  | BlinkFileHandle (name : Z) (remote_id : Z)
  | BlinkDirectoryHandle (name : Z) (remote_id : Z).

(** Virtual method: FileSystemHandle::isFile() *)
Definition blink_is_file (h : BlinkFileSystemHandle) : bool :=
  match h with
  | BlinkFileHandle _ _ => true
  | BlinkDirectoryHandle _ _ => false
  end.

(** Virtual method: FileSystemHandle::isDirectory() *)
Definition blink_is_directory (h : BlinkFileSystemHandle) : bool :=
  match h with
  | BlinkFileHandle _ _ => false
  | BlinkDirectoryHandle _ _ => true
  end.

(** Method: FileSystemHandle::kind()
    In file_system_handle.h:
    return isFile() ? "file" : "directory" (or V8 enum equivalent) *)
Definition blink_handle_kind (h : BlinkFileSystemHandle) : FileSystemHandleKind :=
  if blink_is_file h then KindFile else KindDirectory.

(** Method: FileSystemHandle::name() *)
Definition blink_handle_name (h : BlinkFileSystemHandle) : Z :=
  match h with
  | BlinkFileHandle n _ => n
  | BlinkDirectoryHandle n _ => n
  end.

(** Factory: FileSystemHandle::CreateFromMojoEntry in file_system_handle.cc *)
Definition create_from_mojo_entry (e : MojoEntry) : BlinkFileSystemHandle :=
  match mojo_entry_handle e with
  | MojoFileHandle id => BlinkFileHandle (mojo_name e) id
  | MojoDirectoryHandle id => BlinkDirectoryHandle (mojo_name e) id
  end.

(** Same-Entry semantic check (Necessary condition on kind) *)
Definition is_same_entry (h1 h2 : BlinkFileSystemHandle) : bool :=
  match h1, h2 with
  | BlinkFileHandle n1 id1, BlinkFileHandle n2 id2 =>
      andb (Z.eqb n1 n2) (Z.eqb id1 id2)
  | BlinkDirectoryHandle n1 id1, BlinkDirectoryHandle n2 id2 =>
      andb (Z.eqb n1 n2) (Z.eqb id1 id2)
  | _, _ => false
  end.
```

---

## 4. Concrete Theorems and Complete Rocq/Coq Proofs

The following theorems formally prove the mathematical properties of `kind_to_int`, the disjointness of `KindFile` and `KindDirectory`, the totality of the enum encoding, and the preservation of invariants across `CreateFromMojoEntry` and `isSameEntry`. All proofs are complete with **0 admits**.

```coq
(** ** 4. Formal Verification Theorems and Proofs *)

(** Theorem 1: Distinct enum values for file and directory.
    Directly establishes the primary mathematical property for kind_to_int. *)
Theorem kind_to_int_file_directory_distinct :
  kind_to_int KindFile <> kind_to_int KindDirectory.
Proof.
  simpl.
  lia.
Qed.

(** Theorem 2: kind_to_int is injective across the entire FileSystemHandleKind domain. *)
Theorem kind_to_int_injective :
  forall (k1 k2 : FileSystemHandleKind),
    kind_to_int k1 = kind_to_int k2 -> k1 = k2.
Proof.
  intros k1 k2 H.
  destruct k1, k2; simpl in H; try reflexivity; lia.
Qed.

(** Theorem 3: kind_to_int always produces a valid integer within [0, 2). *)
Theorem kind_to_int_bounds :
  forall (k : FileSystemHandleKind),
    valid_kind_int (kind_to_int k).
Proof.
  intros k.
  unfold valid_kind_int.
  destruct k; simpl; lia.
Qed.

(** Theorem 4: Left-inverse round-trip totality: int_to_kind (kind_to_int k) = Some k. *)
Theorem kind_int_roundtrip :
  forall (k : FileSystemHandleKind),
    int_to_kind (kind_to_int k) = Some k.
Proof.
  intros k.
  destruct k; simpl; reflexivity.
Qed.

(** Theorem 5: Right-inverse totality on valid integer bounds [0, 2). *)
Theorem int_kind_roundtrip_valid :
  forall (n : Z),
    valid_kind_int n ->
    exists (k : FileSystemHandleKind),
      int_to_kind n = Some k /\ kind_to_int k = n.
Proof.
  intros n [Hlow Hhigh].
  assert (Hcases : n = 0 \/ n = 1) by lia.
  destruct Hcases as [H0 | H1]; subst n.
  - exists KindFile. simpl. split; reflexivity.
  - exists KindDirectory.