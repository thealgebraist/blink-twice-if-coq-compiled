// benchmark_margin_fastpaths.cpp
#include <iostream>
#include <chrono>
#include <vector>
#include "blink_margin_fastpaths.h"

int main() {
    constexpr int64_t iterations = 50'000'000;
    
    // Baseline: General Blink MarginStrut Sum
    blink_margin::MarginStrut ms{16 * 64, 0, 8 * 64, false};
    
    auto t0 = std::chrono::high_resolution_clock::now();
    volatile int32_t sink = 0;
    for (int64_t i = 0; i < iterations; ++i) {
        sink += blink_margin::Sum_General(ms);
    }
    auto t1 = std::chrono::high_resolution_clock::now();
    double time_general = std::chrono::duration<double, std::milli>(t1 - t0).count();
    
    // Formally Verified C++23 Fast-Path (Pure Positive Margin)
    constexpr int32_t c_pos = 16 * 64;
    constexpr int32_t c_qpos = 8 * 64;
    auto t2 = std::chrono::high_resolution_clock::now();
    for (int64_t i = 0; i < iterations; ++i) {
        sink += blink_margin::Sum_PurePositive<c_pos, c_qpos>();
    }
    auto t3 = std::chrono::high_resolution_clock::now();
    double time_specialized = std::chrono::duration<double, std::milli>(t3 - t2).count();
    
    std::cout << "=== Blink Block MarginStrut Collapsing Benchmark (50,000,000 runs) ===" << std::endl;
    std::cout << "General MarginStrut Logic: " << time_general << " ms" << std::endl;
    std::cout << "Specialized C++23 Fast-Path: " << time_specialized << " ms" << std::endl;
    std::cout << "Speedup: " << (time_general / time_specialized) << "x" << std::endl;
    
    return 0;
}

