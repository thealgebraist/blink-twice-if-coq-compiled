# Formal Verification of Chromium Blink's IndexedDB Key Range Interval Containment

**Author:** Web Platform Security & Formal Methods Research Group  
**Target Component:** `third_party/blink/renderer/modules/indexeddb/idb_key_range.cc`  
**Specification:** W3C Indexed Database API 3.0 (IndexedDB 3) §4.6 (Key Ranges)  
**Formalization Target:** `BlinkIDBKeyRangeIntervalSemantics.v` (Rocq / Coq Prover)

---

## 1. Normative W3C Specification Requirements

In the W3C Indexed Database API 3.0 specification, §4.6 defines the semantics of a **key range** (`IDBKeyRange`). A key range represents a continuous interval over the totally ordered space of valid IndexedDB keys (Numbers, Dates, Strings, Binary data, and Arrays).

### 1.1 Structural Representation
Per §4.6, a key range has four associated values:
1. **lower bound**: null or a valid key.
2. **upper bound**: null or a valid key.
3. **lower open flag**: a boolean (true if the lower bound is excluded from the range; false if included).
4. **upper open flag**: a boolean (true if the upper bound is excluded from the range; false if included).

*(Note: If the lower bound is null, the lower open flag is normatively required to be true; similarly, if the upper bound is null, the upper open flag is true).*

### 1.2 Containment Predicate (`includes`)
The normative condition for whether a key $k$ is **in** a key range $R = (\text{lower}, \text{upper}, \text{lowerOpen}, \text{upperOpen})$ is strictly specified as follows:

> A key $k$ is **in** a key range if *both* of the following conditions are fulfilled:
> 1. The lower bound is null, OR it is less than $k$, OR it is both equal to $k$ and the lower open flag is unset (`false`).
> 2. The upper bound is null, OR it is greater than $k$, OR it is both equal to $k$ and the upper open flag is unset (`false`).

### 1.3 Construction Invariants (`bound`, `lowerBound`, `upperBound`, `only`)
When constructing a bounded range via `IDBKeyRange.bound(lower, upper, lowerOpen, upperOpen)`, the specification mandates the following structural validation rules before instantiation:
1.Both `lower` and `upper` must be valid keys.
2. If `lower` is greater than `upper` ($lower > upper$), a `DataError` `DOMException` must be thrown.
3. If `lower` is equal to `upper` ($lower = upper$) and either `lowerOpen` or `upperOpen` is set (`true`), a `DataError` `DOMException` must be thrown (preventing the representation of empty degenerate intervals).

For closed bounded intervals (`lowerOpen = false`, `upperOpen = false`), this reduces directly to the classical mathematical interval containment property:
$$\text{in\_range}(k, \text{lower}, \text{upper}) \iff (\text{lower} \le k \land k \le \text{upper})$$

---

## 2. Chromium Blink Implementation Analysis

In Chromium's Blink rendering engine, `IDBKeyRange` is implemented in `third_party/blink/renderer/modules/indexeddb/idb_key_range.cc` and its accompanying header `idb_key_range.h`.

### 2.1 State Representation and Memory Safety
In `idb_key_range.h`, the internal state of an `IDBKeyRange` Oilpan-managed (`ScriptWrappable`) object is represented using:
* `Member<IDBKey> lower_;`
* `Member<IDBKey> upper_;`
* `LowerBoundType lower_type_;` (`kLowerBoundOpen` or `kLowerBoundClosed`)
* `UpperBoundType upper_type_;` (`kUpperBoundOpen` or `kUpperBoundClosed`)

When a bound is absent (null in JS), Blink represents `lower_` or `upper_` as either `nullptr` or an `IDBKey` with `IDBKey::kInvalidType` (`IsValid() == false`), and enforces `kLowerBoundOpen` / `kUpperBoundOpen`.

### 2.2 Factory Validation (`IDBKeyRange::bound`)
In `idb_key_range.cc`, the `IDBKeyRange::bound` factory method enforces the W3C non-degeneracy invariants using `IDBKey::Compare`:

```cpp
// Conceptual structure of IDBKeyRange::bound in idb_key_range.cc
IDBKeyRange* IDBKeyRange::bound(ScriptState* script_state,
                                const ScriptValue& lower_value,
                                const ScriptValue& upper_value,
                                bool lower_open,
                                bool upper_open,
                                ExceptionState& exception_state) {
  // ... key conversion and validation ...
  int cmp = lower->Compare(upper);
  if (cmp > 0) {
    // lower > upper
    exception_state.ThrowDOMException(DOMExceptionCode::kDataError, ...);
    return nullptr;
  }
  if (cmp == 0 && (lower_open || upper_open)) {
    // lower == upper with at least one open bound
    exception_state.ThrowDOMException(DOMExceptionCode::kDataError, ...);
    return nullptr;
  }
  return MakeGarbageCollected<IDBKeyRange>(
      lower, upper,
      lower_open ? kLowerBoundOpen : kLowerBoundClosed,
      upper_open ? kUpperBoundOpen : kUpperBoundClosed);
}
```

### 2.3 Interval Containment (`IDBKeyRange::includes`)
The `includes()` method evaluates whether a candidate `key` falls within the range:

```cpp
// Conceptual structure of IDBKeyRange::includes in idb_key_range.cc
bool IDBKeyRange::includes(ScriptState* script_state,
                           const ScriptValue& key_value,
                           ExceptionState& exception_state) {
  IDBKey* key = ScriptValue::To<IDBKey*>(...);
  if (!key || !key->IsValid()) {
    exception_state.ThrowDOMException(DOMExceptionCode::kDataError, ...);
    return false;
  }

  if (lower_ && lower_->IsValid()) {
    int cmp = key->Compare(lower_.Get());
    if (cmp < 0)
      return false;
    if (cmp == 0 && lowerOpen())
      return false;
  }

  if (upper_ && upper_->IsValid()) {
    int cmp = key->Compare(upper_.Get());
    if (cmp > 0)
      return false;
    if (cmp == 0 && upperOpen())
      return false;
  }

  return true;
}
```

### 2.4 Critical Engine Invariants
1. **Total Ordering Isomorphism**: `IDBKey::Compare(other)` returns an integer $< 0$, $0$, or $> 0$, inducing a strict total order over valid keys. By isomorphism of countable total orders, we can model the domain of valid `IDBKey` instances as $\mathbb{Z}$ without loss of generality for first-order interval containment properties.
2. **Negation Elimination**: Blink implements containment via early-return guards (`if (cmp < 0) return false; if (cmp == 0 && open) return false;`). This procedural branching must be proven strictly equivalent to the positive disjunctive formulation in the W3C specification.
3. **Storage Boundary Preservation**: Because `IDBKeyRange` objects are serialized into `mojom::blink::IDBKeyRange` and passed across the Mojo IPC boundary to the browser process (`content/browser/indexed_db/`) to construct LevelDB iterators/slices, any discrepancy between renderer-side `includes()`, factory validation, and mathematical interval containment could cause out-of-bounds cursor scans or cross-key-range data leakage.

---

## 3. Formal Specification in Rocq / Coq

Below is the complete, self-contained formalization in `BlinkIDBKeyRangeIntervalSemantics.v`. It models the key space, the W3C normative semantics, the Blink procedural C++ implementation (including `Compare` branches and `bound` exception guards), and proves their exact equivalence.

## 4. Concrete Theorems and Complete Proofs (`BlinkIDBKeyRangeIntervalSemantics.v`)

```coq
(** * BlinkIDBKeyRangeIntervalSemantics.v
    Formal Verification of Chromium Blink IndexedDB IDBKeyRange Interval Containment
    Source: third_party/blink/renderer/modules/indexeddb/idb_key_range.cc
    Specification: W3C IndexedDB 3.0 §4.6
*)

From Coq Require Import ZArith.
From Coq Require Import Bool.
From Coq Require Import Lia.

Open Scope Z_scope.
Open Scope bool_scope.

(** ** 1. Domain Modeling: Keys and Total Ordering *)

(** Valid IndexedDB keys form a strict total order. We model the key domain
    isomorphically via [Z], where [Z.compare] models [IDBKey::Compare]. *)
Definition IDBKey := Z.

(** Blink's [IDBKey::Compare(other)] returns negative (< 0), zero (0),
    or positive (> 0). We model this exact integer return contract. *)
Definition idb_key_compare (k1 k2 : IDBKey) : Z :=
  match (k1 ?= k2) with
  | Lt => -1
  | Eq => 0
  | Gt => 1
  end.

Lemma idb_key_compare_lt : forall k1 k2 : IDBKey,
  (idb_key_compare k1 k2 < 0) <-> (k1 < k2).
Proof.
  intros k1 k2. unfold idb_key_compare.
  destruct (k1 ?= k2) eqn:Hcmp.
  - apply Z.compare_eq_iff in Hcmp. lia.
  - apply Z.compare_lt_iff in Hcmp. lia.
  - apply Z.compare_gt_iff in Hcmp. lia.
Qed.

Lemma idb_key_compare_eq : forall k1 k2 : IDBKey,
  (idb_key_compare k1 k2 = 0) <-> (k1 = k2).
Proof.
  intros k1 k2. unfold idb_key_compare.
  destruct (k1 ?= k2) eqn:Hcmp.
  - apply Z.compare_eq_iff in Hcmp. lia.
  - apply Z.compare_lt_iff in Hcmp. lia.
  - apply Z.compare_gt_iff in Hcmp. lia.
Qed.

Lemma idb_key_compare_gt : forall k1 k2 : IDBKey,
  (idb_key_compare k1 k2 > 0) <-> (k1 > k2).
Proof.
  intros k1 k2. unfold idb_key_compare.
  destruct (k1 ?= k2) eqn:Hcmp.
  - apply Z.compare_eq_iff in Hcmp. lia.
  - apply Z.compare_lt_iff in Hcmp. lia.
  - apply Z.compare_gt_iff in Hcmp. lia.
Qed.

(** Boolean versions of the C++ comparison checks on [cmp]. *)
Definition cmp_lt_zero (cmp : Z) : bool := cmp <? 0.
Definition cmp_eq_zero (cmp : Z) : bool := cmp =? 0.
Definition cmp_gt_zero (cmp : Z) : bool := cmp >? 0.

Lemma cmp_lt_zero_spec : forall k1 k2 : IDBKey,
  cmp_lt_zero (idb_key_compare k1 k2) = true <-> k1 < k2.
Proof.
  intros k1 k2. unfold cmp_lt_zero.
  rewrite Z.ltb_lt. apply idb_key_compare_lt.
Qed.

Lemma cmp_eq_zero_spec : forall k1 k2 : IDBKey,
  cmp_eq_zero (idb_key_compare k1 k2) = true <-> k1 = k2.
Proof.
  intros k1 k2. unfold cmp_eq_zero.
  rewrite Z.eqb_eq. apply idb_key_compare_eq.
Qed.

Lemma cmp_gt_zero_spec : forall k1 k2 : IDBKey,
  cmp_gt_zero (idb_key_compare k1 k2) = true <-> k1 > k2.
Proof.
  intros k1 k2. unfold cmp_gt_zero.
  rewrite Z.gtb_ltb, Z.ltb_lt.
  pose proof (idb_key_compare_gt k1 k2) as H.
  lia.
Qed.

(** ** 2. Structure of IDBKeyRange *)

Record IDBKeyRange := mkIDBKeyRange {
  lower : option IDBKey;
  upper : option IDBKey;
  lower_open : bool;
  upper_open : bool
}.

(** ** 3. W3C Normative Specification (IndexedDB 3.0 §4.6) *)

(** W3C normative predicate for lower bound satisfaction:
    "The lower bound is null, or it is less than key, or it is both equal
     to key and the lower open flag is unset." *)
Definition spec_lower_satisfied (k : IDBKey) (r : IDBKeyRange) : Prop :=
  match r.(lower) with
  | None => True
  | Some l => (l < k) \/ (l = k /\ r.(lower_open) = false)
  end.

(** W3C normative predicate for upper bound satisfaction:
    "The upper bound is null, or it is greater than key, or it is both equal
     to key and the upper open flag is unset." *)
Definition spec_upper_satisfied (k : IDBKey) (r : IDBKeyRange) : Prop :=
  match r.(upper) with
  | None => True
  | Some u => (u > k) \/ (u = k /\ r.(upper_open) = false)
  end.

(** W3C normative key range containment predicate. *)
Definition spec_in_range (k : IDBKey) (r : IDBKeyRange) : Prop :=
  spec_lower_satisfied k r /\ spec_upper_satisfied k r.

(** Pure mathematical closed interval containment predicate:
    in_range(k, lower, upper) = (lower <= k /\ k <= upper) *)
Definition math_closed_in_range (k l u : IDBKey) : Prop :=
  l <= k /\ k <= u.

(** ** 4. Blink Implementation Model (idb_key_range.cc) *)

(** Models the exact control flow of [IDBKeyRange::includes] in Blink:
    ```cpp
    if (lower_ && lower_->IsValid()) {
      int cmp = key->Compare(lower_.Get());
      if (cmp < 0) return false;
      if (cmp == 0 && lowerOpen()) return false