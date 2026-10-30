import ctypes
import sys
from pathlib import Path

# Load compiled C++ library
lib_path = Path("./libblink_clamp.dylib").resolve()
blink_lib = ctypes.CDLL(str(lib_path))

blink_lib.Blink_ClampFlexItemMainSize_Cpp.argtypes = [
    ctypes.c_int32, ctypes.c_int32, ctypes.c_int32, ctypes.c_int32
]
blink_lib.Blink_ClampFlexItemMainSize_Cpp.restype = ctypes.c_int32

# Python mathematical specification mirroring the pure Coq Layer 3
kIntMax = 2147483647
kIntMin = -2147483648
kIndefiniteRaw = -64

def sat32(x: int) -> int:
    if x > kIntMax:
        return kIntMax
    elif x < kIntMin:
        return kIntMin
    return x

def sat_add32(a: int, b: int) -> int:
    return sat32(a + b)

def clamp_upper(x: int, max_val: int) -> int:
    return x if max_val == kIndefiniteRaw else min(x, max_val)

def clamp_lower(x: int, min_val: int) -> int:
    return x if min_val == kIndefiniteRaw else max(x, min_val)

def pure_clamp_flex_item_spec(content_size: int, border_padding: int, min_size: int, max_size: int) -> int:
    s0 = sat_add32(content_size, border_padding)
    s1 = clamp_upper(s0, max_size)
    s2 = clamp_lower(s1, min_size)
    s3 = max(s2, border_padding)
    return max(s3, 0)

# Specialized Stage 1: Unconstrained Max
def spec_stage1_unconstrained(content: int, bp: int, min_s: int) -> int:
    s0 = sat_add32(content, bp)
    s2 = s0 if min_s == kIndefiniteRaw else max(s0, min_s)
    return max(s2, bp, 0)

# Specialized Stage 2: Default Fast Path (min=0, max=none)
def spec_stage2_fast_path(content: int, bp: int) -> int:
    return content + bp

# Specialized Stage 3: Fixed Bounds (min=max=fixed_len)
def spec_stage3_fixed(fixed_len: int) -> int:
    return fixed_len

def run_differential_tests():
    test_cases = [
        # Normal inside bounds
        ("Normal bounds", 3200, 640, 1280, 3500),
        # Clamp to min
        ("Clamp to min", 100, 64, 1280, 6400),
        # Clamp to max
        ("Clamp to max", 8000, 640, 640, 4000),
        # Saturating addition overflow (INT_MAX)
        ("32-bit INT_MAX overflow", 2147483600, 1000, 0, kIndefiniteRaw),
        # Saturating addition underflow (INT_MIN)
        ("32-bit INT_MIN underflow", -2147483600, -1000, kIndefiniteRaw, kIndefiniteRaw),
        # Min overrides Max (CSS Flexbox spec violation resolution)
        ("Min overrides Max", 3000, 100, 5000, 2000),
        # Negative content clamped to border_padding
        ("Negative content clamped to BP", -5000, 320, kIndefiniteRaw, kIndefiniteRaw),
        # Negative content with zero BP clamped to 0
        ("Zero floor", -1000, 0, kIndefiniteRaw, kIndefiniteRaw),
        # Both min and max unconstrained (-64)
        ("Both bounds indefinite", 1500, 250, kIndefiniteRaw, kIndefiniteRaw),
        # Fast path test (min=0, max=-64, valid positive range)
        ("Stage 2 Fast Path Candidate", 1200, 300, 0, kIndefiniteRaw),
        # Fixed box test (min=max=fixed)
        ("Stage 3 Fixed Box Candidate", 500, 200, 1000, 1000),
    ]

    print("=" * 85)
    print(f"{'TEST CASE':<30} | {'C++ BLINK':<12} | {'COQ PURE SPEC':<13} | {'SPECIALIZED':<12} | STATUS")
    print("=" * 85)

    all_passed = True
    for name, c, bp, mn, mx in test_cases:
        cpp_res = blink_lib.Blink_ClampFlexItemMainSize_Cpp(c, bp, mn, mx)
        spec_res = pure_clamp_flex_item_spec(c, bp, mn, mx)
        
        # Check specialized variants where applicable
        specialized_str = "-"
        if mx == kIndefiniteRaw:
            st1 = spec_stage1_unconstrained(c, bp, mn)
            assert st1 == spec_res, f"Stage 1 mismatch: {st1} vs {spec_res}"
            specialized_str = f"St1:{st1}"
            if mn == 0 and c >= 0 and bp >= 0 and (c + bp) <= kIntMax:
                st2 = spec_stage2_fast_path(c, bp)
                assert st2 == spec_res, f"Stage 2 mismatch: {st2} vs {spec_res}"
                specialized_str = f"St2:{st2}"
        elif mn == mx and mn >= bp >= 0:
            st3 = spec_stage3_fixed(mn)
            assert st3 == spec_res, f"Stage 3 mismatch: {st3} vs {spec_res}"
            specialized_str = f"St3:{st3}"

        status = "PASSED" if cpp_res == spec_res else "FAILED"
        if cpp_res != spec_res:
            all_passed = False

        print(f"{name:<30} | {cpp_res:<12} | {spec_res:<13} | {specialized_str:<12} | {status}")

    print("=" * 85)
    if all_passed:
        print("DIFFERENTIAL VERIFICATION RESULT: 100% BIT-FOR-BIT MATCH WITH C++ BLINK!")
    else:
        print("FAILED: Discrepancy detected!")
        sys.exit(1)

if __name__ == "__main__":
    run_differential_tests()

