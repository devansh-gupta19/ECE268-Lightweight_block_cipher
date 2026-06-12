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

// ─── AES Inline Device Core Helper Functions ─────────────────────────────────

__device__ __forceinline__
void d_add_round_key(uint8_t s[16], const uint8_t round_key[16]) {
    #pragma unroll
    for (int i = 0; i < 16; i++) {
        s[i] ^= round_key[i];
    }
}

__device__ __forceinline__
void d_sub_bytes(uint8_t s[16]) {
    #pragma unroll
    for (int i = 0; i < 16; i++) {
        s[i] = d_SBOX[s[i]];
    }
}

__device__ __forceinline__
void d_shift_rows(uint8_t s[16]) {
    uint8_t temp;
    // Row 1: left shift by 1
    temp = s[1]; s[1] = s[5]; s[5] = s[9]; s[9] = s[13]; s[13] = temp;
    // Row 2: left shift by 2
    temp = s[2]; s[2] = s[10]; s[10] = temp;
    temp = s[6]; s[6] = s[14]; s[14] = temp;
    // Row 3: left shift by 3 (right shift by 1)
    temp = s[15]; s[15] = s[11]; s[11] = s[7]; s[7] = s[3]; s[3] = temp;
}

__device__ __forceinline__
uint8_t d_galois_multiply(uint8_t a, uint8_t b) {
    uint8_t p = 0;
    #pragma unroll
    for (int counter = 0; counter < 8; counter++) {
        if (b & 1) p ^= a;
        uint8_t hi_bit_set = a & 0x80;
        a <<= 1;
        if (hi_bit_set) a ^= 0x1B;
        b >>= 1;
    }
    return p;
}

__device__ __forceinline__
void d_mix_columns(uint8_t s[16]) {
    #pragma unroll
    for (int c = 0; c < 4; c++) {
        int idx = c * 4;
        uint8_t a = s[idx], b = s[idx+1], r = s[idx+2], d = s[idx+3];
        
        s[idx]   = d_galois_multiply(a, 2) ^ d_galois_multiply(b, 3) ^ r ^ d;
        s[idx+1] = a ^ d_galois_multiply(b, 2) ^ d_galois_multiply(r, 3) ^ d;
        s[idx+2] = a ^ b ^ d_galois_multiply(r, 2) ^ d_galois_multiply(d, 3);
        s[idx+3] = d_galois_multiply(a, 3) ^ b ^ r ^ d_galois_multiply(d, 2);
    }
}

// Full 10-round AES-128 single-block encryption path
__device__ __forceinline__
void d_aes_encrypt_block(const uint8_t input[16], uint8_t output[16]) {
    #pragma unroll
    for (int i = 0; i < 16; i++) output[i] = input[i];

    d_add_round_key(output, d_round_keys[0]);

    #pragma unroll
    for (int r = 1; r < 10; r++) {
        d_sub_bytes(output);
        d_shift_rows(output);
        d_mix_columns(output);
        d_add_round_key(output, d_round_keys[r]);
    }

    d_sub_bytes(output);
    d_shift_rows(output);
    d_add_round_key(output, d_round_keys[10]);
}

// ─── CTR Kernel (Handles both Encryption and Decryption) ─────────────────────
__global__
void ctr_kernel(const uint8_t* __restrict__ input,
                uint8_t* __restrict__ output,
                const uint8_t* __restrict__ nonce,
                int n_blocks) 
{
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx >= n_blocks) return;

    // Local array representing the 128-bit counter block for this thread
    uint8_t counter_block[16];
    
    // Copy base nonce to local variable
    #pragma unroll
    for (int i = 0; i < 16; i++) {
        counter_block[i] = nonce[i];
    }

    // Per-thread counter = nonce + block index, big-endian add from the LSB
    uint32_t carry = idx;
    for (int i = 15; i >= 0; i--) {
        uint32_t sum = counter_block[i] + carry;
        counter_block[i] = (uint8_t)(sum & 0xFF);
        carry = sum >> 8;
        if (carry == 0) break; 
    }

    uint8_t keystream[16];
    // Encrypt the counter block
    d_aes_encrypt_block(counter_block, keystream);

    // XOR keystream with state chunk data
    int offset = idx * 16;
    #pragma unroll
    for (int i = 0; i < 16; i++) {
        output[offset + i] = input[offset + i] ^ keystream[i];
    }
}

// ─── Host Key Schedule Pipeline ──────────────────────────────────────────────
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

static const uint32_t RCON[10] = {
    0x01000000, 0x02000000, 0x04000000, 0x08000000,
    0x10000000, 0x20000000, 0x40000000, 0x80000000,
    0x1B000000, 0x36000000
};

void generate_round_keys(const uint8_t secret_key[16], uint8_t out_keys[11][16]) {
    std::memcpy(out_keys[0], secret_key, 16);
    
    for (int i = 1; i <= 10; i++) {
        uint8_t* prev = out_keys[i-1];
        uint8_t* cur  = out_keys[i];
        
        uint32_t temp = ((uint32_t)prev[12] << 24) | ((uint32_t)prev[13] << 16) |
                        ((uint32_t)prev[14] << 8)  |  (uint32_t)prev[15];
                        
        // RotWord
        temp = (temp << 8) | (temp >> 24);
        
        // SubWord
        uint8_t b0 = HOST_SBOX[(temp >> 24) & 0xFF];
        uint8_t b1 = HOST_SBOX[(temp >> 16) & 0xFF];
        uint8_t b2 = HOST_SBOX[(temp >> 8)  & 0xFF];
        uint8_t b3 = HOST_SBOX[temp         & 0xFF];
        temp = ((uint32_t)b0 << 24) | ((uint32_t)b1 << 16) | ((uint32_t)b2 << 8) | b3;
        
        // XOR Rcon
        temp ^= RCON[i-1];
        
        uint32_t w0 = (((uint32_t)prev[0] << 24) | ((uint32_t)prev[1] << 16) |
                       ((uint32_t)prev[2] << 8)  |  (uint32_t)prev[3]) ^ temp;
        uint32_t w1 = (((uint32_t)prev[4] << 24) | ((uint32_t)prev[5] << 16) |
                       ((uint32_t)prev[6] << 8)  |  (uint32_t)prev[7]) ^ w0;
        uint32_t w2 = (((uint32_t)prev[8] << 24) | ((uint32_t)prev[9] << 16) |
                       ((uint32_t)prev[10] << 8) |  (uint32_t)prev[11]) ^ w1;
        uint32_t w3 = (((uint32_t)prev[12] << 24) | ((uint32_t)prev[13] << 16) |
                       ((uint32_t)prev[14] << 8)  |  (uint32_t)prev[15]) ^ w2;
                       
        cur[0]  = (w0 >> 24) & 0xFF; cur[1]  = (w0 >> 16) & 0xFF; cur[2]  = (w0 >> 8) & 0xFF; cur[3]  = w0 & 0xFF;
        cur[4]  = (w1 >> 24) & 0xFF; cur[5]  = (w1 >> 16) & 0xFF; cur[6]  = (w1 >> 8) & 0xFF; cur[7]  = w1 & 0xFF;
        cur[8]  = (w2 >> 24) & 0xFF; cur[9]  = (w2 >> 16) & 0xFF; cur[10] = (w2 >> 8) & 0xFF; cur[11] = w2 & 0xFF;
        cur[12] = (w3 >> 24) & 0xFF; cur[13] = (w3 >> 16) & 0xFF; cur[14] = (w3 >> 8) & 0xFF; cur[15] = w3 & 0xFF;
    }
}

// ─── Validation & Performance Sweep Metrics Execution ────────────────────────
int main() {
    const int N_SWEEP = 5;
    const int N_TRIALS = 5;
    const int THREADS = 256;

    const size_t SWEEP_BYTES[5] = {1024, 65536, 1048576, 16777216, 67108864};
    const char* SWEEP_LABELS[5] = {"1KB","64KB","1MB","16MB","64MB"};
    const size_t MAX_BYTES = SWEEP_BYTES[4];
    const int MAX_BLOCKS = (int)(MAX_BYTES / 16);

    std::cout << "=== AES-128 CTR Mode GPU Information ===\n";
    std::cout << "const_mem_round_keys_bytes: " << sizeof(d_round_keys) << "\n";
    std::cout << "const_mem_sbox_bytes: " << sizeof(d_SBOX) << "\n";
    std::cout << "const_mem_total_bytes: " << (sizeof(d_round_keys) + sizeof(d_SBOX)) << "\n";
    std::cout << "n_trials_per_size: " << N_TRIALS << "\n";

    uint8_t secret_key[16] = {
        0x2b, 0x7e, 0x15, 0x16, 0x28, 0xae, 0xd2, 0xa6, 
        0xab, 0xf7, 0x15, 0x88, 0x09, 0xcf, 0x4f, 0x3c
    };
    uint8_t host_nonce[16] = {
        0xf0, 0xf1, 0xf2, 0xf3, 0xf4, 0xf5, 0xf6, 0xf7,
        0xf8, 0xf9, 0xfa, 0xfb, 0xfc, 0xfd, 0xfe, 0xff
    };

    uint8_t h_round_keys[11][16];
    generate_round_keys(secret_key, h_round_keys);
    CUDA_CHECK(cudaMemcpyToSymbol(d_round_keys, h_round_keys, sizeof(d_round_keys)));

    uint8_t* h_plain = new uint8_t[MAX_BYTES];
    uint8_t* h_cipher = new uint8_t[MAX_BYTES];
    uint8_t* h_decrypted = new uint8_t[MAX_BYTES];

    for (size_t i = 0; i < MAX_BYTES; i++) {
        h_plain[i] = (uint8_t)(i & 0xFF);
    }

    uint8_t *d_plain, *d_cipher, *d_decrypted, *d_nonce;
    CUDA_CHECK(cudaMalloc(&d_plain, MAX_BYTES));
    CUDA_CHECK(cudaMalloc(&d_cipher, MAX_BYTES));
    CUDA_CHECK(cudaMalloc(&d_decrypted, MAX_BYTES));
    CUDA_CHECK(cudaMalloc(&d_nonce, 16));

    CUDA_CHECK(cudaMemcpy(d_plain, h_plain, MAX_BYTES, cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMemcpy(d_nonce, host_nonce, 16, cudaMemcpyHostToDevice));

    cudaEvent_t t_start, t_end;
    CUDA_CHECK(cudaEventCreate(&t_start));
    CUDA_CHECK(cudaEventCreate(&t_end));

    // Warmup step 
    int blocks_max = (MAX_BLOCKS + THREADS - 1) / THREADS;
    ctr_kernel<<<blocks_max, THREADS>>>(d_plain, d_cipher, d_nonce, MAX_BLOCKS);
    CUDA_CHECK(cudaDeviceSynchronize());

    std::cout << "\n=== AES-128 CTR GPU Execution Sweep ===\n";
    std::cout << std::fixed << std::setprecision(4);

    auto compute_stats = [](const float* v, int n, double& mean, double& stddev) {
        mean = 0;
        for (int i = 0; i < n; i++) mean += v[i];
        mean /= n;
        double sq = 0;
        for (int i = 0; i < n; i++) sq += ((double)v[i] - mean) * ((double)v[i] - mean);
        stddev = std::sqrt(sq / n);
    };

    for (int s = 0; s < N_SWEEP; s++) {
        size_t current_bytes = SWEEP_BYTES[s];
        int n_blocks = (int)(current_bytes / 16);
        int blks = (n_blocks + THREADS - 1) / THREADS;
        
        float enc_ms_v[N_TRIALS], dec_ms_v[N_TRIALS];
        float temp_ms;

        std::cout << "\n=== gpu_sweep[" << SWEEP_LABELS[s] << "] size: " << n_blocks << " blocks ===\n";

        int iters = (current_bytes < 1024 * 1024) ? 100 : 1;

        for (int tr = 0; tr < N_TRIALS; tr++) {
            // Encryption
            CUDA_CHECK(cudaEventRecord(t_start));
            for (int it = 0; it < iters; it++) {
                ctr_kernel<<<blks, THREADS>>>(d_plain, d_cipher, d_nonce, n_blocks);
            }
            CUDA_CHECK(cudaEventRecord(t_end));
            CUDA_CHECK(cudaEventSynchronize(t_end));
            CUDA_CHECK(cudaEventElapsedTime(&temp_ms, t_start, t_end));
            enc_ms_v[tr] = temp_ms / iters;

            // CTR is symmetric: the same kernel decrypts (keystream XOR)
            CUDA_CHECK(cudaEventRecord(t_start));
            for (int it = 0; it < iters; it++) {
                ctr_kernel<<<blks, THREADS>>>(d_cipher, d_decrypted, d_nonce, n_blocks);
            }
            CUDA_CHECK(cudaEventRecord(t_end));
            CUDA_CHECK(cudaEventSynchronize(t_end));
            CUDA_CHECK(cudaEventElapsedTime(&temp_ms, t_start, t_end));
            dec_ms_v[tr] = temp_ms / iters;
        }

        CUDA_CHECK(cudaMemcpy(h_cipher, d_cipher, current_bytes, cudaMemcpyDeviceToHost));
        CUDA_CHECK(cudaMemcpy(h_decrypted, d_decrypted, current_bytes, cudaMemcpyDeviceToHost));

        bool all_ok = true;
        if (std::memcmp(h_plain, h_decrypted, current_bytes) != 0) {
            std::cerr << "[ERROR] Plaintext mismatch at size " << SWEEP_LABELS[s] << "!\n";
            all_ok = false;
        }

        if (all_ok) {
            std::cout << "[SUCCESS] All " << n_blocks << " blocks successfully verified.\n";
        }

        double enc_mean, enc_std, dec_mean, dec_std;
        compute_stats(enc_ms_v, N_TRIALS, enc_mean, enc_std);
        compute_stats(dec_ms_v, N_TRIALS, dec_mean, dec_std);

        double bytes_d = (double)current_bytes;
        double enc_mbps_s = bytes_d / (enc_mean * 1e-3) / 1e6;
        double dec_mbps_s = bytes_d / (dec_mean * 1e-3) / 1e6;

        std::cout << "encryption_ms_mean:   " << enc_mean   << "\n";
        std::cout << "encryption_ms_stddev: " << enc_std    << "\n";
        std::cout << "encryption_MBps:      " << enc_mbps_s << "\n";
        std::cout << "decryption_ms_mean:   " << dec_mean   << "\n";
        std::cout << "decryption_ms_stddev: " << dec_std    << "\n";
        std::cout << "decryption_MBps:      " << dec_mbps_s << "\n";
    }

    // Free resources
    delete[] h_plain;
    delete[] h_cipher;
    delete[] h_decrypted;
    CUDA_CHECK(cudaFree(d_plain));
    CUDA_CHECK(cudaFree(d_cipher));
    CUDA_CHECK(cudaFree(d_decrypted));
    CUDA_CHECK(cudaFree(d_nonce));
    CUDA_CHECK(cudaEventDestroy(t_start));
    CUDA_CHECK(cudaEventDestroy(t_end));

    return 0;
}
