#include <iostream>
#include <iomanip>
#include <cstdint>
#include <bitset>
#include <array>
#include <cassert>
#include <cuda_runtime.h>

// CUDA error checking macro
#define CUDA_CHECK(call)                                                    \
    do {                                                                    \
        cudaError_t _e = (call);                                            \
        if (_e != cudaSuccess) {                                            \
            std::cerr << "CUDA error at " << __FILE__ << ":" << __LINE__   \
                      << "  " << cudaGetErrorString(_e) << "\n";           \
            std::exit(1);                                                   \
        }                                                                   \
    } while (0)

// PRESENT-80 implementation
// ─── GPU constant memory ─────────────────────────────────────────────────────
// Round keys and S-boxes are read-only and shared across all threads.
// __constant__ memory is cached and broadcast to an entire warp for free.

__constant__ uint64_t d_round_keys[32];

__constant__ uint8_t d_SBOX[16] = {
    0xC, 0x5, 0x6, 0xB, 0x9, 0x0, 0xA, 0xD,
    0x3, 0xE, 0xF, 0x8, 0x4, 0x7, 0x1, 0x2
};

__constant__ uint8_t d_INV_SBOX[16] = {
    0x5, 0xE, 0xF, 0x8, 0xC, 0x1, 0x2, 0xD,
    0xB, 0x4, 0x6, 0x3, 0x0, 0x7, 0x9, 0xA
};

// P-layer: bit j goes to position (j*16) % 63; bit 63 stays at 63.
__device__ __forceinline__
uint64_t d_p_layer(uint64_t state) {
    uint64_t result = 0;
    #pragma unroll
    for (int j = 0; j < 63; ++j) {
        if ((state >> j) & 1)
            result |= (1ULL << ((j * 16) % 63));
    }
    if ((state >> 63) & 1)
        result |= (1ULL << 63);
    return result;
}

// Inverse P-layer: bit j goes to position (j*4) % 63; bit 63 stays at 63.
__device__ __forceinline__
uint64_t d_inv_p_layer(uint64_t state) {
    uint64_t result = 0;
    #pragma unroll
    for (int j = 0; j < 63; ++j) {
        if ((state >> j) & 1)
            result |= (1ULL << ((j * 4) % 63));
    }
    if ((state >> 63) & 1)
        result |= (1ULL << 63);
    return result;
}

// S-box layer: applies a 4-bit S-box to each of the 16 nibbles of the 64-bit state.
__device__ __forceinline__
uint64_t d_sbox_layer(uint64_t state, const uint8_t* sbox) {
    uint64_t result = 0;
    
    #pragma unroll
    for (int i = 0; i < 16; ++i) {
        // Extract the i-th 4-bit nibble
        uint8_t nibble = (state >> (i * 4)) & 0xF;
        // Apply S-box and shift it back into the correct position
        result |= ((uint64_t)sbox[nibble] << (i * 4));
    }
    
    return result;
}

__global__
void encrypt_kernel(const uint64_t* __restrict__ plaintexts,
                          uint64_t* __restrict__ ciphertexts,
                    int n)
{
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx >= n) return;

    uint64_t state = plaintexts[idx];

    // 31 full rounds: addRoundKey → sBoxLayer → pLayer
    #pragma unroll
    for (int r = 0; r < 31; ++r) {
        state ^= d_round_keys[r];
        state  = d_sbox_layer(state, d_SBOX);
        state  = d_p_layer(state);
    }

    // Final key addition (no S-box or P-layer)
    state ^= d_round_keys[31];

    ciphertexts[idx] = state;
}

// ─── Decrypt kernel ───────────────────────────────────────────────────────────

__global__
void decrypt_kernel(const uint64_t* __restrict__ ciphertexts,
                          uint64_t* __restrict__ plaintexts,
                    int n)
{
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx >= n) return;

    uint64_t state = ciphertexts[idx];

    // Reverse 31 rounds: addRoundKey → inv_pLayer → inv_sBoxLayer
    #pragma unroll
    for (int r = 31; r >= 1; --r) {
        state ^= d_round_keys[r];
        state  = d_inv_p_layer(state);
        state  = d_sbox_layer(state, d_INV_SBOX);
    }

    // Final (initial) key addition
    state ^= d_round_keys[0];

    plaintexts[idx] = state;
}

// CPU key schedule generation

static const uint8_t HOST_SBOX[16] = {
    0xC, 0x5, 0x6, 0xB, 0x9, 0x0, 0xA, 0xD,
    0x3, 0xE, 0xF, 0x8, 0x4, 0x7, 0x1, 0x2
};

void generate_round_keys(const std::array<uint8_t, 10>& key,
                         uint64_t out_keys[32])
{
    std::bitset<80> K;

    // Load 80-bit key: key[0] is MSB, key[9] is LSB
    for (int i = 0; i < 10; ++i)
        for (int j = 0; j < 8; ++j)
            K[79 - (i * 8 + (7 - j))] = (key[i] >> j) & 1;

    for (int round = 1; round <= 32; ++round) {
        // Extract leftmost 64 bits as round key
        uint64_t rk = 0;
        for (int i = 0; i < 64; ++i)
            if (K[16 + i]) rk |= (1ULL << i);
        out_keys[round - 1] = rk;

        if (round == 32) break;

        // a) Rotate left by 61
        K = (K << 61) | (K >> 19);

        // b) S-Box on top nibble K[79:76]
        uint8_t top = 0;
        for (int i = 0; i < 4; ++i)
            if (K[76 + i]) top |= (1 << i);
        top = HOST_SBOX[top];
        for (int i = 0; i < 4; ++i)
            K[76 + i] = (top >> i) & 1;

        // c) XOR round counter into K[19:15]
        uint8_t ctr = 0;
        for (int i = 0; i < 5; ++i)
            if (K[15 + i]) ctr |= (1 << i);
        ctr ^= round;
        for (int i = 0; i < 5; ++i)
            K[15 + i] = (ctr >> i) & 1;
    }
}

// ─── Main ─────────────────────────────────────────────────────────────────────

int main()
{
    const int    N_SWEEP   = 5;
    const int    N_TRIALS  = 5;
    const int    THREADS   = 256;

    const size_t SWEEP_BYTES[5]  = {1024, 65536, 1048576, 16777216, 67108864};
    const char*  SWEEP_LABELS[5] = {"1KB","64KB","1MB","16MB","64MB"};
    const int    N_MAX     = (int)(SWEEP_BYTES[4] / 8);  // 8,388,608 blocks (64 MB)

    // ── GPU info block ────────────────────────────────────────────────────
    std::cout << "=== PRESENT-80 gpu info ===\n";
    std::cout << "const_mem_round_keys_bytes: " << sizeof(d_round_keys) << "\n";
    std::cout << "const_mem_sbox_bytes: " << sizeof(d_SBOX) << "\n";
    std::cout << "const_mem_inv_sbox_bytes: " << sizeof(d_INV_SBOX) << "\n";
    std::cout << "const_mem_total_bytes: " << (sizeof(d_round_keys) + sizeof(d_SBOX) + sizeof(d_INV_SBOX)) << "\n";
    std::cout << "key_schedule_size_bytes: " << sizeof(d_round_keys) << "\n";
    std::cout << "n_trials_per_size: " << N_TRIALS << "\n";

    // ── Parameters ────────────────────────────────────────────────────────
    std::array<uint8_t, 10> key = {
        0x01, 0x23, 0x45, 0x67, 0x89, 0xAB, 0xCD, 0xEF, 0x01, 0x23
    };
    const uint64_t BASE_PLAINTEXT = 0x0000000000000110ULL;

    // ── 1. Key schedule on CPU → upload to GPU constant memory ────────────
    uint64_t h_round_keys[32];
    generate_round_keys(key, h_round_keys);
    CUDA_CHECK(cudaMemcpyToSymbol(d_round_keys, h_round_keys, 32 * sizeof(uint64_t)));

    // ── 2. Allocate host + device buffers at N_MAX (reused for all sizes) ─
    uint64_t* h_plain     = new uint64_t[N_MAX];
    uint64_t* h_cipher    = new uint64_t[N_MAX];
    uint64_t* h_decrypted = new uint64_t[N_MAX];
    for (int i = 0; i < N_MAX; ++i)
        h_plain[i] = BASE_PLAINTEXT + (uint64_t)i;

    uint64_t *d_plain, *d_cipher, *d_decrypted;
    CUDA_CHECK(cudaMalloc(&d_plain,     N_MAX * sizeof(uint64_t)));
    CUDA_CHECK(cudaMalloc(&d_cipher,    N_MAX * sizeof(uint64_t)));
    CUDA_CHECK(cudaMalloc(&d_decrypted, N_MAX * sizeof(uint64_t)));
    CUDA_CHECK(cudaMemcpy(d_plain, h_plain, N_MAX * sizeof(uint64_t), cudaMemcpyHostToDevice));

    cudaEvent_t t_start, t_end;
    CUDA_CHECK(cudaEventCreate(&t_start));
    CUDA_CHECK(cudaEventCreate(&t_end));

    // ── 3. Warmup: one full N_MAX encrypt ─────────────────────────────────
    int blocks_max = (N_MAX + THREADS - 1) / THREADS;
    encrypt_kernel<<<blocks_max, THREADS>>>(d_plain, d_cipher, N_MAX);
    CUDA_CHECK(cudaDeviceSynchronize());

    // ── 4. GPU sweep: 5 sizes × 5 trials each ─────────────────────────────
    std::cout << "\n=== PRESENT-80 GPU sweep ===\n";
    std::cout << std::fixed << std::setprecision(4);

    // inline stats helper (mean + population stddev over float vector)
    auto compute_stats = [](const float* v, int n, double& mean, double& stddev) {
        mean = 0;
        for (int i = 0; i < n; i++) mean += v[i];
        mean /= n;
        double sq = 0;
        for (int i = 0; i < n; i++) sq += ((double)v[i] - mean) * ((double)v[i] - mean);
        stddev = std::sqrt(sq / n);
    };

    for (int s = 0; s < N_SWEEP; s++) {
        int n    = (int)(SWEEP_BYTES[s] / 8);
        int blks = (n + THREADS - 1) / THREADS;
        float enc_ms_v[N_TRIALS], dec_ms_v[N_TRIALS];
        float temp_ms;

        std::cout << "\n=== gpu_sweep[" << SWEEP_LABELS[s] << "] size: " << n << " blocks ===\n";

        // Run more iterations for smaller payloads to drown out driver latency
        int iters = (n * 8 < 1024 * 1024) ? 100 : 1;
        for (int tr = 0; tr < N_TRIALS; tr++) {
            CUDA_CHECK(cudaEventRecord(t_start));
            for (int it = 0; it < iters; it++) {
                encrypt_kernel<<<blks, THREADS>>>(d_plain, d_cipher, n);
            }
            CUDA_CHECK(cudaEventRecord(t_end));
            CUDA_CHECK(cudaGetLastError());
            CUDA_CHECK(cudaEventSynchronize(t_end));
            CUDA_CHECK(cudaEventElapsedTime(&temp_ms, t_start, t_end));
            enc_ms_v[tr] = temp_ms / iters;  // Average per iteration

            CUDA_CHECK(cudaEventRecord(t_start));
            for (int it = 0; it < iters; it++) {
                decrypt_kernel<<<blks, THREADS>>>(d_cipher, d_decrypted, n);
            }
            CUDA_CHECK(cudaEventRecord(t_end));
            CUDA_CHECK(cudaGetLastError());
            CUDA_CHECK(cudaEventSynchronize(t_end));
            CUDA_CHECK(cudaEventElapsedTime(&temp_ms, t_start, t_end));
            dec_ms_v[tr] = temp_ms / iters;  // Average per iteration
        }

        // Get results from the device and verift the correctness of encryption + decryption
        CUDA_CHECK(cudaMemcpy(h_cipher,    d_cipher,    n * sizeof(uint64_t), cudaMemcpyDeviceToHost));
        CUDA_CHECK(cudaMemcpy(h_decrypted, d_decrypted, n * sizeof(uint64_t), cudaMemcpyDeviceToHost));
        bool all_ok = true;
        for (int i = 0; i < n; ++i) {
            if (h_decrypted[i] != h_plain[i]) {
                std::cerr << std::dec << "[ERROR] Block " << i << " mismatch!\n";
                all_ok = false;
                break;
            }
        }
        if (all_ok)
            std::cout << std::dec << "[SUCCESS] All " << n << " blocks verified.\n";

        double enc_mean, enc_std, dec_mean, dec_std;
        compute_stats(enc_ms_v, N_TRIALS, enc_mean, enc_std);
        compute_stats(dec_ms_v, N_TRIALS, dec_mean, dec_std);

        double bytes_d    = (double)n * 8.0;
        double enc_mbps_s = bytes_d / (enc_mean * 1e-3) / 1e6;
        double dec_mbps_s = bytes_d / (dec_mean * 1e-3) / 1e6;


        std::cout << "encryption_ms_mean:   "      << enc_mean   << "\n";
        std::cout << "encryption_ms_stddev: "      << enc_std    << "\n";
        std::cout << "encryption_MBps:      "      << enc_mbps_s << "\n";
        std::cout << "decryption_ms_mean:   "      << dec_mean   << "\n";
        std::cout << "decryption_ms_stddev: "      << dec_std    << "\n";
        std::cout << "decryption_MBps:      "      << dec_mbps_s << "\n";

        // Add an extra blank line to separate sizes in terminal output
        std::cout << "\n";
    }

    // Cleanup
    delete[] h_plain;
    delete[] h_cipher;
    delete[] h_decrypted;
    CUDA_CHECK(cudaFree(d_plain));
    CUDA_CHECK(cudaFree(d_cipher));
    CUDA_CHECK(cudaFree(d_decrypted));
    CUDA_CHECK(cudaEventDestroy(t_start));
    CUDA_CHECK(cudaEventDestroy(t_end));

    return 0;
}
