// benchmark_fastpaths.cpp
// Microbenchmark comparing General Blink C++ routines vs.
// Auto-synthesized, Formally Verified C++23 Fast-Paths

#include "blink_specialized_fastpaths.h"
#include <chrono>
#include <iostream>
#include <vector>

using namespace blink_formal;

int main() {
    constexpr int kIterations = 50'000'000;

    BoxStrut zero_padding{LayoutUnit(0), LayoutUnit(0)};
    LogicalSize square_ratio{LayoutUnit(640), LayoutUnit(640)}; // 10px : 10px (1:1)
    LayoutUnit block_size(3200); // 50px

    std::cout << "========================================================================\n";
    std::cout << "BLINK LAYOUT BENCHMARK: General Execution vs. Verified C++23 Fast-Path\n";
    std::cout << "Iterations: " << kIterations << "\n";
    std::cout << "========================================================================\n";

    // 1. Benchmark General Aspect-Ratio Function (with runtime branches & 64-bit MulDiv)
    auto t1 = std::chrono::high_resolution_clock::now();
    volatile int32_t sink1 = 0;
    for (int i = 0; i < kIterations; ++i) {
        LayoutUnit res = InlineSizeFromAspectRatio_General(
            zero_padding, square_ratio, EBoxSizing::kContentBox, block_size
        );
        sink1 += res.RawValue();
    }
    auto t2 = std::chrono::high_resolution_clock::now();
    double time_general = std::chrono::duration<double, std::milli>(t2 - t1).count();

    // 2. Benchmark Verified C++23 Fast-Path (Stage 2: Square ContentBox Specialization)
    auto t3 = std::chrono::high_resolution_clock::now();
    volatile int32_t sink2 = 0;
    for (int i = 0; i < kIterations; ++i) {
        LayoutUnit res = FastInlineSizeFromAspectRatio<
            EBoxSizing::kContentBox,
            AspectRatioRegime::kSquareRatio,
            PaddingRegime::kZeroPadding
        >(zero_padding, square_ratio, block_size);
        sink2 += res.RawValue();
    }
    auto t4 = std::chrono::high_resolution_clock::now();
    double time_fastpath = std::chrono::duration<double, std::milli>(t4 - t3).count();

    // 3. Validation
    if (sink1 != sink2) {
        std::cerr << "ERROR: Results do not match!\n";
        return 1;
    }

    std::cout << "General Function Execution Time : " << time_general << " ms\n";
    std::cout << "Verified Fast-Path Time         : " << time_fastpath << " ms\n";
    std::cout << "Speedup Factor                  : " << (time_general / time_fastpath) << "x faster!\n";
    std::cout << "Semantic Result                 : " << (sink1 / kIterations) << " (Exact Match)\n";
    std::cout << "========================================================================\n";

    return 0;
}

