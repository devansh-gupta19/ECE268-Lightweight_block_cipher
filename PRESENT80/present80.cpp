#include <iostream>
#include <cstdint>
#include <bitset>
#include <array>
#include <iomanip>
#include <chrono>
#include <cmath>

class Present80 {
private:
    uint64_t round_keys[32];

    // PRESENT 4-bit S-Box and its inverse
    static const uint8_t SBOX[16];
    static const uint8_t INV_SBOX[16];

    void generate_round_keys(const std::array<uint8_t, 10>& key) {
        std::bitset<80> K;
        
        // Load 80-bit key: key[0] is MSB, key[9] is LSB
        for (int i = 0; i < 10; ++i) {
            for (int j = 0; j < 8; ++j) {
                K[79 - (i * 8 + (7 - j))] = (key[i] >> j) & 1;
            }
        }

        for (int round = 1; round <= 32; ++round) {
            // Extract 64-bit round key (Leftmost 64 bits: K[79..16])
            uint64_t rk = 0;
            for (int i = 0; i < 64; ++i) {
                if (K[16 + i]) rk |= (1ULL << i);
            }
            round_keys[round - 1] = rk;

            if (round == 32) break;

            // Key Update
            // a) Rotate left by 61
            K = (K << 61) | (K >> 19);

            // b) S-Box on the top nibble (K[79..76])
            uint8_t top_nibble = 0;
            for (int i = 0; i < 4; ++i) {
                if (K[76 + i]) top_nibble |= (1 << i);
            }
            top_nibble = SBOX[top_nibble];
            for (int i = 0; i < 4; ++i) {
                K[76 + i] = (top_nibble >> i) & 1;
            }

            // c) Add round_counter to K[19..15]
            uint8_t counter_bits = 0;
            for (int i = 0; i < 5; ++i) {
                if (K[15 + i]) counter_bits |= (1 << i);
            }
            counter_bits ^= round;
            for (int i = 0; i < 5; ++i) {
                K[15 + i] = (counter_bits >> i) & 1;
            }
        }
    }

public:
    Present80(const std::array<uint8_t, 10>& key) {
        generate_round_keys(key);
    }

    uint64_t encrypt(uint64_t plaintext) const {
        uint64_t state = plaintext;
        
        for (int round = 0; round < 31; ++round) {
            // 1. addRoundKey
            state ^= round_keys[round];

            // 2. sBoxLayer
            uint64_t sbox_state = 0;
            for (int j = 0; j < 16; ++j) {
                uint8_t nibble = (state >> (j * 4)) & 0xF;
                nibble = SBOX[nibble];
                sbox_state |= ((uint64_t)nibble << (j * 4));
            }
            state = sbox_state;

            // 3. pLayer
            uint64_t permuted = 0;
            for (int j = 0; j < 64; ++j) {
                if ((state >> j) & 1) {
                    int p = (j == 63) ? 63 : (j * 16) % 63;
                    permuted |= (1ULL << p);
                }
            }
            state = permuted;
        }
        
        // Final key addition
        state ^= round_keys[31];
        return state;
    }

    uint64_t decrypt(uint64_t ciphertext) const {
        uint64_t state = ciphertext;
        
        for (int round = 31; round >= 1; --round) {
            // 1. addRoundKey
            state ^= round_keys[round];
            
            // 2. inv_pLayer
            uint64_t permuted = 0;
            for (int j = 0; j < 64; ++j) {
                if ((state >> j) & 1) {
                    int p = (j == 63) ? 63 : (j * 4) % 63;
                    permuted |= (1ULL << p);
                }
            }
            state = permuted;

            // 3. inv_sBoxLayer
            uint64_t sbox_state = 0;
            for (int j = 0; j < 16; ++j) {
                uint8_t nibble = (state >> (j * 4)) & 0xF;
                nibble = INV_SBOX[nibble];
                sbox_state |= ((uint64_t)nibble << (j * 4));
            }
            state = sbox_state;
        }
        
        // Initial key addition
        state ^= round_keys[0];
        return state;
    }

    // Batch helpers used by the sweep
    void encrypt_batch(const uint64_t* plaintexts,
                       uint64_t*       ciphertexts,
                       int             n) const {
        for (int i = 0; i < n; ++i)
            ciphertexts[i] = encrypt(plaintexts[i]);
    }
 
    void decrypt_batch(const uint64_t* ciphertexts,
                       uint64_t*       plaintexts,
                       int             n) const {
        for (int i = 0; i < n; ++i)
            plaintexts[i] = decrypt(ciphertexts[i]);
    }
};

const uint8_t Present80::SBOX[16] = {
    0xC, 0x5, 0x6, 0xB, 0x9, 0x0, 0xA, 0xD, 
    0x3, 0xE, 0xF, 0x8, 0x4, 0x7, 0x1, 0x2
};

const uint8_t Present80::INV_SBOX[16] = {
    0x5, 0xE, 0xF, 0x8, 0xC, 0x1, 0x2, 0xD, 
    0xB, 0x4, 0x6, 0x3, 0x0, 0x7, 0x9, 0xA
};

// ─── Timing helpers ───────────────────────────────────────────────────────────
 
using Clock    = std::chrono::high_resolution_clock;
using DSeconds = std::chrono::duration<double>;          // seconds as double
using DMillis  = std::chrono::duration<double, std::milli>;
 
// Returns elapsed milliseconds between two time_points
static inline double elapsed_ms(Clock::time_point start, Clock::time_point end) {
    return DMillis(end - start).count();
}
 
// Computes mean and population stddev over an array of doubles
static void compute_stats(const double* v, int n, double& mean, double& stddev) {
    mean = 0.0;
    for (int i = 0; i < n; ++i) mean += v[i];
    mean /= n;
    double sq = 0.0;
    for (int i = 0; i < n; ++i) sq += (v[i] - mean) * (v[i] - mean);
    stddev = std::sqrt(sq / n);
}

// --- Official Test Vector Validation ---

struct TestVector { std::array<uint8_t,10> key; uint64_t pt; uint64_t expected_ct; };

static bool run_official_tests() {
    // PRESENT-80 test vectors from Bogdanov et al., CHES 2007, Appendix A
    TestVector tvs[] = {
        { {0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00}, 0x0000000000000000ULL, 0x5579C1387B228445ULL },
        { {0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF}, 0x0000000000000000ULL, 0xE72C46C0F5945049ULL },
        { {0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00}, 0xFFFFFFFFFFFFFFFFULL, 0xA112FFC72F68417BULL },
        { {0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF}, 0xFFFFFFFFFFFFFFFFULL, 0x3333DCD3213210D2ULL },
    };
    bool all_pass = true;
    std::cout << std::hex << std::uppercase << std::setfill('0');
    std::cout << "=== PRESENT-80 Official Test Vectors ===\n";
    for (int i = 0; i < 4; ++i) {
        Present80 c(tvs[i].key);
        uint64_t ct = c.encrypt(tvs[i].pt);
        uint64_t dec = c.decrypt(ct);
        bool ct_ok  = (ct  == tvs[i].expected_ct);
        bool dec_ok = (dec == tvs[i].pt);
        std::cout << "TV" << (i+1) << ": ct=" << std::setw(16) << ct
                  << "  expected=" << std::setw(16) << tvs[i].expected_ct
                  << "  " << (ct_ok && dec_ok ? "[PASS]" : "[FAIL]") << "\n";
        if (!ct_ok || !dec_ok) all_pass = false;
    }
    std::cout << (all_pass ? "[ALL OFFICIAL VECTORS PASS]\n" : "[OFFICIAL VECTOR FAILURE]\n");
    return all_pass;
}

// --- Execution & Verification ---

int main() {
    if (!run_official_tests()) return 1;
    std::cout << "\n";
    const int    N_SWEEP  = 5;
    const int    N_TRIALS = 5;
 
    // Mirror exactly the same sweep sizes as the CUDA benchmark
    const size_t SWEEP_BYTES[5]  = {1024, 65536, 1048576, 16777216, 67108864};
    const char*  SWEEP_LABELS[5] = {"1KB", "64KB", "1MB", "16MB", "64MB"};
    const int    N_MAX = (int)(SWEEP_BYTES[4] / 8);   // 8,388,608 blocks (64 MB)
 
    // ── CPU info block (mirrors gpu info block in the CUDA file) ──────────
    std::cout << "\n=== PRESENT-80 cpu info ===\n";
    std::cout << std::dec;
    std::cout << "round_keys_bytes:  " << (32 * sizeof(uint64_t)) << "\n";
    std::cout << "sbox_bytes:        " << 16 << "\n";
    std::cout << "inv_sbox_bytes:    " << 16 << "\n";
    std::cout << "n_trials_per_size: " << N_TRIALS << "\n";
 
    // ── 2. Key + cipher instance (key schedule is a one-time setup cost,
    //       excluded from all timed regions just as in the CUDA version) ───
    std::array<uint8_t, 10> key = {
        0x01, 0x23, 0x45, 0x67, 0x89, 0xAB, 0xCD, 0xEF, 0x01, 0x23
    };
    const uint64_t BASE_PLAINTEXT = 0x0000000000000110ULL;
    Present80 cipher(key);
 
    // ── 3. Allocate buffers at N_MAX (reused for all sweep sizes) ─────────
    uint64_t* h_plain     = new uint64_t[N_MAX];
    uint64_t* h_cipher    = new uint64_t[N_MAX];
    uint64_t* h_decrypted = new uint64_t[N_MAX];
    for (int i = 0; i < N_MAX; ++i)
        h_plain[i] = BASE_PLAINTEXT + (uint64_t)i;
 
    // ── 4. CPU sweep: 5 sizes × 5 trials each ─────────────────────────────
    std::cout << std::fixed << std::setprecision(4);
    std::cout << "\n=== PRESENT-80 cpu sweep ===\n";
 
    for (int s = 0; s < N_SWEEP; s++) {
        int n = (int)(SWEEP_BYTES[s] / 8);
 
        std::cout << "\n=== cpu_sweep[" << SWEEP_LABELS[s] << "] size: " << n << " blocks ===\n";
 
        // Run the batch 100× for inputs smaller than 1 MB to dilute the
        // overhead of clock_gettime and OS scheduling jitter, then divide.
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
 
        // ── Correctness check for this size (all blocks, last trial) ─────
        bool all_ok = true;
        for (int i = 0; i < n; ++i) {
            if (h_decrypted[i] != h_plain[i]) {
                std::cerr << std::dec << "[ERROR] Block " << i
                          << " mismatch at size " << SWEEP_LABELS[s] << "!\n";
                all_ok = false;
                break;
            }
        }
        if (all_ok)
            std::cout << std::dec << "[SUCCESS] All " << n << " blocks verified.\n";
 
        // ── Stats + print ───────────────
        double enc_mean, enc_std, dec_mean, dec_std;
        compute_stats(enc_ms_v, N_TRIALS, enc_mean, enc_std);
        compute_stats(dec_ms_v, N_TRIALS, dec_mean, dec_std);
 
        double bytes_d    = (double)n * 8.0;
        double enc_gbps_s = bytes_d / (enc_mean * 1e-3) / 1e9;
        double dec_gbps_s = bytes_d / (dec_mean * 1e-3) / 1e9;
 
        std::cout << std::fixed << std::setprecision(4);
        std::cout << "encryption_ms_mean:   " << enc_mean   << "\n";
        std::cout << "encryption_ms_stddev: " << enc_std    << "\n";
        std::cout << "encryption_GBps:      " << enc_gbps_s << "\n";
        std::cout << "decryption_ms_mean:   " << dec_mean   << "\n";
        std::cout << "decryption_ms_stddev: " << dec_std    << "\n";
        std::cout << "decryption_GBps:      " << dec_gbps_s << "\n";
        std::cout << "\n";
    }
 
    // ── 5. Cleanup ────────────────────────────────────────────────────────
    delete[] h_plain;
    delete[] h_cipher;
    delete[] h_decrypted;

    return 0;
}