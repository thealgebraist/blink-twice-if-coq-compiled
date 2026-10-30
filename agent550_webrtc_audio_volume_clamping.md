# Formal Verification of WebRTC Audio Track Volume Gain Multiplier Non-Negativity in Chromium Blink

**Formal Theory Target:** `BlinkWebRTCAudioGainClampingSemantics.v`  
**Chromium Subsystem:** `third_party/blink/renderer/modules/mediastream/media_stream_audio_processor.cc`  
**Normative Specifications:** W3C WebRTC 1.0 §5.2 (`RTCRtpSender`), W3C Media Capture and Streams (`MediaStreamTrack`), Web Audio API §1.2  
**Mathematical Property:** $\forall g \in \mathbb{Z},\; \text{clamp\_gain}(g) \in [0, 1000] \implies \text{clamp\_gain}(g) \ge 0$ (Basis Points Representation)

---

## 1. Normative W3C, WHATWG, and IETF Specification Requirements

### 1.1 W3C WebRTC 1.0: Real-Time Communication Between Browsers (§5.2)
In W3C WebRTC 1.0 §5.2 (`RTCRtpSender` Interface) and its dependency, W3C Media Capture and Streams (`MediaStreamTrack`), audio data sourced from a `MediaStreamTrack` is processed through a media pipeline before packetization via Secure Real-time Transport Protocol (SRTP, RFC 3711) and transmission over an `RTCPeerConnection`.

The specification mandates that media processing steps applied to an audio source—including Automatic Gain Control (AGC), Echo Cancellation (AEC), and Noise Suppression (NS)—must preserve signal integrity and adhere to strict boundary invariants:
1. **Amplitude Scaling Monotonicity & Non-Negativity:** Volume gain multipliers represent scalar energy amplification or attenuation factors applied to Pulse-Code Modulation (PCM) sample frames. A negative volume gain multiplier is semantically invalid under WebRTC track constraints; applying a negative scalar $g < 0$ to a PCM frame $S[n]$ results in a $180^\circ$ phase inversion ($S'[n] = -|g| \cdot S[n]$) rather than attenuation. Phase inversion breaks acoustic echo cancellation (AEC) adaptive filters (such as NLMS—Normalized Least Mean Squares) which rely on phase-coherent reference signals.
2. **Upper-Bound Clamping (Anti-Clipping):** Unbounded gain multipliers cause digital hard clipping when PCM samples exceed the representable range $[-1.0, +1.0]$ (in 32-bit float) or $[-32768, +32767]$ (in 16-bit signed integer `int16_t`), introducing severe harmonic distortion and violating RFC 7587 (RTP Payload Format for the Opus Speech and Audio Codec) signal conditioning expectations.

### 1.2 WebRTC Audio Processing Module (APM) Scaling Domain
Within the browser's media capture pipeline, floating-point volume multipliers $G_{\text{float}} \in [0.0, 1.0]$ (or amplified ranges up to $10.0\times$ in basis points) are discretized into integer domains for lock-free atomic exchange and deterministic fixed-point DSP execution. 

Specifically, when scaling factors are expressed in **basis points** (where $100\text{ bps} = 1.0\times$ unity gain, and $1000\text{ bps} = 10.0\times$ maximum amplification, or normalized millibel/basis-point steps in $[0, 1000]$), the normative requirement dictates:
$$\forall g_{\text{raw}} \in \mathbb{Z}, \quad g_{\text{effective}} = \min(\max(g_{\text{raw}}, 0), 1000)$$
Under no circumstances may an out-of-bounds parameter from IPC, hardware volume callbacks, or JavaScript constraint mutations (`applyConstraints`) result in a negative multiplier $g_{\text{effective}} < 0$.

---

## 2. Chromium Blink Implementation & Invariants

### 2.1 Architectural Context: `media_stream_audio_processor.cc`
In Chromium's Blink rendering engine, `blink::MediaStreamAudioProcessor` (implemented in `third_party/blink/renderer/modules/mediastream/media_stream_audio_processor.cc`) serves as the bridge between raw audio capture (`media::AudioParameters`, `media::AudioBus`) and the WebRTC `webrtc::AudioProcessing` (APM) pipeline.

```
[ Hardware Capture / IPC ] 
       │ (media::AudioBus, raw volume)
       ▼
[ blink::MediaStreamAudioDeliverer ]
       │
       ▼
[ blink::MediaStreamAudioProcessor::ProcessData() ]  <-- Real-Time Audio Thread
       │  ├─ Audio Gain Clamping & Basis Point Discretization
       │  ├─ webrtc::AudioProcessing (AEC3, AGC2, NS)
       │  └─ Post-Gain Scaling & PCM Frame Conditioning
       ▼
[ blink::WebRtcAudioSink / RTCRtpSender ]
```

### 2.2 Implementation Mechanics and Clamping Invariants
During real-time audio capture, `MediaStreamAudioProcessor::ProcessData` executes on the high-priority real-time audio capture thread. It receives captured audio frames alongside an input volume scalar `volume` provided by the OS audio layer or upstream track processor.

1. **Input Domain Hazard:** The raw volume metric passed from OS drivers (ALSA, PulseAudio, CoreAudio, WASAPI) or mutated via cross-thread `std::atomic` / Mojo IPC boundaries can transiently fall outside the nominal $[0.0, 1.0]$ or $[0, 1000]$ basis-point envelope due to driver bugs, uninitialized hardware mixer states, or floating-point rounding inaccuracies during dBFS-to-linear conversion.
2. **Clamping Enforcement:** Before applying the gain multiplier to the `media::AudioBus` (via `AudioBus::Scale(float)`) or passing the quantized integer volume level to WebRTC's AGC controller (`webrtc::AudioProcessing::set_stream_analog_level`), Blink enforces strict boundary clampingequivalent to `std::clamp(gain_bps, 0, 1000)` (or `base::clamp`).
3. **Sample-Level Preservation:** Given a clamped gain $G \in [0, 1000]$ (representing $\frac{G}{1000}$ or $\frac{G}{100}$ linear gain) and a PCM sample $s \in \mathbb{Z}$, the scaled output sample $s' = \lfloor \frac{s \cdot G}{1000} \rfloor$ preserves the sign of $s$ (for $G > 0$) or zeroes the signal ($G = 0$), strictly preventing unintended phase inversion ($\text{sgn}(s') = -\text{sgn}(s)$ for $s \neq 0, G > 0$).

---

## 3. Formal Specification in Rocq / Coq

We formalize the discrete basis-point gain semantics, the clamping operator, the fixed-point PCM scaling pipeline, and the safety predicates in Rocq (Coq). The formalization uses `ZArith` to model signed arbitrary-precision integers (capturing both 32-bit/64-bit C++ `int32_t`/`int64_t` arithmetic without silent overflow masking) and `Bool` for decidable runtime state checks.

### 3.1 Core Definitions (`BlinkWebRTCAudioGainClampingSemantics.v`)

* **`GainBPS`**: Represented over $\mathbb{Z}$, where $0$ corresponds to complete silence ($0.0\times$), $100$ (or $1000$) corresponds to nominal/maximum bound ($1000\text{ bps}$), and negative values represent malformed phase-inverting inputs.
* **`clamp_gain`**: Models `std::clamp(g, 0, 1000)` using standard `Z.max` and `Z.min` lattice operations.
* **`apply_gain_to_sample`**: Models the discrete DSP scaling operation $\text{sample} \times \text{clamped\_gain}$.

---

## 4. Concrete Theorems and Complete Mechanized Proofs

Below is the complete, self-contained, and admitted-free Rocq/Coq vernacular file `BlinkWebRTCAudioGainClampingSemantics.v`. Every theorem is proven constructively using `Lia` (Linear Integer Arithmetic) and `ZArith` structural lemmas.

```coq
(** * BlinkWebRTCAudioGainClampingSemantics.v
    Formal Verification of WebRTC Audio Track Volume Gain Multiplier Non-Negativity
    Target: third_party/blink/renderer/modules/mediastream/media_stream_audio_processor.cc
    Specification: W3C WebRTC 1.0 Section 5.2
*)

From Coq Require Import ZArith.
From Coq Require Import Bool.
From Coq Require Import Lia.
From Coq Require Import List.
Import ListNotations.

Open Scope Z_scope.

(** ** 1. Constants and Domain Definitions *)

(** Minimum allowable gain in basis points (0 bps = 0.0x mute) *)
Definition MIN_GAIN_BPS : Z := 0.

(** Maximum allowable gain in basis points (1000 bps = upper bound) *)
Definition MAX_GAIN_BPS : Z := 1000.

(** Unity gain reference in basis points (100 bps = 1.0x nominal) *)
Definition UNITY_GAIN_BPS : Z := 100.

(** Type alias for raw and clamped gain values in basis points *)
Definition GainBPS := Z.

(** Type alias for discrete PCM audio samples (e.g., int16_t promoted to int32_t) *)
Definition PCMSample := Z.

(** ** 2. Clamping and DSP Operational Semantics *)

(** Models C++ std::clamp(g, MIN_GAIN_BPS, MAX_GAIN_BPS) in media_stream_audio_processor.cc *)
Definition clamp_gain (g : GainBPS) : GainBPS :=
  Z.min (Z.max g MIN_GAIN_BPS) MAX_GAIN_BPS.

(** Alternative compositional clamping order: min first, then max *)
Definition clamp_gain_alt (g : GainBPS) : GainBPS :=
  Z.max MIN_GAIN_BPS (Z.min g MAX_GAIN_BPS).

(** Boolean decidability predicate for valid gain bounds [0, 1000] *)
Definition is_valid_gain_b (g : GainBPS) : bool :=
  (MIN_GAIN_BPS <=? g) && (g <=? MAX_GAIN_BPS).

(** Propositional validity invariant for gain in [0, 1000] basis points *)
Definition ValidGain (g : GainBPS) : Prop :=
  MIN_GAIN_BPS <= g /\ g <= MAX_GAIN_BPS.

(** Propositional non-negativity invariant *)
Definition NonNegativeGain (g : GainBPS) : Prop :=
  0 <= g.

(** Models scaling a PCM sample by a clamped gain multiplier (pre-normalization numerator) *)
Definition scale_pcm_numerator (s : PCMSample) (g : GainBPS) : Z :=
  s * (clamp_gain g).

(** Models an audio bus channel as a list of PCM samples *)
Definition AudioChannel := list PCMSample.

(** Scales an entire audio channel buffer using the clamped gain *)
Definition process_audio_channel (ch : AudioChannel) (raw_gain : GainBPS) : AudioChannel :=
  let cg := clamp_gain raw_gain in
  map (fun s => s * cg) ch.

(** ** 3. Core Safety and Invariant Theorems *)

(** Theorem 1: Equivalency of std::clamp orderings.
    Proves that max-then-min and min-then-max are extensionally equal since MIN <= MAX. *)
Theorem clamp_gain_order_equiv : forall (g : GainBPS),
  clamp_gain g = clamp_gain_alt g.
Proof.
  intros g.
  unfold clamp_gain, clamp_gain_alt, MIN_GAIN_BPS, MAX_GAIN_BPS.
  lia.
Qed.

(** Theorem 2: Universal Bounds Preservation.
    For any arbitrary integer input g, clamp_gain(g) strictly resides in [0, 1000]. *)
Theorem clamp_gain_in_bounds : forall (g : GainBPS),
  ValidGain (clamp_gain g).
Proof.
  intros g.
  unfold ValidGain, clamp_gain, MIN_GAIN_BPS, MAX_GAIN_BPS.
  lia.
Qed.

(** Theorem 3: Non-Negative Gain Preservation (Primary Safety Target).
    No input gain value can ever produce a negative effective gain multiplier. *)
Theorem clamp_gain_non_negative : forall (g : GainBPS),
  NonNegativeGain (clamp_gain g).
Proof.
  intros g.
  unfold NonNegativeGain.
  pose proof (clamp_gain_in_bounds g) as [Hlow _].
  unfold MIN_GAIN_BPS in Hlow.
  exact Hlow.
Qed.

(** Theorem 4: Reflection between Boolean check and Propositional Invariant. *)
Theorem is_valid_gain_b_reflect : forall (g : GainBPS),
  is_valid_gain_b g = true <-> ValidGain g.
Proof.
  intros g.
  unfold is_valid_gain_b, ValidGain, MIN_GAIN_BPS, MAX_GAIN_BPS.
  rewrite andb_true_iff.
  rewrite Z.leb_le.
  rewrite Z.leb_le.
  tauto.
Qed.

(** Theorem 5: Clamped gain always satisfies the runtime boolean check. *)
Theorem clamp_gain_satisfies_check : forall (g : GainBPS),
  is_valid_gain_b (clamp_gain g) = true.
Proof.
  intros g.
  apply is_valid_gain_b_reflect.
  apply clamp_gain_in_bounds.
Qed.

(** Theorem 6: Idempotence of Gain Clamping.
    Re-clamping an already clamped gain across pipeline stages leaves it unchanged. *)
Theorem clamp_gain_idempotent : forall (g : GainBPS),
  clamp_gain (clamp_gain g) = clamp_gain g.
Proof.
  intros g.
  unfold clamp_gain, MIN_GAIN_BPS, MAX_GAIN_BPS.
  lia.
Qed.

(** Theorem 7: Identity on Valid Inputs.
    If the input gain is already within [0, 1000], clamp_gain acts as an identity function. *)
Theorem clamp_gain_identity_on_valid : forall (g : GainBPS),
  ValidGain g -> clamp_gain g = g.
Proof.
  intros g [Hmin Hmax].
  unfold clamp_gain, MIN_GAIN_BPS, MAX_GAIN_BPS in *.
  lia.
Qed.

(** Theorem 8: Monotonicity of Gain Clamping.
    Preserves relative volume ordering: g1 <= g2 implies clamp(g1) <= clamp(g2). *)
Theorem clamp_gain_monotonic : forall (g1 g2 : GainBPS),
  g1 <= g2 -> clamp_gain g1 <= clamp_gain g2.
Proof.
  intros g1 g2 Hle.
  unfold clamp_gain, MIN_GAIN_BPS, MAX_GAIN_BPS.
  lia.
Qed.

(** Theorem 9: Exact Boundary Saturation Characterization.
    Explicitly characterizes underflow saturation to 0 and overflow saturation to 1000. *)
Theorem clamp_gain_