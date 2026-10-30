Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink WebAssembly Linear Memory Page Allocation Semantics *)
(** WebAssembly Core Spec §5.4: 1 page = 64 KiB = 65536 bytes *)

Definition WASM_PAGE_SIZE : Z := 65536.

Definition wasm_memory_byte_size (pages : Z) : Z :=
  pages * WASM_PAGE_SIZE.

Theorem wasm_memory_byte_size_nonneg : forall pages,
  0 <= pages ->
  0 <= wasm_memory_byte_size pages.
Proof.
  intros pages Hpos.
  unfold wasm_memory_byte_size, WASM_PAGE_SIZE.
  lia.
Qed.

Theorem wasm_memory_byte_size_monotonic : forall p1 p2,
  p1 <= p2 ->
  wasm_memory_byte_size p1 <= wasm_memory_byte_size p2.
Proof.
  intros p1 p2 Hle.
  unfold wasm_memory_byte_size, WASM_PAGE_SIZE.
  lia.
Qed.
