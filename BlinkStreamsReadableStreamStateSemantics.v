Require Import ZArith.
Require Import Lia.
Require Import Bool.
Open Scope Z_scope.

(** * Blink Streams ReadableStream State Semantics *)
(** Streams Standard §3.3: closed and errored are terminal states *)

Definition STREAM_READABLE : Z := 1.
Definition STREAM_CLOSED   : Z := 2.
Definition STREAM_ERRORED  : Z := 3.

Definition is_terminal_stream_state (st : Z) : bool :=
  (st =? STREAM_CLOSED) || (st =? STREAM_ERRORED).

Theorem closed_is_terminal :
  is_terminal_stream_state STREAM_CLOSED = true.
Proof.
  reflexivity.
Qed.

Theorem errored_is_terminal :
  is_terminal_stream_state STREAM_ERRORED = true.
Proof.
  reflexivity.
Qed.

Theorem readable_is_not_terminal :
  is_terminal_stream_state STREAM_READABLE = false.
Proof.
  reflexivity.
Qed.
