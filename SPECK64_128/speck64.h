#pragma once
#include <cstdint>

class Speck64_128 {
public:
    // SPECK-64/128 utilizes 27 rounds
    static constexpr int ROUNDS = 27;
private:
    uint32_t round_keys[ROUNDS];

    static inline uint32_t ROTR32(uint32_t x, int r) {
        return (x >> r) | (x << (32 - r));
    }
    static inline uint32_t ROTL32(uint32_t x, int r) {
        return (x << r) | (x >> (32 - r));
    }
    static inline void ER(uint32_t& x, uint32_t& y, uint32_t k) {
        x = (ROTR32(x, 8) + y) ^ k;
        y = ROTL32(y, 3) ^ x;
    }
    static inline void DR(uint32_t& x, uint32_t& y, uint32_t k) {
        y = ROTR32(y ^ x, 3);
        x = ROTL32((x ^ k) - y, 8);
    }

public:
    void expandKey(const uint32_t K[4]) {
        uint32_t b = K[0];
        uint32_t a[3] = {K[1], K[2], K[3]};
        round_keys[0] = b;
        for (uint32_t i = 0; i < ROUNDS - 1; ++i) {
            ER(a[i % 3], b, i);
            round_keys[i + 1] = b;
        }
    }

    void encrypt(const uint32_t Pt[2], uint32_t Ct[2]) const {
        // Load into registers
        uint32_t x = Pt[1]; // Left word
        uint32_t y = Pt[0]; // Right word

        // Force loop unrolling to remove branch penalties
        #pragma GCC unroll 32
        for (int i = 0; i < ROUNDS; ++i) {
            ER(x, y, round_keys[i]);
        }

        // Store back to memory
        Ct[1] = x;
        Ct[0] = y;
    }

    void decrypt(const uint32_t Ct[2], uint32_t Pt[2]) const {
        // Load into registers
        uint32_t x = Ct[1]; // Left word
        uint32_t y = Ct[0]; // Right word

        // Use a forward loop to ensure auto-vectorization doesn't break
        #pragma GCC unroll 32
        for (int i = 0; i < ROUNDS; ++i) {
            // Reverse the key index mathematically
            DR(x, y, round_keys[ROUNDS - 1 - i]);
        }

        // Store back to memory
        Pt[1] = x;
        Pt[0] = y;
    }

    const uint32_t* round_keys_ptr() const { return round_keys; }

    // Batch helpers used by the sweep.
    // Each block is a pair of consecutive uint32_t words: [right, left] = [w[0], w[1]].
    void encrypt_batch(const uint32_t* __restrict pt, uint32_t* __restrict ct, int n_blocks) const {
        for (int i = 0; i < n_blocks; ++i)
            encrypt(pt + i * 2, ct + i * 2);
    }
 
    void decrypt_batch(const uint32_t* __restrict ct, uint32_t* __restrict pt, int n_blocks) const {
        for (int i = 0; i < n_blocks; ++i)
            decrypt(ct + i * 2, pt + i * 2);
    }
};
