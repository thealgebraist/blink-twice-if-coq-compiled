import os
import time
import concurrent.futures
from google import genai
from google.genai import types

API_KEY = os.environ.get("GEMINI_API_KEY")
if not API_KEY and os.path.exists("key.txt"):
    with open("key.txt", "r") as f:
        API_KEY = f.read().strip()

client = genai.Client(api_key=API_KEY)
MODEL_NAME = "gemini-4-argon"

AGENTS = [
    {
        "id": 545,
        "filename": "agent545_webrtc_sdp_state.md",
        "topic": "WebRTC SDP offer/answer signaling state machine",
        "source": "third_party/blink/renderer/modules/peerconnection/rtc_peer_connection.cc",
        "spec": "WebRTC 1.0 §4.3.1",
        "theory": "BlinkWebRTCSignalingStateSemantics.v",
        "math": "signaling states: stable(0), have-local-offer(1), have-remote-offer(2), closed(3); closed is terminal."
    },
    {
        "id": 546,
        "filename": "agent546_webrtc_ice_gathering.md",
        "topic": "WebRTC ICE candidate gathering state monotonicity",
        "source": "third_party/blink/renderer/modules/peerconnection/rtc_ice_gathering_state.cc",
        "spec": "WebRTC 1.0 §4.3.2",
        "theory": "BlinkWebRTCICEGatheringStateSemantics.v",
        "math": "monotonic rank: new(0) < gathering(1) < complete(2); complete is terminal."
    },
    {
        "id": 547,
        "filename": "agent547_webrtc_ice_connection.md",
        "topic": "WebRTC ICE connection state transitions",
        "source": "third_party/blink/renderer/modules/peerconnection/rtc_ice_transport.cc",
        "spec": "WebRTC 1.0 §4.3.3",
        "theory": "BlinkWebRTCICEConnectionStateSemantics.v",
        "math": "ice connection states: new(0), checking(1), connected(2), completed(3), failed(4), disconnected(5), closed(6)."
    },
    {
        "id": 548,
        "filename": "agent548_webrtc_rtp_sequence_wrap.md",
        "topic": "WebRTC RTP packet sequence number 16-bit modular wrap-around",
        "source": "third_party/webrtc/modules/rtp_rtcp/source/rtp_packet_received.cc",
        "spec": "RFC 3550 §5.1",
        "theory": "BlinkWebRTCRTPSequenceWrapSemantics.v",
        "math": "next_seq(s) = (s + 1) mod 65536; sequence number stays within [0, 65535]."
    },
    {
        "id": 549,
        "filename": "agent549_webrtc_jitter_buffer_clamping.md",
        "topic": "WebRTC jitter buffer delay bounds clamping",
        "source": "third_party/webrtc/modules/video_coding/jitter_estimator.cc",
        "spec": "RFC 3550 §6.4.1",
        "theory": "BlinkWebRTCJitterBufferDelayClampingSemantics.v",
        "math": "clamped_delay = min(max_delay, max(min_delay, target_delay)); min <= clamped <= max."
    },
    {
        "id": 550,
        "filename": "agent550_webrtc_audio_volume_clamping.md",
        "topic": "WebRTC audio track volume gain multiplier non-negativity",
        "source": "third_party/blink/renderer/modules/mediastream/media_stream_audio_processor.cc",
        "spec": "WebRTC 1.0 §5.2",
        "theory": "BlinkWebRTCAudioGainClampingSemantics.v",
        "math": "gain in [0, 1000] basis points; non-negative gain preservation."
    },
    {
        "id": 551,
        "filename": "agent551_mediastream_track_active.md",
        "topic": "MediaStreamTrack enabled muted boolean conjunction",
        "source": "third_party/blink/renderer/modules/mediastream/media_stream_track_impl.cc",
        "spec": "Media Capture and Streams §4.3.1",
        "theory": "BlinkMediaStreamTrackActiveSemantics.v",
        "math": "is_active = enabled && !muted && (readyState == live)."
    },
    {
        "id": 552,
        "filename": "agent552_mediastream_track_id_unique.md",
        "topic": "MediaStream track collection unique track ID set invariants",
        "source": "third_party/blink/renderer/modules/mediastream/media_stream.cc",
        "spec": "Media Capture and Streams §4.2",
        "theory": "BlinkMediaStreamTrackSetUniquenessSemantics.v",
        "math": "distinct tracks have distinct IDs: id1 <> id2 -> track1 <> track2."
    },
    {
        "id": 553,
        "filename": "agent553_webrtc_datachannel_chunk_size.md",
        "topic": "WebRTC DataChannel message chunk fragmentation size limit",
        "source": "third_party/blink/renderer/modules/peerconnection/rtc_data_channel.cc",
        "spec": "RFC 8831 §6.6",
        "theory": "BlinkWebRTCDataChannelChunkLimitSemantics.v",
        "math": "chunk_size <= 65536 bytes; maximum packet chunk limit bounding."
    },
    {
        "id": 554,
        "filename": "agent554_webrtc_datachannel_buffered_amount.md",
        "topic": "WebRTC DataChannel bufferedAmount non-negative decreasing monotonicity",
        "source": "third_party/blink/renderer/modules/peerconnection/rtc_data_channel.cc",
        "spec": "WebRTC 1.0 §6.2",
        "theory": "BlinkWebRTCDataChannelBufferedAmountSemantics.v",
        "math": "drain_bytes(buffered, sent) = max(0, buffered - sent); monotonic non-increasing."
    },
    {
        "id": 555,
        "filename": "agent555_webrtc_rtp_sender_priority.md",
        "topic": "WebRTC RTCRtpSender encodings priority total ordering",
        "source": "third_party/blink/renderer/modules/peerconnection/rtc_rtp_sender.cc",
        "spec": "WebRTC 1.0 §5.2.2",
        "theory": "BlinkWebRTCRTPSenderPriorityOrderSemantics.v",
        "math": "priority rank: very-low(0) < low(1) < medium(2) < high(3)."
    },
    {
        "id": 556,
        "filename": "agent556_webrtc_dtls_handshake_state.md",
        "topic": "WebRTC DTLS handshake state progression",
        "source": "third_party/blink/renderer/modules/peerconnection/rtc_dtls_transport.cc",
        "spec": "WebRTC 1.0 §5.5",
        "theory": "BlinkWebRTCDTLSHandshakeStateSemantics.v",
        "math": "dtls state progression: new(0) -> connecting(1) -> connected(2); closed(3) / failed(4) terminal."
    },
    {
        "id": 557,
        "filename": "agent557_webrtc_srtp_key_derivation.md",
        "topic": "WebRTC SRTP key derivation length preservation",
        "source": "third_party/webrtc/pc/dtls_srtp_transport.cc",
        "spec": "RFC 5764 §4.2",
        "theory": "BlinkWebRTCSRTPKeyDerivationLengthSemantics.v",
        "math": "derived key length matches cryptographic cipher requirement (16 bytes for AES-128, 32 bytes for AES-256)."
    },
    {
        "id": 558,
        "filename": "agent558_webrtc_stats_timestamp_monotonic.md",
        "topic": "WebRTC statistics timestamp monotonicity",
        "source": "third_party/blink/renderer/modules/peerconnection/rtc_stats_report.cc",
        "spec": "WebRTC Statistics API §4",
        "theory": "BlinkWebRTCStatsTimestampMonotonicitySemantics.v",
        "math": "stats_timestamp(t2) >= stats_timestamp(t1) for t2 >= t1."
    },
    {
        "id": 559,
        "filename": "agent559_mediarecorder_timecode_monotonic.md",
        "topic": "MediaRecorder chunk timecode progression monotonicity",
        "source": "third_party/blink/renderer/modules/mediarecorder/media_recorder.cc",
        "spec": "MediaStream Recording §4.1",
        "theory": "BlinkMediaRecorderTimecodeMonotonicitySemantics.v",
        "math": "chunk_timecode(c2) >= chunk_timecode(c1) for subsequent chunks."
    },
    {
        "id": 560,
        "filename": "agent560_audiocontext_samplerate_validity.md",
        "topic": "AudioContext sample rate standard validity",
        "source": "third_party/blink/renderer/modules/webaudio/audio_context.cc",
        "spec": "Web Audio API §1.2",
        "theory": "BlinkAudioContextSampleRateBoundsSemantics.v",
        "math": "valid_sample_rate(sr) = (22050 <=? sr) && (sr <=? 96000)."
    }
]

def run_agent(agent):
    prompt = f"""You are a formal methods expert and WebRTC/Media researcher analyzing Chromium Blink's WebRTC and Media Stream architecture.
Topic: {agent['topic']}
Chromium Source: {agent['source']}
Specification: {agent['spec']}
Formal Theory Target: {agent['theory']}
Mathematical Property: {agent['math']}

Write a comprehensive research report in Markdown covering:
1. Exact normative W3C/WHATWG/IETF specification requirements.
2. Blink implementation details and invariants in {agent['source']}.
3. Formal specification definitions in Rocq/Coq (types, functions, predicates).
4. Concrete theorems with complete, admitted-free Rocq/Coq proofs using ZArith/Lia/Bool.
5. Verification analysis proving 0 admits and preservation of real-time streaming invariants.

Respond with the report in Markdown format."""

    config = types.GenerateContentConfig(
        thinking_config=types.ThinkingConfig(thinking_budget=2048),
        max_output_tokens=3500,
        temperature=0.2,
    )
    
    t0 = time.time()
    try:
        response = client.models.generate_content(
            model=MODEL_NAME,
            contents=prompt,
            config=config,
        )
        duration = time.time() - t0
        content = response.text
        with open(agent["filename"], "w") as f:
            f.write(content)
        
        usage = response.usage_metadata
        prompt_tokens = usage.prompt_token_count if usage else 0
        cand_tokens = usage.candidates_token_count if usage else 0
        print(f"[Agent {agent['id']}] Done in {duration:.1f}s | tokens: in={prompt_tokens}, out={cand_tokens}")
        with open("token_usage.log", "a") as f:
            f.write(f"Wave40-Agent{agent['id']},{MODEL_NAME},{prompt_tokens},{cand_tokens},{duration:.2f}\n")
        return True
    except Exception as e:
        print(f"[Agent {agent['id']}] FAILED: {e}")
        return False

print(f"Launching 16 concurrent agents for Wave 40 using {MODEL_NAME}...")
with concurrent.futures.ThreadPoolExecutor(max_workers=16) as executor:
    futures = [executor.submit(run_agent, agent) for agent in AGENTS]
    results = [f.result() for f in concurrent.futures.as_completed(futures)]

print(f"Wave 40 complete: {sum(results)}/16 succeeded.")
