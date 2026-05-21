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
    // ── Parameters (from reference code) ──────────────────────────────────
    std::array<uint8_t, 10> key = {
        0x01, 0x23, 0x45, 0x67, 0x89, 0xAB, 0xCD, 0xEF, 0x01, 0x23
    };
    const uint64_t BASE_PLAINTEXT = 0x0000000000000110ULL;

    // Number of blocks to encrypt in parallel. Each block is simply
    // BASE_PLAINTEXT + i so we have N distinct, verifiable inputs.
    const int N       = 1 << 20;   // 1 048 576 blocks (~8 MB)
    const int THREADS = 256;       // threads per block (multiple of warp size 32)
    const int BLOCKS  = (N + THREADS - 1) / THREADS;

    // ── 1. Key schedule on CPU → upload to GPU constant memory ────────────
    uint64_t h_round_keys[32];
    generate_round_keys(key, h_round_keys);

    CUDA_CHECK(cudaMemcpyToSymbol(d_round_keys, h_round_keys,
                                  32 * sizeof(uint64_t)));

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

    if (h_plain[0] == h_decrypted[0])
        std::cout << "\n[SUCCESS] Decrypted message matches the original plaintext.\n";
    else
        std::cout << "\n[ERROR]   Decrypted message mismatch.\n";

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
