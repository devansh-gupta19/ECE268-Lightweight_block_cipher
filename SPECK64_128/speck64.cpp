#include <iostream>
#include <cstdint>
#include <iomanip>
#include <chrono>
#include <cmath>
#include "speck64.h"

// Timing helpers
 
using Clock   = std::chrono::high_resolution_clock;
using DMillis = std::chrono::duration<double, std::milli>;
 
static inline double elapsed_ms(Clock::time_point start, Clock::time_point end) {
    return DMillis(end - start).count();
}
 
static void compute_stats(const double* v, int n, double& mean, double& stddev) {
    mean = 0.0;
    for (int i = 0; i < n; ++i) mean += v[i];
    mean /= n;
    double sq = 0.0;
    for (int i = 0; i < n; ++i) sq += (v[i] - mean) * (v[i] - mean);
    stddev = std::sqrt(sq / n);
}

// ─── Official test vectors ────────────────────────────────────────────────────
static bool run_official_tests() {
    // NSA test vector for SPECK-64/128 (from the original SIMON/SPECK paper, 2013)
    //   Key:        1b1a1918 13121110 0b0a0908 03020100
    //   Plaintext:  3b726574 7475432d  (left=3b726574, right=7475432d)
    //   Ciphertext: 8c6fa548 454e028b  (left=8c6fa548, right=454e028b)
    struct TV {
        uint32_t key[4];
        uint32_t pt[2];    // [0]=right, [1]=left
        uint32_t exp_ct[2];
    };

    TV tvs[] = {
        {
            {0x03020100, 0x0b0a0908, 0x13121110, 0x1b1a1918},
            {0x7475432d, 0x3b726574},
            {0x454e028b, 0x8c6fa548}
        }
    };

    std::cout << std::hex << std::uppercase << std::setfill('0');
    std::cout << "=== SPECK-64/128 Official Test Vectors ===\n";

    bool all_pass = true;
    for (int i = 0; i < 1; ++i) {
        Speck64_128 cipher;
        cipher.expandKey(tvs[i].key);
 
        uint32_t ct[2]  = {0, 0};
        uint32_t dec[2] = {0, 0};
        cipher.encrypt(tvs[i].pt, ct);
        cipher.decrypt(ct, dec);
 
        bool ct_ok  = (ct[0]  == tvs[i].exp_ct[0] && ct[1]  == tvs[i].exp_ct[1]);
        bool dec_ok = (dec[0] == tvs[i].pt[0]      && dec[1] == tvs[i].pt[1]);
 
        std::cout << "TV" << (i + 1)
                  << ": ct="       << std::setw(8) << ct[1]            << " " << std::setw(8) << ct[0]
                  << "  expected=" << std::setw(8) << tvs[i].exp_ct[1] << " " << std::setw(8) << tvs[i].exp_ct[0]
                  << "  " << (ct_ok && dec_ok ? "[PASS]" : "[FAIL]") << "\n";
 
        if (!ct_ok || !dec_ok) all_pass = false;
    }
 
    std::cout << (all_pass ? "[ALL OFFICIAL VECTORS PASS]\n" : "[OFFICIAL VECTOR FAILURE]\n");
    return all_pass;
}

// --- Test Implementation ---
int main() {
    // ── 1. Known-answer correctness check — abort if cipher is broken ─────
    if (!run_official_tests()) return 1;

    const int N_SWEEP  = 5;
    const int N_TRIALS = 5;

    // Same five sweep sizes as speck64_ecb.cu / speck64_ctr.cu (8 bytes per block)
    const size_t SWEEP_BYTES[5]  = {1024, 65536, 1048576, 16777216, 67108864};
    const char*  SWEEP_LABELS[5] = {"1KB", "64KB", "1MB", "16MB", "64MB"};
    const int    N_MAX = (int)(SWEEP_BYTES[4] / 8);  // 8,388,608 blocks (64 MB)

    // ── CPU info block ────────────────────────────────────────────────────
    std::cout << std::dec;
    std::cout << "\n=== SPECK-64/128 cpu info ===\n";
    std::cout << "block_size_bytes:  8\n";
    std::cout << "key_size_bytes:    16\n";
    std::cout << "rounds:            " << Speck64_128::ROUNDS << "\n";
    std::cout << "round_keys_bytes:  " << (Speck64_128::ROUNDS * sizeof(uint32_t)) << "\n";
    std::cout << "n_trials_per_size: " << N_TRIALS << "\n";

    // ── 2. Key expansion (one-time; excluded from all timed regions) ──────
    // Key: 1b1a1918 13121110 0b0a0908 03020100  (same as the NSA test vector)
    const uint32_t KEY[4] = {0x03020100, 0x0b0a0908, 0x13121110, 0x1b1a1918};
    Speck64_128 cipher;
    cipher.expandKey(KEY);

    // ── 3. Allocate buffers at N_MAX (reused across all sweep sizes) ──────
    // Layout: block i occupies words [2i] (right) and [2i+1] (left).
    // Plaintext is initialized with a simple counter so every block is distinct.
    uint32_t* h_plain     = new uint32_t[N_MAX * 2];
    uint32_t* h_cipher    = new uint32_t[N_MAX * 2];
    uint32_t* h_decrypted = new uint32_t[N_MAX * 2];

    for (int i = 0; i < N_MAX; ++i) {
        h_plain[i * 2]     = (uint32_t)(0x7475432d + i);  // right word (increments)
        h_plain[i * 2 + 1] = 0x3b726574;                   // left word (constant)
    }

    // ── 4. Sweep: 5 sizes × 5 trials each ────────────────────────────────
    std::cout << std::fixed << std::setprecision(4);
    std::cout << "\n=== SPECK-64/128 cpu sweep ===\n";

    for (int s = 0; s < N_SWEEP; s++) {
        int n = (int)(SWEEP_BYTES[s] / 8);  // number of 8-byte blocks

        std::cout << "\n=== cpu_sweep[" << SWEEP_LABELS[s] << "] size: " << n << " blocks ===\n";

        // Run the batch multiple times for small sizes to amortise clock resolution
        // and OS scheduling jitter — same strategy as the CUDA sweep.
        int iters = (SWEEP_BYTES[s] < 1024 * 1024) ? 100 : 1;

        double enc_ms_v[N_TRIALS], dec_ms_v[N_TRIALS];

        for (int tr = 0; tr < N_TRIALS; tr++) {
            // Encrypt
            auto enc_start = Clock::now();
            for (int it = 0; it < iters; it++)
                cipher.encrypt_batch(h_plain, h_cipher, n);
            auto enc_end = Clock::now();
            enc_ms_v[tr] = elapsed_ms(enc_start, enc_end) / iters;

            // Decrypt (feeds from the last encrypt's output)
            auto dec_start = Clock::now();
            for (int it = 0; it < iters; it++)
                cipher.decrypt_batch(h_cipher, h_decrypted, n);
            auto dec_end = Clock::now();
            dec_ms_v[tr] = elapsed_ms(dec_start, dec_end) / iters;
        }

        // ── Correctness: verify all n blocks round-trip (last trial's output) ─
        bool all_ok = true;
        for (int i = 0; i < n; ++i) {
            if (h_decrypted[i * 2]     != h_plain[i * 2] ||
                h_decrypted[i * 2 + 1] != h_plain[i * 2 + 1]) {
                std::cerr << std::dec << "[ERROR] Block " << i
                            << " mismatch at size " << SWEEP_LABELS[s] << "!\n";
                all_ok = false;
                break;
            }
        }
        if (all_ok)
            std::cout << std::dec << "[SUCCESS] All " << n << " blocks verified.\n";

        // ── Stats (mean + population stddev over N_TRIALS) ────────────────
        double enc_mean, enc_std, dec_mean, dec_std;
        compute_stats(enc_ms_v, N_TRIALS, enc_mean, enc_std);
        compute_stats(dec_ms_v, N_TRIALS, dec_mean, dec_std);

        // Throughput: bytes processed ÷ wall-clock seconds
        // Each block is 8 bytes; same formula used in the PRESENT-80 and CUDA benchmarks.
        double bytes_d    = (double)n * 8.0;
        double enc_mbps_s = bytes_d / (enc_mean * 1e-3) / 1e6;
        double dec_mbps_s = bytes_d / (dec_mean * 1e-3) / 1e6;

        // Field names match the PRESENT-80 CPU sweep output for easy side-by-side plotting
        std::cout << std::fixed << std::setprecision(4);
        std::cout << "encryption_ms_mean:   " << enc_mean   << "\n";
        std::cout << "encryption_ms_stddev: " << enc_std    << "\n";
        std::cout << "encryption_MBps:      " << enc_mbps_s << "\n";
        std::cout << "decryption_ms_mean:   " << dec_mean   << "\n";
        std::cout << "decryption_ms_stddev: " << dec_std    << "\n";
        std::cout << "decryption_MBps:      " << dec_mbps_s << "\n";
        std::cout << "\n";
    }

    // ── 5. Cleanup ────────────────────────────────────────────────────────
    delete[] h_plain;
    delete[] h_cipher;
    delete[] h_decrypted;

    return 0;
}