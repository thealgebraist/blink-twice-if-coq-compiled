**AUDIT LOG: AGENT 473**
**TARGET:** Chromium / Blink Rendering Engine (`third_party/blink/renderer/core/css/`)
**SUBJECT:** `RuleSet` Bucket Index Derivation (`CompactRuleMap`)

### 1. Executive Overview
In Blink, the `RuleSet` class partitions CSS rules into "buckets" to prevent matching every rule against every DOM element. Rules are categorized by their rightmost (key) sub-selector into primary hash maps:
*   `id_rules_` (Key: `AtomicString` of ID)
*   `class_rules_` (Key: `AtomicString` of Class)
*   `tag_rules_` (Key: `AtomicString` of Tag LocalName)
*   `attr_rules_` (Key: `AtomicString` of Attribute LocalName)

Historically, these were implemented as `HeapHashMap<AtomicString, Member<HeapLinkedStack<RuleData>>>`. In modern Blink, these have been consolidated into `CompactRuleMap`, which utilizes `WTF::HashTable` to map `AtomicString` keys to contiguous `RuleData` vectors (`RuleSet::Interval`). 

The bucket index derivation relies entirely on the pre-computed hash stored inside the `AtomicString`'s underlying `StringImpl` and WTF's open-addressing probing mechanism.

---

### 2. Hash Generation Phase (Key Preparation)
A CSS selector key (e.g., `#header`, `.btn`, `div`) is interned as a `WTF::AtomicString` during CSS parsing. 

1.  **Case Normalization:** 
    *   Tag names (in HTML documents) and attribute names are lowercased (`AtomicString::LowerASCII()`) *prior* to bucket insertion/lookup.
    *   IDs and Classes remain case-sensitive (unless inside quirks mode, which handles case folding differently).
2.  **Hash Extraction:**
    *   `AtomicString` wraps a `StringImpl*`.
    *   `StringImpl` caches a 24-bit hash value computed via **SuperFastHash** (Paul Hsieh's hash algorithm) over the 8-bit (`LChar`) or 16-bit (`UChar`) character buffer.
    *   During `RuleSet` bucketing, the hash is not recomputed. It is extracted directly via a bit-shift operation on the `StringImpl` flags:
        ```cpp
        // Conceptual extraction from StringImpl
        unsigned GetHash() const { return hash_and_flags_ >> kHashShift; }
        ```

---

### 3. Hash Conditioning (Avalanching)
When `CompactRuleMap` queries the underlying `WTF::HashTable`, the `AtomicStringHash` traits struct is invoked. Because `StringImpl` hashes are already well-distributed via SuperFastHash, `AtomicStringHash::GetHash()` returns the raw 24-bit integer.

However, `WTF::HashTable` applies a secondary conditioning step (unless explicitly bypassed by `IntHashTraits`, which `AtomicString` does not bypass in all contexts, though it often relies on identity in pointer-hash contexts. **Correction for `AtomicString`**: `AtomicString` uniqueness guarantees pointer equality, *but* `AtomicStringHash` uses the string's content hash, not the pointer address, to maintain deterministic behavior and cross-String alignment).

1.  **Zero-Hash Avoidance:** `WTF::HashTable` reserves `0` and `-1` (all 1s) for empty/deleted slot tracking in certain trait configurations. `StringImpl` guarantees its internal hash is never `0` (if SuperFastHash outputs `0`, it is coerced to `0x80000000 >> kHashShift`).

---

### 4. Bucket Index Derivation (Primary Probe)
`WTF::HashTable` enforces that the `table_size_` (capacity) is always a **power of two** ($2^n$). This allows the expensive modulo operation (`%`) to be replaced with a bitwise `AND`.

Given:
*   $H$: The 24-bit hash extracted from the `AtomicString`.
*   $M$: The `table_size_mask_`, defined as `table_size_ - 1`.

**The initial bucket index ($I_0$) is derived via:**
$$I_0 = H \ \& \ M$$

```cpp
// Inside WTF::HashTable::LookupForWriting / Lookup
unsigned size_mask = table_size_mask_;
unsigned h = HashFunctions::GetHash(key);
unsigned i = h & size_mask; // Initial Bucket Index
```

---

### 5. Collision Resolution (Secondary Index Derivation)
If bucket $I_0$ is occupied by a *different* `AtomicString` (checked via fast pointer comparison `entry.key.Impl() == key.Impl()`), `WTF::HashTable` resolves the collision using **Quadratic Probing** (specifically, triangular number probing).

Given:
*   $k$: The probe count, initialized to `0` and incremented by `1` on each collision ($k = 1, 2, 3 \dots$).
*   $I_{k-1}$: The previous colliding bucket index.

**The subsequent bucket index ($I_k$) is derived via:**
$$I_k = (I_{k-1} + k) \ \& \ M$$

```cpp
// Probing loop inside WTF::HashTable
unsigned probe_count = 0;
while (true) {
    ValueType* entry = table_ + i;
    if (IsEmptyOrDeletedBucket(*entry)) 
        return entry;
    if (HashFunctions::Equal(Extractor::Extract(*entry), key)) 
        return entry; // Bucket Found
    
    probe_count++;
    i = (i + probe_count) & size_mask; // Next Bucket Index
}
```
*Audit Note:* Because $M$ is $2^n - 1$, stepping by $I + k$ (which equals $I_0 + \frac{k(k+1)}{2}$) mathematically guarantees that every single bucket in the table will be visited exactly once before repeating, preventing infinite loops provided the load factor is $< 1.0$.

---

### 6. Compaction Phase (`RuleSet::CompactRules`)
During rule insertion (`RuleSet::AddRule`), rules are temporarily chained. Once all stylesheets are parsed, `CompactRuleMap::Compact()` is executed:

1.  All `RuleData` entries across all buckets are flattened into a single contiguous `HeapVector<RuleData>` (`rule_data_`).
2.  The `WTF::HashTable` buckets no longer point to linked stacks. Instead, the `Value` at the derived bucket index $I$ is rewritten to hold a `RuleSet::Interval` struct:
    ```cpp
    struct Interval {
      unsigned start_index; // Offset into the contiguous RuleData vector
      unsigned length;      // Number of rules in this bucket
    };
    ```
3.  During `ElementRuleCollector` execution (DOM matching), the engine extracts the element's ID/Class/Tag `AtomicString`, derives index $I$ using steps 4 and 5, retrieves the `Interval`, and iterates linearly over the contiguous memory slice `rule_data_[start_index ... start_index + length]`.

### 7. Summary of Vulnerabilities / Edge Cases
*   **Hash Flooding:** Because `StringImpl` uses non-cryptographic SuperFastHash without a random seed, an attacker can craft thousands of CSS class names that yield identical 24-bit hashes ($H$), forcing $O(N)$ quadratic probing during both `RuleSet` construction and DOM matching.
*   **24-bit Truncation:** `StringImpl` hashes are truncated to 24 bits to fit metadata flags into a 32-bit header. Consequently, the maximum entropy before masking is $2^{24}$ (16.7 million unique hashes).

**END OF AUDIT.**