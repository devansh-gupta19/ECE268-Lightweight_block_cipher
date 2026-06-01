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
    // ── GPU info block ────────────────────────────────────────────────────
    std::cout << "=== SPECK-64/128 gpu info ===\n";
    std::cout << "const_mem_round_keys_bytes: 108\n";
    std::cout << "const_mem_sbox_bytes: 0\n";
    std::cout << "const_mem_inv_sbox_bytes: 0\n";
    std::cout << "const_mem_total_bytes: 108\n";
    std::cout << "key_schedule_location: host_precomputed\n";
    std::cout << "key_schedule_upload: cudaMemcpyToSymbol\n";
    std::cout << "key_schedule_size_bytes: 108\n";
    std::cout << "n_trials_per_size: 5\n";

    // ── Parameters ────────────────────────────────────────────────────────
    // Official NSA Test Vector Key for SPECK-64/128
    std::array<uint32_t, 4> key = {
        0x03020100, 0x0b0a0908, 0x13121110, 0x1b1a1918
    };
    // Official NSA Test Vector Plaintext (Left word in upper 32 bits)
    const uint64_t BASE_PLAINTEXT = 0x3b7265747475432dULL;

    const int    N_SWEEP   = 5;
    const size_t SWEEP_BYTES[5]  = {1024, 65536, 1048576, 16777216, 67108864};
    const char*  SWEEP_LABELS[5] = {"1KB","64KB","1MB","16MB","64MB"};
    const int    N_MAX     = (int)(SWEEP_BYTES[4] / 8);  // 8,388,608 blocks (64 MB)
    const int    N_TRIALS  = 5;
    const int    THREADS   = 256;

    // ── 1. Key schedule on CPU → upload to GPU constant memory ────────────
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

    // ── 4. Verification at N_MAX ──────────────────────────────────────────
    CUDA_CHECK(cudaEventRecord(t_start));
    encrypt_kernel<<<blocks_max, THREADS>>>(d_plain, d_cipher, N_MAX);
    CUDA_CHECK(cudaEventRecord(t_end));
    CUDA_CHECK(cudaGetLastError());
    CUDA_CHECK(cudaEventSynchronize(t_end));
    float enc_ms_full = 0;
    CUDA_CHECK(cudaEventElapsedTime(&enc_ms_full, t_start, t_end));

    CUDA_CHECK(cudaEventRecord(t_start));
    decrypt_kernel<<<blocks_max, THREADS>>>(d_cipher, d_decrypted, N_MAX);
    CUDA_CHECK(cudaEventRecord(t_end));
    CUDA_CHECK(cudaGetLastError());
    CUDA_CHECK(cudaEventSynchronize(t_end));
    float dec_ms_full = 0;
    CUDA_CHECK(cudaEventElapsedTime(&dec_ms_full, t_start, t_end));

    CUDA_CHECK(cudaMemcpy(h_cipher,    d_cipher,    N_MAX * sizeof(uint64_t), cudaMemcpyDeviceToHost));
    CUDA_CHECK(cudaMemcpy(h_decrypted, d_decrypted, N_MAX * sizeof(uint64_t), cudaMemcpyDeviceToHost));

    std::cout << std::hex << std::uppercase << std::setfill('0');
    std::cout << "Plaintext  : 0x" << std::setw(16) << h_plain[0]     << "\n";
    std::cout << "Ciphertext : 0x" << std::setw(16) << h_cipher[0]    << "\n";
    std::cout << "Decrypted  : 0x" << std::setw(16) << h_decrypted[0] << "\n";

    // NSA reference vector check (first block only)
    if (h_cipher[0] == 0x8C6FA548454E028BULL && h_plain[0] == h_decrypted[0])
        std::cout << "\n[SUCCESS] Ciphertext matches reference vector and decrypted message matches the original plaintext.\n";
    else
        std::cout << "\n[ERROR]   Ciphertext or decrypted message mismatch.\n";

    bool all_ok = true;
    for (int i = 0; i < N_MAX; ++i) {
        if (h_decrypted[i] != h_plain[i]) {
            std::cerr << std::dec << "[ERROR] Block " << i << " mismatch!\n";
            all_ok = false;
            break;
        }
    }
    if (all_ok)
        std::cout << std::dec << "[SUCCESS] All " << N_MAX << " blocks verified.\n";

    // Legacy performance summary (N_MAX = 64 MB)
    double enc_gbps_full = ((double)N_MAX * 8.0) / (enc_ms_full * 1e-3) / 1e9;
    double dec_gbps_full = ((double)N_MAX * 8.0) / (dec_ms_full * 1e-3) / 1e9;
    std::cout << "\n--- Performance (64MB baseline) ---\n"
              << "Encrypt: " << enc_ms_full << " ms  ("
              << enc_gbps_full << " GB/s)\n"
              << "Decrypt: " << dec_ms_full << " ms  ("
              << dec_gbps_full << " GB/s)\n";

    // ── 5. GPU sweep: 5 sizes × 5 trials each ─────────────────────────────
    std::cout << "\n=== SPECK-64/128 gpu sweep ===\n";
    std::cout << std::fixed << std::setprecision(4);

    // inline stats helper
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

        float enc_ms_v[5], dec_ms_v[5];
        for (int tr = 0; tr < N_TRIALS; tr++) {
            CUDA_CHECK(cudaEventRecord(t_start));
            encrypt_kernel<<<blks, THREADS>>>(d_plain, d_cipher, n);
            CUDA_CHECK(cudaEventRecord(t_end));
            CUDA_CHECK(cudaGetLastError());
            CUDA_CHECK(cudaEventSynchronize(t_end));
            CUDA_CHECK(cudaEventElapsedTime(&enc_ms_v[tr], t_start, t_end));

            CUDA_CHECK(cudaEventRecord(t_start));
            decrypt_kernel<<<blks, THREADS>>>(d_cipher, d_decrypted, n);
            CUDA_CHECK(cudaEventRecord(t_end));
            CUDA_CHECK(cudaGetLastError());
            CUDA_CHECK(cudaEventSynchronize(t_end));
            CUDA_CHECK(cudaEventElapsedTime(&dec_ms_v[tr], t_start, t_end));
        }

        double enc_mean, enc_std, dec_mean, dec_std;
        compute_stats(enc_ms_v, N_TRIALS, enc_mean, enc_std);
        compute_stats(dec_ms_v, N_TRIALS, dec_mean, dec_std);

        double bytes_d    = (double)n * 8.0;
        double enc_gbps_s = bytes_d / (enc_mean * 1e-3) / 1e9;
        double dec_gbps_s = bytes_d / (dec_mean * 1e-3) / 1e9;

        std::cout << "gpu_sweep[" << SWEEP_LABELS[s] << "]_enc_ms_mean: "   << enc_mean   << "\n";
        std::cout << "gpu_sweep[" << SWEEP_LABELS[s] << "]_enc_ms_stddev: " << enc_std    << "\n";
        std::cout << "gpu_sweep[" << SWEEP_LABELS[s] << "]_enc_GBps: "      << enc_gbps_s << "\n";
        std::cout << "gpu_sweep[" << SWEEP_LABELS[s] << "]_dec_ms_mean: "   << dec_mean   << "\n";
        std::cout << "gpu_sweep[" << SWEEP_LABELS[s] << "]_dec_ms_stddev: " << dec_std    << "\n";
        std::cout << "gpu_sweep[" << SWEEP_LABELS[s] << "]_dec_GBps: "      << dec_gbps_s << "\n";
    }

    // ── 6. Cleanup ────────────────────────────────────────────────────────
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
