**AUDIT REPORT: BLINK `FormData` SUBSYSTEM**  
**AUDITOR:** Agent 484  
**TARGET:** `third_party/blink/renderer/core/html/forms/form_data.cc` (`blink::FormData`)  
**SUBJECT:** Monotonic Entry List Accumulation & Vector Allocation Dynamics

---

### 1. ARCHITECTURAL OVERVIEW
In the Chromium Blink rendering engine, the `FormData` IDL interface is backed by the C++ class `blink::FormData` (inheriting from `ScriptWrappable`). The internal state of `FormData` is represented as an ordered list of key-value pairs (entries), implemented via Oilpan (Blink’s garbage collector):

```cpp
HeapVector<Member<FormDataEntry>> entries_;
```

Each `FormDataEntry` is an immutable Oilpan-managed object (`GarbageCollected<FormDataEntry>`) containing the `name` (`String`), `value` (`String`), and an optional `Blob*` or `File*` reference.

### 2. MONOTONIC ACCUMULATION MECHANICS
The term **monotonic entry list accumulation** refers to the memory and structural growth patterns of the `entries_` vector when subjected to standard DOM API mutations, specifically `FormData.prototype.append()`, `FormData.prototype.set()`, and `FormData.prototype.delete()`.

#### A. Unbounded Growth via `append()`
Unlike a standard hash map where inserting an existing key overwrites the previous value, the `append(name, value)` method is strictly additive. 
* **Mechanism:** Invoking `append()` unconditionally instantiates a new `FormDataEntry` on the Oilpan heap and pushes it to the back of the `entries_` `HeapVector`.
* **Complexity:** Amortized $O(1)$ per insertion.
* **Accumulation Vector:** Because `append()` does not check for key collisions, repeated calls with the same key result in strictly monotonic growth of the `entries_` vector size ($N_{t+1} = N_t + 1$). 

#### B. Capacity Monotonicity under `delete()` and `set()`
Even when entries are removed or deduplicated, the underlying backing store exhibits monotonic *capacity* retention:
1. **`delete(name)`:** Iterates through `entries_` ($O(N)$) and removes all matching elements via `EraseAt()`. While the logical `size()` of the vector decreases, `WTF::Vector` (which underpins `HeapVector`) **does not automatically shrink its allocated capacity** upon element erasure. 
2. **`set(name, value)`:** Scans `entries_` ($O(N)$) to locate the first matching key. It replaces the first match in-place and erases all subsequent matching keys. Again, vector capacity remains pinned at its historical high-water mark.

#### C. Reallocation Step-Functions
As `entries_` accumulates items monotonically, exceeding the current capacity of the `HeapVector` triggers a backing store reallocation within the Oilpan `VectorBacking` space:
* Blink’s `WTF::Vector` expands geometrically (typically by a factor of $1.5\times$ or $2\times$ depending on current size thresholds).
* The old backing store is abandoned (left for the next Oilpan sweeping phase), and pointers are copied to the new, larger contiguous block.
* Rapid accumulation in a tight JS loop can cause transient memory spikes (fragmentation in the Oilpan vector arena) before the incremental marking/sweeping cycle reclaims the orphaned backing stores.

---

### 3. SERIALIZATION & IPC IMPLICATIONS (THE "PAYLOAD AMPLIFICATION" EFFECT)
When a `FormData` object is passed to `fetch()` or `XMLHttpRequest.send()`, it must be serialized into a `blink::EncodedFormData` (and subsequently `network::ResourceRequestBody`) to cross the Mojo IPC boundary to the Network Service.

* **Multipart Boundary Generation:** During `FormData::EncodeMultiPartFormData()`, Blink iterates linearly through `entries_`. Every accumulated entry—regardless of duplicate keys—is wrapped in a MIME boundary (`--boundary\r\nContent-Disposition: form-data; name="..."\r\n\r\n...`).
* **Amplification:** A monotonic accumulation of small strings via `append('', '')` yields a disproportionate amplification in the contiguous `Vector<char>` buffer allocated for `EncodedFormData` due to boundary and header overhead (~100+ bytes of overhead per 0-byte entry).

---

### 4. AUDIT FINDINGS & EDGE-CASE RISKS

| Finding ID | Severity | Vector / Mechanism | Description |
| :--- | :--- | :--- | :--- |
| **FD-01** | Low / Info | **Algorithmic Complexity ($O(N^2)$)** | Alternating `append()` (accumulating $N$ items) with `set()` or `delete()` inside a loop degrades performance to $O(N^2)$ due to linear scans over the monotonically growing vector combined with memory shifts (`memmove`) during erasure. |
| **FD-02** | Low | **High-Water Mark Memory Retention** | A long-lived `FormData` instance that accumulates $10^6$ entries and subsequently calls `delete()` on all of them will retain the massive `HeapVector` backing buffer until the `FormData` wrapper itself becomes unreachable and is collected by Oilpan. |
| **FD-03** | Medium | **IPC / OOM Pressure** | Monotonic accumulation of `Blob` references via `append()` is exceptionally cheap in V8/Oilpan (only a pointer is added to `entries_`). However, if consumed by an API that reads the `FormData` into memory simultaneously, it can trigger an Out-Of-Memory (OOM) crash in the renderer or network process. |

---

### 5. CONCLUSION & REMEDIATION STATUS
The monotonic accumulation behavior of `blink::FormData::entries_` is **by design** and strictly dictated by the [WHATWG XMLHttpRequest Specification](https://xhr.spec.whatwg.org/#interface-formdata), which defines `FormData` as an ordered list of tuples rather than an associative array. 

Memory growth is properly bounded by Oilpan's PartitionAlloc limits (`PartitionAlloc` max allocation size prevents integer overflows during vector capacity doubling). No immediate security vulnerabilities exist within the accumulation logic itself, though developers must be aware of the $O(N)$ scan penalties and capacity retention characteristics.

** END OF AUDIT — AGENT 484 **