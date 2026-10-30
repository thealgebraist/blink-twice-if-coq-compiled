# Formal Verification of IndexedDB IDBCursor Direction Monotonicity in Chromium Blink

## 1. Normative Specification Requirements

The W3C Indexed Database API 3.0 (IndexedDB 3) specification defines the cursor traversal semantics in **Section 5 (Cursors)**, specifically under **Section 5.5 (The `IDBCursor` interface)** and **Section 5.7 (Cursor Iteration Operation)**.

### 1.1 Direction Enumeration (`IDBCursorDirection`)
Per IndexedDB 3 §5.1, a cursor's traversal trajectory is governed by four directional modes:
*   `"next"`: The cursor iterates in strictly non-decreasing order of keys. For duplicate keys (in non-unique indexes), it iterates in strictly increasing order of primary keys (object store positions). When a target `key` parameter is supplied to `continue(key)`, the next evaluated position must have a key greater than or equal to `key`, and strictly greater than the cursor's current position.
*   `"nextunique"`: The cursor iterates in strictly increasing order of keys, skipping duplicate keys.
*   `"prev"`: The cursor iterates in strictly non-increasing order of keys (and strictly decreasing order of primary keys for duplicate index keys).
*   `"prevunique"`: The cursor iterates in strictly decreasing order of keys, skipping duplicate keys.

### 1.2 Normative Constraints on `continue(key)` and `continuePrimaryKey(key, primaryKey)`
In IndexedDB 3 §5.5 (`IDBCursor.prototype.continue(key)`):
1.  If `key` is given, the implementation must validate its monotonicity relative to the cursor's current `position`:
    *   If `direction` is `"next"` or `"nextunique"`, and `key` is less than or equal to the cursor's current `position` (i.e., $k_{\text{target}} \le k_{\text{current}}$), the implementation **MUST** throw a `"DataError"` `DOMException`.
    *   If `direction` is `"prev"` or `"prevunique"`, and `key` is greater than or equal to the cursor's current `position` (i.e., $k_{\text{target}} \ge k_{\text{current}}$), the implementation **MUST** throw a `"DataError"` `DOMException`.

In IndexedDB 3 §5.5 (`IDBCursor.prototype.continuePrimaryKey(key, primaryKey)`):
1.  If `direction` is not `"next"` or `"prev"`, throw an `"InvalidAccessError"` `DOMException`.
2.  If `direction` is `"next"`:
    *   If $k_{\text{target}} < k_{\text{current}}$, throw a `"DataError"` `DOMException`.
    *   If $k_{\text{target}} = k_{\text{current}}$ and $pk_{\text{target}} \le pk_{\text{current}}$, throw a `"DataError"` `DOMException`.
3.  If `direction` is `"prev"`:
    *   If $k_{\text{target}} > k_{\text{current}}$, throw a `"DataError"` `DOMException`.
    *   If $k_{\text{target}} = k_{\text{current}}$ and $pk_{\text{target}} \ge pk_{\text{current}}$, throw a `"DataError"` `DOMException`.

### 1.3 Mathematical Monotonicity Property
Let $\mathcal{K}$ be a totally ordered set of valid IndexedDB keys ($\mathcal{K} \simeq \mathbb{Z}$ for discrete abstraction). For a cursor state $C = (d, k, pk) \in \text{Direction} \times \mathcal{K} \times \mathcal{K}$:
*   For explicit key advancement (`continue(k')`):
    $$\text{ Direction } \in \{\text{Next}, \text{NextUnique}\} \implies k' > k$$
    $$\text{ Direction } \in \{\text{Prev}, \text{PrevUnique}\} \implies k' < k$$
*   For compound index advancement (`continuePrimaryKey(k', pk')`):
    $$\text{ Direction } = \text{Next} \implies (k' > k) \lor (k' = k \land pk' > pk)$$
    $$\text{ Direction } = \text{Prev} \implies (k' < k) \lor (k' = k \land pk' < pk)$$

---

## 2. Chromium Blink Implementation Analysis

In Chromium, the renderer-side validation and caching logic for IndexedDB cursors is implemented in `third_party/blink/renderer/modules/indexeddb/idb_cursor.cc`.

### 2.1 Renderer Validation in `IDBCursor::continueFunction`
Before dispatching an IPC request (`mojom::blink::IDBCursor::Continue`) to the browser/storage service backing store (LevelDB/SQLite), Blink enforces synchronous boundary checks in `IDBCursor::continueFunction(const ScriptValue& key_value, ExceptionState& exception_state)` and `IDBCursor::continuePrimaryKey(...)`:

```cpp
// Conceptual structure of third_party/blink/renderer/modules/indexeddb/idb_cursor.cc
void IDBCursor::continueFunction(std::unique_ptr<IDBKey> key,
                                 std::unique_ptr<IDBKey> primary_key,
                                 ExceptionState& exception_state) {
  // ... [Transaction active & source deleted checks] ...
  if (!got_value_) {
    exception_state.ThrowDOMException(DOMExceptionCode::kInvalidStateError,
                                      IDBDatabase::kNoValueErrorMessage);
    return;
  }

  if (key) {
    DCHECK(key_);
    if (direction_ == mojom::blink::IDBCursorDirection::Next ||
        direction_ == mojom::blink::IDBCursorDirection::NextNoDuplicate) {
      const bool ok = key_->IsLessThan(key.get()) ||
                      (primary_key && key_->IsEqual(key.get()) &&
                       primary_key_->IsLessThan(primary_key.get()));
      if (!ok) {
        exception_state.ThrowDOMException(
            DOMExceptionCode::kDataError,
            "The parameter is less than or equal to this cursor's position.");
        return;
      }
    } else {
      const bool ok = key->IsLessThan(key_.get()) ||
                      (primary_key && key->IsEqual(key_.get()) &&
                       primary_key->IsLessThan(primary_key_.get()));
      if (!ok) {
        exception_state.ThrowDOMException(
            DOMExceptionCode::kDataError,
            "The parameter is greater than or equal to this cursor's position.");
        return;
      }
    }
  }
  // ... [Prefetch cache invalidation or advancement] ...
}
```

### 2.2 Security Invariants and Prefetch Cache Integrity
Blink utilizes a cursor prefetch optimization (`WebIDBCursor` / `IDBCursor` prefetch queues) where the backing store sends batches of `(key, primary_key, value)` tuples to avoid synchronous Mojo IPC round-trips on every `continue()` call.
*   **Invariant 1 (Strict Ordering Guard):** `IDBKey::Compare` implements a strict weak ordering (which is a total order over valid canonical `IDBKey` representations). If the renderer fails to reject non-monotonic `continue(key)` requests, or if a compromised renderer sends a non-monotonic key or misaligns the prefetch buffer, the cursor could enter an infinite loop or read out-of-bounds keys relative to the active `IDBKeyRange`.
*   **Invariant 2 (Unique Direction Enforcement):** When `primary_key` is null (standard `continue(key)`), the disjunction `(primary_key && ...)` evaluates to `false`, collapsing the condition strictly to `key_->IsLessThan(key.get())` ($k < k'$) for forward directions and `key->IsLessThan(key_.get())` ($k' < k$) for reverse directions.

---

## 3. Formal Specification in Rocq/Coq (`BlinkIDBCursorMonotonicitySemantics.v`)

Below is the self-contained, admitted-free Rocq/Coq formalization of `IDBCursor` monotonicity semantics, covering both simple key continuation, compound `(key, primary_key)` continuation, prefetch step verification, and multi-step transitive trace properties.

```coq
(** * BlinkIDBCursorMonotonicitySemantics.v
    Formal verification of Chromium Blink's IndexedDB IDBCursor direction
    monotonicity (third_party/blink/renderer/modules/indexeddb/idb_cursor.cc)
    against W3C IndexedDB 3.0 Section 5. *)

From Coq Require Import ZArith.
From Coq Require Import Bool.
From Coq Require Import Lia.
From Coq Require Import List.
Import ListNotations.

Open Scope Z_scope.

(** ** 1. Data Types and Domains *)

(** W3C IndexedDB 3 §5.1 IDBCursorDirection / mojom::blink::IDBCursorDirection *)
Inductive IDBCursorDirection : Type :=
  | Next           (* "next" *)
  | NextNoDuplicate (* "nextunique" *)
  | Prev           (* "prev" *)
  | PrevNoDuplicate (* "prevunique" *).

(** Total order abstraction of valid canonical IDBKeys *)
Definition IDBKey := Z.

(** Representation of a cursor's current position in an ObjectStore or Index *)
Record CursorPosition : Type := mkPos {
  pos_key : IDBKey;
  pos_primary_key : IDBKey
}.

(** Representation of the IDBCursor state machine in Blink *)
Record IDBCursorState : Type := mkCursor {
  cursor_dir : IDBCursorDirection;
  cursor_got_value : bool;
  cursor_pos : CursorPosition;
  cursor_range_lower : IDBKey;
  cursor_range_upper : IDBKey
}.

(** DOMException codes relevant to IDBCursor::continueFunction *)
Inductive DOMExceptionCode : Type :=
  | InvalidStateError
  | InvalidAccessError
  | DataError.

(** Result Monad for Blink ExceptionState *)
Inductive BlinkResult (A : Type) : Type :=
  | Ok (val : A)
  | Throw (err : DOMExceptionCode).

Arguments Ok {A} val.
Arguments Throw {A} err.

(** ** 2. Blink Implementation Semantics (idb_cursor.cc) *)

(** IDBKey::IsLessThan and IDBKey::IsEqual *)
Definition idb_key_lt (k1 k2 : IDBKey) : bool := Z.ltb k1 k2.
Definition idb_key_eq (k1 k2 : IDBKey) : bool := Z.eqb k1 k2.

(** Helper checking if direction is forward ("next" or "nextunique") *)
Definition is_forward_direction (d : IDBCursorDirection) : bool :=
  match d with
  | Next | NextNoDuplicate => true
  | Prev | PrevNoDuplicate => false
  end.

(** Helper checking if direction allows continuePrimaryKey ("next" or "prev") *)
Definition allows_primary_key_continue (d : IDBCursorDirection) : bool :=
  match d with
  | Next | Prev => true
  | NextNoDuplicate | PrevNoDuplicate => false
  end.

(** Exact boolean guard in IDBCursor::continueFunction (idb_cursor.cc) *)
Definition blink_continue_key_ok (dir : IDBCursorDirection)
                                 (curr : CursorPosition)
                                 (target_k : IDBKey)
                                 (opt_target_pk : option IDBKey) : bool :=
  if is_forward_direction dir then
    match opt_target_pk with
    | None => idb_key_lt (pos_key curr) target_k
    | Some target_pk =>
        orb (idb_key_lt (pos_key curr) target_k)
            (andb (idb_key_eq (pos_key curr) target_k)
                  (idb_key_lt (pos_primary_key curr) target_pk))
    end
  else
    match opt_target_pk with
    | None => idb_key_lt target_k (pos_key curr)
    | Some target_pk =>
        orb (idb_key_lt target_k (pos_key curr))
            (andb (idb_key_eq target_k (pos_key curr))
                  (idb_key_lt target_pk (pos_primary_key curr)))
    end.

(** Check whether a candidate next record from the backing store satisfies
    the cursor's IDBKeyRange bounds. *)
Definition in_key_range (k lower upper : IDBKey) : bool :=
  andb (Z.leb lower k) (Z.leb k upper).

(** Model of IDBCursor::continueFunction(key, exception_state)
    when advancing to a resolved position [next_pos] that matches or exceeds [target_k].
    In IndexedDB, continue(target_k) positions the cursor at the first record
    reaching or succeeding target_k in the cursor's direction.
    For validating the step from curr to target_k, Blink runs blink_continue_key_ok. *)
Definition blink_cursor_continue (st : IDBCursorState)
                                 (target_k : IDBKey)
                                 (resolved_pk : IDBKey) : BlinkResult IDBCursorState :=
  if negb (cursor_got_value st) then
    Throw InvalidStateError
  else if negb (blink_continue_key_ok (cursor_dir st) (cursor_pos st) target_k None) then
    Throw DataError
  else if negb (in_key_range target_k (cursor_range_lower st) (cursor_range_upper st)) then
    Throw DataError
  else
    Ok (mkCursor (cursor_dir st)
                 true
                 (mkPos target_k resolved_pk)
                 (cursor_range_lower st)
                 (cursor_range_upper st)).

(** Model of IDBCursor::continuePrimaryKey(key, primary_key, exception_state) *)
Definition blink_cursor_continue_primary_key (st : IDBCursorState)
                                             (target_k : IDBKey)
                                             (target_pk : IDBKey) : BlinkResult IDBCursorState :=
  if negb (cursor_got_value st) then
    Throw InvalidStateError
  else if negb (allows_primary_key_continue (cursor_dir st)) then
    Throw InvalidAccessError
  else if negb (blink_continue_key_ok (cursor_dir st) (cursor_pos st) target_k (Some target_pk)) then
    Throw DataError
  else if negb (in_key_range target_k (cursor_range_lower st) (cursor_range_upper st)) then
    Throw DataError
  else
    Ok (mkCursor (cursor_dir st)
                 true
                 (mkPos target_k target_pk)
                 (cursor_range_lower st)
                 (cursor_range_upper st)).

(** ** 3. Normative Specification Predicates (W3C IndexedDB 3 §5) *)

(** Strict key monotonicity required by `continue(key)` *)
Definition spec_strict_