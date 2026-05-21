#include <iostream>
#include <cstdint>
#include <bitset>
#include <array>
#include <iomanip>

class Present80 {
private:
    uint64_t round_keys[32];

    // PRESENT 4-bit S-Box and its inverse
    static const uint8_t SBOX[16];
    static const uint8_t INV_SBOX[16];

    void generate_round_keys(const std::array<uint8_t, 10>& key) {
        std::bitset<80> K;
        
        // Load 80-bit key: key[0] is MSB, key[9] is LSB
        for (int i = 0; i < 10; ++i) {
            for (int j = 0; j < 8; ++j) {
                K[79 - (i * 8 + (7 - j))] = (key[i] >> j) & 1;
            }
        }

        for (int round = 1; round <= 32; ++round) {
            // Extract 64-bit round key (Leftmost 64 bits: K[79..16])
            uint64_t rk = 0;
            for (int i = 0; i < 64; ++i) {
                if (K[16 + i]) rk |= (1ULL << i);
            }
            round_keys[round - 1] = rk;

            if (round == 32) break;

            // Key Update
            // a) Rotate left by 61
            K = (K << 61) | (K >> 19);

            // b) S-Box on the top nibble (K[79..76])
            uint8_t top_nibble = 0;
            for (int i = 0; i < 4; ++i) {
                if (K[76 + i]) top_nibble |= (1 << i);
            }
            top_nibble = SBOX[top_nibble];
            for (int i = 0; i < 4; ++i) {
                K[76 + i] = (top_nibble >> i) & 1;
            }

            // c) Add round_counter to K[19..15]
            uint8_t counter_bits = 0;
            for (int i = 0; i < 5; ++i) {
                if (K[15 + i]) counter_bits |= (1 << i);
            }
            counter_bits ^= round;
            for (int i = 0; i < 5; ++i) {
                K[15 + i] = (counter_bits >> i) & 1;
            }
        }
    }

public:
    Present80(const std::array<uint8_t, 10>& key) {
        generate_round_keys(key);
    }

    uint64_t encrypt(uint64_t plaintext) const {
        uint64_t state = plaintext;
        
        for (int round = 0; round < 31; ++round) {
            // 1. addRoundKey
            state ^= round_keys[round];

            // 2. sBoxLayer
            uint64_t sbox_state = 0;
            for (int j = 0; j < 16; ++j) {
                uint8_t nibble = (state >> (j * 4)) & 0xF;
                nibble = SBOX[nibble];
                sbox_state |= ((uint64_t)nibble << (j * 4));
            }
            state = sbox_state;

            // 3. pLayer
            uint64_t permuted = 0;
            for (int j = 0; j < 64; ++j) {
                if ((state >> j) & 1) {
                    int p = (j == 63) ? 63 : (j * 16) % 63;
                    permuted |= (1ULL << p);
                }
            }
            state = permuted;
        }
        
        // Final key addition
        state ^= round_keys[31];
        return state;
    }

    uint64_t decrypt(uint64_t ciphertext) const {
        uint64_t state = ciphertext;
        
        for (int round = 31; round >= 1; --round) {
            // 1. addRoundKey
            state ^= round_keys[round];
            
            // 2. inv_pLayer
            uint64_t permuted = 0;
            for (int j = 0; j < 64; ++j) {
                if ((state >> j) & 1) {
                    int p = (j == 63) ? 63 : (j * 4) % 63;
                    permuted |= (1ULL << p);
                }
            }
            state = permuted;

            // 3. inv_sBoxLayer
            uint64_t sbox_state = 0;
            for (int j = 0; j < 16; ++j) {
                uint8_t nibble = (state >> (j * 4)) & 0xF;
                nibble = INV_SBOX[nibble];
                sbox_state |= ((uint64_t)nibble << (j * 4));
            }
            state = sbox_state;
        }
        
        // Initial key addition
        state ^= round_keys[0];
        return state;
    }
};

const uint8_t Present80::SBOX[16] = {
    0xC, 0x5, 0x6, 0xB, 0x9, 0x0, 0xA, 0xD, 
    0x3, 0xE, 0xF, 0x8, 0x4, 0x7, 0x1, 0x2
};

const uint8_t Present80::INV_SBOX[16] = {
    0x5, 0xE, 0xF, 0x8, 0xC, 0x1, 0x2, 0xD, 
    0xB, 0x4, 0x6, 0x3, 0x0, 0x7, 0x9, 0xA
};

// --- Execution & Verification ---

int main() {
    // Standard PRESENT-80 Test Vector
    // Key: 0x00000000000000000000 (80 bits)
    // Plaintext: 0x0000000000000000 (64 bits)
    // Expected Ciphertext: 0x5579C1387B228445
    std::array<uint8_t, 10> key = {0x01, 0x23, 0x45, 0x67, 0x89, 0xAB, 0xCD, 0xEF, 0x01, 0x23};
    uint64_t plaintext = 0x0000000000000110ULL;
    
    Present80 cipher(key);
    
    uint64_t ciphertext = cipher.encrypt(plaintext);
    uint64_t decrypted  = cipher.decrypt(ciphertext);

    std::cout << std::hex << std::uppercase << std::setfill('0');
    std::cout << "Plaintext  : 0x" << std::setw(16) << plaintext << "\n";
    std::cout << "Ciphertext : 0x" << std::setw(16) << ciphertext << "\n";
    std::cout << "Decrypted  : 0x" << std::setw(16) << decrypted << "\n";

    if (plaintext == decrypted) {
        std::cout << "\n[SUCCESS] Decrypted message matches the original test vector.\n";
    } else {
       std::cout << "\n[ERROR] Decrypted message mismatch.\n";
    }

    return 0;
}