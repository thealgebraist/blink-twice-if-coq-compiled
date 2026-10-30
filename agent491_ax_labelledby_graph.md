**AUDIT REPORT: Blink Accessibility Engine (`third_party/blink/renderer/modules/accessibility`)**
**Agent ID:** 491  
**Target Subsystem:** `AXRelationCache` / ARIA Graph Traversal  
**Subject:** Cycle-Safe Graph Traversal Protocols  

---

### 1. Threat Model & Vulnerability Surface
ARIA relations (`aria-owns`, `aria-labelledby`, `aria-describedby`, `aria-controls`, `aria-flowto`) allow web authors to superimpose an arbitrary directed graph over the standard DOM tree. Because DOM ID references are string-based and unconstrained, authors can inadvertently or maliciously introduce cycles:

*   **Direct Cycles (Self-Loop):** `<div id="a" aria-owns="a">`
*   **Mutual Cycles:** Node A `aria-owns` Node B; Node B `aria-owns` Node A.
*   **DOM-ARIA Hybrid Cycles:** Node A `aria-owns` Node B, where Node B is a DOM ancestor of Node A.
*   **Transitive Text Cycles:** Node A `aria-labelledby` Node B $\rightarrow$ Node B `aria-labelledby` Node C $\rightarrow$ Node C `aria-labelledby` Node A.

Unmitigated traversal of these structures results in call-stack exhaustion (Renderer crash), infinite loops (Main Thread hang), or corrupted `AXTree` serialization states (triggering browser-process `AXTree::Unserialize` crashes).

---

### 2. Structural Cycle Prevention (`aria-owns`)
`aria-owns` is the highest-risk relation in Blink because it directly mutates the parent-child hierarchy of the `AXObject` tree, violating the strict tree invariant required by OS accessibility APIs.

**Audit of `AXRelationCache::IsValidOwnsRelation`:**
To prevent cyclic graph formation at the structural level, `AXRelationCache` enforces strict pre-traversal validation before registering an ownership relation in `aria_owned_child_to_owner_mapping_`.

#### Protocol 2.1: Ancestor Spine Walk
Before `Owner` can claim `Child` via `aria-owns`, Blink walks the ancestor chain of `Owner` up to the `AXObjectCache` root.

```cpp
// Conceptual representation of Blink's cycle check in AXRelationCache
bool AXRelationCache::IsValidOwnsRelation(AXObject* owner, AXObject* child) const {
  if (!owner || !child || owner == child)
    return false;

  // Walk up the AX parent chain (which includes both DOM parents and 
  // previously established aria-owns parents).
  for (AXObject* ancestor = owner->ParentObjectIncludedInTree(); 
       ancestor; 
       ancestor = ancestor->ParentObjectIncludedInTree()) {
    if (ancestor == child) {
      // CYCLE DETECTED: The proposed child is already an ancestor of the owner.
      return false; 
    }
  }
  return true;
}
```

#### Protocol 2.2: Single-Ownership Enforcement
A node cannot have two parents in a tree (Diamond Graph problem, which complicates cycle detection). `AXRelationCache` maintains a 1:1 child-to-owner hash map (`HeapHashMap<AXID, AXID>`). If Node C is already owned by Node A, Node B's attempt to own Node C is rejected until Node A releases it.

---

### 3. Referential Cycle Prevention (`aria-labelledby` / `aria-describedby`)
Unlike `aria-owns`, text calculation relations do not alter the `AXObject` tree structure; they trigger an on-demand depth-first traversal during the Accessible Name and Description Computation (AccName) algorithm.

**Audit of `AXNodeObject::TextFromElements`:**
Blink tracks state dynamically on the call stack using a `HeapHashSet` of visited objects passed by reference through the recursive calls.

#### Protocol 3.1: Visited Set Propagation
1.  **Initialization:** When `GetName()` is invoked on the root target, an empty `AXObjectSet` (`HeapHashSet<Member<const AXObject>> visited`) is instantiated.
2.  **Pre-Insertion:** Before resolving the `idrefs` of `aria-labelledby`, the current `AXObject` is inserted into `visited`.
3.  **Branch Evaluation:** As Blink iterates over the target elements of the relation:
    *   It checks `visited.Contains(target_ax_object)`.
    *   If **true**: The branch is immediately terminated (returns empty string for that branch), breaking the cycle.
    *   If **false**: The target is added to `visited`, and `TextAlternative()` is called recursively with `visited` passed down.

#### Protocol 3.2: Asymmetric Recursion Restrictions (Spec Compliance)
Per the W3C AccName specification, Blink enforces a hard depth limit on *relational* recursion, while still allowing *DOM subtree* recursion:
*   A node reached via `aria-labelledby` **cannot** traverse its own `aria-labelledby` attribute. Blink tracks a boolean flag (`in_aria_labelled_by_traversal`) in the traversal context.
*   However, a node reached via `aria-labelledby` *can* traverse its DOM children, and one of those children might use `aria-labelledby` pointing back to the root node. **The `visited` set is strictly required to catch this indirect cycle.**

---

### 4. Cache Mutation & Invalidation Edge Cases
The hardest bugs in `AXRelationCache` occur when the DOM mutates *after* initial validation, creating a retroactive cycle.

**Scenario:**
1. `div#A` owns `div#B`. (Valid. Tree: `A -> B`).
2. JS executes: `B.appendChild(A)`. (DOM is now `B -> A`, while ARIA is `A -> B`).

**Blink Mitigation (`AXRelationCache::UpdateRelatedTree`):**
*   When `B.appendChild(A)` occurs, `ChildrenChanged` is fired on `B` and `A`'s old parent.
*   Before finalizing tree updates, `AXObjectCacheImpl::ProcessDeferredAccessibilityEvents` processes dirty relation queues.
*   `AXRelationCache` re-evaluates `UpdateAriaOwns` for the mutated subtrees.
*   During re-evaluation, the Ancestor Spine Walk (Protocol 2.1) detects that `B` is now a DOM ancestor of `A`.
*   `AXRelationCache::RemoveOwnedRelation` is triggered, severing the `aria-owns` link, marking `A` and `B` dirty, and falling back to the standard DOM hierarchy (`B -> A`) to break the cycle.

---

### 5. Agent 491 Audit Recommendations (Hardening)

While auditing the current implementation, the following invariants must be strictly maintained to prevent regressions (specifically `DCHECK` failures in `AXTreeSerializer`):

1.  **Unincluded Node Bypass:** During the Ancestor Spine Walk, traversal *must* use `ParentObjectUnignored()` or `ParentObjectIncludedInTree()` consistently. If an intermediate node in a cycle is `aria-hidden="true"` or `display: none`, using a naive parent getter might return `nullptr` prematurely, hiding the cycle until the intermediate node becomes visible.
2.  **Max Depth Circuit Breaker:** Because `aria-owns` can be chained (`A -> B -> C -> D...`) up to thousands of nodes deep without technically forming a cycle, the cycle-checking spine walk itself can become an $O(N^2)$ performance bottleneck or cause stack overflows during serialization. Blink enforces `kMaxTreeDepth` in the serializer, but `AXRelationCache` should reject `aria-owns` chains that exceed a safe depth threshold at the cache level.
3.  **Garbage Collection (Oilpan) Safety:** All cycle-detection sets (`AXObjectSet`) used during traversal must remain stack-allocated (`STACK_ALLOCATED()`) or use `HeapHashSet<Member<AXObject>>` to ensure Oilpan can trace objects if a GC occurs mid-traversal, preventing Use-After-Free (UAF) vulnerabilities.

**End of Report.**