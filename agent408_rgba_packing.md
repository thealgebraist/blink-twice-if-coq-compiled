**AUDIT LOG: AGENT 408**
**SUBJECT:** Chromium/Blink `RGBA8888` Color Packing Formulation
**STATUS:** ACTIVE

In the Chromium/Blink rendering architecture (referencing `blink::Color` and Skia's `SkColor` representations), `RGBA8888` utilizes a 32-bit unsigned integer (`uint32_t`) where each color channel (Red, Green, Blue, Alpha) is allocated 8 bits (1 byte), yielding values from `0` to `255` (`0x00` to `0xFF`).

Below is the bit-level shift and mask formulation for logical `RGBA8888` packing and unpacking.

### 1. Bit Layout (Logical 32-bit Register)
Assuming a standard logical `RGBA` ordering from Most Significant Byte (MSB) to Least Significant Byte (LSB):

*   **Red (R):** Bits 24–31
*   **Green (G):** Bits 16–23
*   **Blue (B):** Bits 8–15
*   **Alpha (A):** Bits 0–7

*(Note: Internally, Blink's `Color` class and `SkColor` frequently default to `ARGB8888` or platform-dependent `BGRA8888` via `SkPMColor` for premultiplied alpha. However, for strict `RGBA8888` serialization—such as WebGL textures or Canvas `ImageData`—the following formulation applies).*

### 2. Bit Shifts (Offsets)
To position an 8-bit channel value (`0x00`–`0xFF`) into its correct byte boundary within the 32-bit integer, the following bit shifts are defined:

```cpp
constexpr uint32_t kRedShift   = 24;
constexpr uint32_t kGreenShift = 16;
constexpr uint32_t kBlueShift  = 8;
constexpr uint32_t kAlphaShift = 0;
```

### 3. Bit Masks
Masks are formulated by shifting the 8-bit base mask (`0xFF`) to the respective channel's bit offset. These are used to isolate specific channels during unpacking or clearing bits during mutation.

*   **Base Mask:** `0xFF` (Binary: `11111111`)

```cpp
constexpr uint32_t kRedMask   = 0xFF000000; // (0xFFu << 24)
constexpr uint32_t kGreenMask = 0x00FF0000; // (0xFFu << 16)
constexpr uint32_t kBlueMask  = 0x0000FF00; // (0xFFu << 8)
constexpr uint32_t kAlphaMask = 0x000000FF; // (0xFFu << 0)
```

### 4. Packing Formulation
To pack four 8-bit unsigned integers (`uint8_t r, g, b, a`) into a single 32-bit `RGBA8888` integer:

1.  **Sanitize/Cast:** Cast inputs to `uint32_t` (and optionally mask with `0xFF` if inputs are wider than 8 bits to prevent overflow contamination).
2.  **Shift:** Left-shift (`<<`) each channel to its designated bit offset.
3.  **Combine:** Apply bitwise OR (`|`) to merge the non-overlapping bitfields.

```cpp
inline uint32_t PackRGBA8888(uint8_t r, uint8_t g, uint8_t b, uint8_t a) {
    return (static_cast<uint32_t>(r) << 24) |
           (static_cast<uint32_t>(g) << 16) |
           (static_cast<uint32_t>(b) << 8)  |
           (static_cast<uint32_t>(a) << 0);
}
```

### 5. Unpacking Formulation
To extract individual 8-bit channels from a packed 32-bit `uint32_t rgba` value:

1.  **Shift:** Right-shift (`>>`) the 32-bit integer by the channel's offset to move the target byte to the LSB position (bits 0–7).
2.  **Mask:** Apply a bitwise AND (`&`) with `0xFF` to strip all higher-order bits.

```cpp
inline uint8_t UnpackRed(uint32_t rgba)   { return (rgba >> 24) & 0xFF; }
inline uint8_t UnpackGreen(uint32_t rgba) { return (rgba >> 16) & 0xFF; }
inline uint8_t UnpackBlue(uint32_t rgba)  { return (rgba >> 8)  & 0xFF; }
inline uint8_t UnpackAlpha(uint32_t rgba) { return (rgba >> 0)  & 0xFF; }
```
*(Alternatively, one may apply the full channel mask first `(rgba & kRedMask) >> kRedShift`, which is instructionally equivalent in modern C++ compilers).*

### 6. Audit Caveat: Endianness vs. Byte-Array Order
When auditing Blink memory buffers (e.g., `uint8_t*` in V8 `Uint8ClampedArray` for Canvas), a distinction must be made between **Register Order** and **Memory Order**:
*   On **Little-Endian** architectures (x86_64, ARM64), a `uint32_t` packed as `0xRRGGBBAA` in a register is written to memory sequentially as `[AA, BB, GG, RR]`.
*   To achieve a strict byte-array layout of `[RR, GG, BB, AA]` in memory on Little-Endian systems via 32-bit writes, the register must be packed in reverse (`ABGR8888`):
    `A << 24 | B << 16 | G << 8 | R`

**END OF REPORT - AGENT 408**