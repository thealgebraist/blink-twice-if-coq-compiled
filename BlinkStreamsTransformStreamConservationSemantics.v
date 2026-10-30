Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Streams TransformStream Conservation Semantics *)
(** Streams Standard §5.2: identity transform chunk conservation invariant *)

Record TransformState := {
  chunks_in     : Z;
  chunks_out    : Z;
  chunks_queued : Z
}.

Definition conservation_invariant (st : TransformState) : Prop :=
  chunks_in st = chunks_out st + chunks_queued st.

Definition enqueue_transform_chunk (st : TransformState) : TransformState := {|
  chunks_in     := chunks_in st + 1;
  chunks_out    := chunks_out st;
  chunks_queued := chunks_queued st + 1
|}.

Definition dequeue_transform_chunk (st : TransformState) : TransformState := {|
  chunks_in     := chunks_in st;
  chunks_out    := chunks_out st + 1;
  chunks_queued := chunks_queued st - 1
|}.

Theorem enqueue_preserves_conservation : forall st,
  conservation_invariant st ->
  conservation_invariant (enqueue_transform_chunk st).
Proof.
  intros st Hinv.
  unfold conservation_invariant, enqueue_transform_chunk in *. cbn in *.
  lia.
Qed.

Theorem dequeue_preserves_conservation : forall st,
  conservation_invariant st ->
  conservation_invariant (dequeue_transform_chunk st).
Proof.
  intros st Hinv.
  unfold conservation_invariant, dequeue_transform_chunk in *. cbn in *.
  lia.
Qed.
