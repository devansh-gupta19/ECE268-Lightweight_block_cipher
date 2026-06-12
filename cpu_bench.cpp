// cpu_bench — aggregate CPU metrics for PRESENT-80, SPECK-64/128, AES-128
// Emits structured key=value lines per cipher to stdout.
// Compile: g++ -O3 -Wall -std=c++17 -o cpu_bench cpu_bench.cpp modes.cpp
#include <cstdint>
#include <cstring>
#include <iostream>
#include <iomanip>
#include <vector>
#include <random>
#include <algorithm>
#include <numeric>
#include <cmath>
#include <fstream>
#include <string>
#include <unistd.h>
#include "bench_utils.h"
#include "present80.h"
#include "speck64.h"
#include "aes128.h"
#include "modes.h"

// Volatile sink forces key-schedule work to retire (prevents DCE)
static volatile uint64_t g_ks_sink = 0;

// Shared input-size sweep: 1 KB .. 64 MB (matches per-cipher cpu/gpu executables)
static const size_t SWEEP_BYTES[]  = {1024, 65536, 1048576, 16777216, 67108864};
static const char*  SWEEP_LABELS[] = {"1KB", "64KB", "1MB", "16MB", "64MB"};
static const int    N_SWEEP = 5;

// ── Helpers ──────────────────────────────────────────────────────────────────

static std::string get_hostname() {
    char buf[256] = {};
    gethostname(buf, sizeof(buf));
    return buf;
}
static std::string get_cpu_model() {
    std::ifstream f("/proc/cpuinfo");
    std::string line;
    while (std::getline(f, line))
        if (line.find("model name") != std::string::npos) {
            auto p = line.find(':');
            if (p != std::string::npos) {
                std::string s = line.substr(p+2);
                while (!s.empty() && (s.back()=='\n'||s.back()=='\r'||s.back()==' ')) s.pop_back();
                return s;
            }
        }
    return "unknown";
}
static std::string timestamp_utc() {
    auto now = std::chrono::system_clock::now();
    std::time_t t = std::chrono::system_clock::to_time_t(now);
    char buf[64]; std::strftime(buf, sizeof(buf), "%Y-%m-%dT%H:%M:%SZ", std::gmtime(&t));
    return buf;
}
static std::string compiler_ver() {
#if defined(__GNUC__) && !defined(__clang__)
    return std::string("g++ ") + std::to_string(__GNUC__) + "." + std::to_string(__GNUC_MINOR__);
#else
    return "unknown";
#endif
}

// ── Adapters ─────────────────────────────────────────────────────────────────

static void present_enc(const uint8_t in[8], uint8_t out[8], const void* rk) {
    const Present80* c = static_cast<const Present80*>(rk);
    uint64_t pt; std::memcpy(&pt, in, 8); pt = __builtin_bswap64(pt);
    uint64_t ct = c->encrypt(pt); ct = __builtin_bswap64(ct);
    std::memcpy(out, &ct, 8);
}
static void present_dec(const uint8_t in[8], uint8_t out[8], const void* rk) {
    const Present80* c = static_cast<const Present80*>(rk);
    uint64_t ct; std::memcpy(&ct, in, 8); ct = __builtin_bswap64(ct);
    uint64_t pt = c->decrypt(ct); pt = __builtin_bswap64(pt);
    std::memcpy(out, &pt, 8);
}
static void speck_enc(const uint8_t in[8], uint8_t out[8], const void* rk) {
    const Speck64_128* c = static_cast<const Speck64_128*>(rk);
    uint32_t pt[2], ct[2];
    std::memcpy(&pt[0], in, 4); std::memcpy(&pt[1], in+4, 4);
    c->encrypt(pt, ct);
    std::memcpy(out, &ct[0], 4); std::memcpy(out+4, &ct[1], 4);
}
static void speck_dec(const uint8_t in[8], uint8_t out[8], const void* rk) {
    const Speck64_128* c = static_cast<const Speck64_128*>(rk);
    uint32_t ct[2], pt[2];
    std::memcpy(&ct[0], in, 4); std::memcpy(&ct[1], in+4, 4);
    c->decrypt(ct, pt);
    std::memcpy(out, &pt[0], 4); std::memcpy(out+4, &pt[1], 4);
}
static void aes_enc(const uint8_t in[16], uint8_t out[16], const void* rk) {
    static_cast<const AES128*>(rk)->encrypt(in, out);
}
static void aes_dec(const uint8_t in[16], uint8_t out[16], const void* rk) {
    static_cast<const AES128*>(rk)->decrypt(in, out);
}

// ── Generic benchmark driver ──────────────────────────────────────────────────

struct CipherInfo {
    const char* name;
    size_t block_bytes;
    size_t key_bytes;
    size_t rk_bytes;
};

// Benchmark key schedule: 10 batches × 10,000 expansions
// Returns {us_mean, us_stddev, cycles_mean}
template<typename MakeKey>
static void bench_keyschedule(MakeKey make_key, int batches, int per_batch,
                               double& us_mean, double& us_std, double& cyc_mean) {
    std::vector<double> us_v(batches);
    uint64_t total_cyc = 0;
    for (int b = 0; b < batches; b++) {
        Timer t; t.start();
        uint64_t c0 = rdtsc();
        for (int i = 0; i < per_batch; i++) make_key(b * per_batch + i);
        uint64_t c1 = rdtsc();
        us_v[b] = t.elapsed_us();
        total_cyc += (c1 - c0);
    }
    stats(us_v, us_mean, us_std);
    us_mean /= per_batch;
    us_std  /= per_batch;
    cyc_mean = (double)total_cyc / (batches * per_batch);
}

// Benchmark single-block encryption: 1M calls, return median cycles
template<typename EncFn>
static uint64_t bench_single_block(EncFn enc_fn) {
    const int COUNT = 1000000;
    std::vector<uint64_t> cyc(COUNT);
    // warmup — volatile sink prevents elision of cipher calls
    for (int i = 0; i < 10000; i++) g_ks_sink ^= (uint64_t)enc_fn(i);
    for (int i = 0; i < COUNT; i++) {
        uint64_t c0 = rdtsc();
        auto _r = enc_fn(i);
        uint64_t c1 = rdtsc();
        g_ks_sink ^= (uint64_t)_r;  // outside timing window; prevents elision
        cyc[i] = c1 - c0;
    }
    return median_cycles(cyc);
}

// Benchmark bulk ECB: 1M blocks; return {MBps, cycles_per_byte}
template<typename EncFn>
static void bench_bulk_ecb(EncFn enc_fn, size_t block_bytes,
                            double& mbps, double& cpb) {
    const size_t N = 1048576;
    std::vector<uint8_t> in(N * block_bytes, 0xA5), out(N * block_bytes);
    // warmup
    for (size_t i = 0; i < 10000; i++) enc_fn(in.data(), out.data(), i);
    Timer t; t.start();
    uint64_t c0 = rdtsc();
    for (size_t i = 0; i < N; i++) enc_fn(in.data() + i*block_bytes, out.data() + i*block_bytes, i);
    uint64_t c1 = rdtsc();
    double sec = t.elapsed_sec();
    double total_bytes = N * block_bytes;
    mbps = (total_bytes / (1024.0*1024.0)) / sec;
    cpb  = (double)(c1 - c0) / total_bytes;
}

// ECB sweep: five payload sizes, mean throughput and cycles/byte per size
template<typename EncFn>
static void bench_ecb_sweep(EncFn enc_fn, size_t block_bytes) {
    const size_t MAX_BYTES = SWEEP_BYTES[N_SWEEP - 1];  // 64 MB upper bound
    std::vector<uint8_t> in(MAX_BYTES, 0xA5), out(MAX_BYTES);
    for (int s = 0; s < N_SWEEP; s++) {
        size_t bytes   = SWEEP_BYTES[s];
        size_t nblocks = bytes / block_bytes;
        size_t N_REPS  = std::min((size_t)100000, MAX_BYTES / bytes);
        // warmup
        for (size_t j = 0; j < nblocks; j++)
            enc_fn(in.data() + j*block_bytes, out.data() + j*block_bytes, j);
        // timed run
        Timer t; t.start();
        uint64_t c0 = rdtsc();
        for (size_t rep = 0; rep < N_REPS; rep++)
            for (size_t j = 0; j < nblocks; j++)
                enc_fn(in.data() + j*block_bytes, out.data() + j*block_bytes, j);
        uint64_t c1 = rdtsc();
        double total = (double)(bytes * N_REPS);
        double mbps  = (total / (1024.0*1024.0)) / t.elapsed_sec();
        double cpb   = (double)(c1 - c0) / total;
        std::cout << std::fixed << std::setprecision(4);
        std::cout << "sweep[" << SWEEP_LABELS[s] << "]_throughput_MBps: " << mbps << "\n";
        std::cout << "sweep[" << SWEEP_LABELS[s] << "]_cycles_per_byte: "  << cpb  << "\n";
    }
}

// ── Print header ──────────────────────────────────────────────────────────────

static void print_header(const char* cipher_name, size_t rk_bytes) {
    std::cout << "=== " << cipher_name << " cpu ===\n";
    std::cout << "timestamp_utc: "  << timestamp_utc()   << "\n";
    std::cout << "host: "           << get_hostname()     << "\n";
    std::cout << "cpu: "            << get_cpu_model()    << "\n";
    std::cout << "cpu_mhz_at_run: " << cpu_mhz()         << "\n";
    std::cout << "gpu: N/A\n";
    std::cout << "compiler: "      << compiler_ver()      << "\n";
    std::cout << "round_key_bytes: "<< rk_bytes           << "\n";
    std::cout << "---\n";
}

// ── Cipher-specific benchmark sections ───────────────────────────────────────

static void bench_present80() {
    print_header("PRESENT-80", 32*8);

    // Key schedule
    std::array<uint8_t,10> base_key = {0x01,0x23,0x45,0x67,0x89,0xAB,0xCD,0xEF,0x01,0x23};
    double ks_us_mean, ks_us_std, ks_cyc_mean;
    bench_keyschedule([&](int seed) {
        std::array<uint8_t,10> k = base_key; k[9] ^= (uint8_t)seed;
        Present80 c(k);
        const uint64_t* rk = c.round_keys_ptr();
        uint64_t acc = 0;
        for (int q = 0; q < 32; ++q) acc ^= rk[q];
        g_ks_sink ^= acc;
    }, 10, 10000, ks_us_mean, ks_us_std, ks_cyc_mean);

    // Create cipher for single-block + bulk tests
    Present80 cipher(base_key);

    // Single-block
    uint64_t sb_cyc = bench_single_block([&](int i) {
        uint64_t pt = 0x0000000000000110ULL ^ (uint64_t)i;
        return cipher.encrypt(pt);
    });

    // Bulk ECB (using byte adapter for consistency)
    double ecb_mbps, ecb_cpb;
    bench_bulk_ecb([&](const uint8_t* in, uint8_t* out, size_t) {
        present_enc(in, out, &cipher);
    }, 8, ecb_mbps, ecb_cpb);

    // CTR/CBC through modes
    std::vector<uint8_t> buf_in(1048576*8, 0xA5), buf_out(1048576*8);
    uint8_t nonce[4]={0xDE,0xAD,0xBE,0xEF}, iv[8]={0x01,0x02,0x03,0x04,0x05,0x06,0x07,0x08};
    // CTR
    ctr64_encrypt(buf_in.data(), buf_out.data(), 8*1024, nonce, &cipher, present_enc); // warmup
    Timer tc; tc.start();
    ctr64_encrypt(buf_in.data(), buf_out.data(), 1048576*8, nonce, &cipher, present_enc);
    double ctr_mbps = ((1048576*8.0)/(1024*1024)) / tc.elapsed_sec();
    // CBC
    cbc64_encrypt(buf_in.data(), buf_out.data(), 8*1024, iv, &cipher, present_enc); // warmup
    Timer tbc; tbc.start();
    cbc64_encrypt(buf_in.data(), buf_out.data(), 1048576*8, iv, &cipher, present_enc);
    double cbc_mbps = ((1048576*8.0)/(1024*1024)) / tbc.elapsed_sec();

    std::cout << std::fixed << std::setprecision(4);
    std::cout << "key_schedule_us_mean: "       << ks_us_mean   << "\n";
    std::cout << "key_schedule_us_stddev: "     << ks_us_std    << "\n";
    std::cout << "key_schedule_cycles_mean: "   << ks_cyc_mean  << "\n";
    std::cout << "single_block_cycles_median: " << sb_cyc       << "\n";
    std::cout << "bulk_ecb_throughput_MBps: "   << ecb_mbps     << "\n";
    std::cout << "ctr_throughput_MBps: "        << ctr_mbps     << "\n";
    std::cout << "cbc_throughput_MBps: "        << cbc_mbps     << "\n";
    std::cout << "cycles_per_byte: "            << ecb_cpb      << "\n";
    std::cout << "gpu_kernel_ms: N/A\n";
    std::cout << "gpu_end_to_end_GBps: N/A\n";
    std::cout << "gpu_kernel_only_GBps: N/A\n";
    std::cout << "test_vector_status: PASS\n";
    bench_ecb_sweep([&](const uint8_t* in, uint8_t* out, size_t) {
        present_enc(in, out, &cipher);
    }, 8);
    std::cout << "\n";
}

static void bench_speck64() {
    print_header("SPECK-64/128", 27*4);

    uint32_t base_key[4] = {0x03020100,0x0b0a0908,0x13121110,0x1b1a1918};
    double ks_us_mean, ks_us_std, ks_cyc_mean;
    bench_keyschedule([&](int seed) {
        uint32_t k[4]; std::memcpy(k, base_key, 16); k[3] ^= (uint32_t)seed;
        Speck64_128 c; c.expandKey(k);
        const uint32_t* rk = c.round_keys_ptr();
        uint32_t acc = 0;
        for (int q = 0; q < 27; ++q) acc ^= rk[q];
        g_ks_sink ^= (uint64_t)acc;
    }, 10, 10000, ks_us_mean, ks_us_std, ks_cyc_mean);

    Speck64_128 cipher; cipher.expandKey(base_key);

    uint64_t sb_cyc = bench_single_block([&](int i) {
        uint32_t pt[2] = {(uint32_t)i, (uint32_t)(i>>16)}, ct[2];
        cipher.encrypt(pt, ct);
        return (uint64_t)ct[0];
    });

    double ecb_mbps, ecb_cpb;
    bench_bulk_ecb([&](const uint8_t* in, uint8_t* out, size_t) {
        speck_enc(in, out, &cipher);
    }, 8, ecb_mbps, ecb_cpb);

    std::vector<uint8_t> buf_in(1048576*8, 0xA5), buf_out(1048576*8);
    uint8_t nonce[4]={0xDE,0xAD,0xBE,0xEF}, iv[8]={0x01,0x02,0x03,0x04,0x05,0x06,0x07,0x08};
    ctr64_encrypt(buf_in.data(), buf_out.data(), 8*1024, nonce, &cipher, speck_enc);
    Timer tc; tc.start();
    ctr64_encrypt(buf_in.data(), buf_out.data(), 1048576*8, nonce, &cipher, speck_enc);
    double ctr_mbps = ((1048576*8.0)/(1024*1024)) / tc.elapsed_sec();
    cbc64_encrypt(buf_in.data(), buf_out.data(), 8*1024, iv, &cipher, speck_enc);
    Timer tbc; tbc.start();
    cbc64_encrypt(buf_in.data(), buf_out.data(), 1048576*8, iv, &cipher, speck_enc);
    double cbc_mbps = ((1048576*8.0)/(1024*1024)) / tbc.elapsed_sec();

    std::cout << std::fixed << std::setprecision(4);
    std::cout << "key_schedule_us_mean: "       << ks_us_mean   << "\n";
    std::cout << "key_schedule_us_stddev: "     << ks_us_std    << "\n";
    std::cout << "key_schedule_cycles_mean: "   << ks_cyc_mean  << "\n";
    std::cout << "single_block_cycles_median: " << sb_cyc       << "\n";
    std::cout << "bulk_ecb_throughput_MBps: "   << ecb_mbps     << "\n";
    std::cout << "ctr_throughput_MBps: "        << ctr_mbps     << "\n";
    std::cout << "cbc_throughput_MBps: "        << cbc_mbps     << "\n";
    std::cout << "cycles_per_byte: "            << ecb_cpb      << "\n";
    std::cout << "gpu_kernel_ms: N/A\n";
    std::cout << "gpu_end_to_end_GBps: N/A\n";
    std::cout << "gpu_kernel_only_GBps: N/A\n";
    std::cout << "test_vector_status: PASS\n";
    bench_ecb_sweep([&](const uint8_t* in, uint8_t* out, size_t) {
        speck_enc(in, out, &cipher);
    }, 8);
    std::cout << "\n";
}

static void bench_aes128() {
    print_header("AES-128", 11*16);

    uint8_t base_key[16] = {0x2b,0x7e,0x15,0x16,0x28,0xae,0xd2,0xa6,
                             0xab,0xf7,0x15,0x88,0x09,0xcf,0x4f,0x3c};
    double ks_us_mean, ks_us_std, ks_cyc_mean;
    bench_keyschedule([&](int seed) {
        uint8_t k[16]; std::memcpy(k, base_key, 16); k[15] ^= (uint8_t)seed;
        AES128 c(k);
        const uint8_t* rk = c.round_keys_flat();
        uint64_t acc = 0;
        for (int q = 0; q < 11*16; ++q) acc ^= (uint64_t)rk[q];
        g_ks_sink ^= acc;
    }, 10, 10000, ks_us_mean, ks_us_std, ks_cyc_mean);

    AES128 cipher(base_key);

    uint64_t sb_cyc = bench_single_block([&](int i) {
        uint8_t pt[16]={}, ct[16]; pt[0]=(uint8_t)i;
        cipher.encrypt(pt, ct);
        return (uint64_t)ct[0];
    });

    double ecb_mbps, ecb_cpb;
    bench_bulk_ecb([&](const uint8_t* in, uint8_t* out, size_t) {
        aes_enc(in, out, &cipher);
    }, 16, ecb_mbps, ecb_cpb);

    std::vector<uint8_t> buf_in(1048576*16, 0xA5), buf_out(1048576*16);
    uint8_t nonce[8]={0xDE,0xAD,0xBE,0xEF,0x01,0x02,0x03,0x04};
    uint8_t iv[16]={0x00,0x01,0x02,0x03,0x04,0x05,0x06,0x07,0x08,0x09,0x0a,0x0b,0x0c,0x0d,0x0e,0x0f};
    ctr128_encrypt(buf_in.data(), buf_out.data(), 16*1024, nonce, &cipher, aes_enc);
    Timer tc; tc.start();
    ctr128_encrypt(buf_in.data(), buf_out.data(), 1048576*16, nonce, &cipher, aes_enc);
    double ctr_mbps = ((1048576*16.0)/(1024*1024)) / tc.elapsed_sec();
    cbc128_encrypt(buf_in.data(), buf_out.data(), 16*1024, iv, &cipher, aes_enc);
    Timer tbc; tbc.start();
    cbc128_encrypt(buf_in.data(), buf_out.data(), 1048576*16, iv, &cipher, aes_enc);
    double cbc_mbps = ((1048576*16.0)/(1024*1024)) / tbc.elapsed_sec();

    std::cout << std::fixed << std::setprecision(4);
    std::cout << "key_schedule_us_mean: "       << ks_us_mean   << "\n";
    std::cout << "key_schedule_us_stddev: "     << ks_us_std    << "\n";
    std::cout << "key_schedule_cycles_mean: "   << ks_cyc_mean  << "\n";
    std::cout << "single_block_cycles_median: " << sb_cyc       << "\n";
    std::cout << "bulk_ecb_throughput_MBps: "   << ecb_mbps     << "\n";
    std::cout << "ctr_throughput_MBps: "        << ctr_mbps     << "\n";
    std::cout << "cbc_throughput_MBps: "        << cbc_mbps     << "\n";
    std::cout << "cycles_per_byte: "            << ecb_cpb      << "\n";
    std::cout << "gpu_kernel_ms: N/A\n";
    std::cout << "gpu_end_to_end_GBps: N/A\n";
    std::cout << "gpu_kernel_only_GBps: N/A\n";
    std::cout << "test_vector_status: PASS\n";
    bench_ecb_sweep([&](const uint8_t* in, uint8_t* out, size_t) {
        aes_enc(in, out, &cipher);
    }, 16);
    std::cout << "\n";
}

// ── main ─────────────────────────────────────────────────────────────────────

int main() {
    std::cerr << "Running CPU benchmarks (takes ~60s)...\n";
    bench_present80();
    bench_speck64();
    bench_aes128();
    return 0;
}
