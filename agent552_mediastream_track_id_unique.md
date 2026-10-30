# Formal Verification Report: MediaStream Track Collection Unique Track ID Set Invariants in Chromium Blink

## 1. Normative Specification Requirements

The W3C **Media Capture and Streams** specification (specifically **§ 4.2 MediaStream**) defines the core architectural model for grouping synchronized media inputs and outputs. A `MediaStream` consists of a dynamic collection of `MediaStreamTrack` objects, referred to as the stream's *track set*. 

### 1.1 Normative Invariants (§ 4.2)

1. **Track Set Semantics**:
   > "A `MediaStream` object has an associated **track set**, which is an ordered set of `MediaStreamTrack` objects. The order of the tracks in the track set is the order in which the tracks were added to the set, or an implementation-defined order if they were added at the same time."

2. **UUID / Track Identifier Uniqueness**:
   > "Each `MediaStreamTrack` object has an associated `id` attribute, which is a globally unique identifier (UUID) generated when the track is created (or preserved across exact clones where specified, though distinct within a single stream's track set)."
   > "A `MediaStream` object's track set MUST NOT contain more than one `MediaStreamTrack` with the same `id`."

3. **`addTrack(track)` Algorithm (§ 4.2.2)**:
   When the `addTrack(track)` method is invoked on a `MediaStream` $S$:
   - Let $T$ be the `MediaStreamTrack` argument.
   - Let $\mathcal{T}_S$ be $S$'s track set.
   - **Step 2**: If $T$ is already in $\mathcal{T}_S$ (evaluated by track identity / unique track ID within the collection), then abort these steps and return.
   - **Step 3**: Add $T$ to $\mathcal{T}_S$.

4. **`removeTrack(track)` Algorithm (§ 4.2.2)**:
   When the `removeTrack(track)` method is invoked on a `MediaStream` $S$:
   - Let $T$ be the `MediaStreamTrack` argument.
   - Let $\mathcal{T}_S$ be $S$'s track set.
   - **Step 2**: If $T$ is not in $\mathcal{T}_S$, then abort these steps and return.
   - **Step 3**: Remove $T$ from $\mathcal{T}_S$.

5. **`getTrackById(trackId)` Algorithm (§ 4.2.2)**:
   - Returns the unique `MediaStreamTrack` object in $\mathcal{T}_S$ whose `id` attribute equals `trackId`, or `null` if no such track exists. Because IDs are unique within $\mathcal{T}_S$, this lookup is deterministic and well-defined (a partial function $\text{ID} \rightharpoonup \text{Track}$).

---

## 2. Chromium Blink Implementation Analysis

In Chromium's Blink rendering engine, the WebIDL `MediaStream` interface is implemented in `third_party/blink/renderer/modules/mediastream/media_stream.cc` and backed by the lower-level descriptor `MediaStreamDescriptor` (`third_party/blink/renderer/platform/mediastream/media_stream_descriptor.cc`).

### 2.1 Track Storage Architecture

In `blink::MediaStream` (`media_stream.h` / `media_stream.cc`), tracks are segregated by media kind into two Oilpan-managed vectors:
```cpp
using MediaStreamTrackVector = HeapVector<Member<MediaStreamTrack>>;
MediaStreamTrackVector audio_tracks_;
MediaStreamTrackVector video_tracks_;
```

The combined track set of the `MediaStream` is the disjoint union $\mathcal{T}_S = \text{audio\_tracks\_} \cup \text{video\_tracks\_}$.

### 2.2 Invariant Enforcement in `media_stream.cc`

1. **`MediaStream::addTrack(MediaStreamTrack* track, ExceptionState& exception_state)`**:
   Before inserting `track` into `audio_tracks_` or `video_tracks_`, Blink checks for existing membership via `getTrackById(track->id())`:
   ```cpp
   if (!track) {
     exception_state.ThrowDOMException(DOMExceptionCode::kTypeMismatchError,
                                       "The MediaStreamTrack provided is invalid.");
     return;
   }
   if (getTrackById(track->id()))
     return;
   ```
   Because `getTrackById(String id)` scans both `audio_tracks_` and `video_tracks_` for any existing `MediaStreamTrack` whose `id()` matches `track->id()`, `addTrack` strictly enforces that no two tracks in $\text{audio\_tracks\_} \cup \text{video\_tracks\_}$ share the same `id()`.

2. **Constructor Initialization**:
   When a `MediaStream` is constructed from an existing `MediaStreamTrackVector`:
   ```cpp
   for (MediaStreamTrack* track : tracks) {
     if (!getTrackById(track->id())) {
       AddTrackAndUpdateDescriptor(track);
     }
   }
   ```
   Duplicate tracks (or distinct C++ wrapper instances sharing an underlying component ID) are filtered out during construction, establishing the base case of the unique track ID invariant.

3. **`MediaStream::getTrackById(String id)`**:
   ```cpp
   MediaStreamTrack* MediaStream::getTrackById(String id) {
     for (const auto& track : audio_tracks_) {
       if (track->id() == id)
         return track.Get();
     }
     for (const auto& track : video_tracks_) {
       if (track->id() == id)
         return track.Get();
     }
     return nullptr;
   }
   ```
   Under the invariant that `id` is unique across `audio_tracks_` ++ `video_tracks_`, the linear search across `audio_tracks_` followed by `video_tracks_` acts as an injective bijective lookup on the active track set.

4. **Bidirectional Injectivity & Contrapositive Invariant**:
   - **Forward Uniqueness (No Duplicate IDs)**: Any two tracks at distinct positions in the collection have distinct IDs. Consequently, if `track1` and `track2` belong to the stream and `id(track1) = id(track2)`, then `track1 = track2`.
   - **Contrapositive Soundness (Functional ID Assignment)**: Since track IDs are deterministic attributes of `MediaStreamTrack` records, `id(track1) <> id(track2) -> track1 <> track2`.

---

## 3. Formal Specification in Rocq / Coq

Below is the complete, self-contained formalization of `BlinkMediaStreamTrackSetUniquenessSemantics.v`. It models `MediaStreamTrack` records, the segregated `audio_tracks_` and `video_tracks_` vectors in `blink::MediaStream`, the `getTrackById`, `addTrack`, and `removeTrack` transitions, and proves both functional and set-theoretic uniqueness invariants.

```coq
(** * BlinkMediaStreamTrackSetUniquenessSemantics.v
    Formal verification of Chromium Blink MediaStream track collection
    unique track ID set invariants (Media Capture and Streams §4.2,
    third_party/blink/renderer/modules/mediastream/media_stream.cc). *)

From Coq Require Import Bool.Bool.
From Coq Require Import Arith.Arith.
From Coq Require Import ZArith.ZArith.
From Coq Require Import Lists.List.
From Coq Require Import micromega.Lia.
Import ListNotations.

Open Scope Z_scope.

(** ** 1. Core Domain Types *)

(** Track IDs are modeled as integers (representing 128-bit UUIDs / Blink Strings). *)
Definition TrackId := Z.

(** Media kind: Audio or Video. *)
Inductive MediaKind : Type :=
  | KindAudio : MediaKind
  | KindVideo : MediaKind.

Definition media_kind_eqb (k1 k2 : MediaKind) : bool :=
  match k1, k2 with
  | KindAudio, KindAudio => true
  | KindVideo, KindVideo => true
  | _, _ => false
  end.

Lemma media_kind_eqb_eq : forall k1 k2,
  media_kind_eqb k1 k2 = true <-> k1 = k2.
Proof.
  destruct k1, k2; simpl; split; intro H; try reflexivity; discriminate.
Qed.

(** A Blink MediaStreamTrack has an Oilpan pointer identity [ptr_id],
    a string UUID [track_id], and a media [kind]. *)
Record MediaStreamTrack : Type := mkTrack {
  ptr_id   : Z;
  track_id : TrackId;
  kind     : MediaKind
}.

Definition track_eqb (t1 t2 : MediaStreamTrack) : bool :=
  (Z.eqb (ptr_id t1) (ptr_id t2)) &&
  (Z.eqb (track_id t1) (track_id t2)) &&
  (media_kind_eqb (kind t1) (kind t2)).

Lemma track_eqb_eq : forall t1 t2,
  track_eqb t1 t2 = true <-> t1 = t2.
Proof.
  intros [p1 id1 k1] [p2 id2 k2].
  unfold track_eqb; simpl.
  rewrite andb_true_iff, andb_true_iff.
  rewrite Z.eqb_eq, Z.eqb_eq, media_kind_eqb_eq.
  split.
  - intros [[Hp Hid] Hk]. subst. reflexivity.
  - intros H. inversion H. subst. auto.
Qed.

Lemma track_eq_dec : forall (t1 t2 : MediaStreamTrack), {t1 = t2} + {t1 <> t2}.
Proof.
  intros t1 t2.
  destruct (track_eqb t1 t2) eqn:Heq.
  - left. apply track_eqb_eq. exact Heq.
  - right. intro H. apply track_eqb_eq in H. congruence.
Defined.

(** ** 2. Blink MediaStream State Model *)

(** In third_party/blink/renderer/modules/mediastream/media_stream.h:
    MediaStreamTrackVector audio_tracks_;
    MediaStreamTrackVector video_tracks_; *)
Record MediaStream : Type := mkStream {
  audio_tracks : list MediaStreamTrack;
  video_tracks : list MediaStreamTrack
}.

(** Combined track set of the MediaStream. *)
Definition all_tracks (s : MediaStream) : list MediaStreamTrack :=
  audio_tracks s ++ video_tracks s.

(** ** 3. Blink MediaStream Operations (media_stream.cc) *)

(** Helper to search a track vector by track_id. *)
Fixpoint find_track_by_id (id : TrackId) (tracks : list MediaStreamTrack)
  : option MediaStreamTrack :=
  match tracks with
  | [] => None
  | t :: rest =>
      if Z.eqb (track_id t) id then Some t
      else find_track_by_id id rest
  end.

(** MediaStream::getTrackById(String id) scans audio_tracks_ then video_tracks_. *)
Definition getTrackById (s : MediaStream) (id : TrackId) : option MediaStreamTrack :=
  match find_track_by_id id (audio_tracks s) with
  | Some t => Some t
  | None => find_track_by_id id (video_tracks s)
  end.

(** MediaStream::addTrack(MediaStreamTrack* track) *)
Definition addTrack (s : MediaStream) (t : MediaStreamTrack) : MediaStream :=
  match getTrackById s (track_id t) with
  | Some _ => s (* Track ID already present: abort and return unchanged *)
  | None =>
      match kind t with
      | KindAudio =>
          mkStream (audio_tracks s ++ [t]) (video_tracks s)
      | KindVideo =>
          mkStream (audio_tracks s) (video_tracks s ++ [t])
      end
  end.

(** Helper to remove a track by pointer identity / equality, matching
    Blink's EraseAt(FindTrack(track)) in MediaStream::removeTrack. *)
Fixpoint remove_track_from_list (t : MediaStreamTrack) (tracks : list MediaStreamTrack)
  : list MediaStreamTrack :=
  match tracks with
  | [] => []
  | hd :: tl =>
      if track_eqb hd t then remove_track_from_list t tl
      else hd :: remove_track_from_list t tl
  end.

(** MediaStream::removeTrack(MediaStreamTrack* track) *)
Definition removeTrack (s : MediaStream) (t : MediaStreamTrack) : MediaStream :=
  match kind t with
  | KindAudio =>
      mkStream (remove_track_from_list t (audio_tracks s)) (video_tracks s)
  | KindVideo =>
      mkStream (audio_tracks s) (remove_track_from_list t (video_tracks s))
  end.

(** MediaStream Constructor from a list of tracks:
    Iteratively adds tracks whose IDs are not already present. *)
Definition emptyStream : MediaStream := mkStream [] [].

Definition createMediaStream (tracks : list MediaStreamTrack) : MediaStream :=
  fold_left addTrack tracks emptyStream.

(** ** 4. Formal Invariant Definitions *)

(** A list of tracks has unique track IDs if the list of projected track_ids is NoDup. *)
Definition UniqueTrackIdsList (tracks : list MediaStreamTrack) : Prop :=
  NoDup (map track_id tracks).

(** Primary Stream Invariant:
    1. Every track in all_tracks has a globally unique track_id within the stream.
    2. All tracks in audio_tracks have KindAudio.
    3. All tracks in video_tracks have KindVideo. *)
Record StreamWellFormed (s : MediaStream) : Prop := mkWF {
  wf_unique_ids : UniqueTrackIdsList (all_tracks s);
  wf_audio_kind : Forall (fun t => kind t = KindAudio) (audio_tracks s);
  wf_video_kind : Forall (fun t => kind t = KindVideo) (video_tracks s)
}.
```

---

## 4. Concrete Theorems and Complete Admitted-Free Proofs

We now prove the core theorems required by the formal theory target `BlinkMediaStreamTrackSetUniquenessSemantics.v`:
1. **Distinct Track IDs Imply Distinct Tracks**: `track_id t1 <> track_id t2 -> t1 <> t2`.
2. **Injectivity of `track_id` on Well-Formed Streams**: Within any well-formed `MediaStream`, `In t1 (all_tracks s) -> In t2 (all_tracks s) -> t1 <> t2 -> track_id t1 <> track_id t2` (and its equivalent `track_id t1 = track_id t2 -> t1 = t2`).
3. **Exact Correspondence of `getTrackById` and