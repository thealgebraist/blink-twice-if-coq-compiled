**Audit Report: Blink `FileList` Implementation (`length` and Indexing)**
**Auditor:** Agent 488
**Target:** Chromium / Blink Rendering Engine (`third_party/blink/renderer/core/fileapi/file_list.*`)

---

### 1. Executive Summary
The `FileList` interface in Blink represents an array-like object of `File` objects, typically returned by the `HTMLInputElement.files` property or the `DataTransfer.files` property during drag-and-drop operations. 

This audit details the enforcement of **non-negativity** on the `length` attribute and the mechanics of **item indexing**, spanning from the Web IDL binding layer down to the C++ implementation and underlying WTF (Web Template Framework) data structures.

---

### 2. Non-Negativity of `length`

The non-negativity of `FileList.length` is strictly enforced across three layers: the Web IDL specification, the V8-to-Blink binding generator, and the underlying C++ data types.

#### A. Web IDL Layer (`file_list.idl`)
In Blink's IDL definition, the `length` attribute and the `item` method index are defined using the `unsigned long` Web IDL type:
```webidl
[Exposed=Window, Serializable]
interface FileList {
    getter File? item(unsigned long index);
    readonly attribute unsigned long length;
};
```
*Audit Note:* In Web IDL, `unsigned long` maps to an integer range of $[0, 2^{32}-1]$. Negative values are structurally impossible at the specification level.

#### B. C++ Implementation Layer (`file_list.h` / `file_list.cc`)
In the C++ backing class `blink::FileList`, the `length()` method returns an `unsigned` integer (specifically `unsigned int` / `uint32_t`), directly reflecting the size of the internal `WTF::Vector`:
```cpp
unsigned length() const { return files_.size(); }
```
 internally, `files_` is defined as:
```cpp
HeapVector<Member<File>> files_;
```
The `WTF::Vector` (and Oilpan's `HeapVector`) uses `wtf_size_t` (an alias for `uint32_t`) to track capacity and size. Because `wtf_size_t` is unsigned, `files_.size()` is guaranteed to be non-negative ($\ge 0$). Furthermore, `WTF::Vector` enforces a hard maximum capacity limit (typically `kMax Capacity`), preventing integer overflow from wrapping a massive allocation into a negative representation in signed contexts.

---

### 3. Item Indexing Mechanics

Indexing into a `FileList` can occur via two JavaScript patterns: explicit method invocation (`fileList.item(index)`) or indexed property access (`fileList[index]`).

#### A. Bounds Checking in C++ (`FileList::item`)
Both access patterns funnel into the C++ method `FileList::item(unsigned index)`. The implementation performs a strict upper-bound check:

```cpp
File* FileList::item(unsigned index) const {
  if (index >= files_.size())
    return nullptr;
  return files_[index].Get();
}
```
* **Lower-bound check:** Omitted in C++ because `index` is `unsigned`. It is mathematically impossible for `index < 0` at this layer.
* **Upper-bound check:** If `index` is greater than or equal to `files_.size()`, it safely prevents an out-of-bounds (OOB) memory read on the `HeapVector` and returns `nullptr` (which translates to `null` or `undefined` in JS, depending on how it was accessed).

#### B. Explicit Method Access: `fileList.item(index)`
When a script calls `fileList.item(-1)`, the V8-to-Blink bindings layer intercepts the call before reaching C++:
1. V8 converts the JS Number `-1` to an `unsigned long` using the Web IDL `ToUint32` (modulo $2^{32}$) conversion semantics.
2. `-1` wraps around to `4294967295` ($2^{32} - 1$).
3. `FileList::item(4294967295)` is invoked in C++.
4. Assuming the `FileList` does not contain $4.29 \times 10^9$ files (which is impossible due to Oilpan/PartitionAlloc memory limits), the check `index >= files_.size()` evaluates to `true`.
5. `nullptr` is returned, which the binding layer converts to JavaScript **`null`**.

#### C. Indexed Property Access: `fileList[index]`
Because `FileList` defines a `getter` in its IDL, V8 configures an **Indexed Property Getter** on the `FileList` object template. This behaves differently from `.item()` when handling negative or out-of-bounds numbers:

1. **Negative Indices (e.g., `fileList[-1]`):** 
   In JavaScript/ECMAScript, array index properties are strictly defined as canonical numeric strings representing integers in the range $[0, 2^{32}-2]$. Therefore, `-1` is **not** treated as an array index by V8; it is treated as a standard named property `" -1"`. V8 bypasses the Blink indexed property getter entirely, checks the standard prototype chain, finds nothing, and returns **`undefined`**.
2. **Valid Non-Negative Indices (e.g., `fileList[0]`):** 
   V8 recognizes `0` as a valid array index and invokes the Blink indexed property interceptor. Blink calls `FileList::item(0)` and returns the corresponding `File` wrapper.
3. **Out-of-Bounds Non-Negative Indices (e.g., `fileList[999]`):** 
   V8 invokes the Blink indexed property interceptor. `FileList::item(999)` returns `nullptr`. In the context of an indexed property getter (unlike a standard method call), the Blink bindings layer translates a `nullptr` return value into **`undefined`** (to match standard JS Array behavior) rather than `null`.

---

### 4. Audit Conclusion & Security Posture

| Vector | Behavior | Security / Stability Risk |
| :--- | :--- | :--- |
| **`fileList.length`** | Returns `uint32_t` via `HeapVector::size()`. | **None.** Strictly non-negative. |
| **`fileList.item(-1)`** | Casts to `4294967295` via `ToUint32`, fails bounds check, returns `null`. | **None.** Safe unsigned wrap-around handled by upper-bound check. |
| **`fileList[-1]`** | Handled by V8 as a named property lookup; returns `undefined`. | **None.** Does not reach C++ indexing logic. |
| **`fileList[OOB]`** | Fails `index >= files_.size()`, returns `undefined`. | **None.** OOB memory read is prevented before `HeapVector::operator[]` is called. |

**Status:** **SECURE / COMPLIANT.** 
Blink's `FileList` implementation correctly enforces non-negativity and memory-safe indexing in strict accordance with the W3C File API specification and Web IDL standards.