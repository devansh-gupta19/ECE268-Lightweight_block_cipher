#include <iostream>
#include <iomanip>
#include <cstdint>
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

// SPECK-64/128 implementation
// ─── GPU constant memory ─────────────────────────────────────────────────────
// Round keys are read-only and shared across all threads.
// __constant__ memory is cached and broadcast to an entire warp for free.

__constant__ uint32_t d_round_keys[27];

// Circular Right Shift
__device__ __forceinline__
uint32_t d_rotr32(uint32_t x, int r) {
    return (x >> r) | (x << (32 - r));
}

// Circular Left Shift
__device__ __forceinline__
uint32_t d_rotl32(uint32_t x, int r) {
    return (x << r) | (x >> (32 - r));
}

// ─── Encrypt kernel ───────────────────────────────────────────────────────────

__global__
void encrypt_kernel(const uint64_t* __restrict__ plaintexts,
                          uint64_t* __restrict__ ciphertexts,
                    int n)
{
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx >= n) return;

    // Load 64-bit state
    uint64_t state = plaintexts[idx];
    
    // Split into 32-bit words (Left word = upper 32 bits, Right word = lower 32 bits)
    uint32_t y = (uint32_t)(state & 0xFFFFFFFF);
    uint32_t x = (uint32_t)(state >> 32);

    // 27 ARX Rounds
    #pragma unroll
    for (int r = 0; r < 27; ++r) {
        x = (d_rotr32(x, 8) + y) ^ d_round_keys[r];
        y = d_rotl32(y, 3) ^ x;
    }

    // Recombine and store
    ciphertexts[idx] = ((uint64_t)x << 32) | y;
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
    
    uint32_t y = (uint32_t)(state & 0xFFFFFFFF);
    uint32_t x = (uint32_t)(state >> 32);

    // Reverse 27 ARX Rounds
    #pragma unroll
    for (int r = 26; r >= 0; --r) {
        y = d_rotr32(y ^ x, 3);
        x = d_rotl32((x ^ d_round_keys[r]) - y, 8);
    }

    plaintexts[idx] = ((uint64_t)x << 32) | y;
}

// ─── CPU key schedule generation ──────────────────────────────────────────────

void generate_round_keys(const std::array<uint32_t, 4>& key,
                         uint32_t out_keys[27])
{
    uint32_t b = key[0];
    uint32_t a[3] = {key[1], key[2], key[3]}; 

    auto rotr32 = [](uint32_t v, int r) { return (v >> r) | (v << (32 - r)); };
    auto rotl32 = [](uint32_t v, int r) { return (v << r) | (v >> (32 - r)); };

    out_keys[0] = b;
    for (uint32_t i = 0; i < 26; ++i) {
        uint32_t& x = a[i % 3];
        uint32_t& y = b;
        
        x = (rotr32(x, 8) + y) ^ i;
        y = rotl32(y, 3) ^ x;
        
        out_keys[i + 1] = b;
    }
}

// ─── Main ─────────────────────────────────────────────────────────────────────

int main()
{
    const int    N_SWEEP   = 5;
    const int    N_TRIALS  = 5;
    const int    THREADS   = 256;

    // Payload sweep: 1 KB .. 64 MB, five trials per size (kernel time only)
    const size_t SWEEP_BYTES[5]  = {1024, 65536, 1048576, 16777216, 67108864};
    const char*  SWEEP_LABELS[5] = {"1KB","64KB","1MB","16MB","64MB"};
    const int    N_MAX     = (int)(SWEEP_BYTES[4] / 8);  // 8,388,608 blocks at 64 MB

    // ── GPU info block ────────────────────────────────────────────────────
    std::cout << "=== SPECK-64/128 gpu info ===\n";
    std::cout << "const_mem_round_keys_bytes: " << sizeof(d_round_keys) << "\n";
    std::cout << "const_mem_sbox_bytes: 0\n";
    std::cout << "const_mem_inv_sbox_bytes: 0\n";
    std::cout << "const_mem_total_bytes: " << sizeof(d_round_keys) << "\n";
    std::cout << "key_schedule_size_bytes: " << sizeof(d_round_keys) << "\n";
    std::cout << "n_trials_per_size: " << N_TRIALS << "\n";

    // ── Parameters ────────────────────────────────────────────────────────
    // Official NSA Test Vector Key for SPECK-64/128
    std::array<uint32_t, 4> key = {
        0x03020100, 0x0b0a0908, 0x13121110, 0x1b1a1918
    };
    // Official NSA Test Vector Plaintext (Left word in upper 32 bits)
    const uint64_t BASE_PLAINTEXT = 0x3b7265747475432dULL;

    // Host key expansion; round keys uploaded to __constant__ before launch
    uint32_t h_round_keys[27];
    generate_round_keys(key, h_round_keys);
    CUDA_CHECK(cudaMemcpyToSymbol(d_round_keys, h_round_keys, 27 * sizeof(uint32_t)));

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
    std::cout << "\n=== SPECK-64/128 gpu sweep ===\n";
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

        // Get results from the device and verify the correctness of encryption + decryption
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
