#pragma once
#include <chrono>
#include <cstdint>
#include <vector>
#include <algorithm>
#include <numeric>
#include <cmath>
#include <fstream>
#include <string>

// RDTSC for x86_64 cycle counting
#ifdef __x86_64__
  #include <x86intrin.h>
  inline uint64_t rdtsc() { return __rdtsc(); }
#else
  inline uint64_t rdtsc() { return 0; }
#endif

// High-resolution wall-clock timer
class Timer {
    using clock = std::chrono::high_resolution_clock;
    clock::time_point t0;
public:
    void start() { t0 = clock::now(); }
    double elapsed_us() const {
        return std::chrono::duration<double,std::micro>(clock::now()-t0).count();
    }
    double elapsed_sec() const { return elapsed_us() * 1e-6; }
};

// Read CPU MHz from /proc/cpuinfo
inline double cpu_mhz() {
    std::ifstream f("/proc/cpuinfo");
    std::string line;
    while (std::getline(f, line)) {
        if (line.find("cpu MHz") != std::string::npos) {
            auto p = line.find(':');
            if (p != std::string::npos) return std::stod(line.substr(p+1));
        }
    }
    return 3000.0; // fallback
}

// Compute mean and stddev over a vector
inline void stats(const std::vector<double>& v, double& mean, double& stddev) {
    mean = std::accumulate(v.begin(), v.end(), 0.0) / v.size();
    double sq = 0;
    for (auto x : v) sq += (x - mean) * (x - mean);
    stddev = std::sqrt(sq / v.size());
}

inline uint64_t median_cycles(std::vector<uint64_t>& v) {
    std::sort(v.begin(), v.end());
    return v[v.size()/2];
}
