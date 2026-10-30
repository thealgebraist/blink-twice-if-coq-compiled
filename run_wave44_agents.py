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
        "id": 609,
        "filename": "agent609_bluetooth_uuid_16_expansion.md",
        "topic": "Web Bluetooth 16-bit to 128-bit UUID expansion semantics",
        "source": "third_party/blink/renderer/modules/bluetooth/bluetooth_uuid.cc",
        "spec": "Web Bluetooth §3.4.1 / Bluetooth Core Spec v5.4 Vol 3 Part B §2.5.1",
        "theory": "BlinkWebBluetoothUUID16ExpansionSemantics.v",
        "math": "uuid128 = (uuid16 << 96) | BASE_UUID; expansion is strictly injective and reversible."
    },
    {
        "id": 610,
        "filename": "agent610_bluetooth_gatt_connection_state.md",
        "topic": "Web Bluetooth GATT connection state automaton semantics",
        "source": "third_party/blink/renderer/modules/bluetooth/bluetooth_device.cc",
        "spec": "Web Bluetooth §4.2 GATTServer connect/disconnect state machine",
        "theory": "BlinkWebBluetoothGATTConnectionStateSemantics.v",
        "math": "valid transitions: Disconnected -> Connecting -> Connected -> Disconnecting -> Disconnected."
    },
    {
        "id": 611,
        "filename": "agent611_bluetooth_characteristic_properties.md",
        "topic": "Web Bluetooth GATT characteristic properties bitmask semantics",
        "source": "third_party/blink/renderer/modules/bluetooth/bluetooth_remote_gatt_characteristic.cc",
        "spec": "Web Bluetooth §4.5 Characteristic Properties Bitmask (read, write, notify, indicate)",
        "theory": "BlinkWebBluetoothCharacteristicPropertiesSemantics.v",
        "math": "has_property(mask, prop) = (mask & prop) != 0; read/write operations require valid permission flag."
    },
    {
        "id": 612,
        "filename": "agent612_bluetooth_write_chunk_size.md",
        "topic": "Web Bluetooth writeValueWithResponse max chunk size bounding",
        "source": "third_party/blink/renderer/modules/bluetooth/bluetooth_remote_gatt_characteristic.cc",
        "spec": "Web Bluetooth §4.5 writeValue bounds (ATT MTU - 3 <= 512 bytes)",
        "theory": "BlinkWebBluetoothWriteChunkSizeSemantics.v",
        "math": "valid_write_chunk(sz, mtu) = 1 <= sz <= min(mtu - 3, 512)."
    },
    {
        "id": 613,
        "filename": "agent613_usb_interface_number_uniqueness.md",
        "topic": "WebUSB interface number uniqueness within USB configuration",
        "source": "third_party/blink/renderer/modules/webusb/usb_configuration.cc",
        "spec": "WebUSB API §3.4 / USB 2.0 §9.6.3 interface numbering",
        "theory": "BlinkWebUSBInterfaceNumberUniquenessSemantics.v",
        "math": "distinct interfaces within configuration have pairwise distinct interface numbers."
    },
    {
        "id": 614,
        "filename": "agent614_usb_alternate_setting_monotonicity.md",
        "topic": "WebUSB alternate settings validation and selection semantics",
        "source": "third_party/blink/renderer/modules/webusb/usb_interface.cc",
        "spec": "WebUSB API §3.5 selectAlternateSetting",
        "theory": "BlinkWebUSBAlternateSettingSemantics.v",
        "math": "alternate setting index valid iff 0 <= alt_idx < num_alternate_settings."
    },
    {
        "id": 615,
        "filename": "agent615_usb_endpoint_direction_classification.md",
        "topic": "WebUSB endpoint direction and transfer type classification",
        "source": "third_party/blink/renderer/modules/webusb/usb_endpoint.cc",
        "spec": "WebUSB API §3.7 / USB 2.0 §9.6.6 endpoint address bit 7 (IN=1, OUT=0)",
        "theory": "BlinkWebUSBEndpointDirectionSemantics.v",
        "math": "endpoint_dir(addr) = if (addr & 0x80) != 0 then In else Out."
    },
    {
        "id": 616,
        "filename": "agent616_usb_setup_packet_length.md",
        "topic": "WebUSB control transfer setup packet 8-byte layout soundness",
        "source": "third_party/blink/renderer/modules/webusb/usb_device.cc",
        "spec": "WebUSB API §3.3 / USB 2.0 §9.3 Setup Packet (bmRequestType, bRequest, wValue, wIndex, wLength = 8 bytes)",
        "theory": "BlinkWebUSBSetupPacketLengthSemantics.v",
        "math": "setup_packet_size = 1 + 1 + 2 + 2 + 2 = 8 bytes invariant."
    },
    {
        "id": 617,
        "filename": "agent617_hid_report_id_prefix.md",
        "topic": "WebHID report ID prefixing and byte sequence normalization",
        "source": "third_party/blink/renderer/modules/hid/hid_device.cc",
        "spec": "WebHID API §4.2 Input/Output Report ID prefixing",
        "theory": "BlinkWebHIDReportIDPrefixSemantics.v",
        "math": "report_payload_len(raw_len, has_report_id) = if has_id then raw_len - 1 else raw_len."
    },
    {
        "id": 618,
        "filename": "agent618_hid_usage_page_32bit.md",
        "topic": "WebHID 32-bit usage code decomposition into usage page and usage ID",
        "source": "third_party/blink/renderer/modules/hid/hid_collection_info.cc",
        "spec": "WebHID API §3.3 / USB HID 1.11 §5.5 Usage Page (top 16 bits) and Usage (low 16 bits)",
        "theory": "BlinkWebHIDUsagePage32BitSemantics.v",
        "math": "usage_page(u32) = u32 / 65536; usage_id(u32) = u32 mod 65536; u32 = usage_page * 65536 + usage_id."
    },
    {
        "id": 619,
        "filename": "agent619_serial_baud_rate_positive.md",
        "topic": "Web Serial baudRate positive validation and bounds check",
        "source": "third_party/blink/renderer/modules/serial/serial_port.cc",
        "spec": "Web Serial API §3.2 SerialOptions.baudRate validation",
        "theory": "BlinkWebSerialBaudRatePositiveSemantics.v",
        "math": "valid_baud_rate(b) = (0 < b <= 4000000)."
    },
    {
        "id": 620,
        "filename": "agent620_serial_buffer_size_clamping.md",
        "topic": "Web Serial bufferSize default and clamping semantics",
        "source": "third_party/blink/renderer/modules/serial/serial_port.cc",
        "spec": "Web Serial API §3.2 bufferSize default 255 and clamped > 0",
        "theory": "BlinkWebSerialBufferSizeClampingSemantics.v",
        "math": "effective_buf_size(opt) = if opt <= 0 then 255 else min(opt, 16777216)."
    },
    {
        "id": 621,
        "filename": "agent621_serial_parity_stop_bits.md",
        "topic": "Web Serial parity and stopBits enum validity semantics",
        "source": "third_party/blink/renderer/modules/serial/serial_port.cc",
        "spec": "Web Serial API §3.2 ParityType (none/even/odd) and StopBits (1/2)",
        "theory": "BlinkWebSerialParityStopBitsSemantics.v",
        "math": "valid_parity(p) in {none, even, odd}; valid_stop_bits(s) in {1, 2}."
    },
    {
        "id": 622,
        "filename": "agent622_device_permission_isolation.md",
        "topic": "Peripheral device access permission isolation per origin",
        "source": "third_party/blink/renderer/modules/permissions/permission_utils.cc",
        "spec": "W3C Permissions API §4 / WebUSB / WebBluetooth origin isolation",
        "theory": "BlinkWebDevicePermissionIsolationSemantics.v",
        "math": "origin1 <> origin2 -> has_permission(dev, origin1) does not imply has_permission(dev, origin2)."
    },
    {
        "id": 623,
        "filename": "agent623_usb_claim_interface_exclusivity.md",
        "topic": "WebUSB claimInterface mutual exclusivity semantics",
        "source": "third_party/blink/renderer/modules/webusb/usb_device.cc",
        "spec": "WebUSB API §3.3 claimInterface throws NetworkError if already claimed",
        "theory": "BlinkWebUSBClaimInterfaceExclusivitySemantics.v",
        "math": "claim(iface, state) = if is_claimed(iface, state) then Error else Ok(claim_iface(iface, state))."
    },
    {
        "id": 624,
        "filename": "agent624_device_disconnect_cleanup.md",
        "topic": "Peripheral device disconnect teardown and stream cancellation",
        "source": "third_party/blink/renderer/modules/serial/serial_port.cc",
        "spec": "Web Serial / WebUSB / WebHID disconnect event resets open state",
        "theory": "BlinkWebDeviceDisconnectCleanupSemantics.v",
        "math": "disconnect(state) -> is_open = false /\ active_transfers = 0."
    }
]

def run_agent(agent):
    prompt = f"""You are formal verification Agent {agent['id']} specializing in Web Hardware & Peripheral Platform APIs in Chromium Blink and W3C/WHATWG specs.
Topic: {agent['topic']}
Chromium Source: {agent['source']}
Specification: {agent['spec']}
Formal Theory Target: {agent['theory']}
Mathematical Property: {agent['math']}

Write a comprehensive research report in Markdown covering:
1. Exact normative W3C Web Bluetooth / WebUSB / WebHID / Web Serial specification requirements.
2. Blink implementation details and invariants in {agent['source']}.
3. Formal specification definitions in Rocq/Coq (types, functions, predicates).
4. Concrete theorems with complete, admitted-free Rocq/Coq proofs using ZArith/Lia/Bool.
5. Verification analysis proving 0 admits and preservation of hardware API invariants.

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
            f.write(f"Wave44-Agent{agent['id']},{MODEL_NAME},{prompt_tokens},{cand_tokens},{duration:.2f}\n")
        return True
    except Exception as e:
        print(f"[Agent {agent['id']}] FAILED: {e}")
        return False

print(f"Launching 16 concurrent agents for Wave 44 using {MODEL_NAME}...")
with concurrent.futures.ThreadPoolExecutor(max_workers=16) as executor:
    futures = [executor.submit(run_agent, agent) for agent in AGENTS]
    results = [f.result() for f in concurrent.futures.as_completed(futures)]

print(f"Wave 44 complete: {sum(results)}/16 succeeded.")
