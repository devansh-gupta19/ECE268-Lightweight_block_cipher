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
    // ── Parameters (from reference code) ──────────────────────────────────
    
    // Official NSA Test Vector Key for SPECK-64/128
    std::array<uint32_t, 4> key = {
        0x03020100, 0x0b0a0908, 0x13121110, 0x1b1a1918
    };
    
    // Official NSA Test Vector Plaintext for SPECK-64/128:
    // Left word (x) = 0x3b726574, Right word (y) = 0x7475432d
    // Packed as (Left << 32) | Right so upper 32 bits = x = left word (gets ROTR in round fn)
    const uint64_t BASE_PLAINTEXT = 0x3b7265747475432dULL;

    // Number of blocks to encrypt in parallel. Each block is simply
    // BASE_PLAINTEXT + i so we have N distinct, verifiable inputs.
    // 1M blocks to match PRESENT-80 CUDA benchmark for fair comparison.
    const int N       = 1 << 20;   // 1,048,576 blocks (~8 MB)
    const int THREADS = 256;       // threads per block (multiple of warp size 32)
    const int BLOCKS  = (N + THREADS - 1) / THREADS;

    // ── 1. Key schedule on CPU → upload to GPU constant memory ────────────
    uint32_t h_round_keys[27];
    generate_round_keys(key, h_round_keys);

    CUDA_CHECK(cudaMemcpyToSymbol(d_round_keys, h_round_keys,
                                  27 * sizeof(uint32_t)));

    // ── 2. Allocate and fill host plaintext buffer ─────────────────────────
    uint64_t* h_plain     = new uint64_t[N];
    uint64_t* h_cipher    = new uint64_t[N];
    uint64_t* h_decrypted = new uint64_t[N];

    for (int i = 0; i < N; ++i)
        h_plain[i] = BASE_PLAINTEXT + (uint64_t)i;

    // ── 3. Allocate device buffers ─────────────────────────────────────────
    uint64_t *d_plain, *d_cipher, *d_decrypted;
    CUDA_CHECK(cudaMalloc(&d_plain,     N * sizeof(uint64_t)));
    CUDA_CHECK(cudaMalloc(&d_cipher,    N * sizeof(uint64_t)));
    CUDA_CHECK(cudaMalloc(&d_decrypted, N * sizeof(uint64_t)));

    // ── 4. Copy plaintext to device ────────────────────────────────────────
    CUDA_CHECK(cudaMemcpy(d_plain, h_plain,
                          N * sizeof(uint64_t), cudaMemcpyHostToDevice));

    // ── 5. Create CUDA events for timing ──────────────────────────────────
    cudaEvent_t t_start, t_end;
    CUDA_CHECK(cudaEventCreate(&t_start));
    CUDA_CHECK(cudaEventCreate(&t_end));

    // ── 6. Encrypt ────────────────────────────────────────────────────────
    CUDA_CHECK(cudaEventRecord(t_start));
    encrypt_kernel<<<BLOCKS, THREADS>>>(d_plain, d_cipher, N);
    CUDA_CHECK(cudaEventRecord(t_end));
    CUDA_CHECK(cudaGetLastError());
    CUDA_CHECK(cudaEventSynchronize(t_end));

    float enc_ms = 0;
    CUDA_CHECK(cudaEventElapsedTime(&enc_ms, t_start, t_end));

    // ── 7. Decrypt ────────────────────────────────────────────────────────
    CUDA_CHECK(cudaEventRecord(t_start));
    decrypt_kernel<<<BLOCKS, THREADS>>>(d_cipher, d_decrypted, N);
    CUDA_CHECK(cudaEventRecord(t_end));
    CUDA_CHECK(cudaGetLastError());
    CUDA_CHECK(cudaEventSynchronize(t_end));

    float dec_ms = 0;
    CUDA_CHECK(cudaEventElapsedTime(&dec_ms, t_start, t_end));

    // ── 8. Copy results back to host ───────────────────────────────────────
    CUDA_CHECK(cudaMemcpy(h_cipher,    d_cipher,
                          N * sizeof(uint64_t), cudaMemcpyDeviceToHost));
    CUDA_CHECK(cudaMemcpy(h_decrypted, d_decrypted,
                          N * sizeof(uint64_t), cudaMemcpyDeviceToHost));

    // ── 9. Print first block result (mirrors reference code output) ────────
    std::cout << std::hex << std::uppercase << std::setfill('0');
    std::cout << "Plaintext  : 0x" << std::setw(16) << h_plain[0]     << "\n";
    std::cout << "Ciphertext : 0x" << std::setw(16) << h_cipher[0]    << "\n";
    std::cout << "Decrypted  : 0x" << std::setw(16) << h_decrypted[0] << "\n";

    // Expected ciphertext for the first block based on NSA SPECK-64/128 test vector
    if (h_cipher[0] == 0x8C6FA548454E028BULL && h_plain[0] == h_decrypted[0])
        std::cout << "\n[SUCCESS] Ciphertext matches reference vector and decrypted message matches the original plaintext.\n";
    else
        std::cout << "\n[ERROR]   Ciphertext or decrypted message mismatch.\n";

    // ── 10. Verify all N blocks ────────────────────────────────────────────
    bool all_ok = true;
    for (int i = 0; i < N; ++i) {
        if (h_decrypted[i] != h_plain[i]) {
            std::cerr << std::dec
                      << "[ERROR] Block " << i << " mismatch!\n";
            all_ok = false;
            break;
        }
    }
    if (all_ok)
        std::cout << std::dec
                  << "[SUCCESS] All " << N << " blocks verified.\n";

    // ── 11. Performance summary ────────────────────────────────────────────
    double enc_gbps = (N * 8.0) / (enc_ms * 1e-3) / 1e9;
    double dec_gbps = (N * 8.0) / (dec_ms * 1e-3) / 1e9;
    std::cout << "\n--- Performance ---\n"
              << "Encrypt: " << enc_ms << " ms  ("
              << enc_gbps   << " GB/s,  "
              << (N / (enc_ms * 1e-3) / 1e6) << " M blocks/s)\n"
              << "Decrypt: " << dec_ms << " ms  ("
              << dec_gbps   << " GB/s,  "
              << (N / (dec_ms * 1e-3) / 1e6) << " M blocks/s)\n";

    // ── 12. Cleanup ────────────────────────────────────────────────────────
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
