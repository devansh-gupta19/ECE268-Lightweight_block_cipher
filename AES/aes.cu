#include <iostream>
#include <iomanip>
#include <cstdint>
#include <cstring>
#include <cassert>
#include <cmath>
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


// ─── GPU constant memory ─────────────────────────────────────────────────────
__constant__ uint8_t d_round_keys[11][16];

__constant__ uint8_t d_SBOX[256] = {
    0x63,0x7c,0x77,0x7b,0xf2,0x6b,0x6f,0xc5,0x30,0x01,0x67,0x2b,0xfe,0xd7,0xab,0x76,
    0xca,0x82,0xc9,0x7d,0xfa,0x59,0x47,0xf0,0xad,0xd4,0xa2,0xaf,0x9c,0xa4,0x72,0xc0,
    0xb7,0xfd,0x93,0x26,0x36,0x3f,0xf7,0xcc,0x34,0xa5,0xe5,0xf1,0x71,0xd8,0x31,0x15,
    0x04,0xc7,0x23,0xc3,0x18,0x96,0x05,0x9a,0x07,0x12,0x80,0xe2,0xeb,0x27,0xb2,0x75,
    0x09,0x83,0x2c,0x1a,0x1b,0x6e,0x5a,0xa0,0x52,0x3b,0xd6,0xb3,0x29,0xe3,0x2f,0x84,
    0x53,0xd1,0x00,0xed,0x20,0xfc,0xb1,0x5b,0x6a,0xcb,0xbe,0x39,0x4a,0x4c,0x58,0xcf,
    0xd0,0xef,0xaa,0xfb,0x43,0x4d,0x33,0x85,0x45,0xf9,0x02,0x7f,0x50,0x3c,0x9f,0xa8,
    0x51,0xa3,0x40,0x8f,0x92,0x9d,0x38,0xf5,0xbc,0xb6,0xda,0x21,0x10,0xff,0xf3,0xd2,
    0xcd,0x0c,0x13,0xec,0x5f,0x97,0x44,0x17,0xc4,0xa7,0x7e,0x3d,0x64,0x5d,0x19,0x73,
    0x60,0x81,0x4f,0xdc,0x22,0x2a,0x90,0x88,0x46,0xee,0xb8,0x14,0xde,0x5e,0x0b,0xdb,
    0xe0,0x32,0x3a,0x0a,0x49,0x06,0x24,0x5c,0xc2,0xd3,0xac,0x62,0x91,0x95,0xe4,0x79,
    0xe7,0xc8,0x37,0x6d,0x8d,0xd5,0x4e,0xa9,0x6c,0x56,0xf4,0xea,0x65,0x7a,0xae,0x08,
    0xba,0x78,0x25,0x2e,0x1c,0xa6,0xb4,0xc6,0xe8,0xdd,0x74,0x1f,0x4b,0xbd,0x8b,0x8a,
    0x70,0x3e,0xb5,0x66,0x48,0x03,0xf6,0x0e,0x61,0x35,0x57,0xb9,0x86,0xc1,0x1d,0x9e,
    0xe1,0xf8,0x98,0x11,0x69,0xd9,0x8e,0x94,0x9b,0x1e,0x87,0xe9,0xce,0x55,0x28,0xdf,
    0x8c,0xa1,0x89,0x0d,0xbf,0xe6,0x42,0x68,0x41,0x99,0x2d,0x0f,0xb0,0x54,0xbb,0x16
};

__constant__ uint8_t d_INV_SBOX[256] = {
    0x52,0x09,0x6a,0xd5,0x30,0x36,0xa5,0x38,0xbf,0x40,0xa3,0x9e,0x81,0xf3,0xd7,0xfb,
    0x7c,0xe3,0x39,0x82,0x9b,0x2f,0xff,0x87,0x34,0x8e,0x43,0x44,0xc4,0xde,0xe9,0xcb,
    0x54,0x7b,0x94,0x32,0xa6,0xc2,0x23,0x3d,0xee,0x4c,0x95,0x0b,0x42,0xfa,0xc3,0x4e,
    0x08,0x2e,0xa1,0x66,0x28,0xd9,0x24,0xb2,0x76,0x5b,0xa2,0x49,0x6d,0x8b,0xd1,0x25,
    0x72,0xf8,0xf6,0x64,0x86,0x68,0x98,0x16,0xd4,0xa4,0x5c,0xcc,0x5d,0x65,0xb6,0x92,
    0x6c,0x70,0x48,0x50,0xfd,0xed,0xb9,0xda,0x5e,0x15,0x46,0x57,0xa7,0x8d,0x9d,0x84,
    0x90,0xd8,0xab,0x00,0x8c,0xbc,0xd3,0x0a,0xf7,0xe4,0x58,0x05,0xb8,0xb3,0x45,0x06,
    0xd0,0x2c,0x1e,0x8f,0xca,0x3f,0x0f,0x02,0xc1,0xaf,0xbd,0x03,0x01,0x13,0x8a,0x6b,
    0x3a,0x91,0x11,0x41,0x4f,0x67,0xdc,0xea,0x97,0xf2,0xcf,0xce,0xf0,0xb4,0xe6,0x73,
    0x96,0xac,0x74,0x22,0xe7,0xad,0x35,0x85,0xe2,0xf9,0x37,0xe8,0x1c,0x75,0xdf,0x6e,
    0x47,0xf1,0x1a,0x71,0x1d,0x29,0xc5,0x89,0x6f,0xb7,0x62,0x0e,0xaa,0x18,0xbe,0x1b,
    0xfc,0x56,0x3e,0x4b,0xc6,0xd2,0x79,0x20,0x9a,0xdb,0xc0,0xfe,0x78,0xcd,0x5a,0xf4,
    0x1f,0xdd,0xa8,0x33,0x88,0x07,0xc7,0x31,0xb1,0x12,0x10,0x59,0x27,0x80,0xec,0x5f,
    0x60,0x51,0x7f,0xa9,0x19,0xb5,0x4a,0x0d,0x2d,0xe5,0x7a,0x9f,0x93,0xc9,0x9c,0xef,
    0xa0,0xe0,0x3b,0x4d,0xae,0x2a,0xf5,0xb0,0xc8,0xeb,0xbb,0x3c,0x83,0x53,0x99,0x61,
    0x17,0x2b,0x04,0x7e,0xba,0x77,0xd6,0x26,0xe1,0x69,0x14,0x63,0x55,0x21,0x0c,0x7d
};

// ─── Device helpers for AES Operations ───────────────────────────────────────

__device__ __forceinline__ void d_add_round_key(uint8_t s[16], int round) {
    #pragma unroll
    for (int i = 0; i < 16; i++) {
        s[i] ^= d_round_keys[round][i];
    }
}

__device__ __forceinline__ void d_sub_bytes(uint8_t s[16]) {
    #pragma unroll
    for (int i = 0; i < 16; i++) s[i] = d_SBOX[s[i]];
}

__device__ __forceinline__ void d_inv_sub_bytes(uint8_t s[16]) {
    #pragma unroll
    for (int i = 0; i < 16; i++) s[i] = d_INV_SBOX[s[i]];
}

__device__ __forceinline__ void d_shift_rows(uint8_t s[16]) {
    uint8_t t;
    // row 1 left by 1
    t = s[1]; s[1]=s[5]; s[5]=s[9]; s[9]=s[13]; s[13]=t;
    // row 2 left by 2
    t=s[2];  s[2]=s[10];  s[10]=t;
    t=s[6];  s[6]=s[14];  s[14]=t;
    // row 3 left by 3 (= right by 1)
    t=s[15]; s[15]=s[11]; s[11]=s[7]; s[7]=s[3]; s[3]=t;
}

__device__ __forceinline__ void d_inv_shift_rows(uint8_t s[16]) {
    uint8_t t;
    // row 1 right by 1
    t=s[13]; s[13]=s[9]; s[9]=s[5]; s[5]=s[1]; s[1]=t;
    // row 2 right by 2
    t=s[2];  s[2]=s[10];  s[10]=t;
    t=s[6];  s[6]=s[14];  s[14]=t;
    // row 3 right by 3 (= left by 1)
    t=s[3];  s[3]=s[7];   s[7]=s[11]; s[11]=s[15]; s[15]=t;
}

// Since b is a compile-time constant during MixColumns unrolling, the compiler 
// resolves branches automatically, making this highly efficient on the GPU.
__device__ __forceinline__ uint8_t d_gmul(uint8_t a, uint8_t b) {
    uint8_t p = 0;
    #pragma unroll
    for (int i = 0; i < 8; i++) {
        if (b & 1) p ^= a;
        bool hi = (a & 0x80);
        a <<= 1;
        if (hi) a ^= 0x1b;
        b >>= 1;
    }
    return p;
}

__device__ __forceinline__ void d_mix_columns(uint8_t s[16]) {
    #pragma unroll
    for (int c = 0; c < 4; c++) {
        uint8_t* col = s + c*4;
        uint8_t a0=col[0], a1=col[1], a2=col[2], a3=col[3];
        col[0] = d_gmul(2,a0)^d_gmul(3,a1)^a2^a3;
        col[1] = a0^d_gmul(2,a1)^d_gmul(3,a2)^a3;
        col[2] = a0^a1^d_gmul(2,a2)^d_gmul(3,a3);
        col[3] = d_gmul(3,a0)^a1^a2^d_gmul(2,a3);
    }
}

__device__ __forceinline__ void d_inv_mix_columns(uint8_t s[16]) {
    #pragma unroll
    for (int c = 0; c < 4; c++) {
        uint8_t* col = s + c*4;
        uint8_t a0=col[0], a1=col[1], a2=col[2], a3=col[3];
        col[0] = d_gmul(0x0e,a0)^d_gmul(0x0b,a1)^d_gmul(0x0d,a2)^d_gmul(0x09,a3);
        col[1] = d_gmul(0x09,a0)^d_gmul(0x0e,a1)^d_gmul(0x0b,a2)^d_gmul(0x0d,a3);
        col[2] = d_gmul(0x0d,a0)^d_gmul(0x09,a1)^d_gmul(0x0e,a2)^d_gmul(0x0b,a3);
        col[3] = d_gmul(0x0b,a0)^d_gmul(0x0d,a1)^d_gmul(0x09,a2)^d_gmul(0x0e,a3);
    }
}

// ─── Kernels ─────────────────────────────────────────────────────────────────

__global__
void encrypt_kernel(const uint8_t* __restrict__ plaintexts,
                          uint8_t* __restrict__ ciphertexts,
                    int n)
{
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx >= n) return;

    uint8_t s[16];
    
    // Load block from global memory
    int offset = idx * 16;
    #pragma unroll
    for(int i = 0; i < 16; i++) {
        s[i] = plaintexts[offset + i];
    }

    d_add_round_key(s, 0);
    #pragma unroll
    for (int r = 1; r <= 9; r++) {
        d_sub_bytes(s);
        d_shift_rows(s);
        d_mix_columns(s);
        d_add_round_key(s, r);
    }
    d_sub_bytes(s);
    d_shift_rows(s);
    d_add_round_key(s, 10);

    // Store block to global memory
    #pragma unroll
    for(int i = 0; i < 16; i++) {
        ciphertexts[offset + i] = s[i];
    }
}

__global__
void decrypt_kernel(const uint8_t* __restrict__ ciphertexts,
                          uint8_t* __restrict__ plaintexts,
                    int n)
{
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx >= n) return;

    uint8_t s[16];
    
    // Load block from global memory
    int offset = idx * 16;
    #pragma unroll
    for(int i = 0; i < 16; i++) {
        s[i] = ciphertexts[offset + i];
    }

    d_add_round_key(s, 10);
    #pragma unroll
    for (int r = 9; r >= 1; r--) {
        d_inv_shift_rows(s);
        d_inv_sub_bytes(s);
        d_add_round_key(s, r);
        d_inv_mix_columns(s);
    }
    d_inv_shift_rows(s);
    d_inv_sub_bytes(s);
    d_add_round_key(s, 0);

    // Store block to global memory
    #pragma unroll
    for(int i = 0; i < 16; i++) {
        plaintexts[offset + i] = s[i];
    }
}

// ─── CPU Key Schedule Generation ──────────────────────────────────────────────

static const uint8_t HOST_SBOX[256] = {
    0x63,0x7c,0x77,0x7b,0xf2,0x6b,0x6f,0xc5,0x30,0x01,0x67,0x2b,0xfe,0xd7,0xab,0x76,
    0xca,0x82,0xc9,0x7d,0xfa,0x59,0x47,0xf0,0xad,0xd4,0xa2,0xaf,0x9c,0xa4,0x72,0xc0,
    0xb7,0xfd,0x93,0x26,0x36,0x3f,0xf7,0xcc,0x34,0xa5,0xe5,0xf1,0x71,0xd8,0x31,0x15,
    0x04,0xc7,0x23,0xc3,0x18,0x96,0x05,0x9a,0x07,0x12,0x80,0xe2,0xeb,0x27,0xb2,0x75,
    0x09,0x83,0x2c,0x1a,0x1b,0x6e,0x5a,0xa0,0x52,0x3b,0xd6,0xb3,0x29,0xe3,0x2f,0x84,
    0x53,0xd1,0x00,0xed,0x20,0xfc,0xb1,0x5b,0x6a,0xcb,0xbe,0x39,0x4a,0x4c,0x58,0xcf,
    0xd0,0xef,0xaa,0xfb,0x43,0x4d,0x33,0x85,0x45,0xf9,0x02,0x7f,0x50,0x3c,0x9f,0xa8,
    0x51,0xa3,0x40,0x8f,0x92,0x9d,0x38,0xf5,0xbc,0xb6,0xda,0x21,0x10,0xff,0xf3,0xd2,
    0xcd,0x0c,0x13,0xec,0x5f,0x97,0x44,0x17,0xc4,0xa7,0x7e,0x3d,0x64,0x5d,0x19,0x73,
    0x60,0x81,0x4f,0xdc,0x22,0x2a,0x90,0x88,0x46,0xee,0xb8,0x14,0xde,0x5e,0x0b,0xdb,
    0xe0,0x32,0x3a,0x0a,0x49,0x06,0x24,0x5c,0xc2,0xd3,0xac,0x62,0x91,0x95,0xe4,0x79,
    0xe7,0xc8,0x37,0x6d,0x8d,0xd5,0x4e,0xa9,0x6c,0x56,0xf4,0xea,0x65,0x7a,0xae,0x08,
    0xba,0x78,0x25,0x2e,0x1c,0xa6,0xb4,0xc6,0xe8,0xdd,0x74,0x1f,0x4b,0xbd,0x8b,0x8a,
    0x70,0x3e,0xb5,0x66,0x48,0x03,0xf6,0x0e,0x61,0x35,0x57,0xb9,0x86,0xc1,0x1d,0x9e,
    0xe1,0xf8,0x98,0x11,0x69,0xd9,0x8e,0x94,0x9b,0x1e,0x87,0xe9,0xce,0x55,0x28,0xdf,
    0x8c,0xa1,0x89,0x0d,0xbf,0xe6,0x42,0x68,0x41,0x99,0x2d,0x0f,0xb0,0x54,0xbb,0x16
};

static const uint8_t HOST_RCON[10] = {
    0x01,0x02,0x04,0x08,0x10,0x20,0x40,0x80,0x1b,0x36
};

void generate_aes_round_keys(const uint8_t key[16], uint8_t out_keys[11][16]) {
    std::memcpy(out_keys[0], key, 16);
    for (int i = 1; i <= 10; i++) {
        const uint8_t* prev = out_keys[i-1];
        uint8_t* cur  = out_keys[i];
        
        cur[0] = HOST_SBOX[prev[13]] ^ HOST_RCON[i-1] ^ prev[0];
        cur[1] = HOST_SBOX[prev[14]] ^ prev[1];
        cur[2] = HOST_SBOX[prev[15]] ^ prev[2];
        cur[3] = HOST_SBOX[prev[12]] ^ prev[3];
        
        for (int j = 4; j < 16; j++) cur[j] = prev[j] ^ cur[j-4];
    }
}

// ─── Main ─────────────────────────────────────────────────────────────────────

int main()
{
    const int    N_SWEEP   = 5;
    const int    N_TRIALS  = 5;
    const int    THREADS   = 256;

    const size_t SWEEP_BYTES[5]  = {1024, 65536, 1048576, 16777216, 67108864};
    const char* SWEEP_LABELS[5] = {"1KB","64KB","1MB","16MB","64MB"};
    const int    N_MAX     = (int)(SWEEP_BYTES[4] / 16);  // Blocks for 64 MB

    // ── GPU info block ────────────────────────────────────────────────────
    std::cout << "=== AES-128 gpu info ===\n";
    std::cout << "const_mem_round_keys_bytes: " << sizeof(d_round_keys) << "\n";
    std::cout << "const_mem_sbox_bytes:       " << sizeof(d_SBOX) << "\n";
    std::cout << "const_mem_inv_sbox_bytes:   " << sizeof(d_INV_SBOX) << "\n";
    std::cout << "const_mem_total_bytes:      " << (sizeof(d_round_keys) + sizeof(d_SBOX) + sizeof(d_INV_SBOX)) << "\n";
    std::cout << "key_schedule_size_bytes:    " << sizeof(d_round_keys) << "\n";
    std::cout << "n_trials_per_size:          " << N_TRIALS << "\n";

    // ── Parameters ────────────────────────────────────────────────────────
    uint8_t key[16] = {
        0x00,0x11,0x22,0x33,0x44,0x55,0x66,0x77,
        0x88,0x99,0xaa,0xbb,0xcc,0xdd,0xee,0xff
    };

    // ── 1. Key schedule on CPU → upload to GPU constant memory ────────────
    uint8_t h_round_keys[11][16];
    generate_aes_round_keys(key, h_round_keys);
    CUDA_CHECK(cudaMemcpyToSymbol(d_round_keys, h_round_keys, 11 * 16 * sizeof(uint8_t)));

    // ── 2. Allocate host + device buffers at N_MAX (reused for all sizes) ─
    uint8_t* h_plain     = new uint8_t[N_MAX * 16];
    uint8_t* h_cipher    = new uint8_t[N_MAX * 16];
    uint8_t* h_decrypted = new uint8_t[N_MAX * 16];
    for (size_t i = 0; i < N_MAX * 16; ++i)
        h_plain[i] = (uint8_t)(i & 0xFF);

    uint8_t *d_plain, *d_cipher, *d_decrypted;
    CUDA_CHECK(cudaMalloc(&d_plain,     N_MAX * 16 * sizeof(uint8_t)));
    CUDA_CHECK(cudaMalloc(&d_cipher,    N_MAX * 16 * sizeof(uint8_t)));
    CUDA_CHECK(cudaMalloc(&d_decrypted, N_MAX * 16 * sizeof(uint8_t)));
    CUDA_CHECK(cudaMemcpy(d_plain, h_plain, N_MAX * 16 * sizeof(uint8_t), cudaMemcpyHostToDevice));

    cudaEvent_t t_start, t_end;
    CUDA_CHECK(cudaEventCreate(&t_start));
    CUDA_CHECK(cudaEventCreate(&t_end));

    // ── 3. Warmup: one full N_MAX encrypt ─────────────────────────────────
    int blocks_max = (N_MAX + THREADS - 1) / THREADS;
    encrypt_kernel<<<blocks_max, THREADS>>>(d_plain, d_cipher, N_MAX);
    CUDA_CHECK(cudaDeviceSynchronize());

    // ── 4. GPU sweep: 5 sizes × 5 trials each ─────────────────────────────
    std::cout << "\n=== AES-128 GPU sweep ===\n";
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
        int n    = (int)(SWEEP_BYTES[s] / 16);
        int blks = (n + THREADS - 1) / THREADS;
        float enc_ms_v[N_TRIALS], dec_ms_v[N_TRIALS];
        float temp_ms;

        std::cout << "\n=== gpu_sweep[" << SWEEP_LABELS[s] << "] size: " << n << " blocks ===\n";

        // Run more iterations for smaller payloads to drown out driver latency
        int iters = (SWEEP_BYTES[s] < 1024 * 1024) ? 100 : 1;
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
        CUDA_CHECK(cudaMemcpy(h_cipher,    d_cipher,    n * 16 * sizeof(uint8_t), cudaMemcpyDeviceToHost));
        CUDA_CHECK(cudaMemcpy(h_decrypted, d_decrypted, n * 16 * sizeof(uint8_t), cudaMemcpyDeviceToHost));
        bool all_ok = true;
        if (std::memcmp(h_plain, h_decrypted, SWEEP_BYTES[s]) != 0) {
            std::cerr << "[ERROR] Mismatch at size " << SWEEP_LABELS[s] << "!\n";
            all_ok = false;
        }

        if (all_ok)
            std::cout << "[SUCCESS] All " << n << " blocks verified.\n";

        double enc_mean, enc_std, dec_mean, dec_std;
        compute_stats(enc_ms_v, N_TRIALS, enc_mean, enc_std);
        compute_stats(dec_ms_v, N_TRIALS, dec_mean, dec_std);

        double bytes_d    = (double)n * 16.0;
        double enc_gbps_s = bytes_d / (enc_mean * 1e-3) / 1e9;
        double dec_gbps_s = bytes_d / (dec_mean * 1e-3) / 1e9;

        std::cout << "encryption_ms_mean:   "      << enc_mean   << "\n";
        std::cout << "encryption_ms_stddev: "      << enc_std    << "\n";
        std::cout << "encryption_GBps:      "      << enc_gbps_s << "\n";
        std::cout << "decryption_ms_mean:   "      << dec_mean   << "\n";
        std::cout << "decryption_ms_stddev: "      << dec_std    << "\n";
        std::cout << "decryption_GBps:      "      << dec_gbps_s << "\n";
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
