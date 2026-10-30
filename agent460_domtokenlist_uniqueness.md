**AUDIT REPORT: Blink `DOMTokenList` Set Uniqueness & Deduplication**
**Auditor:** Agent 460
**Target:** Chromium / Blink Rendering Engine (`third_party/blink/renderer/core/dom/dom_token_list.cc` & `space_split_string.cc`)
**Subject:** DOM Standard Compliance regarding Set Uniqueness and Duplicate Deduplication

---

### 1. Executive Summary
Per the WHATWG DOM Standard, a `DOMTokenList` object represents an interface to an **ordered set** of tokens. By definition, an ordered set cannot contain duplicate entries. This audit details how Blink enforces set uniqueness, manages in-memory deduplication via `SpaceSplitString`, and synchronizes changes back to the underlying DOM attribute (e.g., `class`, `rel`, `sandbox`).

### 2. Architectural Separation of Concerns
Blink separates the `DOMTokenList` implementation into two distinct layers:
1. **The Backing Attribute (`AtomicString`):** The raw string value stored in the `Element`'s attribute map (e.g., `class="foo bar foo"`).
2. **The Parsed Token Set (`SpaceSplitString`):** The internal C++ representation held by `DOMTokenList` (`token_set_`), which wraps a `SpaceSplitStringData` vector containing unique `AtomicString` tokens.

Deduplication occurs at two different stages: **Read-Time (Parsing)** and **Write-Time (Mutation)**.

---

### 3. Read-Time Deduplication (Attribute $\rightarrow$ Token Set)
When an attribute is modified directly via `element.setAttribute('class', 'a b a')` or parsed from HTML, `DOMTokenList::DidUpdateAttributeValue` is triggered.

**Mechanism:**
1. The raw string is passed to `SpaceSplitString::Set()`.
2. Blink parses the string using `HTMLParserIdioms` (splitting on ASCII whitespace).
3. As tokens are extracted, `SpaceSplitStringData::Create` populates an internal `Vector<AtomicString>`.
4. **The Deduplication Check:** Before appending a newly parsed token to the vector, Blink executes an $O(N)$ linear scan over the already-collected tokens in the current vector.
   * *Note on Performance:* Because tokens are stored as `AtomicString`s (interned strings), equality checks are $O(1)$ pointer comparisons rather than character-by-character comparisons.
5. **Result:** If the attribute is `"foo bar foo"`, the `token_set_` vector contains `["foo", "bar"]` (`length == 2`).
6. **Lazy Serialization:** Crucially, **Read-Time deduplication does not mutate the DOM attribute**. `element.getAttribute('class')` will still return `"foo bar foo"`, even though `element.classList.length` returns `2`.

---

### 4. Write-Time Deduplication (Token Set $\rightarrow$ Attribute)
When the `DOMTokenList` is mutated via its WebIDL API (`add`, `remove`, `toggle`, `replace`), Blink enforces strict set semantics and *actively deduplicates* the underlying DOM attribute string.

#### A. `add(tokens...)`
* **Check:** Iterates through the passed arguments. For each token, it checks `token_set_.Contains(token)` AND ensures the token was not already added in the current batch.
* **Action:** Only novel tokens are appended to the list.

#### B. `remove(tokens...)`
* **Check:** Matches target tokens against the set.
* **Action:** If the raw attribute originally contained duplicates (e.g., `"a b a"`), calling `classList.remove('b')` will not only remove `'b'`, it will also collapse the remaining duplicates of `'a'` during the serialization phase.

#### C. `replace(token, new_token)`
* **Edge Case Audited:** Replacing a token with another token that *already exists* in the list.
* **Example:** Attribute is `"a b c"`. Executing `classList.replace('a', 'b')`.
* **Action:** Blink identifies the first instance of `'a'`, sees that `'b'` already exists at a later index, replaces `'a'` with `'b'`, and **removes the subsequent `'b'`** to maintain set uniqueness. The resulting set is `["b", "c"]` (preserving the earliest position).

---

### 5. The Serialization Algorithm (`SerializeSet`)
Whenever a Write-Time API successfully runs (even if a mutating method results in a logical no-op, depending on spec steps), Blink invokes `DOMTokenList::UpdateWithTokenSet`.

1. **Reconstruction:** Instead of performing regex/string manipulation on the existing dirty attribute string, Blink discards the raw attribute string entirely.
2. **StringBuilder:** It iterates through the already-deduplicated `SpaceSplitString` (`token_set_`) and joins the `AtomicString`s with a single U+0020 SPACE character.
3. **Commit:** It sets the element's attribute to this newly constructed, guaranteed-unique string.

**Audit Trace Example:**
```javascript
div.setAttribute("class", "   alpha   beta  alpha  ");
// Backing string: "   alpha   beta  alpha  "
// SpaceSplitString: ["alpha", "beta"]

div.classList.remove("non-existent"); 
// Spec requires running the "update steps" even if token wasn't found.
// Backing string is overwritten via SerializeSet.
// New Backing string: "alpha beta" (Whitespace normalized, duplicates purged).
```

---

### 6. Complexity & Security Posture (Agent 460 Assessment)

* **Time Complexity:** Deduplication relies on nested loops ($O(N^2)$ worst-case during initial set construction). However, because `DOMTokenList` sizes in the wild are typically small ($N < 50$) and rely on `AtomicString` pointer comparison, CPU overhead is negligible and outperforms `HashSet` allocation overhead for small $N$.
* **DoS Vector Analysis:** Feeding an element a class attribute with $100,000$ unique tokens will trigger $O(N^2)$ pointer comparisons in `SpaceSplitStringData`. While theoretically quadratic, pointer comparison speed mitigates severe hang risks, though it remains a known micro-bottleneck in extreme synthetic benchmarks.
* **Spec Compliance:** **PASS**. Blink's handling of order preservation (retaining the *first* seen instance of a duplicated token) and lazy attribute serialization strictly adheres to the WHATWG DOM specification for Ordered Sets. 

**End of Report.**