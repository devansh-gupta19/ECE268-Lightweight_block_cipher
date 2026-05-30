#include <cstdint>
#include <cstring>
#include <iostream>
#include <iomanip>
#include <chrono>
#include <vector>
#include <random>
#include <algorithm>
#include <numeric>
#include <cmath>
#include <fstream>
#include <string>
#include <unistd.h>
#include "bench_utils.h"
#include "aes128.h"

// ============================================================
// Test vectors (NIST FIPS 197)
// ============================================================

static bool run_test_vectors() {
    struct TV { uint8_t key[16]; uint8_t pt[16]; uint8_t expected_ct[16]; };

    // AppB
    TV tvB = {
        {0x2b,0x7e,0x15,0x16,0x28,0xae,0xd2,0xa6,0xab,0xf7,0x15,0x88,0x09,0xcf,0x4f,0x3c},
        {0x32,0x43,0xf6,0xa8,0x88,0x5a,0x30,0x8d,0x31,0x31,0x98,0xa2,0xe0,0x37,0x07,0x34},
        {0x39,0x25,0x84,0x1d,0x02,0xdc,0x09,0xfb,0xdc,0x11,0x85,0x97,0x19,0x6a,0x0b,0x32}
    };
    // AppC
    TV tvC = {
        {0x00,0x01,0x02,0x03,0x04,0x05,0x06,0x07,0x08,0x09,0x0a,0x0b,0x0c,0x0d,0x0e,0x0f},
        {0x00,0x11,0x22,0x33,0x44,0x55,0x66,0x77,0x88,0x99,0xaa,0xbb,0xcc,0xdd,0xee,0xff},
        {0x69,0xc4,0xe0,0xd8,0x6a,0x7b,0x04,0x30,0xd8,0xcd,0xb7,0x80,0x70,0xb4,0xc5,0x5a}
    };

    TV tvs[2] = {tvB, tvC};
    const char* names[2] = {"FIPS197 AppB", "FIPS197 AppC"};
    bool all_pass = true;

    for (int t = 0; t < 2; t++) {
        AES128 aes(tvs[t].key);
        uint8_t ct[16], dec[16];
        aes.encrypt(tvs[t].pt, ct);
        aes.decrypt(ct, dec);

        bool ct_ok  = (std::memcmp(ct,  tvs[t].expected_ct, 16) == 0);
        bool dec_ok = (std::memcmp(dec, tvs[t].pt,          16) == 0);

        std::cerr << names[t] << ": encrypt=" << (ct_ok  ? "PASS" : "FAIL")
                  << "  decrypt=" << (dec_ok ? "PASS" : "FAIL") << "\n";
        if (!ct_ok || !dec_ok) all_pass = false;
    }
    return all_pass;
}

// ============================================================
// Helpers: hostname, cpu model
// ============================================================

static std::string get_hostname() {
    char buf[256] = {};
    if (gethostname(buf, sizeof(buf)) == 0) return buf;
    return "unknown";
}

static std::string get_cpu_model() {
    std::ifstream f("/proc/cpuinfo");
    std::string line;
    while (std::getline(f, line)) {
        if (line.find("model name") != std::string::npos) {
            auto p = line.find(':');
            if (p != std::string::npos) {
                std::string s = line.substr(p+2);
                // trim trailing whitespace
                while (!s.empty() && (s.back()=='\n'||s.back()=='\r'||s.back()==' ')) s.pop_back();
                return s;
            }
        }
    }
    return "unknown";
}

static std::string get_compiler_version() {
#if defined(__GNUC__) && !defined(__clang__)
    return std::string("g++ ") + std::to_string(__GNUC__) + "." +
           std::to_string(__GNUC_MINOR__) + "." + std::to_string(__GNUC_PATCHLEVEL__);
#elif defined(__clang__)
    return std::string("clang++ ") + std::to_string(__clang_major__) + "." +
           std::to_string(__clang_minor__);
#else
    return "unknown";
#endif
}

static std::string timestamp_utc() {
    auto now = std::chrono::system_clock::now();
    std::time_t t = std::chrono::system_clock::to_time_t(now);
    char buf[64];
    std::strftime(buf, sizeof(buf), "%Y-%m-%dT%H:%M:%SZ", std::gmtime(&t));
    return buf;
}

// ============================================================
// main
// ============================================================

int main() {
    // ---- Test vectors first ----
    bool tv_pass = run_test_vectors();
    if (!tv_pass) {
        std::cerr << "ERROR: AES test vector failure\n";
        return 1;
    }

    // ---- Setup ----
    double mhz = cpu_mhz();

    std::mt19937_64 rng(0xECE268);
    auto rand_byte = [&]() -> uint8_t { return rng() & 0xFF; };

    // Generate a random key
    uint8_t key[16];
    for (auto& b : key) b = rand_byte();

    AES128 aes(key);

    // ---- Key schedule benchmark ----
    // 10 batches x 10,000 = 100,000 expansions
    const int KS_BATCHES = 10;
    const int KS_PER_BATCH = 10000;
    const int KS_WARMUP = 10000;

    // Warm up
    {
        uint8_t k2[16]; std::memcpy(k2, key, 16);
        for (int i = 0; i < KS_WARMUP; i++) {
            k2[0] ^= (uint8_t)i;
            AES128 tmp(k2);
            (void)tmp;
        }
    }

    std::vector<double> ks_us_samples;
    ks_us_samples.reserve(KS_BATCHES);
    uint64_t ks_cycles_total = 0;

    for (int b = 0; b < KS_BATCHES; b++) {
        uint8_t k2[16]; std::memcpy(k2, key, 16);
        k2[0] ^= (uint8_t)b;
        Timer t; t.start();
        uint64_t c0 = rdtsc();
        for (int i = 0; i < KS_PER_BATCH; i++) {
            k2[1] ^= (uint8_t)i;
            AES128 tmp(k2);
            (void)tmp;
        }
        uint64_t c1 = rdtsc();
        double us = t.elapsed_us();
        ks_us_samples.push_back(us);
        ks_cycles_total += (c1 - c0);
    }

    double ks_us_mean, ks_us_std;
    stats(ks_us_samples, ks_us_mean, ks_us_std);
    // mean/stddev per expansion
    double ks_per_mean = ks_us_mean / KS_PER_BATCH;
    double ks_per_std  = ks_us_std  / KS_PER_BATCH;
    double ks_cycles_mean = (double)ks_cycles_total / (KS_BATCHES * KS_PER_BATCH);

    // ---- Single-block latency ----
    const int SB_COUNT   = 1000000;
    const int SB_WARMUP  = 10000;

    uint8_t pt[16], ct[16];
    for (auto& b : pt) b = rand_byte();

    // Warm up
    for (int i = 0; i < SB_WARMUP; i++) {
        pt[0] ^= (uint8_t)i;
        aes.encrypt(pt, ct);
    }

    std::vector<uint64_t> sb_cycles;
    sb_cycles.reserve(SB_COUNT);
    for (int i = 0; i < SB_COUNT; i++) {
        uint64_t c0 = rdtsc();
        aes.encrypt(pt, ct);
        uint64_t c1 = rdtsc();
        sb_cycles.push_back(c1 - c0);
        pt[0] ^= ct[0]; // prevent constant folding
    }
    uint64_t sb_median = median_cycles(sb_cycles);

    // ---- Bulk ECB throughput ----
    const size_t BULK_BLOCKS = 1048576; // 16 MB
    const int BULK_WARMUP = 10000;

    std::vector<uint8_t> bulk_in(BULK_BLOCKS * 16);
    std::vector<uint8_t> bulk_out(BULK_BLOCKS * 16);
    for (auto& b : bulk_in) b = rand_byte();

    // Warm up
    for (int i = 0; i < BULK_WARMUP; i++) {
        aes.encrypt(bulk_in.data(), bulk_out.data());
    }

    Timer bulk_timer;
    uint64_t bulk_c0 = rdtsc();
    bulk_timer.start();
    for (size_t i = 0; i < BULK_BLOCKS; i++) {
        aes.encrypt(bulk_in.data() + i*16, bulk_out.data() + i*16);
    }
    uint64_t bulk_c1 = rdtsc();
    double bulk_sec = bulk_timer.elapsed_sec();

    double bulk_mb       = (BULK_BLOCKS * 16.0) / (1024.0 * 1024.0);
    double bulk_mbps     = bulk_mb / bulk_sec;
    double bulk_cpb      = (double)(bulk_c1 - bulk_c0) / (BULK_BLOCKS * 16.0);

    // ---- Output structured log ----
    std::cout << "=== AES-128 cpu ===\n";
    std::cout << "timestamp_utc: "         << timestamp_utc()       << "\n";
    std::cout << "host: "                  << get_hostname()         << "\n";
    std::cout << "cpu: "                   << get_cpu_model()        << "\n";
    std::cout << "cpu_mhz_at_run: "        << mhz                   << "\n";
    std::cout << "gpu: N/A\n";
    std::cout << "compiler: "             << get_compiler_version()  << "\n";
    std::cout << "binary_size_bytes: TBD\n";
    std::cout << "sloc: TBD\n";
    std::cout << "round_key_bytes: 176\n";
    std::cout << "---\n";
    std::cout << std::fixed << std::setprecision(4);
    std::cout << "key_schedule_us_mean: "      << ks_per_mean         << "\n";
    std::cout << "key_schedule_us_stddev: "    << ks_per_std          << "\n";
    std::cout << "key_schedule_cycles_mean: "  << ks_cycles_mean      << "\n";
    std::cout << "single_block_cycles_median: "<< sb_median           << "\n";
    std::cout << "bulk_ecb_throughput_MBps: "  << bulk_mbps           << "\n";
    std::cout << "ctr_throughput_MBps: TBD\n";
    std::cout << "cbc_throughput_MBps: TBD\n";
    std::cout << "cycles_per_byte: "          << bulk_cpb            << "\n";
    std::cout << "gpu_kernel_ms: N/A\n";
    std::cout << "gpu_end_to_end_GBps: N/A\n";
    std::cout << "gpu_kernel_only_GBps: N/A\n";
    std::cout << "test_vector_status: " << (tv_pass ? "PASS" : "FAIL") << "\n";

    return 0;
}
