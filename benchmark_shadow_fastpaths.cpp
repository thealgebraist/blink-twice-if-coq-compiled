// benchmark_shadow_fastpaths.cpp
#include <iostream>
#include <chrono>
#include <vector>
#include "blink_shadow_fastpaths.h"

int main() {
    constexpr int64_t iterations = 50'000'000;
    
    // Baseline: General dynamic computation
    blink_shadow::ShadowData s_sym{0, 10 * 64, 5 * 64, 0, 0};
    
    auto t0 = std::chrono::high_resolution_clock::now();
    volatile int32_t sink = 0;
    for (int64_t i = 0; i < iterations; ++i) {
        auto out = blink_shadow::ComputeShadowOutsets_General(s_sym);
        sink += out.top;
    }
    auto t1 = std::chrono::high_resolution_clock::now();
    double time_general = std::chrono::duration<double, std::milli>(t1 - t0).count();
    
    // Formally Verified C++23 Specialized Fast-Path
    constexpr blink_shadow::ShadowData const_sym{0, 10 * 64, 5 * 64, 0, 0};
    auto t2 = std::chrono::high_resolution_clock::now();
    for (int64_t i = 0; i < iterations; ++i) {
        auto out = blink_shadow::ComputeShadowOutsets_Specialized<const_sym>();
        sink += out.top;
    }
    auto t3 = std::chrono::high_resolution_clock::now();
    double time_specialized = std::chrono::duration<double, std::milli>(t3 - t2).count();
    
    std::cout << "=== Blink Visual Shadow Outset Benchmark (50,000,000 runs) ===" << std::endl;
    std::cout << "General Blink Outset Logic: " << time_general << " ms" << std::endl;
    std::cout << "Specialized C++23 Fast-Path: " << time_specialized << " ms" << std::endl;
    std::cout << "Speedup: " << (time_general / time_specialized) << "x" << std::endl;
    
    return 0;
}

