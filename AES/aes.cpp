#include <cstdint>
#include <cstring>
#include <iostream>
#include <iomanip>
#include <chrono>
#include <vector>
#include <cmath>
#include "aes128.h"

// ─── Timing & Math Helpers ────────────────────────────────────────────────────

using Clock    = std::chrono::high_resolution_clock;
using DMillis  = std::chrono::duration<double, std::milli>;

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

// Batch Execution Helpers
static void encrypt_batch(const AES128& cipher, const uint8_t* in, uint8_t* out, int num_blocks) {
    for (int i = 0; i < num_blocks; i++) {
        cipher.encrypt(in + (i * 16), out + (i * 16));
    }
}

static void decrypt_batch(const AES128& cipher, const uint8_t* in, uint8_t* out, int num_blocks) {
    for (int i = 0; i < num_blocks; i++) {
        cipher.decrypt(in + (i * 16), out + (i * 16));
    }
}

// Test vectors (NIST FIPS 197)
static bool run_test_vectors() {
    struct TV { uint8_t key[16]; uint8_t pt[16]; uint8_t expected_ct[16]; };

    // FIPS-197 Appendix B
    TV tvB = {
        {0x2b,0x7e,0x15,0x16,0x28,0xae,0xd2,0xa6,0xab,0xf7,0x15,0x88,0x09,0xcf,0x4f,0x3c},
        {0x32,0x43,0xf6,0xa8,0x88,0x5a,0x30,0x8d,0x31,0x31,0x98,0xa2,0xe0,0x37,0x07,0x34},
        {0x39,0x25,0x84,0x1d,0x02,0xdc,0x09,0xfb,0xdc,0x11,0x85,0x97,0x19,0x6a,0x0b,0x32}
    };
    // FIPS-197 Appendix C
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

// Main Execution
int main() {
    // ---- Test vectors first ----
    if (!run_test_vectors()) {
        std::cerr << "ERROR: AES test vector failure\n";
        return 1;
    }

    std::cout << "\n";
    const int    N_SWEEP  = 5;
    const int    N_TRIALS = 5;

    // Sweep sizes
    const size_t SWEEP_BYTES[5]  = {1024, 65536, 1048576, 16777216, 67108864};
    const char* SWEEP_LABELS[5] = {"1KB", "64KB", "1MB", "16MB", "64MB"};
    const size_t MAX_BYTES = SWEEP_BYTES[4]; 

    std::cout << "=== AES-128 cpu info ===\n";
    std::cout << std::dec;
    std::cout << "block_bytes:       16\n";
    std::cout << "key_bytes:         16\n";
    std::cout << "n_trials_per_size: " << N_TRIALS << "\n";

    // Setup key and cipher
    uint8_t key[16] = {
        0x00,0x11,0x22,0x33,0x44,0x55,0x66,0x77,
        0x88,0x99,0xaa,0xbb,0xcc,0xdd,0xee,0xff
    };
    AES128 cipher(key);

    // Allocate buffers 
    std::vector<uint8_t> h_plain(MAX_BYTES);
    std::vector<uint8_t> h_cipher(MAX_BYTES);
    std::vector<uint8_t> h_decrypted(MAX_BYTES);

    // fill plaintext with a deterministic byte ramp (0,1,2,...)
    for (size_t i = 0; i < MAX_BYTES; ++i) {
        h_plain[i] = (uint8_t)(i & 0xFF);
    }

    std::cout << std::fixed << std::setprecision(4);
    std::cout << "\n=== AES-128 cpu sweep ===\n";

    for (int s = 0; s < N_SWEEP; s++) {
        int num_blocks = (int)(SWEEP_BYTES[s] / 16);

        std::cout << "\n=== cpu_sweep[" << SWEEP_LABELS[s] << "] size: " << num_blocks << " blocks ===\n";

        // Iteration scaling for smaller inputs to avoid clock precision issues
        int iters = (SWEEP_BYTES[s] < 1024 * 1024) ? 100 : 1;

        double enc_ms_v[N_TRIALS], dec_ms_v[N_TRIALS];

        for (int tr = 0; tr < N_TRIALS; tr++) {
            // Encrypt
            auto enc_start = Clock::now();
            for (int it = 0; it < iters; it++) {
                encrypt_batch(cipher, h_plain.data(), h_cipher.data(), num_blocks);
            }
            auto enc_end = Clock::now();
            enc_ms_v[tr] = elapsed_ms(enc_start, enc_end) / iters;

            // Decrypt
            auto dec_start = Clock::now();
            for (int it = 0; it < iters; it++) {
                decrypt_batch(cipher, h_cipher.data(), h_decrypted.data(), num_blocks);
            }
            auto dec_end = Clock::now();
            dec_ms_v[tr] = elapsed_ms(dec_start, dec_end) / iters;
        }

        // Correctness check for this sweep size
        bool all_ok = true;
        if (std::memcmp(h_plain.data(), h_decrypted.data(), SWEEP_BYTES[s]) != 0) {
            std::cerr << "[ERROR] Mismatch at size " << SWEEP_LABELS[s] << "!\n";
            all_ok = false;
        }
        
        if (all_ok) {
            std::cout << "[SUCCESS] All " << num_blocks << " blocks verified.\n";
        }

        // Calculate and output stats
        double enc_mean, enc_std, dec_mean, dec_std;
        compute_stats(enc_ms_v, N_TRIALS, enc_mean, enc_std);
        compute_stats(dec_ms_v, N_TRIALS, dec_mean, dec_std);

        double bytes_d    = (double)(SWEEP_BYTES[s]);
        double enc_mbps_s = bytes_d / (enc_mean * 1e-3) / 1e6;
        double dec_mbps_s = bytes_d / (dec_mean * 1e-3) / 1e6;

        std::cout << "encryption_ms_mean:   " << enc_mean   << "\n";
        std::cout << "encryption_ms_stddev: " << enc_std    << "\n";
        std::cout << "encryption_MBps:      " << enc_mbps_s << "\n";
        std::cout << "decryption_ms_mean:   " << dec_mean   << "\n";
        std::cout << "decryption_ms_stddev: " << dec_std    << "\n";
        std::cout << "decryption_MBps:      " << dec_mbps_s << "\n";
    }

    return 0;
}
