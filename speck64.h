#pragma once
#include <cstdint>

class Speck64_128 {
private:
    static constexpr int ROUNDS = 27;
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
        Ct[0] = Pt[0]; Ct[1] = Pt[1];
        for (int i = 0; i < ROUNDS; ++i)
            ER(Ct[1], Ct[0], round_keys[i]);
    }

    void decrypt(const uint32_t Ct[2], uint32_t Pt[2]) const {
        Pt[0] = Ct[0]; Pt[1] = Ct[1];
        for (int i = ROUNDS - 1; i >= 0; --i)
            DR(Pt[1], Pt[0], round_keys[i]);
    }
};
