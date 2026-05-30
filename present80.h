#pragma once
#include <cstdint>
#include <array>
#include <bitset>

class Present80 {
private:
    uint64_t round_keys[32];

    static const uint8_t SBOX[16];
    static const uint8_t INV_SBOX[16];

    void generate_round_keys(const std::array<uint8_t, 10>& key) {
        std::bitset<80> K;

        for (int i = 0; i < 10; ++i)
            for (int j = 0; j < 8; ++j)
                K[79 - (i * 8 + (7 - j))] = (key[i] >> j) & 1;

        for (int round = 1; round <= 32; ++round) {
            uint64_t rk = 0;
            for (int i = 0; i < 64; ++i)
                if (K[16 + i]) rk |= (1ULL << i);
            round_keys[round - 1] = rk;

            if (round == 32) break;

            K = (K << 61) | (K >> 19);

            uint8_t top_nibble = 0;
            for (int i = 0; i < 4; ++i)
                if (K[76 + i]) top_nibble |= (1 << i);
            top_nibble = SBOX[top_nibble];
            for (int i = 0; i < 4; ++i)
                K[76 + i] = (top_nibble >> i) & 1;

            uint8_t counter_bits = 0;
            for (int i = 0; i < 5; ++i)
                if (K[15 + i]) counter_bits |= (1 << i);
            counter_bits ^= round;
            for (int i = 0; i < 5; ++i)
                K[15 + i] = (counter_bits >> i) & 1;
        }
    }

public:
    Present80(const std::array<uint8_t, 10>& key) {
        generate_round_keys(key);
    }

    uint64_t encrypt(uint64_t plaintext) const {
        uint64_t state = plaintext;

        for (int round = 0; round < 31; ++round) {
            state ^= round_keys[round];

            uint64_t sbox_state = 0;
            for (int j = 0; j < 16; ++j) {
                uint8_t nibble = (state >> (j * 4)) & 0xF;
                sbox_state |= ((uint64_t)SBOX[nibble] << (j * 4));
            }
            state = sbox_state;

            uint64_t permuted = 0;
            for (int j = 0; j < 64; ++j) {
                if ((state >> j) & 1) {
                    int p = (j == 63) ? 63 : (j * 16) % 63;
                    permuted |= (1ULL << p);
                }
            }
            state = permuted;
        }

        state ^= round_keys[31];
        return state;
    }

    uint64_t decrypt(uint64_t ciphertext) const {
        uint64_t state = ciphertext;

        for (int round = 31; round >= 1; --round) {
            state ^= round_keys[round];

            uint64_t permuted = 0;
            for (int j = 0; j < 64; ++j) {
                if ((state >> j) & 1) {
                    int p = (j == 63) ? 63 : (j * 4) % 63;
                    permuted |= (1ULL << p);
                }
            }
            state = permuted;

            uint64_t sbox_state = 0;
            for (int j = 0; j < 16; ++j) {
                uint8_t nibble = (state >> (j * 4)) & 0xF;
                sbox_state |= ((uint64_t)INV_SBOX[nibble] << (j * 4));
            }
            state = sbox_state;
        }

        state ^= round_keys[0];
        return state;
    }
};

inline const uint8_t Present80::SBOX[16] = {
    0xC, 0x5, 0x6, 0xB, 0x9, 0x0, 0xA, 0xD,
    0x3, 0xE, 0xF, 0x8, 0x4, 0x7, 0x1, 0x2
};

inline const uint8_t Present80::INV_SBOX[16] = {
    0x5, 0xE, 0xF, 0x8, 0xC, 0x1, 0x2, 0xD,
    0xB, 0x4, 0x6, 0x3, 0x0, 0x7, 0x9, 0xA
};
